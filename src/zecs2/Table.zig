const Table = @This();

const std = @import("std");
const Alloc = std.mem.Allocator;
const RwLock = std.Thread.RwLock;

size: usize,
capacity: usize,
expand_rows: usize = 4,
row_size: usize,
column_sizes: []usize,
column_offsets: []usize,
data: []u8,
rwLock: RwLock = RwLock{}, // locks entire table

pub const TableError = error{ bytesSizeInvalid, columnIndexInvalid, rowIndexInvalid };

pub fn init(alloc: Alloc, column_sizes: []usize, initial_capacity: usize) !Table {
    const offsets = try alloc.alloc(usize, column_sizes.len);
    var current_offset: usize = 0;
    var row_size: usize = 0;
    for (column_sizes, 0..) |s, i| {
        row_size += s;
        offsets[i] = current_offset;
        current_offset += s * initial_capacity;
    }

    return Table{
        .size = 0,
        .capacity = initial_capacity,
        .row_size = row_size,
        .column_sizes = try alloc.dupe(usize, column_sizes),
        .column_offsets = offsets,
        .data = try alloc.alloc(u8, row_size * initial_capacity),
    };
}

pub fn deinit(self: *Table, alloc: Alloc) void {
    self.rwLock.lock();
    defer self.rwLock.unlock();
    alloc.free(self.column_sizes);
    alloc.free(self.column_offsets);
    alloc.free(self.data);
}

fn expandUnsafe(self: *Table, alloc: Alloc, num_rows: usize) !void {
    const new_capacity = self.capacity + num_rows;
    const new_data = try alloc.alloc(u8, new_capacity * self.row_size);
    var current_offset: usize = 0;

    for (self.column_sizes, self.column_offsets, 0..) |size, offset, i| {
        @memcpy(new_data[current_offset .. current_offset + self.size * size], self.data[offset .. offset + self.size * size]);
        self.column_offsets[i] = current_offset;
        current_offset += new_capacity * size;
    }

    alloc.free(self.data);
    self.data = new_data;

    self.capacity = new_capacity;
}

fn shrinkUnsafe(self: *Table, alloc: Alloc, num_rows: usize) !void {
    const new_capacity = self.capacity - num_rows;
    const new_data = try alloc.alloc(u8, new_capacity * self.row_size);
    var current_offset: usize = 0;

    for (self.column_sizes, self.column_offsets, 0..) |size, offset, i| {
        @memcpy(new_data[current_offset .. current_offset + self.size * size], self.data[offset .. offset + self.size * size]);
        self.column_offsets[i] = current_offset;
        current_offset += new_capacity * size;
    }

    alloc.free(self.data);
    self.data = new_data;

    self.capacity = new_capacity;
}

fn updateColumnOffsetsUnsafe(self: *Table) void {
    var current_offset: usize = 0;
    for (self.column_sizes, 0..) |s, i| {
        self.column_offsets[i] = current_offset;
        current_offset += s * self.capacity;
    }
}

// add a num_rows param
pub fn addRow(self: *Table, alloc: Alloc) !void {
    self.rwLock.lock();
    defer self.rwLock.unlock();

    if (self.size + 1 > self.capacity) try self.expandUnsafe(alloc, self.expand_rows);
    self.size += 1;
}

// add a num_rows param, or a slice or row_indicies
pub fn removeRow(self: *Table, row_index: usize, do_swapback: bool) !void {
    self.rwLock.lock();
    self.rwLock.unlock();

    if (self.size - 1 == row_index) {
        // clear removed cell value
        for (self.column_sizes, 0..) |_, i| {
            var cell = try self.getCellUnsafe(row_index, i);
            @memset(cell, 170); // or whatever the defaul u8 value is, 170?
        }
    } else if (do_swapback) {
        for (self.column_sizes, 0..) |_, i| {
            // set the 'removed' cell value to the last cell value
            try self.setCell(row_index, i, try self.getCellUnsafe(self.size - 1, i));
            // clear last cell value
            var cell = try self.getCellUnsafe(self.size - 1, i);
            @memset(cell, 170); // or whatever the defaul u8 value is, 170?
        }
    } else {
        for (self.column_sizes, 0..) |c_size, i| {
            // shift column bytes from next cell to column end 'up' by the size of the cell
            const offset = self.column_offsets[i] + (c_size * row_index);
            const col_end = offset + c_size * (self.size - 1);
            std.mem.copyForwards(u8, self.data[offset .. col_end - c_size], self.data[offset + c_size .. col_end]);
            // clear last cell value
            var cell = try self.getCellUnsafe(self.size - 1, i);
            @memset(cell, 170); // or whatever the defaul u8 value is, 170?
        }
    }
    self.size -= 1;
}

pub fn setCell(self: *Table, row_index: usize, column_index: usize, bytes: []u8) !void {
    self.rwLock.lock();
    defer self.rwLock.unlock();
    return try self.setCellUnsafe(row_index, column_index, bytes);
}

pub fn setCellUnsafe(self: *Table, row_index: usize, column_index: usize, bytes: []u8) !void {
    if (column_index >= self.column_sizes.len) return TableError.columnIndexInvalid;
    if (self.column_sizes[column_index] != bytes.len) return TableError.bytesSizeInvalid;
    if (row_index >= self.size) return TableError.rowIndexInvalid;

    const offset = self.column_offsets[column_index] + (self.column_sizes[column_index] * row_index);
    std.mem.copyForwards(u8, self.data[offset .. offset + bytes.len], bytes);
}

pub fn getCell(self: *Table, row_index: usize, column_index: usize) ![]u8 {
    self.rwLock.lock();
    defer self.rwLock.unlock();
    return try self.getCellUnsafe(row_index, column_index);
}

pub fn getCellUnsafe(self: *Table, row_index: usize, column_index: usize) ![]u8 {
    if (column_index >= self.column_sizes.len) return TableError.columnIndexInvalid;
    if (row_index >= self.size) return TableError.rowIndexInvalid;

    const offset = self.column_offsets[column_index] + (self.column_sizes[column_index] * row_index);
    return self.data[offset .. offset + self.column_sizes[column_index]];
}

fn print(self: *Table, w: anytype) !void {
    self.rwLock.lock();
    defer self.rwLock.unlock();

    _ = try w.write("Table {\n");
    try w.print("  .size = {},\n  .capacity = {},\n  .row_size = {},\n  .column_sizes = [\n", .{ self.size, self.capacity, self.row_size });
    for (self.column_sizes) |size| {
        _ = try w.print("    {},\n", .{size});
    }
    _ = try w.write("  ],\n  .column_offsets = [\n");
    for (self.column_offsets) |offset| {
        try w.print("    {},\n", .{offset});
    }
    _ = try w.print("  ],\n  .data.len = {},\n  .data = [\n", .{self.data.len});

    for (0..self.size) |row_index| {
        try w.print("    {} -> [", .{row_index});
        for (0..self.column_sizes.len) |column_index| {
            try w.print(" {}:{any}{s} ", .{ column_index, try self.getCellUnsafe(row_index, column_index), if (column_index != self.column_sizes.len - 1) "," else "" });
        }
        try w.print("]{s}\n", .{if (row_index != self.size - 1) "," else ""});
    }
    _ = try w.write("  ]\n}}\n");
}

test "grow_shrink" {
    const alloc = std.testing.allocator;
    var sizes = [_]usize{
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
    };
    var table = try Table.init(
        alloc,
        &sizes,
        4,
    );
    defer table.deinit(alloc);

    std.debug.assert(std.mem.eql(
        u8,
        table.data,
        &[_]u8{
            // capacity row 0  |  capacity row 1  |   capacity row 2   |  capacity row 3  |
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 0
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 1
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 2
        },
    ));

    table.rwLock.lock();
    try table.expandUnsafe(alloc, 2);
    table.rwLock.unlock();

    std.debug.assert(std.mem.eql(
        u8,
        table.data,
        &[_]u8{
            // capacity row 0  |  capacity row 1   |  capacity row 2   |  capacity row 3   |  capacity row 4   |  capacity row 5  |
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 0
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 1
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 2
        },
    ));

    table.rwLock.lock();
    try table.shrinkUnsafe(alloc, 3);
    table.rwLock.unlock();

    std.debug.assert(std.mem.eql(
        u8,
        table.data,
        &[_]u8{
            // capacity row 0  |  capacity row 1  |  capacity row 2  |
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 0
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 1
            170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, 170, // column 2
        },
    ));
}

test "addRow" {
    const alloc = std.testing.allocator;
    var sizes = [_]usize{
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
    };
    var table = try Table.init(
        alloc,
        &sizes,
        2,
    );
    defer table.deinit(alloc);

    try table.addRow(alloc);

    var b1: []u8 = @ptrCast(@alignCast(@constCast(std.mem.asBytes(&@as(u32, 1)))));
    try table.setCell(0, 0, b1);

    var b2: []u8 = @ptrCast(@alignCast(@constCast(std.mem.asBytes(&@as(u32, 2)))));
    try table.setCell(0, 1, b2);

    var b3: []u8 = @ptrCast(@alignCast(@constCast(std.mem.asBytes(&@as(u32, 3)))));
    try table.setCell(0, 2, b3);

    std.debug.assert(std.mem.eql(
        u8,
        table.data,
        &[_]u8{
            // row 0   |  capacity row 1  |
            1, 0, 0, 0, 170, 170, 170, 170, // column 0
            2, 0, 0, 0, 170, 170, 170, 170, // column 1
            3, 0, 0, 0, 170, 170, 170, 170, // column 2
        },
    ));
}

test "removeRow_swapback" {
    const alloc = std.testing.allocator;
    var sizes = [_]usize{
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
    };
    var table = try Table.init(
        alloc,
        &sizes,
        4,
    );
    defer table.deinit(alloc);

    try table.addRow(alloc);
    try table.addRow(alloc);
    try table.addRow(alloc);
    try table.addRow(alloc);

    // cell values
    var zeros = [_]u8{ 0, 0, 0, 0 };
    var ones = [_]u8{ 1, 1, 1, 1 };
    var twos = [_]u8{ 2, 2, 2, 2 };
    var threes = [_]u8{ 3, 3, 3, 3 };
    var fours = [_]u8{ 4, 4, 4, 4 };
    var fives = [_]u8{ 5, 5, 5, 5 };

    for (0..4) |row| {
        for (0..sizes.len) |col| {
            var bytes: []u8 = switch (row) {
                0 => &ones,
                1 => &twos,
                2 => &threes,
                3 => &fours,
                else => &zeros,
            };
            try table.setCell(row, col, bytes);
        }
    }

    try table.removeRow(1, true);

    try table.addRow(alloc);
    for (0..sizes.len) |col| {
        try table.setCell(3, col, &fives);
    }

    std.debug.assert(std.mem.eql(
        u8,
        table.data,
        &[_]u8{
            // row 0   |   row 1   |   row 2   |   row 3  |
            1, 1, 1, 1, 4, 4, 4, 4, 3, 3, 3, 3, 5, 5, 5, 5, // column 0
            1, 1, 1, 1, 4, 4, 4, 4, 3, 3, 3, 3, 5, 5, 5, 5, // column 1
            1, 1, 1, 1, 4, 4, 4, 4, 3, 3, 3, 3, 5, 5, 5, 5, // column 2
        },
    ));
}

test "removeRow_no_swapback" {
    const alloc = std.testing.allocator;
    var sizes = [_]usize{
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
        @as(usize, @sizeOf(u32)),
    };
    var table = try Table.init(
        alloc,
        &sizes,
        4,
    );
    defer table.deinit(alloc);

    try table.addRow(alloc);
    try table.addRow(alloc);
    try table.addRow(alloc);
    try table.addRow(alloc);

    var zeros = [_]u8{ 0, 0, 0, 0 };
    var ones = [_]u8{ 1, 1, 1, 1 };
    var twos = [_]u8{ 2, 2, 2, 2 };
    var threes = [_]u8{ 3, 3, 3, 3 };
    var fours = [_]u8{ 4, 4, 4, 4 };
    var fives = [_]u8{ 5, 5, 5, 5 };

    for (0..4) |row| {
        for (0..sizes.len) |col| {
            var bytes: []u8 = switch (row) {
                0 => &ones,
                1 => &twos,
                2 => &threes,
                3 => &fours,
                else => &zeros,
            };
            try table.setCell(row, col, bytes);
        }
    }

    try table.removeRow(1, false);

    try table.addRow(alloc);
    for (0..sizes.len) |col| {
        try table.setCell(3, col, &fives);
    }

    std.debug.assert(std.mem.eql(
        u8,
        table.data,
        &[_]u8{
            // row 0   |   row 1  |   row 2   |   row 3   |
            1, 1, 1, 1, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, // column 0
            1, 1, 1, 1, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, // column 1
            1, 1, 1, 1, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, // column 2
        },
    ));
}
