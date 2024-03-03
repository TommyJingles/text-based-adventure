//! These structs are ONLY meant for testing only.
//!  Thoughts:
//!    - how do slices and lists and the like get properly serialized?
//!    - I don't want "magic strings" used as component ids, typing
//!    - I can't do: pub const SomeType = u32, they both end up being u32
//!    - I could do SomeType = struct {value: u32}, but feels like bloat

const std = @import("std");
// const print = std.debug.print;
const Allocator = std.mem.Allocator;
const Types = @import("./Types.zig");

pub fn registerAllTypes(tm: *Types) void {
    _ = tm.register(Vec3);
    _ = tm.register(Name);
    _ = tm.register(UList);
    _ = tm.register(Position);
    _ = tm.register(Rotation);
    _ = tm.register(Scale);
    _ = tm.register(Parent);
    _ = tm.register(Children);
}

pub const Vec3 = struct {
    x: f32,
    y: f32,
    z: f32,
};

pub const Name = struct {
    value: std.ArrayList(u8),

    pub fn init(alloc: Allocator) Name {
        return .{
            .value = std.ArrayList(u8).init(alloc),
        };
    }
    pub fn deinit(self: *Name) void {
        self.value.deinit();
    }
};

pub const UList = struct {
    value: std.ArrayListUnmanaged(u8),
    pub fn init(alloc: Allocator) UList {
        _ = alloc;
        return .{ .value = std.ArrayListUnmanaged(u8){} };
    }
    pub fn deinit(self: *UList, alloc: Allocator) void {
        self.value.deinit(alloc);
    }
};

pub const Position = struct {
    value: Vec3 = Vec3{ .x = 0, .y = 0, .z = 0 },
};

pub const Rotation = struct {
    value: Vec3 = Vec3{ .x = 0, .y = 0, .z = 0 },
};

pub const Scale = struct {
    value: Vec3 = Vec3{ .x = 0, .y = 0, .z = 0 },
};

pub const Parent = struct {
    value: u32, // EntityID
};

pub const Children = struct {
    value: std.ArrayList(u32), // EntityIDs

    pub fn init(alloc: Allocator) Children {
        return Children{
            .value = std.ArrayList(u32).initCapacity(alloc, 1) catch unreachable,
        };
    }
    pub fn deinit(self: *Children) void {
        self.value.deinit();
    }
};
