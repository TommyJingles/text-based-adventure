const std = @import("std");

test "json test" {
    // https://www.huy.rocks/everyday/01-09-2022-zig-json-in-5-minutes
    // https://ziggit.dev/t/resources-for-parsing-json-strings/1276/7

    const json =
        \\ {
        \\   "a": 15, "b": true,
        \\   "c": "hello world",
        \\   "d": [{"e": "hit!"}]
        \\ }
    ;

    const parsed = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json, .{});
    defer parsed.deinit();

    std.debug.print("\n", .{});
    parsed.value.dump();

    const root = parsed.value.object;

    std.debug.print("\nroot.a = {}", .{root.get("a").?.integer});
    std.debug.print("\nroot.b = {}", .{root.get("b").?.bool});
    std.debug.print("\nroot.c = {s}", .{root.get("c").?.string});
    std.debug.print("\nroot.d = {}", .{root.get("d").?.array});
    std.debug.print("\nroot.d.e = {s}", .{root.get("d").?.array.items[0].object.get("e").?.string});

    std.debug.print("\n", .{});
}
