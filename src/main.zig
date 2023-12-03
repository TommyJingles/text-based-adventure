const std = @import("std");
const Terminal = @import("./terminal.zig").Terminal;
const ansi = @import("./ansi.zig");
const Player = @import("./player.zig").Player;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var terminal = Terminal.init(allocator);
    defer terminal.deinit();

    try terminal.write(ansi.style.ResetAll);
    try terminal.write("What is your ");
    try terminal.write(ansi.style.FgBlue);
    try terminal.write(ansi.style.Bold);
    try terminal.write("First Name");
    try terminal.write(ansi.style.ResetAll);
    try terminal.write(" : ");
    try terminal.write(ansi.style.FgGreen);
    try terminal.flush();
    _ = try terminal.read();

    try terminal.write(ansi.style.ResetAll);
    try terminal.write("What is your ");
    try terminal.write(ansi.style.FgBlue);
    try terminal.write(ansi.style.Bold);
    try terminal.write("Last Name");
    try terminal.write(ansi.style.ResetAll);
    try terminal.write(" : ");
    try terminal.write(ansi.style.FgGreen);
    try terminal.flush();
    _ = try terminal.read();

    try terminal.write(ansi.style.ResetAll);
    try terminal.dump_input();
}
