const Entities = @This();
const std = @import("std");
const Allocator = std.mem.Allocator;
const Types = @import("./Types.zig");
const Archetype = @import("./Archetype.zig");

pub const EntityPointer = struct { archetype_id: u32, row_index: usize };

pointers: std.AutoHashMapUnmanaged(u32, EntityPointer),
archetypes: std.AutoHashMapUnmanaged(u32, Archetype),
// shared: Blackboard,

// pub fn init(alloc: Allocator) !Entities {}
// pub fn deinit(self: *Entities) void {}

// pub fn create(self: *Entities) u32 {}
// pub fn destroy(self: *Entities, entity_id: u32) void {}

// has(self: *Entities, entity_id: u32) bool {}
// get(self: *Entities, entity_id: u32) ??? {}
// set(self: *Entities, entity_id: u32) void {}
// remove(self: *Entities, entity_id: u32) void {}

// hasShared(self: *Entities, entity_id: u32, shared_id: u32) bool
// setShared(self: *Entities, entity_id: u32, shared_id: u32) void
// removeShared(self: *Entities, entity_id: u32, shared_id: u32) void

// createSharedValue(self: *Entities, name: []const u8, ???) u32 {}
// getSharedValue(self: *Entities, shared_id: u32) []u8 {}
// setSharedValue(self: *Entities, shared_id: u32, ???) void {}
// destroySharedValue(self: *Entities, shared_id: u32) void {}

test "Entities" {}
