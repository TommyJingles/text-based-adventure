const std = @import("std");

pub const Player = struct {
    first_name: []const u8 = undefined,
    last_name: []const u8 = undefined,

    pub fn setFirstName(self: *Player, first_name: []const u8) void {
        self.first_name = first_name;
    }
    pub fn setLastName(self: *Player, last_name: []const u8) void {
        self.last_name = last_name;
    }
};
