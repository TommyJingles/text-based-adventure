const std = @import("std");

// https://discord.com/channels/605571803288698900/1165773790068883517
pub extern "kernel32" fn SetConsoleOutputCP(
    wCodePageID: u32,
) callconv(@import("std").os.windows.WINAPI) bool;

pub const Terminal = struct {
    alloc: std.mem.Allocator,
    buffer: std.ArrayList(u8),
    writer: std.fs.File.Writer,
    reader: std.fs.File.Reader,

    pub fn init(alloc: std.mem.Allocator) Terminal {
        _ = SetConsoleOutputCP(65001);
        return Terminal{ .alloc = alloc, .buffer = std.ArrayList(u8).init(alloc), .writer = std.io.getStdOut().writer(), .reader = std.io.getStdIn().reader() };
    }

    pub fn deinit(self: *Terminal) void {
        self.buffer.deinit();
    }

    pub fn write(self: *Terminal, comptime fmt: []const u8, args: anytype) !void {
        try std.fmt.format(self.writer, fmt, args);
    }

    pub fn read(self: *Terminal) ![]const u8 {
        try self.buffer.resize(0);
        try self.reader.readUntilDelimiterArrayList(&self.buffer, '\n', 4096);
        return std.mem.trimRight(u8, self.buffer.items, "\r");
    }
};
