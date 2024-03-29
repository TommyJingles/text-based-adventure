const Archetype = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const Types = @import("./Types.zig");
const TypeID = @import("./common.zig").TypeID;
const EntityID = @import("./common.zig").EntityID;
const SharedID = @import("./common.zig").SharedID;
const ArchID = @import("./common.zig").ArchID;
const Column = @import("./Column.zig");

pub const VOID_ARCH_ID = ArchID{ .val = std.math.maxInt(u32) };
pub const ArchetypeError = error{ InvalidColumnTypeID, InvalidByteLen, InvalidRowIndex };

id: ArchID,
// TODO: #multithreading, lock per list, per column, per row?
entity_ids: std.ArrayListUnmanaged(EntityID),
shared_ids: std.ArrayListUnmanaged(SharedID),
columns: std.AutoHashMapUnmanaged(TypeID, Column),

pub fn init(alloc: Allocator, types: *Types, identity: *Identity) !Archetype {
    var arch = Archetype{ // formatting
        .id = identity.getID(),
        .entity_ids = try std.ArrayListUnmanaged(EntityID).initCapacity(alloc, 1),
        .shared_ids = try std.ArrayListUnmanaged(SharedID).initCapacity(alloc, 1),
        .columns = std.AutoHashMapUnmanaged(TypeID, Column){},
    };

    try arch.shared_ids.appendSlice(alloc, identity.shared_ids.items);

    for (identity.column_ids.items) |cid| {
        var info = types.map.getPtr(cid);
        if (info) |inf| {
            try arch.columns.put(alloc, cid, Column{
                .info = inf,
                .bytes = try std.ArrayListUnmanaged(u8).initCapacity(alloc, inf.size),
            });
        } else {
            return ArchetypeError.InvalidColumnTypeID;
        }
    }

    return arch;
}

pub fn deinit(self: *Archetype, alloc: Allocator) void {
    var itr = self.columns.valueIterator();
    while (itr.next()) |column| {
        column.deinit(alloc);
    }
    self.columns.deinit(alloc);
    self.entity_ids.deinit(alloc);
    self.shared_ids.deinit(alloc);
}

pub fn add(self: *Archetype, alloc: Allocator, eid: EntityID) !usize {
    try self.entity_ids.append(alloc, eid);
    var itr = self.columns.valueIterator();
    while (itr.next()) |col| {
        col.add(alloc, null) catch |e| {
            _ = self.entity_ids.orderedRemove(self.entity_ids.items.len - 1);
            return e;
        };
    }
    return self.entity_ids.items.len - 1;
}

/// returns entity_id if swapback was performed otherwise null
pub fn remove(self: *Archetype, alloc: Allocator, row_index: usize) !?EntityID {
    var itr = self.columns.valueIterator();
    while (itr.next()) |col| {
        try col.remove(alloc, row_index);
    }
    var swap_entity_id = self.entity_ids.getLast();
    _ = self.entity_ids.swapRemove(row_index);
    if (row_index != self.entity_ids.items.len) {
        return swap_entity_id;
    }
    return null;
}

pub fn get(self: *Archetype, index: usize, cid: TypeID) ?[]u8 {
    if (self.columns.getPtr(cid)) |col| {
        return col.get(index) catch return null;
    }
    return null;
}

pub fn set(self: *Archetype, alloc: Allocator, index: usize, cid: TypeID, bytes: []u8, deinit_old_value: bool) !void {
    if (self.columns.getPtr(cid)) |col| {
        return try col.set(alloc, index, bytes, deinit_old_value);
    }
    return ArchetypeError.InvalidColumnTypeID;
}

pub fn has(self: *Archetype, cid: TypeID) bool {
    return self.columns.contains(cid);
}

pub fn hasShared(self: *Archetype, sid: SharedID) bool {
    for (self.shared_ids.items) |id| {
        if (sid.val == id.val) return true;
    }
    return false;
}

pub fn hasEntity(self: *Archetype, eid: EntityID) bool {
    for (self.entity_ids.items) |id| {
        if (eid.val == id.val) return true;
    }
    return false;
}

/// user is responsible for freeing returned list
pub fn getColumnIds(self: *Archetype, alloc: Allocator) !std.ArrayList(TypeID) {
    var list = try std.ArrayList(TypeID).initCapacity(alloc, self.columns.size);
    var itr = self.columns.keyIterator();
    while (itr.next()) |id| {
        list.add(id);
    }
    return list;
}

/// user is responsible for freeing returned list
pub fn getSharedIds(self: *Archetype, alloc: Allocator) ?std.ArrayList(SharedID) {
    var list = try std.ArrayList(SharedID).initCapacity(alloc, self.shared_ids.items.len);
    list.appendSliceAssumeCapacity(self.shared_ids.items.len);
    return list;
}

test "archetype" {
    std.debug.print("\n\n", .{});
    const TestVector = struct { x: u32 = 0, y: u32 = 0, z: u32 = 0 };

    var alloc = std.testing.allocator;

    var print_buf = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer print_buf.deinit();

    var types = Types.init(alloc);
    defer types.deinit();

    var tv_info = types.registerType(.{ .name = "TestVector", .type = TestVector });
    var lst_info = types.registerType(.{ .name = "Name", .type = std.ArrayListUnmanaged(u8) });

    var cids = [_]TypeID{ tv_info.id, lst_info.id };
    var identity = try Identity.init(alloc, &cids, null);
    defer identity.deinit();

    var arch = try Archetype.init(alloc, &types, &identity);

    std.debug.assert(arch.has(tv_info.id));
    std.debug.assert(arch.has(lst_info.id));

    var e0_id = EntityID{ .val = 0 };
    var e0_index = try arch.add(alloc, e0_id);
    std.debug.print("\ne0  id: {}, index: {}\n", .{ e0_id, e0_index });

    var e0_tv: *TestVector = @ptrCast(@alignCast(arch.get(e0_index, tv_info.id).?.ptr));
    e0_tv.x = 1;
    e0_tv.y = 2;
    e0_tv.z = 3;

    var e0_lst: *std.ArrayListUnmanaged(u8) = @ptrCast(@alignCast(arch.get(e0_index, lst_info.id).?.ptr));
    try e0_lst.appendSlice(alloc, "hello world");

    var e1_id = EntityID{ .val = 1 };
    var e1_index = try arch.add(alloc, e1_id);
    std.debug.print("\ne1  id: {}, index: {}\n", .{ e1_id, e1_index });

    var e1_tv: *TestVector = @ptrCast(@alignCast(arch.get(e1_index, tv_info.id).?.ptr));
    e1_tv.x = 4;
    e1_tv.y = 5;
    e1_tv.z = 6;

    var e1_lst: *std.ArrayListUnmanaged(u8) = @ptrCast(@alignCast(arch.get(e1_index, lst_info.id).?.ptr));
    try e1_lst.appendSlice(alloc, "goodbye world");

    if (try arch.remove(alloc, e0_index)) |swap_id| {
        std.debug.assert(swap_id.val == e1_id.val);
        e1_index = e0_index;
    }

    tv_info.dynamic.print(&print_buf, 0, arch.get(e1_index, tv_info.id).?);
    try print_buf.appendSlice("\n\n");
    lst_info.dynamic.print(&print_buf, 0, arch.get(e1_index, lst_info.id).?);

    std.debug.print("\n{s}\n", .{print_buf.items});

    arch.deinit(alloc);
}

pub const Identity = struct {
    alloc: Allocator,
    column_ids: std.ArrayListUnmanaged(TypeID),
    shared_ids: std.ArrayListUnmanaged(SharedID),

    pub fn init(alloc: Allocator, column_ids: ?[]TypeID, shared_ids: ?[]SharedID) !Identity {
        var identity = Identity{ .alloc = alloc, .column_ids = std.ArrayListUnmanaged(TypeID){}, .shared_ids = std.ArrayListUnmanaged(SharedID){} };
        if (column_ids) |cids| {
            try identity.column_ids.appendSlice(alloc, cids);
        }

        if (shared_ids) |sids| {
            try identity.shared_ids.appendSlice(alloc, sids);
        }
        return identity;
    }

    pub fn fromArchetype(alloc: Allocator, archetype: ?*Archetype) !Identity {
        var identity = Identity{ .alloc = alloc, .column_ids = std.ArrayListUnmanaged(TypeID){}, .shared_ids = std.ArrayListUnmanaged(TypeID){} };
        if (archetype) |arch| {
            var itr = arch.columns.keyIterator();
            while (itr.next()) |col_id| {
                try identity.column_ids.append(identity.alloc, col_id.*);
            }
            try identity.shared_ids.appendSlice(identity.alloc, arch.shared_ids.items);
        }
        return identity;
    }

    pub fn deinit(self: *Identity) void {
        self.column_ids.deinit(self.alloc);
        self.shared_ids.deinit(self.alloc);
    }

    pub fn addComponentID(self: *Identity, cid: TypeID) !void {
        if (self.column_ids.items.len != 0) {
            for (self.column_ids.items, 0..) |_id, i| {
                if (_id.val == cid.val) return; // it's already in there, do not duplicate
                if (_id.val > cid.val) {
                    try self.column_ids.insert(self.alloc, i, cid);
                    return;
                }
            }
        }
        try self.column_ids.append(self.alloc, cid);
        //std.mem.sort(u32, self.column_ids.items, {}, comptime std.sort.asc(u32));
    }

    pub fn removeComponentID(self: *Identity, cid: TypeID) !void {
        for (self.column_ids.items, 0..) |_id, i| {
            if (_id.val == cid.val) {
                _ = self.column_ids.orderedRemove(i);
                break;
            }
        }
    }

    pub fn addSharedID(self: *Identity, sid: SharedID) !void {
        if (self.shared_ids.items.len != 0) {
            for (self.shared_ids.items, 0..) |_id, i| {
                if (_id.val == sid.val) return; // it's already in there, do not duplicate
                if (_id.val > sid.val) {
                    try self.shared_ids.insert(self.alloc, i, sid);
                    return;
                }
            }
        }
        try self.shared_ids.append(self.alloc, sid);
    }

    pub fn removeSharedID(self: *Identity, sid: SharedID) !void {
        for (self.shared_ids.items, 0..) |_id, i| {
            if (_id.val == sid.val) {
                _ = self.shared_ids.orderedRemove(i);
                break;
            }
        }
    }

    pub fn getID(self: *Identity) ArchID {
        if (self.column_ids.items.len == 0 and self.shared_ids.items.len == 0) return VOID_ARCH_ID;

        var h: ArchID = ArchID{ .val = 17 };
        for (self.column_ids.items) |cid| {
            h.val *%= 31;
            h.val +%= cid.val;
        }
        for (self.shared_ids.items) |sid| {
            h.val *%= 31;
            h.val +%= sid.val;
        }
        return h;
    }
};

test "Identity" {
    std.debug.print("\n\n", .{});
    var alloc = std.testing.allocator;

    var types = Types.init(alloc);
    defer types.deinit();

    var identity = try Identity.init(alloc, null, null);
    defer identity.deinit();

    std.debug.print("\nvoid_arch identity id: {}\n", .{identity.getID()});

    try identity.addComponentID(TypeID{ .val = 29496729 });
    try identity.addComponentID(TypeID{ .val = 62949672 });
    try identity.addComponentID(TypeID{ .val = 44496725 });

    try identity.addSharedID(SharedID{ .val = 329496723 });
    try identity.addSharedID(SharedID{ .val = 129496722 });
    try identity.addSharedID(SharedID{ .val = 259496729 });

    std.debug.print("\nIdentity{{ id() = {}, .column_ids = {any}, .shared_ids = {any} }}\n", .{ identity.getID(), identity.column_ids.items, identity.shared_ids.items });

    try identity.removeComponentID(TypeID{ .val = 62949672 });
    try identity.removeSharedID(SharedID{ .val = 129496722 });

    std.debug.print("\nIdentity{{ id() = {}, .column_ids = {any}, .shared_ids = {any} }}\n", .{ identity.getID(), identity.column_ids.items, identity.shared_ids.items });
}
