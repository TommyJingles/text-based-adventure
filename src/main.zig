const std = @import("std");
const Terminal = @import("terminal.zig").Terminal;
const Player = @import("player.zig").Player;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var terminal = Terminal.init(allocator);
    defer terminal.deinit();

    try terminal.write("What is your first name? : ", .{});
    const fname = try terminal.read();
    try terminal.write("What is your first name? : ", .{});
    const lname = try terminal.read();

    var player = Player{ .first_name = fname, .last_name = lname };

    try terminal.write("Player: first_name = \"{s}\", last_name = \"{s}\"", player);
}
