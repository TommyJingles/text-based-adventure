// pub fn main() !void {
//     const mod = Module.init("zecs_3d_transforms");

//     mod.addTypes(.{
//         .{ .name = "position", .type = Vec3 },
//         .{ .name = "rotation", .type = Vec3 },
//         .{ .name = "scale", .type = Vec3 },
//         .{ .name = "matrix", .type = Mat4x4 },
//         .{ .name = "parent", .type = EntityID },
//         .{ .name = "children", .type = []EntityID },
//     });
//     mod.addShared(.{
//         .{ .name = "chunk", .type = WorldChunk },
//     });
//     mod.addSystems(.{
//         .{ .name = "TransformUpdate", .type = TransformUpdate },
//     });
//     mod.events(.{
//         .{ .name = "TransformUpdate_CustomEvent" },
//     });

//     const types = Types.init(alloc);

//     const world = World.init(alloc, &types);
//     world.registerMod(mod);
// }
