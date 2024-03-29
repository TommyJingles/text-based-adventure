const std = @import("std");
const Alloc = std.testing.allocator;
const List = std.ArrayListUnmanaged;
const Map = std.HashMapUnmanaged;
const ID = @import("./ID.zig");
const Type = @import("./Type.zig");
const Column = @import("./Column.zig");

const Archetype = @This();

id: ID.Arch,
entity_ids: List(ID.Entity),
shared_ids: List(ID.Shared),
component_ids: List(ID.Type), // cached ids from column types, may not be ideal.
columns: Map(ID.Type, Column),

pub fn init() Archetype {}

pub fn deinit(self: *Archetype) void {
    _ = self;
}
