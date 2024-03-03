const std = @import("std");
const Terminal = @import("./terminal.zig").Terminal;
const ansi = @import("./ansi.zig");

pub const Command = struct {
    name: []const u8,
    desc: []const u8,
    verify: *const fn (terminal: *Terminal) bool,
    run: *const fn (terminal: *Terminal) anyerror!void,
};

pub const list = [_]Command{
    Command{
        .name = "exit",
        .desc = "application exists and returns to normal terminal flow",
        .verify = (struct {
            pub fn verify(terminal: *Terminal) bool {
                const cmd = terminal.input.getLast();
                return std.mem.startsWith(u8, cmd.items, "exit");
            }
        }).verify,
        .run = (struct {
            pub fn run(terminal: *Terminal) !void {
                _ = terminal;
            }
        }).run,
    },
    Command{
        .name = "help",
        .desc = "list available commands",
        .verify = (struct {
            pub fn verify(terminal: *Terminal) bool {
                _ = terminal;
                return false;
            }
        }).verify,
        .run = (struct {
            pub fn run(terminal: *Terminal) !void {
                _ = terminal;
            }
        }).run,
    },
    Command{
        .name = "history",
        .desc = "displays command history",
        .verify = (struct {
            pub fn verify(terminal: *Terminal) bool {
                const cmd = terminal.input.getLast();
                return std.mem.startsWith(u8, cmd.items, "history");
            }
        }).verify,
        .run = (struct {
            pub fn run(terminal: *Terminal) !void {
                try terminal.write(ansi.style.ResetAll);
                try terminal.write(ansi.style.FgYellow);
                try terminal.write_input_history();
                try terminal.write(ansi.style.ResetAll);
                try terminal.flush();
            }
        }).run,
    },
    Command{
        .name = "test",
        .desc = "displays a test output",
        .verify = (struct {
            pub fn verify(terminal: *Terminal) bool {
                const cmd = terminal.input.getLast();
                return std.mem.startsWith(u8, cmd.items, "test");
            }
        }).verify,
        .run = (struct {
            pub fn run(terminal: *Terminal) !void {
                try terminal.write(ansi.style.ResetAll);
                try terminal.write(ansi.style.Encircled);
                try terminal.write(ansi.style.FgRed);
                try terminal.write(ansi.style.BlinkFast);
                try terminal.write("hello world!");
                try terminal.write(ansi.style.ResetAll);
                try terminal.flush();
            }
        }).run,
    },
};
