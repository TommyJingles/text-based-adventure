const std = @import("std");
const Type = @import("./Type.zig");
const Allocator = std.mem.Allocator;

const Column = @This();

// TODO: iterator
// TODO: #multithreading, lock per column?
typ: *const Type,
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
                // TODO: handle this better
                std.debug.panic("^ error: {}, column id: {}, index: {}, length: {}\n\n", .{ e, self.typ.id, i, length });
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
        if (byts.len != self.typ.size) return ColumnError.InvalidByteLen;
        start = self.bytes.items.len;
        end = start + self.typ.size;
        try self.bytes.appendSlice(alloc, byts);
    } else {
        start = self.bytes.items.len;
        end = start + self.typ.size;
        try self.bytes.resize(alloc, end);
        self.typ.dynamic.init(alloc, self.bytes.items[start..end]);
    }
    // std.debug.print("\nadd()   new l: {}, start: {}, end: {}, bytes: {any}, self.bytes.items.len: {}  value: {any}\n", .{ self.len(), start, end, bytes, self.bytes.items.len, self.bytes.items[start..end] });
}

// NOTE: caller should mind the component swapback
pub fn remove(self: *Column, alloc: Allocator, index: usize) !void {
    const length: usize = self.len();
    if (index > length) return ColumnError.InvalidRowIndex;

    self.typ.dynamic.deinit(alloc, try self.get(index));

    // std.debug.print("\nremove()    l: {}, i: {} where: ", .{ length, index });

    if (length == 1) { // the only component
        // std.debug.print("here 1\n", .{});
        self.bytes.shrinkAndFree(alloc, 0);
    } else if (index == length - 1) { // the last component of several
        // std.debug.print("here 2\n", .{});
        self.bytes.shrinkAndFree(alloc, self.bytes.items.len - self.typ.size);
    } else {
        // std.debug.print("here 3\n", .{});

        const remove_start: usize = index * self.typ.size;
        const remove_end: usize = remove_start + self.typ.size;
        const last_start: usize = self.bytes.items.len - self.typ.size;
        const last_end: usize = self.bytes.items.len;

        var remove_bytes = self.bytes.items[remove_start..remove_end];
        var last_bytes = self.bytes.items[last_start..last_end];

        std.mem.copyForwards(u8, remove_bytes, last_bytes);
        self.bytes.shrinkAndFree(alloc, self.bytes.items.len - self.typ.size);
    }
}

pub fn get(self: *Column, index: usize) ![]u8 {
    const length: usize = self.len();
    if (index > length - 1) return ColumnError.InvalidRowIndex;

    const start: usize = index * self.typ.size;
    const end: usize = start + self.typ.size;
    // std.debug.print("\nget()    l: {}, i: {}, s: {}, e: {}, bytes: {any}\n", .{ length, index, start, end, self.bytes.items[start..end] });
    return self.bytes.items[start..end];
}

pub fn set(self: *Column, alloc: Allocator, index: usize, bytes: []u8, deinit_old_value: bool) !void {
    const length: usize = self.len();
    if (index > length) return ColumnError.InvalidRowIndex;
    if (bytes.len != self.typ.size) return ColumnError.InvalidByteLen;

    const start: usize = index * self.typ.size;
    const end: usize = start + self.typ.size;

    var target_bytes = self.bytes.items[start..end];

    if (deinit_old_value) {
        self.typ.dynamic.deinit(alloc, target_bytes);
    }
    std.mem.copyForwards(u8, target_bytes, bytes);
    // std.debug.print("\nset()    l: {}, i: {}, s: {}, e: {}, deinit: {}, bytes: {any}\n", .{ length, index, start, end, deinit_old_value, bytes });
}

pub fn copy(self: *Column, alloc: Allocator, from_index: usize, to_index: usize, deinit_old_value: bool) !void {
    const length: usize = self.len();
    if (from_index > length or to_index > length) return ColumnError.InvalidRowIndex;
    if (from_index == to_index) return;

    const from_start: usize = from_index * self.typ.size;
    const from_end: usize = from_start + self.typ.size;
    const to_start: usize = to_index * self.typ.size;
    const to_end: usize = to_start + self.typ.size;

    var from_bytes = self.bytes.items[from_start..from_end];
    var to_bytes = self.bytes.items[to_start..to_end];

    if (deinit_old_value) {
        self.typ.dynamic.deinit(alloc, to_bytes);
    }

    std.mem.copyForwards(u8, to_bytes, from_bytes);
    // std.debug.print("\ncopy()    l: {}, fi: {}, fs: {}, fe: {}, ti: {}, ts: {}, te: {}, deinit: {}\n", .{ length, from_index, from_start, from_end, to_index, to_start, to_end, deinit_old_value });
}

pub fn len(self: *Column) usize {
    return self.bytes.items.len / self.typ.size;
}
