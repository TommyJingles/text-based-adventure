const std = @import("std");
pub const hash = std.hash.Murmur3_32.hash;

pub const TypeID = struct { val: u32 };
pub const ArchID = struct { val: u32 };
pub const SharedID = struct { val: u32 };
pub const EntityID = struct { val: u32 };
