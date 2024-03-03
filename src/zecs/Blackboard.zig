const std = @import("std");
const Types = @import("./Types.zig");
const Allocator = std.mem.Allocator;
const hash = std.hash.Murmur3_32.hash;

const Blackboard = @This();

// inspired by: https://github.com/prime31/zig-ecs/blob/master/src/ecs/type_store.zig

pub const Entry = struct { type_id: u32, bytes: []u8 };

allocator: Allocator,
types: *Types,
map: std.AutoHashMapUnmanaged(u32, Entry),

pub fn init(allocator: Allocator, typs: *Types) Blackboard {
    return .{ .allocator = allocator, .types = typs, .map = std.AutoHashMapUnmanaged(u32, Entry){} };
}

pub fn deinit(self: *Blackboard) void {
    var itr = self.map.valueIterator();
    while (itr.next()) |value| {
        self.allocator.free(value.bytes);
    }
    self.map.deinit(self.allocator);
}

pub fn getID(self: *Blackboard, name: []const u8) u32 {
    _ = self;
    return hash(name);
}

pub fn set(self: *Blackboard, id: u32, instance: anytype) u32 {
    var info = self.types.get(Types.id(@TypeOf(instance))).?;
    const bytes = self.allocator.alloc(u8, info.size) catch unreachable;
    @memcpy(bytes, std.mem.asBytes(&instance));
    self.remove(id);
    self.map.put(self.allocator, id, Entry{ .type_id = info.id, .bytes = bytes }) catch unreachable;
    return id;
}

pub fn setByName(self: *Blackboard, name: []const u8, instance: anytype) u32 {
    return self.set(hash(name), instance);
}

pub fn setRaw(self: *Blackboard, id: u32, type_id: u32, bytes: []u8) u32 {
    var info = self.types.get(type_id).?;
    const _bytes = self.allocator.alloc(u8, info.size) catch unreachable;
    @memcpy(_bytes, bytes);
    self.map.put(self.allocator, id, Entry{ .type_id = info.id, .bytes = bytes }) catch unreachable;
    return id;
}

pub fn setRawByName(self: *Blackboard, name: []const u8, type_id: u32, bytes: []u8) u32 {
    return self.setRaw(hash(name), type_id, bytes);
}

pub fn get(self: *Blackboard, id: u32, comptime T: type) ?*T {
    if (self.map.get(id)) |entry| {
        return @as(*T, @ptrCast(@alignCast(entry.bytes)));
    }
    return null;
}

pub fn getRaw(self: *Blackboard, id: u32) ?[]u8 {
    if (self.map.get(id)) |entry| {
        return entry.bytes;
    }
    return null;
}

pub fn getByName(self: *Blackboard, name: []const u8, comptime T: type) ?*T {
    return self.get(hash(name), T);
}

pub fn getRawByName(self: *Blackboard, name: []const u8) ?[]u8 {
    return self.getRaw(hash(name));
}

pub fn remove(self: *Blackboard, id: u32) void {
    if (self.map.get(id)) |entry| {
        self.allocator.free(entry.bytes);
        _ = self.map.remove(id);
    }
}

pub fn removeByName(self: *Blackboard, name: []const u8) void {
    var id = hash(name);
    if (self.map.get(id)) |entry| {
        self.allocator.free(entry.bytes);
        _ = self.map.remove(id);
    }
}

pub fn has(self: *Blackboard, name: []const u8) bool {
    return self.map.contains(hash(name));
}

test "NamedBlackboard" {
    const Thing = struct { a: u32, b: i16 };
    const Thang = struct { c: f32 };

    var alloc = std.testing.allocator;
    var types = Types.init(alloc);
    defer types.deinit();

    try types.registerAll(.{ Thing, Thang });
    var board = Blackboard.init(alloc, &types);
    defer board.deinit();

    var id = board.setByName("Thing1", Thing{ .a = 1, .b = 2 });
    _ = board.set(id, Thing{ .a = 3, .b = 4 });

    var thing1 = board.get(id, Thing).?.*;
    try std.testing.expectEqual(board.getByName("Thing1", Thing), board.get(id, Thing));
    try std.testing.expectEqual(Thing{ .a = 3, .b = 4 }, thing1);
    std.debug.assert(std.mem.eql(u8, &std.mem.toBytes(thing1), board.getRaw(id).?));

    board.remove(id);
    var thing2 = board.getByName("Thing1", Thing);
    std.debug.assert(thing2 == null);
}
