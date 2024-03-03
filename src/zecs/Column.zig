const std = @import("std");
const Types = @import("./Types.zig");
const Allocator = std.mem.Allocator;

const Column = @This();

// TODO: iterator
// TODO: #multithreading, lock per column? spliterator?
info: *const Types.Info,
bytes: std.ArrayListUnmanaged(u8),

pub const ColumnError = error{ InvalidByteLen, InvalidRowIndex };

pub fn deinit(self: *Column, alloc: Allocator) void {
    if (self.bytes.items.len == 0) return;

    var length = self.len();
    // std.debug.print("\ndeinit() length: {}\n", .{length});

    if (length > 0) {
        var i = length - 1;
        while (true) {
            self.remove(alloc, i) catch |e| {
                std.debug.panic("^ ERROR: {}, column id: {}, index: {}, length: {}\n\n", .{ e, self.info.id, i, length });
            };
            if (i == 0) break;
            i -= 1;
        }
    }

    self.bytes.deinit(alloc);
}

pub fn add(self: *Column, alloc: Allocator, bytes: ?[]u8) !void {
    var start: usize = undefined;
    var end: usize = undefined;
    if (bytes) |byts| {
        if (byts.len != self.info.size) return ColumnError.InvalidByteLen;
        start = self.bytes.items.len;
        end = start + self.info.size;
        try self.bytes.appendSlice(alloc, byts);
    } else {
        start = self.bytes.items.len;
        end = start + self.info.size;
        try self.bytes.resize(alloc, end);
        self.info.dynamic.init(alloc, self.bytes.items[start..end]);
    }
    // std.debug.print("\nadd()   new l: {}, start: {}, end: {}, bytes: {any}, self.bytes.items.len: {}  value: {any}\n", .{ self.len(), start, end, bytes, self.bytes.items.len, self.bytes.items[start..end] });
}

// NOTE: caller should mind the component swapback
pub fn remove(self: *Column, alloc: Allocator, index: usize) !void {
    const length: usize = self.len();
    if (index > length) return ColumnError.InvalidRowIndex;

    self.info.dynamic.deinit(alloc, try self.get(index));

    // std.debug.print("\nremove()    l: {}, i: {} where: ", .{ length, index });

    if (length == 1) { // the only component
        // std.debug.print("here 1\n", .{});
        self.bytes.shrinkAndFree(alloc, 0);
    } else if (index == length - 1) { // the last component of several
        // std.debug.print("here 2\n", .{});
        self.bytes.shrinkAndFree(alloc, self.bytes.items.len - self.info.size);
    } else {
        // std.debug.print("here 3\n", .{});

        const remove_start: usize = index * self.info.size;
        const remove_end: usize = remove_start + self.info.size;
        const last_start: usize = self.bytes.items.len - self.info.size;
        const last_end: usize = self.bytes.items.len;

        var remove_bytes = self.bytes.items[remove_start..remove_end];
        var last_bytes = self.bytes.items[last_start..last_end];

        std.mem.copyForwards(u8, remove_bytes, last_bytes);
        self.bytes.shrinkAndFree(alloc, self.bytes.items.len - self.info.size);
    }
}

pub fn get(self: *Column, index: usize) ![]u8 {
    const length: usize = self.len();
    if (index > length - 1) return ColumnError.InvalidRowIndex;

    const start: usize = index * self.info.size;
    const end: usize = start + self.info.size;
    // std.debug.print("\nget()    l: {}, i: {}, s: {}, e: {}, bytes: {any}\n", .{ length, index, start, end, self.bytes.items[start..end] });
    return self.bytes.items[start..end];
}

pub fn set(self: *Column, alloc: Allocator, index: usize, bytes: []u8, deinit_old_value: bool) !void {
    const length: usize = self.len();
    if (index > length) return ColumnError.InvalidRowIndex;
    if (bytes.len != self.info.size) return ColumnError.InvalidByteLen;

    const start: usize = index * self.info.size;
    const end: usize = start + self.info.size;

    var target_bytes = self.bytes.items[start..end];

    if (deinit_old_value) {
        self.info.dynamic.deinit(alloc, target_bytes);
    }
    std.mem.copyForwards(u8, target_bytes, bytes);
    // std.debug.print("\nset()    l: {}, i: {}, s: {}, e: {}, deinit: {}, bytes: {any}\n", .{ length, index, start, end, deinit_old_value, bytes });
}

pub fn copy(self: *Column, alloc: Allocator, from_index: usize, to_index: usize, deinit_old_value: bool) !void {
    const length: usize = self.len();
    if (from_index > length or to_index > length) return ColumnError.InvalidRowIndex;
    if (from_index == to_index) return;

    const from_start: usize = from_index * self.info.size;
    const from_end: usize = from_start + self.info.size;
    const to_start: usize = to_index * self.info.size;
    const to_end: usize = to_start + self.info.size;

    var from_bytes = self.bytes.items[from_start..from_end];
    var to_bytes = self.bytes.items[to_start..to_end];

    if (deinit_old_value) {
        self.info.dynamic.deinit(alloc, to_bytes);
    }

    std.mem.copyForwards(u8, to_bytes, from_bytes);
    // std.debug.print("\ncopy()    l: {}, fi: {}, fs: {}, fe: {}, ti: {}, ts: {}, te: {}, deinit: {}\n", .{ length, from_index, from_start, from_end, to_index, to_start, to_end, deinit_old_value });
}

pub fn len(self: *Column) usize {
    return self.bytes.items.len / self.info.size;
}

test "column" {
    const TestVector = struct { x: u32 = 0, y: u32 = 0, z: u32 = 0 };

    var alloc = std.testing.allocator;
    var types = Types.init(alloc);
    defer types.deinit();

    var info_ptr = types.registerType(.{ .name = "My Vector", .type = TestVector });

    var list = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer list.deinit();

    var column = Column{ .info = info_ptr, .bytes = std.ArrayListUnmanaged(u8){} };
    defer column.deinit(alloc);

    var start_bytes = try alloc.alloc(u8, info_ptr.size);
    defer alloc.free(start_bytes);
    info_ptr.dynamic.init(alloc, start_bytes);

    try column.add(alloc, start_bytes);
    try column.add(alloc, null);
    try column.add(alloc, null);

    var bytes = try column.get(0);

    var seed_bytes_1 = std.mem.asBytes(&TestVector{ .x = 1, .y = 2, .z = 3 }).*;
    try column.set(alloc, 0, &seed_bytes_1, false);

    var seed_bytes_2 = std.mem.asBytes(&TestVector{ .x = 4, .y = 5, .z = 6 }).*;
    try column.set(alloc, 1, &seed_bytes_2, false);

    var concrete: *TestVector = @ptrCast(@alignCast(bytes.ptr));
    concrete.x = 5;
    concrete.y = 5;
    concrete.z = 5;

    try column.copy(alloc, 1, 0, true);

    try column.remove(alloc, 0);
}
