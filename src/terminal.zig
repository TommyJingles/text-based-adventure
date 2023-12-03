const std = @import("std");
const ansi = @import("./ansi.zig");

// https://discord.com/channels/605571803288698900/1165773790068883517
pub extern "kernel32" fn SetConsoleOutputCP(
    wCodePageID: u32,
) callconv(@import("std").os.windows.WINAPI) bool;

pub const Terminal = struct {
    alloc: std.mem.Allocator,
    in_buf: std.ArrayList(u8),
    writer: std.fs.File.Writer,
    out_buf: std.ArrayList(u8),
    reader: std.fs.File.Reader,
    input: std.ArrayList(std.ArrayList(u8)),
    max_inputs: usize = 3,

    pub fn init(alloc: std.mem.Allocator) Terminal {
        // configs output to accept unicode
        _ = SetConsoleOutputCP(65001);

        return Terminal{
            .alloc = alloc,
            .in_buf = std.ArrayList(u8).init(alloc),
            .writer = std.io.getStdOut().writer(),
            .out_buf = std.ArrayList(u8).init(alloc),
            .reader = std.io.getStdIn().reader(),
            .input = std.ArrayList(std.ArrayList(u8)).init(alloc),
        };
    }

    pub fn deinit(self: *Terminal) void {
        self.in_buf.deinit();
        for (self.input.items) |str| {
            str.deinit();
        }
        self.input.deinit();
    }

    pub fn write(self: *Terminal, str: []const u8) !void {
        try self.out_buf.writer().writeAll(str);
    }

    pub fn write_fmt(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        try std.fmt.format(self.out_buf.writer(), fmt, args);
    }

    pub fn write_now(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        try std.fmt.format(self.writer, fmt, args);
    }

    pub fn flush(self: *Terminal) !void {
        try self.writer.writeAll(self.out_buf.items);
        try self.out_buf.resize(0);
    }

    pub fn read(self: *Terminal) ![]const u8 {
        try self.in_buf.resize(0);
        try self.reader.readUntilDelimiterArrayList(&self.in_buf, '\n', 4096);
        const slice = std.mem.trimRight(u8, self.in_buf.items, "\r");
        var str = try std.ArrayList(u8).initCapacity(self.alloc, slice.len);
        if (self.input.items.len > 0 and self.input.items.len >= self.max_inputs) {
            _ = self.input.orderedRemove(0);
        }
        try str.appendSlice(slice);
        try self.input.append(str);
        return str.items;
    }
    pub fn write_input_history(self: *Terminal) !void {
        var i: usize = 0;
        try self.write_fmt("\n------ INPUT HISTORY [max lines: {}] ------", .{self.max_inputs});
        for (self.input.items) |str| {
            try self.write_fmt("\n{}:   {s}", .{ i, str.items });
            i += 1;
        }
    }
    pub fn write_input_prefix(self: *Terminal) !void {
        try self.write(ansi.style.ResetAll);
        try self.write(ansi.style.FgBlue);
        try self.write("\ncommand");
        try self.write(ansi.style.FgWhite);
        try self.write(": ");
        try self.write(ansi.style.FgGreen);
        try self.flush();
    }
};
