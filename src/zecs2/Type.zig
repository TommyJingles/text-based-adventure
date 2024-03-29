const std = @import("std");
const Alloc = std.mem.Allocator;
const List = std.ArrayListUnmanaged;
const Map = std.HashMapUnmanaged;
const ID = @import("./ID.zig");
const Traits = @import("./Traits.zig");
const Trait = Traits.Trait;
const Type = @This();

pub const TypeError = error{InvalidCast};

id: ID.Type,
mod: []const u8 = "DEFAULT",
name: []const u8,
size: usize,
alignment: u16,
dynamic: Dynamic,
print_ptr: *const fn (*Type, Alloc) anyerror![]u8,

pub fn init(comptime conf: Config) Type {
    return Type{
        // preserve formatting
        .id = ID.Type{ .val = std.hash.Murmur3_32.hash(conf.mod ++ "." ++ conf.name) },
        .mod = conf.mod,
        .name = conf.name,
        .size = @sizeOf(conf.type),
        .alignment = @sizeOf(conf.type),
        .dynamic = Dynamic{
            .init = CreateDynamicInit(conf),
            .deinit = CreateDynamicDeinit(conf),
            .print = CreateDynamicPrint(conf),
        },
        .print_ptr = CreateTypePrint(conf),
    };
}

pub fn deinit(self: *Type, alloc: Alloc) void {
    _ = self;
    _ = alloc;
}

pub fn print(self: *Type, alloc: Alloc) ![]u8 {
    return self.print_ptr(self, alloc);
}

pub fn CreateDynamicInit(comptime conf: Config) *const fn (Alloc, []u8) void {
    const InitFns = struct {
        pub fn init_no_alloc(_: Alloc, buffer: []u8) void {
            std.mem.copyForwards(u8, buffer, std.mem.asBytes(&conf.type.init()));
        }

        pub fn init_alloc(alloc: Alloc, buffer: []u8) void {
            std.mem.copyForwards(u8, buffer, std.mem.asBytes(&conf.type.init(alloc)));
        }

        pub fn init_default(alloc: Alloc, buffer: []u8) void {
            _ = alloc;
            std.mem.copyForwards(u8, buffer, std.mem.asBytes(&conf.type{}));
        }
    };
    if (conf.init) |init_fn| return init_fn;
    if (comptime Traits.hasTrait(conf.type, Trait{ .name = "init", .type = fn () conf.type })) return InitFns.init_no_alloc;
    if (comptime Traits.hasTrait(conf.type, Trait{ .name = "init", .type = fn (Alloc) conf.type })) return InitFns.init_alloc;
    return InitFns.init_default;
}

pub fn CreateDynamicDeinit(comptime conf: Config) *const fn (Alloc, []u8) void {
    const DeinitsFns = struct {
        pub fn deinit_alloc(alloc: Alloc, bytes: []u8) void {
            if (bytes.len == @sizeOf(conf.type)) {
                var val: *conf.type = @ptrCast(@alignCast(bytes.ptr));
                val.deinit(alloc);
            }
        }

        pub fn deinit_no_alloc(alloc: Alloc, bytes: []u8) void {
            _ = alloc;
            if (bytes.len == @sizeOf(conf.type)) {
                var val: *conf.type = @ptrCast(@alignCast(bytes.ptr));
                val.deinit();
            }
        }

        pub fn deinit_default(_: Alloc, _: []u8) void {}
    };

    if (conf.deinit) |deinit_fn| return deinit_fn;
    if (comptime Traits.hasTrait(conf.type, Trait{ .name = "deinit", .type = fn (*conf.type) void })) return DeinitsFns.deinit_no_alloc;
    if (comptime Traits.hasTrait(conf.type, Trait{ .name = "deinit", .type = fn (*conf.type, Alloc) void })) return DeinitsFns.deinit_alloc;
    return DeinitsFns.deinit_default;
}

pub fn CreateDynamicPrint(comptime conf: Config) *const fn (Alloc, []u8) anyerror![]u8 {
    return (struct {
        pub fn prnt(alloc: Alloc, bytes: []u8) anyerror![]u8 {
            var list = std.ArrayList(u8).init(alloc);
            defer list.deinit();
            var writer = list.writer();
            var value: *conf.type = @ptrCast(@alignCast(bytes.ptr));

            try writer.print("{s}.{s} <{s}> = {{\n", .{ conf.mod, conf.name, @typeName(conf.type) });

            const type_info: std.builtin.Type = @typeInfo(conf.type);

            inline for (type_info.Struct.fields, 0..) |field, i| {
                try writer.print("  {s}: {s}", .{ field.name, @typeName(field.type) });

                switch (@typeInfo(field.type)) {
                    .Struct => {
                        var v = @field(value, field.name);
                        const ValueType = @TypeOf(v);
                        if (ValueType == std.ArrayListAlignedUnmanaged(u8, null) or ValueType == std.ArrayListAligned(u8, null)) {
                            try writer.print(".items = \"{s}\"", .{v.items});
                        } else if (ValueType == []const u8 or ValueType == []u8) {
                            try writer.print(" = \"{s}\"", .{v});
                        } else {
                            try writer.print(" = {any}", .{v});
                        }
                    },
                    .Array => {
                        var v = @field(value, field.name);
                        const ValueType = @TypeOf(v);

                        if (ValueType == []const u8 or ValueType == []u8) {
                            try writer.print(" = \"{s}\"", .{v});
                        } else {
                            try writer.print(" = {any}", .{v});
                        }
                    },
                    .Pointer => {
                        var v = @field(value, field.name);
                        const ValueType = @TypeOf(v);

                        if (ValueType == []const u8 or ValueType == []u8) {
                            try writer.print(" = \"{s}\"", .{v});
                        } else {
                            try writer.print(" = {any}", .{v});
                        }
                    },
                    .Void => try writer.print(" = VOID", .{}),
                    else => try writer.print(" = {any}", .{@field(value, field.name)}),
                }
                if (i != type_info.Struct.fields.len) try writer.print(",", .{});
                try writer.print("\n", .{});
            }
            try writer.print("}}", .{});
            return try list.toOwnedSlice();
        }
    }).prnt;
}

pub fn CreateTypePrint(comptime conf: Config) *const fn (*Type, Alloc) anyerror![]u8 {
    return (struct {
        pub fn prnt(self: *Type, alloc: Alloc) anyerror![]u8 {
            var list = std.ArrayList(u8).init(alloc);
            defer list.deinit();
            var writer = list.writer();

            try writer.print(
                \\Type {{
                \\  id: {},
                \\  mod: {s},
                \\  name: {s},
                \\  type: {s},
                \\  size: {},
                \\  alignment: {},
                \\  dynamic: {{
                \\    init: {s},
                \\    deinit: {s},
                \\    print: {s}
                \\  }}
                \\}}
            , .{
                self.id,
                self.mod,
                self.name,
                @typeName(conf.type),
                self.size,
                self.alignment,
                @typeName(@TypeOf(self.dynamic.init)),
                @typeName(@TypeOf(self.dynamic.deinit)),
                @typeName(@TypeOf(self.dynamic.print)),
            });

            return try list.toOwnedSlice();
        }
    }).prnt;
}

/// cast a concrete type to a byte slice
pub fn asBytes(self: *Type, value_ptr: anytype) ![]u8 {
    var bytes: []u8 = @ptrCast(@alignCast(@constCast(std.mem.asBytes(value_ptr))));
    if (self.size == bytes.len) {
        return bytes;
    } else {
        return TypeError.InvalidCast;
    }
}

/// cast a byte slice to a pointer to a concrete type
pub fn asType(self: *Type, comptime T: type, value: []u8) !*T {
    if (self.size == value.len and value.len == @sizeOf(T)) {
        var casted_value: *T = @ptrCast(@alignCast(value.ptr));
        return casted_value;
    } else {
        return TypeError.InvalidCast;
    }
}

pub const Config = struct {
    type: type,
    name: []const u8,
    mod: []const u8 = "DEFAULT",
    // below are overrides for the procedural dynamic fns
    init: ?*const fn (Alloc) []u8 = null,
    deinit: ?*const fn (Alloc, []u8) void = null,
    print: ?*const fn (Alloc, []u8) []u8 = null,
};

/// A collection of functions to operate on a slice of bytes
pub const Dynamic = struct {
    /// fill the provided byte slice relative to a new type value
    init: *const fn (Alloc, []u8) void,

    /// given a byte slice, cast, deinit as needed
    deinit: *const fn (Alloc, []u8) void,

    /// given a byte slice, cast, deinit as needed
    print: *const fn (Alloc, []u8) anyerror![]u8,

    // serialize, deserialize, netPack, netUnpack
};
