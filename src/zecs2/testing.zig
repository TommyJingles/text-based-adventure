const std = @import("std");
const print = std.debug.print;
const Type = @import("./Type.zig");
const Column = @import("./Column.zig");

// default values are needed for the Type.dynamic.init
// TODO: procedurally check if default values apply, otherewise init with zeros? Maybe *anyopaque param list?
const Vec3 = struct { x: u32 = 0, y: u32 = 0, z: u32 = 0 };

test "builtin.Type" {
    const printInfo = (struct {
        pub fn printInfo(comptime T: type) void {
            switch (@typeInfo(T)) {
                .Type => |e| std.debug.print("\n{s}     U: .Type\n{any}\n", .{ @typeName(T), e }),
                .Void => |e| std.debug.print("\n{s}     U: .Void\n{any}\n", .{ @typeName(T), e }),
                .Bool => |e| std.debug.print("\n{s}     U: .Bool\n{any}\n", .{ @typeName(T), e }),
                .NoReturn => |e| std.debug.print("\n{s}     U: .NoReturn\n{any}\n", .{ @typeName(T), e }),
                .Int => |e| std.debug.print("\n{s}     U: .Int\n{any}\n", .{ @typeName(T), e }),
                .Float => |e| std.debug.print("\n{s}     U: .Float\n{any}\n", .{ @typeName(T), e }),
                .Pointer => |e| std.debug.print("\n{s}     U: .Pointer\n{any}\n", .{ @typeName(T), e }),
                .Array => |e| std.debug.print("\n{s}     U: .Array\n{any}\n", .{ @typeName(T), e }),
                .Struct => |e| {
                    std.debug.print("\n{s}     U: .Struct\n", .{@typeName(T)});
                    std.debug.print("{s} {{ .layout = {}, .backing_integer = {?}, ", .{ @typeName(@TypeOf(e)), e.layout, e.backing_integer });
                    std.debug.print(".fields: {{", .{});
                    inline for (e.fields, 0..) |field, i| {
                        std.debug.print(" {s}: {s}{s}", .{ field.name, @typeName(field.type), if (i != e.fields.len - 1) "," else "" });
                    }

                    std.debug.print(" }}, .is_tuple = {} }}\n", .{e.is_tuple});
                },
                .ComptimeFloat => |e| std.debug.print("\n{s}     U: .ComptimeFloat\n{any}\n", .{ @typeName(T), e }),
                .ComptimeInt => |e| std.debug.print("\n{s}     U: .ComptimeInt\n{any}\n", .{ @typeName(T), e }),
                .Undefined => |e| std.debug.print("\n{s}     U: .Undefined\n{any}\n", .{ @typeName(T), e }),
                .Null => |e| std.debug.print("\n{s}     U: .Null\n{any}\n", .{ @typeName(T), e }),
                .Optional => |e| std.debug.print("\n{s}     U: .Optional\n{any}\n", .{ @typeName(T), e }),
                .ErrorUnion => |e| std.debug.print("\n{s}     U: .ErrorUnion\n{any}\n", .{ @typeName(T), e }),
                .ErrorSet => |e| std.debug.print("\n{s}     U: .ErrorSet\n{any}\n", .{ @typeName(T), e }),
                .Enum => |e| std.debug.print("\n{s}     U: .Enum\n{any}\n", .{ @typeName(T), e }),
                .Union => |e| std.debug.print("\n{s}     U: .Union\n{any}\n", .{ @typeName(T), e }),
                .Fn => |e| std.debug.print("\n{s}     U: .Fn\n{any}\n", .{ @typeName(T), e }),
                .Opaque => |e| std.debug.print("\n{s}     U: .Opaque\n{any}\n", .{ @typeName(T), e }),
                .Frame => |e| std.debug.print("\n{s}     U: .Frame\n{any}\n", .{ @typeName(T), e }),
                .AnyFrame => |e| std.debug.print("\n{s}     U: .AnyFrame\n{any}\n", .{ @typeName(T), e }),
                .Vector => |e| std.debug.print("\n{s}     U: .Vector\n{any}\n", .{ @typeName(T), e }),
                .EnumLiteral => |e| std.debug.print("\n{s}     U: .EnumLiteral\n{any}\n", .{ @typeName(T), e }),
            }
        }
    }).printInfo;

    std.debug.print("\n\n~~~   Pointers   ~~~\n", .{});
    // printInfo(*u8);
    printInfo([]u8);
    // printInfo([]const u8);
    // printInfo([*]u8);
    // printInfo([:0]u8);
    // printInfo(*const fn (std.mem.Allocator, []u8) anyerror!void);

    std.debug.print("\n\n~~~   Arrays   ~~~\n", .{});
    printInfo([32]u8);
    printInfo([32:0]u8);

    std.debug.print("\n\n~~~   std collections   ~~~\n", .{});
    printInfo(std.ArrayListUnmanaged(u8));
    printInfo(std.AutoHashMapUnmanaged(u32, u32));
    printInfo(std.ArrayListUnmanaged(void));

    std.debug.print("\n\n~~~   sdtd atomic / thread   ~~~\n", .{});
    printInfo(std.atomic.Atomic(u32));
    printInfo(std.Thread.Mutex);

    std.debug.print("\n\n~~~   Integers   ~~~\n", .{});
    // printInfo(u1);
    // printInfo(u8);
    // printInfo(i16);
    printInfo(u32);

    std.debug.print("\n\n~~~   Floats   ~~~\n", .{});
    printInfo(f32);
    // printInfo(f64);

    std.debug.print("\n\n~~~   Structs   ~~~\n", .{});
    printInfo(Vec3);
    printInfo(struct { a: u8 });

    std.debug.print("\n\n~~~   Tuple   ~~~\n\n", .{});
    printInfo(@TypeOf(.{ 1, 2.3, "four" }));
    printInfo(@TypeOf(.{ .key = "value" }));

    // std.debug.print("\n\n~~~   Other   ~~~\n\n", .{});
    // printInfo(void);
    // printInfo(@TypeOf({}));
    // printInfo(@TypeOf(null));
    // printInfo(@TypeOf(undefined));

    std.debug.print("\n", .{});
}

test "Type" {
    const alloc = std.testing.allocator;
    var typ = Type.init(.{ .name = "Position", .type = Vec3 });
    const out = try typ.print(alloc);
    defer alloc.free(out);
    print("\n{s}\n", .{out});

    const v_out = try typ.dynamic.print(alloc, try typ.asBytes(&Vec3{ .x = 1, .y = 2, .z = 3 }));
    defer alloc.free(v_out);
    print("\n{s}\n", .{v_out});
}

test "Column" {
    const List = std.ArrayListUnmanaged;
    const alloc = std.testing.allocator;

    // simple struct
    var typ = Type.init(.{ .name = "Position", .type = Vec3 });

    var column = Column{ .typ = &typ, .bytes = try List(u8).initCapacity(alloc, typ.size) };
    defer column.deinit(alloc);

    try column.add(alloc, try typ.asBytes(&Vec3{}));
    try column.add(alloc, try typ.asBytes(&Vec3{ .x = 1, .y = 2, .z = 3 }));
    try column.remove(alloc, 0);

    // unmanaged list
    var typ2 = Type.init(.{ .name = "List", .type = List(u8) });

    var column2 = Column{ .typ = &typ2, .bytes = try List(u8).initCapacity(alloc, typ2.size) };
    defer column2.deinit(alloc);

    try column2.add(alloc, null);
    var l1 = try typ2.asType(List(u8), try column2.get(0));
    try l1.appendSlice(alloc, "Hello World");

    try column2.add(alloc, null);
    var l2 = try typ2.asType(List(u8), try column2.get(1));
    try l2.appendSlice(alloc, "Goodbye World");

    try column2.remove(alloc, 0);
    var l3 = try typ2.asType(List(u8), try column2.get(0));
    print("l3.items: {s}\n", .{l3.items});

    // slices
    var typ3 = Type.init(.{ .name = "Slice", .type = []const u8 });
    var out = try typ3.print(alloc);

    defer alloc.free(out);
    print("\n{s}\n", .{&out});
}
