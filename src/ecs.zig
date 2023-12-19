// Entity Component System, Archetype-based
// my variation of this: https://devlog.hexops.com/2022/lets-build-ecs-part-2-databases/

const std = @import("std");
const testing = std.testing;
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

// Not 100% sure how I want to do this yet, but I need a way to convert a Type to an ID
// thinking of using std.hash.XxHash32 and the Component name
// pub const Types = struct {
//     // pub const TypeInfo = struct {name: []const u8, initable: bool, ?}
//     allocator: std.mem.Allocator,
//     map: std.AutoArrayHashMapUnmanaged(u32, []const u8), // u32, TypeInfo

//     pub fn init(alloc: std.mem.Allocator) Types {
//         return .{ .allocator = alloc, .map = std.AutoArrayHashMapUnmanaged(u32, []const u8){} };
//     }

//     pub fn deinit(self: *Types) void {
//         self.map.deinit(self.allocator);
//     }

//     pub fn id(self: *Types, comptime typ: type) u32 {
//         _ = self;
//         return std.hash.XxHash32.hash(0, @typeName(typ));
//     }

//     pub fn get(self: *Types, type_id: u32) ?[]const u8 {
//         return self.map.get(type_id);
//     }

//     pub fn register(self: *Types, comptime typ: type) !u32 {
//         const type_id = self.id(typ);
//         try self.map.put(self.allocator, type_id, @typeName(typ));
//         return type_id;
//     }
// };

// test "types_test" {
//     var types = Types.init(testing.allocator);
//     defer types.deinit();
//     const MyComponent = struct { x: f32, y: f32, z: f32 };
//     const id = try types.register(MyComponent);
//     std.debug.print("\nname: {s},\tid: {}\n", .{ types.get(id).?, id });
// }

pub const id = (struct {
    pub fn hash(comptime typ: type) u32 {
        return std.hash.XxHash32.hash(0, @typeName(typ));
    }
}).hash;

/// An entity ID uniquely identifies an entity globally within an Entities set.
pub const EntityID = u32;

pub const void_archetype_hash = std.math.maxInt(u32);

/// Represents the storage for a single type of component within a single type of entity.
///
/// Database equivalent: a column within a table.
pub fn Column(comptime Component: type) type {
    return struct {
        /// A reference to the total number of entities with the same type as is being stored here.
        total_rows: *usize,

        /// The actual densely stored component data.
        data: std.ArrayListUnmanaged(Component) = .{},

        const Self = @This();

        pub fn deinit(storage: *Self, allocator: Allocator) void {
            storage.data.deinit(allocator);
        }

        // If the storage of this component is sparse, it is turned dense as calling this method
        // indicates that the caller expects to set this component for most entities rather than
        // sparsely.
        pub fn set(storage: *Self, allocator: Allocator, row_index: u32, component: Component) !void {
            if (storage.data.items.len <= row_index) try storage.data.appendNTimes(allocator, undefined, storage.data.items.len + 1 - row_index);
            storage.data.items[row_index] = component;
        }

        /// Removes the given row index.
        pub fn remove(storage: *Self, row_index: u32) void {
            if (storage.data.items.len > row_index) {
                _ = storage.data.swapRemove(row_index);
            }
        }

        /// Gets the component value for the given entity ID.
        pub inline fn get(storage: Self, row_index: u32) Component {
            return storage.data.items[row_index];
        }

        pub inline fn copy(dst: *Self, allocator: Allocator, src_row: u32, dst_row: u32, src: *Self) !void {
            try dst.set(allocator, dst_row, src.get(src_row));
        }
    };
}

/// A type-erased representation of columnstorage(T) (where T is unknown).
pub const AnyColumn = struct {
    ptr: *anyopaque,
    deinit: *const fn (erased: *anyopaque, allocator: Allocator) void,
    remove: *const fn (erased: *anyopaque, row: u32) void,
    cloneType: *const fn (erased: AnyColumn, total_entities: *usize, allocator: Allocator, retval: *AnyColumn) error{OutOfMemory}!void,
    copy: *const fn (dst_erased: *anyopaque, allocator: Allocator, src_row: u32, dst_row: u32, src_erased: *anyopaque) error{OutOfMemory}!void,

    // Casts this `Erasedcolumnstorage` into `*columnstorage(Component)` with the given type
    // (unsafe).
    pub fn cast(ptr: *anyopaque, comptime Component: type) *Column(Component) {
        var concrete: *Column(Component) = @ptrCast(@alignCast(ptr));
        return concrete;
    }
};

pub const Archetype = struct {
    allocator: Allocator,
    /// The hash of every component name in this archetype, i.e. the name of this archetype.
    hash: u32,

    /// A mapping of rows in the table to entity IDs.
    ///
    /// Doubles as the counter of total number of rows that have been reserved within this
    /// archetype table.
    entity_ids: std.ArrayListUnmanaged(EntityID) = .{},

    /// A string hashmap of component_name -> type-erased *columnstorage(Component)
    columns: std.AutoHashMapUnmanaged(u32, AnyColumn),

    /// Calculates the storage.hash value. This is a hash of all the component type_id, and can
    /// effectively be used to uniquely identify this table within the database.
    pub fn calculateHash(self: *Archetype) void {
        self.hash = 0;
        var iter = self.columns.iterator();
        while (iter.next()) |entry| {
            self.hash ^= entry.key_ptr.*;
        }
        // same loop, but for shared_columns (u32 values)
    }

    pub fn deinit(self: *Archetype) void {
        var itr = self.columns.valueIterator();
        while (itr.next()) |erased| {
            erased.deinit(erased, self.allocator);
        }
        self.entity_ids.deinit(self.allocator);
        self.columns.deinit(self.allocator);
    }

    /// New reserves a row for storing an entity within this archetype table.
    pub fn new(self: *Archetype, entity: EntityID) !u32 {
        // Return a new row index
        const new_row_index = self.entity_ids.items.len;
        try self.entity_ids.append(self.allocator, entity);
        return @as(u32, @intCast(new_row_index));
    }

    /// Undoes the last call to the new() operation, effectively unreserving the row that was last
    /// reserved.
    pub fn undoNew(self: *Archetype) void {
        _ = self.entity_ids.pop();
    }

    /// Sets the value of the named component (column) for the given row in the table. Realizes the
    /// deferred allocation of column storage for N entities (storage.counter) if it is not already.
    pub fn set(self: *Archetype, row_index: u32, component: anytype) !void {
        var component_storage_erased = self.columns.get(id(@TypeOf(component))).?;
        var component_storage = AnyColumn.cast(component_storage_erased.ptr, @TypeOf(component));
        try component_storage.set(self.allocator, row_index, component);
    }

    /// Removes the specified row. See also the `Entity.delete()` helper.
    ///
    /// This merely marks the row as removed, the same row index will be recycled the next time a
    /// new row is requested via `new()`.
    pub fn remove(self: *Archetype, row_index: u32) !void {
        _ = self.entity_ids.swapRemove(row_index);
        var itr = self.columns.valueIterator();
        while (itr.next()) |component_storage| {
            component_storage.remove(component_storage, row_index);
        }
    }
};

pub const Entities = struct {
    allocator: Allocator,

    /// TODO!
    nextEntityID: EntityID = 0,

    /// A mapping of entity IDs (array indices) to where an entity's component values are actually
    /// stored.
    pointers: std.AutoHashMapUnmanaged(EntityID, Pointer) = .{},

    /// A mapping of archetype hash to their storage.
    ///
    /// Database equivalent: table name -> tables representing entities.
    archetypes: std.AutoArrayHashMapUnmanaged(u32, Archetype) = .{},

    /// Points to where an entity is stored, specifically in which archetype table and in which row
    /// of that table. That is, the entity's component values are stored at:
    ///
    /// ```
    /// Entities.archetypes[ptr.archetype_index].rows[ptr.row_index]
    /// ```
    ///
    pub const Pointer = struct {
        archetype_index: u16,
        row_index: u32,
    };

    pub fn init(allocator: Allocator) !Entities {
        var entities = Entities{ .allocator = allocator };

        try entities.archetypes.put(allocator, void_archetype_hash, Archetype{
            .allocator = allocator,
            .columns = .{},
            .hash = void_archetype_hash,
        });

        return entities;
    }

    pub fn deinit(self: *Entities) void {
        self.pointers.deinit(self.allocator);
        var iter = self.archetypes.iterator();
        while (iter.next()) |entry| {
            entry.value_ptr.deinit();
        }
        self.archetypes.deinit(self.allocator);
    }

    pub fn initAnyColumn(self: *const Entities, total_rows: *usize, comptime Component: type) !AnyColumn {
        var new_ptr = try self.allocator.create(Column(Component));
        new_ptr.* = Column(Component){ .total_rows = total_rows };

        // maybe this could be in the 'types' and during 'register' this is created?
        // that way I can just do: types.getAnyColumn(id)?
        return AnyColumn{
            .ptr = new_ptr,
            .deinit = (struct {
                pub fn deinit(erased: *anyopaque, allocator: Allocator) void {
                    var ptr = AnyColumn.cast(erased, Component);
                    ptr.deinit(allocator);
                    allocator.destroy(ptr);
                }
            }).deinit,
            .remove = (struct {
                pub fn remove(erased: *anyopaque, row: u32) void {
                    var ptr = AnyColumn.cast(erased, Component);
                    ptr.remove(row);
                }
            }).remove,
            .cloneType = (struct {
                pub fn cloneType(erased: AnyColumn, _total_rows: *usize, allocator: Allocator, retval: *AnyColumn) !void {
                    var new_clone = try allocator.create(Column(Component));
                    new_clone.* = Column(Component){ .total_rows = _total_rows };
                    var tmp = erased;
                    tmp.ptr = new_clone;
                    retval.* = tmp;
                }
            }).cloneType,
            .copy = (struct {
                pub fn copy(dst_erased: *anyopaque, allocator: Allocator, src_row: u32, dst_row: u32, src_erased: *anyopaque) !void {
                    var dst = AnyColumn.cast(dst_erased, Component);
                    var src = AnyColumn.cast(src_erased, Component);
                    return dst.copy(allocator, src_row, dst_row, src);
                }
            }).copy,
        };
    }

    /// Returns a new entity.
    pub fn new(self: *Entities) !EntityID {
        const new_id = self.nextEntityID;
        self.nextEntityID += 1;

        var void_archetype = self.archetypes.getPtr(void_archetype_hash).?;
        const new_row = try void_archetype.new(new_id);
        const void_pointer = Pointer{
            .archetype_index = 0, // void archetype is guaranteed to be first index
            .row_index = new_row,
        };

        self.pointers.put(self.allocator, new_id, void_pointer) catch |err| {
            void_archetype.undoNew();
            return err;
        };
        return new_id;
    }

    /// Returns the archetype storage for the given entity.
    pub inline fn archetypeByID(self: *Entities, entity: EntityID) *Archetype {
        const ptr = self.pointers.get(entity).?;
        return &self.archetypes.values()[ptr.archetype_index];
    }

    /// Removes an entity.
    pub fn remove(self: *Entities, entity: EntityID) !void {
        var archetype = self.archetypeByID(entity);
        const ptr = self.pointers.get(entity).?;

        // A swap removal will be performed, update the entity stored in the last row of the
        // archetype table to point to the row the entity we are removing is currently located.
        const last_row_entity_id = archetype.entity_ids.items[archetype.entity_ids.items.len - 1];
        try self.pointers.put(self.allocator, last_row_entity_id, Pointer{
            .archetype_index = ptr.archetype_index,
            .row_index = ptr.row_index,
        });

        // Perform a swap removal to remove our entity from the archetype table.
        try archetype.remove(ptr.row_index);

        try self.remove(entity);
    }

    /// Sets the named component to the specified value for the given entity,
    /// moving the entity from it's current archetype table to the new archetype
    /// table if required.
    pub fn setComponent(self: *Entities, entity: EntityID, component: anytype) !void {
        var archetype = self.archetypeByID(entity);

        // Determine the old hash for the archetype.
        const old_hash = archetype.hash;

        // Determine the new hash for the archetype + new component
        var have_already = archetype.columns.contains(id(@TypeOf(component)));
        const new_hash = if (have_already) old_hash else old_hash ^ id(@TypeOf(component));

        // Find the archetype storage for this entity. Could be a new archetype storage table (if a
        // new component was added), or the same archetype storage table (if just updating the
        // value of a component.)
        var archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);
        if (!archetype_entry.found_existing) {
            archetype_entry.value_ptr.* = Archetype{
                .allocator = self.allocator,
                .columns = .{},
                .hash = 0,
            };
            var new_archetype = archetype_entry.value_ptr;

            // Create storage/columns for all of the existing columns on the entity.
            var column_iter = archetype.columns.iterator();
            while (column_iter.next()) |entry| {
                var erased: AnyColumn = undefined;
                entry.value_ptr.cloneType(entry.value_ptr.*, &new_archetype.entity_ids.items.len, self.allocator, &erased) catch |err| {
                    assert(self.archetypes.swapRemove(new_hash));
                    return err;
                };
                new_archetype.columns.put(self.allocator, entry.key_ptr.*, erased) catch |err| {
                    assert(self.archetypes.swapRemove(new_hash));
                    return err;
                };
            }

            // Create storage/column for the new component.
            const erased = self.initAnyColumn(&new_archetype.entity_ids.items.len, @TypeOf(component)) catch |err| {
                assert(self.archetypes.swapRemove(new_hash));
                return err;
            };
            new_archetype.columns.put(self.allocator, id(@TypeOf(component)), erased) catch |err| {
                assert(self.archetypes.swapRemove(new_hash));
                return err;
            };

            new_archetype.calculateHash();
        }

        // HERE
        // Either new storage (if the entity moved between storage tables due to having a new
        // component) or the prior storage (if the entity already had the component and it's value
        // is merely being updated.)
        var current_archetype_storage = archetype_entry.value_ptr;

        if (new_hash == old_hash) {
            // Update the value of the existing component of the entity.
            const ptr = self.pointers.get(entity).?;
            try current_archetype_storage.set(ptr.row_index, component);
            return;
        }

        // Copy to all component values for our entity from the old archetype storage
        // (archetype) to the new one (current_archetype_storage).
        const new_row = try current_archetype_storage.new(entity);
        const old_ptr = self.pointers.get(entity).?;

        // Update the storage/columns for all of the existing columns on the entity.
        var column_iter = archetype.columns.iterator();
        while (column_iter.next()) |entry| {
            var old_component_storage = entry.value_ptr;
            var new_component_storage = current_archetype_storage.columns.get(entry.key_ptr.*).?;
            new_component_storage.copy(new_component_storage.ptr, self.allocator, new_row, old_ptr.row_index, old_component_storage.ptr) catch |err| {
                current_archetype_storage.undoNew();
                return err;
            };
        }
        current_archetype_storage.entity_ids.items[new_row] = entity;

        // Update the storage/column for the new component.
        current_archetype_storage.set(new_row, component) catch |err| {
            current_archetype_storage.undoNew();
            return err;
        };

        var swapped_entity_id = archetype.entity_ids.items[archetype.entity_ids.items.len - 1];
        archetype.remove(old_ptr.row_index) catch |err| {
            current_archetype_storage.undoNew();
            return err;
        };
        try self.pointers.put(self.allocator, swapped_entity_id, old_ptr);

        try self.pointers.put(self.allocator, entity, Pointer{
            .archetype_index = @as(u16, @intCast(archetype_entry.index)),
            .row_index = new_row,
        });
        return;
    }

    /// gets the component of the given type (which must be correct, otherwise undefined
    /// behavior will occur). Returns null if the component does not exist on the entity.
    pub fn getComponent(self: *Entities, entity: EntityID, comptime Component: type) ?Component {
        var archetype = self.archetypeByID(entity);

        var component_storage_erased = archetype.columns.get(id(Component)) orelse return null;

        const ptr = self.pointers.get(entity).?;
        var component_storage = AnyColumn.cast(component_storage_erased.ptr, Component);
        return component_storage.get(ptr.row_index);
    }

    /// Removes the component from the entity, or noop if it doesn't have such a component.
    pub fn removeComponent(self: *Entities, entity: EntityID, component: anytype) !void {
        var cid = id(@TypeOf(component));
        var archetype = self.archetypeByID(entity);
        if (!archetype.columns.contains(id(component))) return;

        // Determine the old hash for the archetype.
        const old_hash = archetype.hash;

        // Determine the new hash for the archetype with the component removed
        var new_hash: u32 = 0;
        var iter = archetype.columns.iterator();
        while (iter.next()) |entry| {
            const component_id = entry.key_ptr.*;
            if (component_id != cid) new_hash ^= cid;
        }
        assert(new_hash != old_hash);

        // Find the archetype storage for this entity. Could be a new archetype storage table (if a
        // new component was added), or the same archetype storage table (if just updating the
        // value of a component.)
        var archetype_entry = try self.archetypes.getOrPut(self.allocator, new_hash);
        if (!archetype_entry.found_existing) {
            archetype_entry.value_ptr.* = Archetype{
                .allocator = self.allocator,
                .columns = .{},
                .hash = 0,
            };
            var new_archetype = archetype_entry.value_ptr;

            // Create storage/columns for all of the existing columns on the entity.
            var column_iter = archetype.columns.iterator();
            while (column_iter.next()) |entry| {
                if (entry.key_ptr.* == cid) continue;
                var erased: AnyColumn = undefined;
                entry.value_ptr.cloneType(entry.value_ptr.*, &new_archetype.entity_ids.items.len, self.allocator, &erased) catch |err| {
                    assert(self.archetypes.swapRemove(new_hash));
                    return err;
                };
                new_archetype.columns.put(self.allocator, entry.key_ptr.*, erased) catch |err| {
                    assert(self.archetypes.swapRemove(new_hash));
                    return err;
                };
            }
            new_archetype.calculateHash();
        }

        // Either new storage (if the entity moved between storage tables due to having a new
        // component) or the prior storage (if the entity already had the component and it's value
        // is merely being updated.)
        var current_archetype_storage = archetype_entry.value_ptr;

        // Copy to all component values for our entity from the old archetype storage
        // (archetype) to the new one (current_archetype_storage).
        const new_row = try current_archetype_storage.new(entity);
        const old_ptr = self.pointers.get(entity).?;

        // Update the storage/columns for all of the existing columns on the entity.
        var column_iter = current_archetype_storage.columns.iterator();
        while (column_iter.next()) |entry| {
            var src_component_storage = archetype.columns.get(entry.key_ptr.*).?;
            var dst_component_storage = entry.value_ptr;
            dst_component_storage.copy(dst_component_storage.ptr, self.allocator, new_row, old_ptr.row_index, src_component_storage.ptr) catch |err| {
                current_archetype_storage.undoNew();
                return err;
            };
        }
        current_archetype_storage.entity_ids.items[new_row] = entity;

        var swapped_entity_id = archetype.entity_ids.items[archetype.entity_ids.items.len - 1];
        archetype.remove(old_ptr.row_index) catch |err| {
            current_archetype_storage.undoNew();
            return err;
        };
        try self.pointers.put(self.allocator, swapped_entity_id, old_ptr);

        try self.pointers.put(self.allocator, entity, Pointer{
            .archetype_index = @as(u16, @intCast(archetype_entry.index)),
            .row_index = new_row,
        });
        return;
    }
};

test "test_entities" {
    const allocator = testing.allocator;
    var entities = try Entities.init(allocator);
    defer entities.deinit();

    const player = try entities.new();

    // Define component types, any Zig type will do!
    // A location component.
    const Location = struct {
        x: f32 = 0,
        y: f32 = 0,
        z: f32 = 0,
    };

    const Name = []const u8;

    try entities.setComponent(player, @as(Name, "jane"));
    try entities.setComponent(player, Location{});
    try entities.setComponent(player, @as(Name, "joe"));

    try testing.expectEqual(Location{}, entities.getComponent(player, Location).?);
    try testing.expectEqual(@as(Name, "joe"), entities.getComponent(player, Name).?);

    try entities.removeComponent(player, Location);
    try testing.expect(entities.getComponent(player, Location) == null);

    try entities.remove(player);
}

pub const Systems = struct {};

pub const World = struct {
    entities: Entities,
    systems: Systems,

    pub fn init(alloc: std.mem.Allocator) !World {
        return .{ .entities = try Entities.init(alloc), .systems = Systems{} };
    }

    pub fn deinit(self: *World) void {
        // self.types.deinit();
        self.entities.deinit();
        // self.systems.deinit();
    }
};
