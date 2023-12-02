const std = @import("std");

pub const Player = struct {
    first_name: []const u8,
    last_name: []const u8,

    pub fn init(first_name: []const u8, last_name: []const u8) Player {
        return Player{ .first_name = first_name, .last_name = last_name };
    }
};
