const std = @import("std");
const Allocator = std.mem.Allocator;
const Types = @import("./Types.zig");
const Shared = @import("./Shared.zig");
const Archetype = @import("./Archetype.zig");
const TypeID = @import("./common.zig").TypeID;
const SharedID = @import("./common.zig").SharedID;
const ArchID = @import("./common.zig").ArchID;
const EntityID = @import("./common.zig").EntityID;
const Identity = Archetype.Identity;

const hash = std.hash.Murmur3_32.hash; // make a utils class, add id types in there too

const World = @This();

pub const WorldError = error{ InvalidTypeID, InvalidColumnID, InvalidSharedID, InvalidEntityID, InvalidArchetypeID };
pub const SharedEntry = struct { tid: TypeID, bytes: []u8 };
pub const EntityPointer = struct { aid: ArchID, row_index: usize };

alloc: Allocator,
id: u32,
name: []const u8,
types: *Types,
shared: std.AutoHashMapUnmanaged(SharedID, SharedEntry),
archetypes: std.AutoHashMapUnmanaged(ArchID, Archetype),
pointers: std.AutoHashMapUnmanaged(EntityID, EntityPointer),
// systems: std.AutoHashMapUnmanaged(SystemID, ISystem),
// events: std.AutoHashMapUnmanaged(EventID, Event),
next_id: EntityID = EntityID{ .val = 0 },

pub fn init(alloc: Allocator, name: []const u8, types: *Types) !World {
    var w = World{
        .alloc = alloc,
        .id = hash(name),
        .name = name,
        .types = types,
        .shared = std.AutoHashMapUnmanaged(SharedID, SharedEntry){},
        .archetypes = std.AutoHashMapUnmanaged(ArchID, Archetype){},
        .pointers = std.AutoHashMapUnmanaged(EntityID, EntityPointer){},
    };

    var identity = try Identity.init(alloc, null, null);
    defer identity.deinit();
    try w.archetypes.put(alloc, Archetype.VOID_ARCH_ID, try Archetype.init(alloc, types, &identity));

    return w;
}

pub fn deinit(self: *World) void {
    var shared_itr = self.shared.keyIterator();
    while (shared_itr.next()) |entry| {
        _ = entry;
        // self.destroySharedValue(entry);
    }
    self.shared.deinit(self.alloc);

    var arch_itr = self.archetypes.valueIterator();
    while (arch_itr.next()) |arch| {
        arch.deinit(self.alloc);
    }
    self.archetypes.deinit(self.alloc);

    self.pointers.deinit(self.alloc);
}

// pub fn queryArchetypes (self: *World) ??? {}

pub fn hasEntity(self: *World, eid: EntityID) bool {
    return self.pointers.contains(eid);
}

// need a way to recycle entity ids
pub fn createEntity(self: *World, identity: ?Archetype.Identity) !EntityID {
    var iden = if (identity) |idty| idty else try Archetype.Identity.init(self.alloc, null, null);
    var arch_id = iden.getID();

    var archetype: ?*Archetype = undefined;
    if (self.archetypes.getPtr(arch_id)) |existing_arch| {
        archetype = existing_arch;
    } else {
        try self.archetypes.put(self.alloc, arch_id, try Archetype.init(self.alloc, self.types, &iden));
        archetype = self.archetypes.getPtr(arch_id);
    }

    if (archetype) |arch| {
        var ri = try arch.add(self.alloc, self.next_id);
        try self.pointers.put(self.alloc, self.next_id, EntityPointer{ .aid = arch.id, .row_index = ri });

        defer self.next_id.val += 1;
        return self.next_id;
    } else {
        return WorldError.InvalidArchetypeID;
    }
}
pub fn destroyEntity(self: *World, eid: EntityID) !void {
    if (self.pointers.getPtr(eid)) |pointer| {
        if (self.archetypes.getPtr(pointer.aid)) |arch| {
            const swapback_eid = arch.entity_ids.getLastOrNull();
            if (swapback_eid) |seid| {
                if (try arch.remove(self.alloc, pointer.row_index)) |swapback_index| {
                    if (self.pointers.getPtr(seid)) |swap_pointer| {
                        swap_pointer.row_index = swapback_index;
                    }
                }
            }
        } else {
            return WorldError.InvalidArchetypeID;
        }
    } else {
        return WorldError.InvalidEntityID;
    }
}

/// this does a row copy only, no row deletion
fn copyComponents(self: *World, from_arch: *Archetype, from_index: usize, to_arch: *Archetype, to_index: usize, delete_old_value: bool) !void {
    var from_itr = from_arch.columns.keyIterator();
    while (from_itr.next()) |col_id| {
        if (to_arch.columns.contains(col_id.*)) {
            var from_bytes = from_arch.get(from_index, col_id.*);
            if (from_bytes) |bytes| {
                try to_arch.set(self.alloc, to_index, col_id.*, bytes, delete_old_value);
            }
        }
    }
}
// pub fn queryEntities (self: *World) ??? {}

pub fn hasComponent(self: *World, eid: EntityID, cid: TypeID) bool {
    if (self.types.get(cid)) |info| {
        if (self.pointers.getPtr(eid)) |pointer| {
            if (self.archetypes.getPtr(pointer.archetype_id)) |arch| {
                return arch.has(info.id);
            }
        }
    }
    return false;
}

pub fn getComponent(self: *World, eid: u32, cid: TypeID, T: type) !?*T {
    if (self.types.get(cid)) |info| {
        if (self.pointers.getPtr(eid)) |pointer| {
            if (self.archetypes.getPtr(pointer.archetype_id)) |arch| {
                var bytes = arch.get(pointer.row_index, info.id);
                if (bytes) |byts| {
                    return info.asTypePtr(T, byts);
                } else {
                    return null;
                }
            } else {
                return WorldError.InvalidArchetypeID;
            }
        } else {
            return WorldError.InvalidEntityID;
        }
    }
    return WorldError.InvalidTypeID;
}

pub fn getComponentRaw(self: *World, eid: u32, cid: TypeID) !?[]u8 {
    if (self.types.get(cid)) |info| {
        if (self.pointers.getPtr(eid)) |pointer| {
            if (self.archetypes.getPtr(pointer.archetype_id)) |arch| {
                return arch.get(pointer.row_index, info.id);
            } else {
                return WorldError.InvalidArchetypeID;
            }
        } else {
            return WorldError.InvalidEntityID;
        }
    }
    return WorldError.InvalidTypeID;
}

pub fn setComponentRaw(self: *World, eid: EntityID, cid: TypeID, bytes: []u8) !void {
    if (self.types.get(cid)) |info| {
        // get entity pointer
        if (self.pointers.getPtr(eid)) |pointer| {
            // get existing archetype
            if (self.archetypes.getPtr(pointer.archetype_id)) |current_arch| {
                if (current_arch.has(info.id)) {
                    // if existing archetype has column, business as usual
                    try current_arch.set(self.alloc, pointer.row_index, info.id, bytes, true);
                } else {
                    // figure out the destination archetype identity
                    var next_arch_identity = try Identity.fromArchetype(self.alloc, current_arch);
                    try next_arch_identity.addComponentID(info.id);
                    const next_arch_id = next_arch_identity.getID();

                    var next_arch: *Archetype = undefined;

                    // get existing archetype from computed identity, else create a new archetype
                    if (self.archetypes.getPtr(next_arch_id)) |found_arch| {
                        next_arch = found_arch;
                    } else {
                        try self.archetypes.put(self.alloc, next_arch_id, try Archetype.init(self.alloc, self.types, &next_arch_identity));
                        next_arch = self.archetypes.getPtr(next_arch_id).?;
                    }

                    // add existing entity to next archetype row
                    var new_ri = try next_arch.add(self.alloc, eid);

                    // set new component
                    try next_arch.set(self.alloc, new_ri, info.id, bytes, true);

                    // copy overlapping components
                    try self.copyComponents(current_arch, pointer.row_index, next_arch, new_ri, true);

                    // remove old row
                    var swap_eid = try current_arch.remove(self.alloc, pointer.row_index);

                    // swapback pointer if applicable
                    if (swap_eid) |seid| {
                        if (self.pointers.getPtr(seid)) |swap_pointer| {
                            swap_pointer.row_index = pointer.row_index;
                        }
                    }

                    // update entity pointer
                    pointer.archetype_id = next_arch.id;
                    pointer.row_index = new_ri;
                }
            } else {
                return WorldError.InvalidArchetypeID;
            }
        } else {
            return WorldError.InvalidEntityID;
        }
    }
    return WorldError.InvalidTypeID;
}
pub fn removeComponent(self: *World, eid: u32, cid: TypeID) !void {
    if (self.types.get(cid)) |info| {
        // get entity pointer
        if (self.pointers.getPtr(eid)) |pointer| {
            // get existing archetype
            if (self.archetypes.getPtr(pointer.archetype_id)) |current_arch| {
                // figure out the destination archetype identity
                var next_arch_identity = try Identity.fromArchetype(self.alloc, current_arch);
                try next_arch_identity.removeComponentID(info.id);
                var next_arch_id = next_arch_identity.getID();

                var next_arch: *Archetype = undefined;

                // get existing archetype from computed identity, else create a new archetype
                if (self.archetypes.getPtr(next_arch_id)) |found_arch| {
                    next_arch = found_arch;
                } else {
                    try self.archetypes.put(self.alloc, next_arch_id, try Archetype.init(self.alloc, self.types, &next_arch_identity));
                    next_arch = self.archetypes.getPtr(next_arch_id).?;
                }

                // add existing entity to next archetype row
                var new_ri = try next_arch.add(self.alloc, eid);

                // copy overlapping components
                try self.copyComponents(current_arch, pointer.row_index, next_arch, new_ri, true);

                // remove old row
                var swap_eid = try current_arch.remove(self.alloc, pointer.row_index);

                // swapback pointer if applicable
                if (swap_eid) |seid| {
                    if (self.pointers.getPtr(seid)) |swap_pointer| {
                        swap_pointer.row_index = pointer.row_index;
                    }
                }

                // update entity pointer
                pointer.archetype_id = next_arch.id;
                pointer.row_index = new_ri;
            }
        } else {
            return WorldError.InvalidEntityID;
        }
    }
    return WorldError.InvalidTypeID;
}

// // ... System, Event

test "entity_create_destroy" {
    var alloc = std.testing.allocator;

    var types = Types.init(alloc);
    defer types.deinit();

    var w = try World.init(alloc, "test world", &types);
    defer w.deinit();

    var eid = try w.createEntity(null);
    try w.destroyEntity(eid);
}

test "entity_components_raw" {
    var alloc = std.testing.allocator;

    var types = Types.init(alloc);
    defer types.deinit();

    var name_info = types.registerType(.{ .name = "Name", .type = std.ArrayListUnmanaged(u8) });

    var w = try World.init(alloc, "test world", &types);
    defer w.deinit();

    var eid = try w.createEntity(null);

    std.debug.assert(w.hasComponent(eid, name_info.id) == false);

    var name = std.ArrayListUnmanaged(u8){};
    defer name.deinit(alloc);

    try w.setComponentRaw(eid, name_info.id, try name_info.asBytes(&name));

    var comp = try w.getComponentRaw(eid, name_info.id);
    var name_component = try name_info.asType(std.ArrayListUnmanaged(u8), comp.?);

    try name_component.appendSlice(alloc, "Hello World!");

    try w.removeComponent(eid, name_info);
}
