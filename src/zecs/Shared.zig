const std = @import("std");
const Types = @import("./Types.zig");
const Allocator = std.mem.Allocator;
const hash = std.hash.Murmur3_32.hash;

const TypeID = @import("./common.zig").TypeID;
const SharedID = @import("./common.zig").SharedID;

const Shared = @This();

pub const SharedError = error{ InvalidSharedID, InvalidTypeID, InvalidByteLen, EntryAlreadyExists, EntryDoesNotExists };

pub const Entry = struct { tid: TypeID, bytes: []u8 };

alloc: Allocator,
types: *Types,
map: std.AutoHashMapUnmanaged(SharedID, Entry),

pub fn init(alloc: Allocator, typs: *Types) Shared {
    return Shared{ .alloc = alloc, .types = typs, .map = std.AutoHashMapUnmanaged(SharedID, Entry){} };
}

pub fn deinit(self: *Shared) void {
    var itr = self.map.valueIterator();
    while (itr.next()) |value| {
        if (self.types.get(value.tid)) |info| {
            info.dynamic.deinit(self.alloc, value.bytes);
        }
        self.alloc.free(value.bytes);
    }
    self.map.deinit(self.alloc);
}

pub fn create(self: *Shared, name: []const u8, tid: TypeID, bytes: []u8) !SharedID {
    if (self.types.get(tid)) |info| {
        if (info.size == bytes.len) {
            const sid = self.getId(name);
            if (self.map.contains(sid)) {
                return SharedError.EntryAlreadyExists;
            } else {
                var entry = Entry{ .tid = info.id, .bytes = try self.alloc.alloc(u8, bytes.len) };
                try info.overwrite(entry.bytes, bytes);
                try self.map.put(self.alloc, sid, entry);
                return sid;
            }
        } else {
            return SharedError.InvalidByteLen;
        }
    } else {
        return SharedError.InvalidTypeID;
    }
}

pub fn destroy(self: *Shared, sid: SharedID) !void {
    if (self.map.get(sid)) |entry| {
        if (self.types.get(entry.tid)) |info| {
            info.dynamic.deinit(self.alloc, entry.bytes);
            self.alloc.free(entry.bytes);
            _ = self.map.remove(sid);
        } else {
            return SharedError.InvalidTypeID;
        }
    } else {
        return SharedError.InvalidSharedID;
    }
}

pub fn get(self: *Shared, sid: SharedID) ?[]u8 {
    return if (self.map.get(sid)) |entry| entry.bytes else null;
}

pub fn set(self: *Shared, sid: SharedID, value: []u8, deinit_previous: bool) !void {
    if (self.map.get(sid)) |entry| {
        if (self.types.get(entry.tid)) |info| {
            if (info.size == value.len) {
                if (deinit_previous) {
                    info.dynamic.deinit(self.alloc, entry.bytes);
                }
                try info.overwrite(entry.bytes, value);
            } else {
                return SharedError.InvalidByteLen;
            }
        } else {
            return SharedError.InvalidTypeID;
        }
    } else {
        return SharedError.EntryDoesNotExists;
    }
}

pub fn getId(self: *Shared, name: []const u8) SharedID {
    _ = self;
    return SharedID{ .val = hash(name) };
}

pub fn has(self: *Shared, sid: SharedID) bool {
    return self.map.contains(sid);
}

test "init_deinit" {
    const TestVector = struct { x: u32 = 0, y: u32 = 0, z: u32 = 0 };

    var alloc = std.testing.allocator;

    var types = Types.init(alloc);
    defer types.deinit();

    var info = types.registerType(.{ .name = "My Vector", .type = TestVector });
    var shared = Shared.init(alloc, &types);
    defer shared.deinit();

    var sid = try shared.create("my_name", info.id, try info.asBytes(&TestVector{ .x = 1, .y = 2, .z = 3 }));

    try shared.destroy(sid);
}

test "get_set" {
    const TestVector = struct { x: u32 = 0, y: u32 = 0, z: u32 = 0 };

    var alloc = std.testing.allocator;

    var types = Types.init(alloc);
    defer types.deinit();

    var info = types.registerType(.{ .name = "My Vector", .type = TestVector });
    var shared = Shared.init(alloc, &types);
    defer shared.deinit();

    var sid = try shared.create("my_name", info.id, try info.asBytes(&TestVector{ .x = 1, .y = 2, .z = 3 }));

    std.debug.print("\nbytes 1: {any}\n", .{shared.get(sid).?});
    std.debug.print("\nasType 1: {}\n", .{try info.asType(TestVector, shared.get(sid).?)});

    var as_bytes = try info.asBytes(&TestVector{ .x = 2, .y = 3, .z = 4 });
    std.debug.print("\nas_bytes: {any}\n", .{as_bytes});
    try shared.set(sid, as_bytes, false);

    std.debug.print("\nbytes 2: {any}\n", .{shared.get(sid).?});

    var tv: *TestVector = try info.asType(TestVector, shared.get(sid).?);
    std.debug.print("\ntv 1: {}\n", .{tv.*});

    var tv2 = TestVector{ .x = 5, .y = 5, .z = 5 };
    std.debug.print("\ntv2 1: {}\n", .{tv2});
    try shared.set(sid, try info.asBytes(&tv2), false);
    std.debug.print("\nbytes 3: {any}\n", .{shared.get(sid).?});
    std.debug.print("\nasType 2: {}\n", .{(try info.asType(TestVector, shared.get(sid).?)).*});

    try shared.destroy(sid);
}
