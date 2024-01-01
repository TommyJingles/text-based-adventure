const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const hash = std.hash.Murmur3_32.hash;

pub const EntityID = u32;

pub const Types = struct {
    pub const Info = struct {
        id: u32,
        name: []const u8,
        size: usize = 0,
        alignment: u16 = 0,
    };

    map: std.AutoHashMap(u32, Info),

    pub fn id(comptime T: type) u32 {
        return hash(@typeName(T));
    }
    pub fn ids(type_ids: std.ArrayList(u32), comptime args: anytype) void {
        inline for (args) |entry| {
            // need safety checking or something here
            try type_ids.*.append(Types.id(entry));
        }
    }

    pub fn init(allocator: Allocator) Types {
        return .{ .map = std.AutoHashMap(u32, Info).init(allocator) };
    }

    pub fn deinit(self: *Types) void {
        self.map.deinit();
    }

    pub fn register(self: *Types, comptime T: type) !u32 {
        // https://discord.com/channels/605571803288698900/1189370877876379688
        var tid = hash(@typeName(T));
        if (self.map.contains(tid)) {
            return tid;
        } else {
            var info = Info{ .id = tid, .name = @typeName(T), .size = @sizeOf(T), .alignment = @alignOf(T) };
            try self.map.put(info.id, info);
            return info.id;
        }
    }

    pub fn registerAll(self: *Types, type_ids: *std.ArrayList(u32), comptime args: anytype) !void {
        inline for (args) |entry| {
            // need type checking or something here
            try type_ids.*.append(try self.register(entry));
        }
    }

    pub fn get(self: *Types, tid: u32) ?Info {
        return self.map.get(tid);
    }

    pub fn getByType(self: *Types, comptime T: type) ?Info {
        return self.map.get(hash(@typeName(T)));
    }
};

test "Types" {
    const Thing = struct {
        a: u32 = 0,
        b: i16 = 0,
        pub fn init(alloc: Allocator) !@This() {
            _ = alloc;
            return .{};
        }
    };

    const Thang = struct {
        c: f32,
        pub fn deinit(alloc: Allocator) void {
            _ = alloc;
            return .{};
        }
    };

    const Theng = struct {
        pub fn func() void {}
    };

    var alloc = std.testing.allocator;
    var types = Types.init(alloc);
    defer types.deinit();

    const theng_id = try types.register(Theng);
    std.debug.print("\ntheng_id: {}", .{theng_id});

    var id_list = std.ArrayList(u32).init(alloc);
    defer id_list.deinit();

    try types.registerAll(&id_list, .{ Thing, Thang });
    std.debug.print("\nid_list: {any}\n", .{id_list.items});

    var info_1 = types.get(theng_id).?;
    var info_2 = types.getByType(Theng).?;
    assert(info_1.id == info_2.id);
}

pub const Archetype = struct {
    id: u32,
    entity_ids: std.ArrayListUnmanaged(EntityID),
    shared_ids: std.ArrayListUnmanaged(u32),
    columns: std.AutoArrayHashMapUnmanaged(u32, std.ArrayListUnmanaged(u8)),

    const ArchetypeError = error{ InvalidColumnTypeID, InvalidRowIndex };

    pub fn hash(c_ids: ?[]u32, s_ids: ?[]u32) u32 {
        if (c_ids == null and s_ids == null) return std.math.maxInt(u32);

        var h: u32 = 0;
        if (c_ids) |cids| {
            for (cids) |c| {
                h ^= c;
            }
        }
        if (s_ids) |sids| {
            for (sids) |s| {
                h ^= s;
            }
        }
        return h;
    }

    pub fn init(alloc: Allocator, c_ids: ?[]u32, s_ids: ?[]u32) !Archetype {
        var arch = Archetype{
            .id = Archetype.hash(c_ids, s_ids),
            .entity_ids = std.ArrayListUnmanaged(u32){},
            .shared_ids = std.ArrayListUnmanaged(u32){},
            .columns = std.AutoArrayHashMapUnmanaged(u32, std.ArrayListUnmanaged(u8)){},
        };
        if (s_ids) |sids| {
            try arch.shared_ids.appendSlice(alloc, sids);
        }
        if (c_ids) |cids| {
            for (cids) |c| {
                try arch.columns.put(alloc, c, .{});
            }
        }

        return arch;
    }

    pub fn deinit(self: *Archetype, alloc: Allocator) void {
        var itr = self.columns.iterator();
        while (itr.next()) |entry| {
            entry.value_ptr.*.deinit(alloc);
        }
        self.columns.deinit(alloc);
        self.shared_ids.deinit(alloc);
        self.entity_ids.deinit(alloc);
    }

    pub fn new(self: *Archetype, alloc: Allocator, types: *Types, entity_id: EntityID) !usize {
        try self.entity_ids.append(alloc, entity_id);
        var itr = self.columns.iterator();
        while (itr.next()) |entry| {
            var info = types.get(entry.key_ptr.*);
            if (info) |inf| {
                try entry.value_ptr.*.ensureTotalCapacity(alloc, entry.value_ptr.*.items.len + inf.size);
            }
        }
        return self.entity_ids.items.len - 1;
    }

    pub fn remove(self: *Archetype, alloc: Allocator, typs: *Types, row_index: usize) !void {
        if (row_index >= self.entity_ids.items.len) return ArchetypeError.InvalidRowIndex;

        var itr = self.columns.iterator();
        if (self.entity_ids.items.len == 1) {
            while (itr.next()) |entry| {
                entry.value_ptr.*.clearRetainingCapacity();
            }
        } else if (self.entity_ids.items.len - 1 == row_index) {
            while (itr.next()) |entry| {
                var info = typs.get(entry.key_ptr.*).?;
                var bytes = entry.value_ptr.*;
                try bytes.resize(alloc, bytes.items.len - info.size);
            }
        } else {
            while (itr.next()) |entry| {
                var info = typs.get(entry.key_ptr.*).?;
                var bytes = entry.value_ptr.*;
                try bytes.replaceRange(alloc, row_index * info.size, info.size, bytes.items[bytes.items.len - info.size .. bytes.items.len]);
                try bytes.resize(alloc, bytes.items.len - info.size);
            }
        }

        _ = self.entity_ids.swapRemove(row_index);
    }

    pub fn set(self: *Archetype, row_index: usize, component: anytype) !void {
        var id = Types.id(@TypeOf(component));
        if (!self.columns.contains(id)) return ArchetypeError.InvalidColumnTypeID;

        var column = self.columns.get(id).?;

        const size = @sizeOf(@TypeOf(component));
        var offset = row_index * size;
        if (offset + size > column.items.len) return ArchetypeError.InvalidRowIndex;

        var bytes = std.mem.toBytes(component);
        @memcpy(column.items[offset .. offset + size], &bytes);
    }

    pub fn get(self: *Archetype, row_index: usize, comptime T: type) !*T {
        var id = Types.id(T);
        if (!self.columns.contains(id)) return ArchetypeError.InvalidID;

        var column = self.columns.get(id).?;

        const size = @sizeOf(T);
        var offset = row_index * size;
        if (offset + size > column.items.len) return ArchetypeError.InvalidRowIndex;

        return @as(*T, @ptrCast(@alignCast(column.items[offset .. offset + size])));
    }
};

test "Archetype" {
    const print_archetype = (struct {
        fn print_archetype(typs: *Types, a: *Archetype) void {
            std.debug.print("{{", .{});
            std.debug.print("\n  id = {},", .{a.id});
            std.debug.print("\n  entity_ids = {},", .{a.entity_ids});
            std.debug.print("\n  shared_ids = {},", .{a.shared_ids});
            std.debug.print("\n  columns = ({})[", .{a.columns.keys().len});
            var itr = a.columns.iterator();
            while (itr.next()) |entry| {
                var info = typs.get(entry.key_ptr.*).?;
                std.debug.print("\n    {{id: {}, data: {any} }},", .{ info.id, entry.value_ptr.* });
            }
            std.debug.print("\n  ],\n}}\n", .{});
        }
    }).print_archetype;

    const Thing = struct { val: u32 };
    const Thang = struct { val: f32 };

    var alloc = std.testing.allocator;
    var types = Types.init(alloc);
    defer types.deinit();

    var c_list = std.ArrayList(u32).init(alloc);
    defer c_list.deinit();
    try c_list.append(try types.register(Thing)); // TODO: appendAll(), which is then used for the c_list, s_list
    try c_list.append(try types.register(Thang));

    var void_arch = try Archetype.init(alloc, null, null);
    defer void_arch.deinit(alloc);
    _ = try void_arch.new(alloc, &types, 0);
    try void_arch.remove(alloc, &types, 0);

    var arch = try Archetype.init(alloc, c_list.items, null);
    defer arch.deinit(alloc);

    var eid0: u32 = 0;
    var row0 = try arch.new(alloc, &types, eid0);
    try arch.set(row0, Thing{ .val = 12 });
    try arch.set(row0, Thang{ .val = 34.5 });

    var eid1: u32 = 1;
    var row1 = try arch.new(alloc, &types, eid1);

    try arch.set(row1, Thing{ .val = 34 });
    try arch.set(row1, Thang{ .val = 56.7 });

    std.debug.print("\narch = ", .{});
    print_archetype(&types, &arch);

    var arch2 = try Archetype.init(alloc, null, null);
    defer arch2.deinit(alloc);
    std.debug.print("\narch2 = ", .{});
    print_archetype(&types, &arch2);

    var arch3 = try Archetype.init(alloc, arch.columns.keys(), arch.shared_ids.items);
    defer arch3.deinit(alloc);
    std.debug.print("\narch3 = ", .{});
    print_archetype(&types, &arch3);
}

// inspired by: https://github.com/prime31/zig-ecs/blob/master/src/ecs/type_store.zig
pub const NamedBlackboard = struct {
    pub const Entry = struct { type_id: u32, bytes: []u8 };

    allocator: Allocator,
    types: *Types,
    map: std.AutoHashMapUnmanaged(u32, Entry),

    pub fn init(allocator: Allocator, typs: *Types) NamedBlackboard {
        return .{ .allocator = allocator, .types = typs, .map = std.AutoHashMapUnmanaged(u32, Entry){} };
    }

    pub fn deinit(self: *NamedBlackboard) void {
        var itr = self.map.valueIterator();
        while (itr.next()) |value| {
            self.allocator.free(value.bytes);
        }
        self.map.deinit(self.allocator);
    }

    pub fn getID(self: *NamedBlackboard, name: []const u8) u32 {
        _ = self;
        return hash(name);
    }

    pub fn set(self: *NamedBlackboard, id: u32, instance: anytype) u32 {
        var info = self.types.get(Types.id(@TypeOf(instance))).?;
        const bytes = self.allocator.alloc(u8, info.size) catch unreachable;
        @memcpy(bytes, std.mem.asBytes(&instance));
        self.remove(id);
        self.map.put(self.allocator, id, Entry{ .type_id = info.id, .bytes = bytes }) catch unreachable;
        return id;
    }

    pub fn setByName(self: *NamedBlackboard, name: []const u8, instance: anytype) u32 {
        return self.set(hash(name), instance);
    }

    pub fn setRaw(self: *NamedBlackboard, id: u32, type_id: u32, bytes: []u8) u32 {
        var info = self.types.get(type_id).?;
        const _bytes = self.allocator.alloc(u8, info.size) catch unreachable;
        @memcpy(_bytes, bytes);
        self.map.put(self.allocator, id, Entry{ .type_id = info.id, .bytes = bytes }) catch unreachable;
        return id;
    }

    pub fn setRawByName(self: *NamedBlackboard, name: []const u8, type_id: u32, bytes: []u8) u32 {
        return self.setRaw(hash(name), type_id, bytes);
    }

    pub fn get(self: *NamedBlackboard, id: u32, comptime T: type) ?*T {
        if (self.map.get(id)) |entry| {
            return @as(*T, @ptrCast(@alignCast(entry.bytes)));
        }
        return null;
    }

    pub fn getRaw(self: *NamedBlackboard, id: u32) ?[]u8 {
        if (self.map.get(id)) |entry| {
            return entry.bytes;
        }
        return null;
    }

    pub fn getByName(self: *NamedBlackboard, name: []const u8, comptime T: type) ?*T {
        return self.get(hash(name), T);
    }

    pub fn getRawByName(self: *NamedBlackboard, name: []const u8) ?[]u8 {
        return self.getRaw(hash(name));
    }

    pub fn remove(self: *NamedBlackboard, id: u32) void {
        if (self.map.get(id)) |entry| {
            self.allocator.free(entry.bytes);
            _ = self.map.remove(id);
        }
    }

    pub fn removeByName(self: *NamedBlackboard, name: []const u8) void {
        var id = hash(name);
        if (self.map.get(id)) |entry| {
            self.allocator.free(entry.bytes);
            _ = self.map.remove(id);
        }
    }

    pub fn has(self: *NamedBlackboard, name: []const u8) bool {
        return self.map.contains(hash(name));
    }
};

test "NamedBlackboard" {
    const Thing = struct { a: u32, b: i16 };
    const Thang = struct { c: f32 };

    var alloc = std.testing.allocator;
    var types = Types.init(alloc);
    defer types.deinit();

    var type_ids = std.ArrayList(u32).init(alloc);
    defer type_ids.deinit();

    try types.registerAll(&type_ids, .{ Thing, Thang });
    var board = NamedBlackboard.init(alloc, &types);
    defer board.deinit();

    var id = board.setByName("Thing1", Thing{ .a = 1, .b = 2 });
    _ = board.set(id, Thing{ .a = 3, .b = 4 });

    var thing1 = board.get(id, Thing).?.*;
    try std.testing.expectEqual(board.getByName("Thing1", Thing), board.get(id, Thing));
    try std.testing.expectEqual(Thing{ .a = 3, .b = 4 }, thing1);
    assert(std.mem.eql(u8, &std.mem.toBytes(thing1), board.getRaw(id).?));

    board.remove(id);
    var thing2 = board.getByName("Thing1", Thing);
    assert(thing2 == null);
}

pub const Entities = struct {
    pub const Pointer = struct { archetype_id: u32, row_index: usize };

    allocator: Allocator,
    types: *Types,
    pointers: std.AutoHashMapUnmanaged(EntityID, Pointer) = .{},
    shared: NamedBlackboard,
    archetypes: std.AutoArrayHashMapUnmanaged(u32, Archetype) = .{},
    void_archetype_id: u32 = std.math.maxInt(u32),
    next_entity_id: u32 = 0,

    pub fn init(allocator: Allocator, types: *Types) !Entities {
        var entities = Entities{ .allocator = allocator, .types = types, .shared = NamedBlackboard.init(allocator, types) };
        var arch: Archetype = try Archetype.init(allocator, null, null);
        try entities.archetypes.put(allocator, entities.void_archetype_id, arch);
        return entities;
    }

    pub fn deinit(self: *Entities) void {
        self.pointers.deinit(self.allocator);
        self.shared.deinit();
        var itr = self.archetypes.iterator();
        while (itr.next()) |entry| {
            entry.value_ptr.deinit(self.allocator);
        }
        self.archetypes.deinit(self.allocator);
    }

    pub fn create(self: *Entities) !EntityID {
        var arch: Archetype = self.archetypes.get(self.void_archetype_id).?;
        var id: u32 = self.next_entity_id;
        var row_index: usize = try arch.new(self.allocator, self.types, id);
        try self.pointers.put(self.allocator, id, Pointer{ .archetype_id = arch.id, .row_index = row_index });
        self.next_entity_id += 1;
        return id;
    }

    pub fn delete(self: *Entities, entity_id: EntityID) !void {
        var pointer: Pointer = self.pointers.get(entity_id).?;
        var arch: Archetype = self.archetypes.get(pointer.archetype_id).?;
        var swap_id: u32 = arch.entity_ids.items[arch.entity_ids.items.len - 1];
        try arch.remove(self.allocator, self.types, pointer.row_index);
        if (entity_id != swap_id) {
            _ = self.pointers.remove(swap_id);
            try self.pointers.put(self.allocator, swap_id, Pointer{ .archetype_id = arch.id, .row_index = pointer.row_index });
        }
        _ = try self.delete(entity_id);

        return;
    }
};

test "Entities" {
    const print_archetype = (struct {
        fn print_archetype(typs: *Types, a: *Archetype) void {
            std.debug.print("{{", .{});
            std.debug.print("\n  id = {},", .{a.id});
            std.debug.print("\n  entity_ids = {},", .{a.entity_ids});
            std.debug.print("\n  shared_ids = {},", .{a.shared_ids});
            std.debug.print("\n  columns = ({})[", .{a.columns.keys().len});
            var itr = a.columns.iterator();
            while (itr.next()) |entry| {
                var info = typs.get(entry.key_ptr.*).?;
                std.debug.print("\n    {{id: {}, data: {any} }},", .{ info.id, entry.value_ptr.* });
            }
            std.debug.print("\n  ],\n}}\n", .{});
        }
    }).print_archetype;

    _ = print_archetype;

    const Thing = struct { a: u32, b: i16 };
    const Thang = struct { c: f32 };

    var alloc = std.testing.allocator;
    var types = Types.init(alloc);
    defer types.deinit();

    var type_ids = std.ArrayList(u32).init(alloc);
    defer type_ids.deinit();

    try types.registerAll(&type_ids, .{ Thing, Thang });
    var board = NamedBlackboard.init(alloc, &types);
    defer board.deinit();

    // init, deinit
    var entities = try Entities.init(alloc, &types);
    defer entities.deinit();

    // // create, createWith, createAs
    var ent1 = try entities.create();
    std.debug.print("\nent1: {}, pointer: {?}\n", .{ ent1, entities.pointers.get(ent1) });
    // var void_arch = entities.archetypes.get(entities.void_archetype_id).?;
    // print_archetype(&types, &void_arch);
}
