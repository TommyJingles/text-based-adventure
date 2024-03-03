const Archetype = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const Types = @import("./Types.zig");
const Column = @import("./Column.zig");

pub const VOID_ARCH_ID = std.math.maxInt(u32);
pub const ArchetypeError = error{ InvalidColumnTypeID, InvalidByteLen, InvalidRowIndex };

id: u32,
// TODO: #multithreading, lock per for entity_ids?
entity_ids: std.ArrayListUnmanaged(u32),
shared_ids: std.ArrayListUnmanaged(u32),
columns: std.AutoHashMapUnmanaged(u32, Column),

pub fn init(alloc: Allocator, types: *Types, component_ids: ?[]u32, shared_ids: ?[]u32) !Archetype {
    var arch = Archetype{ // formatting
        .id = hash(component_ids, shared_ids),
        .entity_ids = try std.ArrayListUnmanaged(u32).initCapacity(alloc, 1),
        .shared_ids = try std.ArrayListUnmanaged(u32).initCapacity(alloc, 1),
        .columns = std.AutoHashMapUnmanaged(u32, Column){},
    };

    if (shared_ids) |sids| {
        try arch.shared_ids.appendSlice(alloc, sids);
    }
    if (component_ids) |cids| {
        for (cids) |c| {
            var info = types.map.getPtr(c);
            if (info) |inf| {
                try arch.columns.put(alloc, c, Column{
                    .info = inf,
                    .bytes = try std.ArrayListUnmanaged(u8).initCapacity(alloc, inf.size),
                });
            } else {
                return ArchetypeError.InvalidColumnTypeID;
            }
        }
    }

    return arch;
}

pub fn deinit(self: *Archetype, alloc: Allocator) void {
    var itr = self.columns.iterator();
    while (itr.next()) |entry| {
        std.debug.print("\ndeinit() column.info.id:    {}\n", .{entry.value_ptr.info.id});
        entry.value_ptr.deinit(alloc);
    }
    self.columns.deinit(alloc);
    self.entity_ids.deinit(alloc);
    self.shared_ids.deinit(alloc);
}

pub fn add(self: *Archetype, alloc: Allocator, entity_id: u32) !usize {
    try self.entity_ids.append(alloc, entity_id);
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
pub fn remove(self: *Archetype, alloc: Allocator, row_index: usize) !?u32 {
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

pub fn get(self: *Archetype, index: usize, type_id: u32) ?[]u8 {
    if (self.columns.getPtr(type_id)) |col| {
        return col.get(index) catch return null;
    }
    return null;
}

pub fn set(self: *Archetype, alloc: Allocator, index: usize, type_id: u32, bytes: []u8, deinit_old_value: bool) !void {
    if (self.columns.getPtr(type_id)) |col| {
        return try col.set(alloc, index, bytes, deinit_old_value);
    }
    return ArchetypeError.InvalidColumnTypeID;
}

pub fn has(self: *Archetype, type_id: u32) bool {
    return self.columns.contains(type_id);
}

pub fn hasShared(self: *Archetype, shared_id: u32) bool {
    for (self.shared_ids.items) |id| {
        if (shared_id == id) return true;
    }
    return false;
}

pub fn hasEntity(self: *Archetype, entity_id: u32) bool {
    for (self.entity_ids.items) |id| {
        if (entity_id == id) return true;
    }
    return false;
}

pub fn hash(component_type_ids: ?[]u32, shared_value_ids: ?[]u32) u32 {
    if (component_type_ids == null and shared_value_ids == null) return VOID_ARCH_ID;

    var h: u32 = 0;
    if (component_type_ids) |cids| {
        for (cids) |c| {
            h ^= c;
        }
    }
    if (shared_value_ids) |sids| {
        for (sids) |s| {
            h ^= s;
        }
    }
    return h;
}

test "archetype" {
    std.debug.print("\n\n", .{});
    const TestVector = struct { x: u32 = 0, y: u32 = 0, z: u32 = 0 };

    var alloc = std.testing.allocator;

    var list = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer list.deinit();

    var types = Types.init(alloc);
    defer types.deinit();

    var tv_info_ptr = types.registerType(.{ .name = "TestVector", .type = TestVector });
    var lst_info_ptr = types.registerType(.{ .name = "Name", .type = std.ArrayListUnmanaged(u8) });

    var cids = [_]u32{ tv_info_ptr.id, lst_info_ptr.id };
    var arch = try Archetype.init(alloc, &types, &cids, null);

    std.debug.assert(arch.has(tv_info_ptr.id));
    std.debug.assert(arch.has(lst_info_ptr.id));

    var e0_id: u32 = 0;
    var e0_index = try arch.add(alloc, e0_id);
    std.debug.print("\ne0  id: {}, index: {}\n", .{ e0_id, e0_index });

    var e0_tv: *TestVector = @ptrCast(@alignCast(arch.get(e0_index, tv_info_ptr.id).?.ptr));
    e0_tv.x = 1;
    e0_tv.y = 2;
    e0_tv.z = 3;

    var e0_lst: *std.ArrayListUnmanaged(u8) = @ptrCast(@alignCast(arch.get(e0_index, lst_info_ptr.id).?.ptr));
    try e0_lst.appendSlice(alloc, "hello world");

    var e1_id: u32 = 1;
    var e1_index = try arch.add(alloc, e1_id);
    std.debug.print("\ne1  id: {}, index: {}\n", .{ e1_id, e1_index });

    var e1_tv: *TestVector = @ptrCast(@alignCast(arch.get(e1_index, tv_info_ptr.id).?.ptr));
    e1_tv.x = 4;
    e1_tv.y = 5;
    e1_tv.z = 6;

    var e1_lst: *std.ArrayListUnmanaged(u8) = @ptrCast(@alignCast(arch.get(e1_index, lst_info_ptr.id).?.ptr));
    try e1_lst.appendSlice(alloc, "goodbye world");

    if (try arch.remove(alloc, e0_index)) |swap_id| {
        std.debug.assert(swap_id == e1_id);
        e1_index = e0_index;
    }

    tv_info_ptr.dynamic.print(&list, 0, arch.get(e1_index, tv_info_ptr.id).?);
    try list.appendSlice("\n\n");
    lst_info_ptr.dynamic.print(&list, 0, arch.get(e1_index, lst_info_ptr.id).?);

    std.debug.print("\n{s}\n", .{list.items});

    arch.deinit(alloc);
}
