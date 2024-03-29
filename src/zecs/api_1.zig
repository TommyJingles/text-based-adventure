// pub fn main() !void {
//     const TestingModule = Module(.{
//         .name = "TestMod",
//         .components = .{
//             .{.name = "Level", .type = u32},
//             .{.name = "Value", .type = f32},
//             .{.name = "Name", .type = std.ArrayListUnmanaged(u8)},  // chance to override init, deinit, ... fns here
//         },
//         .shared = .{
//             .{.name = "Shared Key", .type = u32}
//         },
//         .systems = .{
//             .{ .name = "update", .group = "Testing Group", .after = "Some Group", .systems = .{
//                 .{.type = MySystem, .threading = .Wide},
//                 .{.type = OtherSystem, .threading = .Background,},
//                 .{.type = SyncSystem, .threading = .Main, .wait_for=.{OtherSystem}},
//             }},
//         }
//     });

//     const types = Types.init(alloc); // can be shared between worlds

//     try types.registerComponent(.{ .module = "Whatever", .name = "Level", .type = u32 }); // option to override dynamic fns here

//     const world = World.init(alloc, &types);
//     try world.registerModules(.{ TestingModule });

//     const mod = world.getMod("Testing");

//     const level_id = world.getMod("Testing").getComponent("level");

//     const entityID = try world.createEntity(.{
//         ComponentID(level_id, @as(u32, 123)),
//         Component("testMod", "Name", "Bob"),
//         SharedRef("Existing Shared Key"),
//         SharedValue("Shared Key", "new or override value"),
//     });

//     try world.set(entityID, .testMod, .value, @as(f32, 0.5));  // entity, mod enum, component enum, value

//     try world.setAll(entityID, .{
//         Component(.testMod, .Level, @as(u32, 555)),
//         Component(.testMod, .Name, "Bob"),
//     });

//     var num = try world.get(entityID, .Component, "Level", u32); // .ComponentRaw .Shared, .SharedRaw and []u8

//     const query = try world.Query(.All, .{ // .All could be a set of entities or archetypes? tuple order matters
//         .withComponents(.{ "Level", "Name" }),
//         .Shared(.{"Shared Key"}),
//         .Filter(callback),
//         .noneComponents(.{"Name"}),
//     });

//     var match = query.test(entityID);

//     var a_itr = query.archetypeIterator(alloc); // manual, Spliterator option?

//     while (a_itr.next()) |arch| {
//         if (arch.hasColumn("Unknown Key")) |col| {
//             // do archetype / column logic
//         }
//         var e_itr = arch.entityIterator(alloc);
//         while (e_itr.next()) |index| {
//             // do entity logic
//         }
//     }

//     // unsure how this would work exactly
//     // .Wide .Main .Parallel .Background -- how to schedule this logic, which thread
//     // .Entity is an enum which could be .Archetype -- what query iterator to use
//     world.jobs.Schedule(.Wide, .Entity, query, (struct{
//         pub fn run(self, ThreadInfo, QueryInfo) void {
//             // logic, errors must be handled here
//         }
//     }).run);
//     world.jobs.join();
// }
