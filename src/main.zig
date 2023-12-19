const std = @import("std");
const Player = @import("./player.zig").Player;
const Terminal = @import("./terminal.zig").Terminal;
const commands = @import("./commands.zig");
const ansi = @import("./ansi.zig");

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var allocator = gpa.allocator();

    var terminal = Terminal.init(allocator);
    defer terminal.deinit();

    terminal.max_inputs = 5;

    var play = true;
    while (play) {
        try terminal.write_input_prefix();
        const c = try terminal.read();
        var i: usize = 0;
        var cmd_found = false;
        for (commands.list) |cmd| {
            if (cmd.verify(&terminal)) {
                cmd_found = true;
                try cmd.run(&terminal);
                // temp cheating because i'm not passing 'game' state to fns yet
                // idk why I'm getting "extra capture in for loop" error with |cmd, i| syntax
                if (i == 0) {
                    play = false;
                }
            }
            i += 1;
        }
        if (!cmd_found) {
            // cheating again, for now
            if (std.mem.startsWith(u8, c, "help")) {
                for (commands.list) |cmd| {
                    try terminal.write(ansi.style.FgGreen);
                    try terminal.write(cmd.name);
                    try terminal.write("\t\t");
                    try terminal.write(ansi.style.FgYellow);
                    try terminal.write(cmd.desc);
                    try terminal.write(ansi.style.ResetAll);
                    try terminal.write("\n");
                    try terminal.flush();
                }
            } else {
                try terminal.write(ansi.style.FgRed);
                try terminal.write(ansi.style.Bold);
                try terminal.write("command not reconized. type 'help' for options.");
                try terminal.write(ansi.style.ResetAll);
                try terminal.flush();
            }
        }
    }
    try terminal.write_now(ansi.style.ResetAll, .{});
}
