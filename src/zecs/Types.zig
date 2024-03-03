const std = @import("std");
const Writer = std.io.Writer;
const Allocator = std.mem.Allocator;
const Traits = @import("./traits.zig");
const Trait = Traits.Trait;
const hash = std.hash.Murmur3_32.hash;
pub const TypeID = u32;

map: std.AutoHashMap(u32, Info),

pub fn init(alloc: Allocator) @This() {
    return .{
        .map = std.AutoHashMap(u32, Info).init(alloc),
    };
}

pub fn deinit(self: *@This()) void {
    self.map.deinit();
}

// unregisterType?

pub fn registerType(self: *@This(), comptime conf: Config) *Info {
    const id: u32 = hash(conf.name);
    if (self.map.contains(id)) {
        return self.map.getPtr(id).?;
    } else {
        var info = Info.init(conf);
        self.map.put(info.id, info) catch unreachable;
        return self.map.getPtr(info.id).?;
    }
}

pub fn getByName(self: *@This(), name: []const u8) ?*Info {
    var itr = self.map.valueIterator();
    while (itr.next()) |inf| {
        if (std.mem.eql(u8, inf.name, name)) {
            return inf;
        }
    }
    return null;
}

pub fn getByNamespace(self: *@This(), namespace: []const u8) ?*Info {
    var itr = self.map.valueIterator();
    while (itr.next()) |inf| {
        if (std.mem.eql(u8, inf.namespace, namespace)) {
            return inf;
        }
    }
    return null;
}

test "types" {
    const TestVector = struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };

    var alloc = std.testing.allocator;
    var types = @This().init(alloc);
    defer types.deinit();

    var info = types.registerType(.{ .name = "My Vector", .type = TestVector });

    var list = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer list.deinit();

    try info.print(&list);

    std.debug.assert(std.meta.eql(info, types.getByName("My Vector").?.*));
    std.debug.assert(std.meta.eql(info, types.getByNamespace("Types.test.types.TestVector").?.*));

    std.debug.print("\n{s}\n", .{list.items});
}

pub const Config = struct {
    name: []const u8,
    type: type,
    init: ?*const fn (Allocator) []u8 = null,
    deinit: ?*const fn (Allocator, []u8) void = null,
    print: ?*const fn (*Info, *std.ArrayList(u8), usize, []u8) void = null,
    // serialize, deserialize, netPack, netUnpack
};

pub const Info = struct {
    id: u32,
    name: []const u8,
    namespace: []const u8,
    size: usize,
    alignment: u16,
    // tags? fields -> {offset, type_id}?
    dynamic: DynamicFns,
    _print: *const fn (*Info, *std.ArrayList(u8)) anyerror!void,
    // _type: *const fn(*Info, comptime name: []const u8) type,

    pub const DynamicFns = struct {
        init: *const fn (Allocator, []u8) void,
        deinit: *const fn (Allocator, []u8) void,
        print: *const fn (*std.ArrayList(u8), usize, []u8) void,
        // serialize, deserialize, netPack, netUnpack
    };

    pub fn init(comptime conf: Config) Info {
        const info = Info{
            //preserve formatting
            .id = hash(conf.name),
            .name = conf.name,
            .namespace = @typeName(conf.type),
            .size = @sizeOf(conf.type),
            .alignment = @alignOf(conf.type),
            .dynamic = DynamicFns{
                .init = init_blk: {
                    const InitsStruct = struct {
                        pub fn init_no_alloc(_: Allocator, bytes: []u8) void {
                            std.mem.copyForwards(u8, bytes, std.mem.asBytes(&conf.type.init()));
                        }

                        pub fn init_alloc(alloc: Allocator, bytes: []u8) void {
                            std.mem.copyForwards(u8, bytes, std.mem.asBytes(&conf.type.init(alloc)));
                        }

                        pub fn init_default(_: Allocator, bytes: []u8) void {
                            std.mem.copyForwards(u8, bytes, std.mem.asBytes(&conf.type{}));
                        }
                    };
                    if (conf.init) |init_fn| {
                        break :init_blk init_fn;
                    } else if (comptime Traits.hasTrait(conf.type, Traits.Trait{ .name = "init", .type = fn () conf.type })) {
                        break :init_blk InitsStruct.init_no_alloc;
                    } else if (comptime Traits.hasTrait(conf.type, Traits.Trait{ .name = "init", .type = fn (Allocator) conf.type })) {
                        break :init_blk InitsStruct.init_alloc;
                    } else {
                        break :init_blk InitsStruct.init_default;
                    }
                },
                .deinit = deinit_blk: {
                    const DeinitsStruct = struct {
                        pub fn deinit_alloc(alloc: Allocator, bytes: []u8) void {
                            if (bytes.len == @sizeOf(conf.type)) {
                                var val: *conf.type = @ptrCast(@alignCast(bytes.ptr));
                                val.deinit(alloc);
                            }
                        }

                        pub fn deinit_no_alloc(alloc: Allocator, bytes: []u8) void {
                            _ = alloc;
                            if (bytes.len == @sizeOf(conf.type)) {
                                var val: *conf.type = @ptrCast(@alignCast(bytes.ptr));
                                val.deinit();
                            }
                        }

                        pub fn deinit_default(_: Allocator, _: []u8) void {}
                    };

                    if (conf.deinit) |deinit_fn| {
                        break :deinit_blk deinit_fn;
                    } else if (comptime Traits.hasTrait(conf.type, Traits.Trait{ .name = "deinit", .type = fn (*conf.type) void })) {
                        break :deinit_blk DeinitsStruct.deinit_no_alloc;
                    } else if (comptime Traits.hasTrait(conf.type, Traits.Trait{ .name = "deinit", .type = fn (*conf.type, Allocator) void })) {
                        break :deinit_blk DeinitsStruct.deinit_alloc;
                    } else {
                        break :deinit_blk DeinitsStruct.deinit_default;
                    }
                },
                .print = print_blk: {
                    if (conf.print) |print_fn| {
                        break :print_blk print_fn;
                    } else {
                        break :print_blk (struct {
                            pub fn prnt(list: *std.ArrayList(u8), indent: usize, bytes: []u8) void {
                                var writer = list.writer();
                                var value: *conf.type = @ptrCast(@alignCast(bytes.ptr));

                                list.appendNTimes(' ', indent * 2) catch unreachable;
                                writer.print("\"{s}\" = {{", .{conf.name}) catch unreachable;

                                const tti = @typeInfo(conf.type);
                                inline for (tti.Struct.fields) |f| {
                                    list.append('\n') catch unreachable;
                                    list.appendNTimes(' ', (indent + 1) * 2) catch unreachable;
                                    writer.print("{s}: {s}", .{ f.name, @typeName(f.type) }) catch unreachable;

                                    switch (@typeInfo(f.type)) {
                                        // switch on struct fields, print
                                        .Struct => {
                                            var v = @field(value, f.name);
                                            const ValueType = @TypeOf(v);
                                            // std.debug.print("###\tValueType -> {s}", .{@typeName(ValueType)});
                                            if (ValueType == std.ArrayListAlignedUnmanaged(u8, null) or ValueType == std.ArrayListAligned(u8, null)) {
                                                writer.print(".items = \"{s}\"", .{v.items}) catch unreachable;
                                            } else if (ValueType == []const u8 or ValueType == []u8) {
                                                writer.print(" = \"{s}\"", .{v}) catch unreachable;
                                            } else {
                                                writer.print(" = {any}", .{v}) catch unreachable;
                                            }
                                        },
                                        .Array => {
                                            var v = @field(value, f.name);
                                            const ValueType = @TypeOf(v);

                                            if (ValueType == []const u8 or ValueType == []u8) {
                                                writer.print(" = \"{s}\"", .{v}) catch unreachable;
                                            } else {
                                                writer.print(" = {any}", .{v}) catch unreachable;
                                            }
                                        },
                                        .Pointer => {
                                            var v = @field(value, f.name);
                                            const ValueType = @TypeOf(v);

                                            if (ValueType == []const u8 or ValueType == []u8) {
                                                writer.print(" = \"{s}\"", .{v}) catch unreachable;
                                            } else {
                                                writer.print(" = {any}", .{v}) catch unreachable;
                                            }
                                        },
                                        .Void => writer.print(" = NULL", .{}) catch unreachable,
                                        else => writer.print(" = {any}", .{@field(value, f.name)}) catch unreachable,
                                    }
                                }

                                list.append('\n') catch unreachable;
                                list.appendNTimes(' ', indent * 2) catch unreachable;
                                writer.print("}}", .{}) catch unreachable;
                            }
                        }).prnt;
                    }
                },
            },
            ._print = (struct {
                pub fn _print(self: *Info, list: *std.ArrayList(u8)) anyerror!void {
                    var w = list.writer();
                    try list.appendSlice("Info {\n");
                    try w.print("  id: {s} = {},\n", .{ @typeName(@TypeOf(self.id)), self.id });
                    try w.print("  name: {s} = \"{s}\",\n", .{ @typeName(@TypeOf(self.name)), self.name });
                    try w.print("  namespace: {s} = \"{s}\",\n", .{ @typeName(@TypeOf(self.namespace)), self.namespace });
                    try w.print("  size: {s} = {},\n", .{ @typeName(@TypeOf(self.size)), self.size });
                    try w.print("  alignment: {s} = {},\n", .{ @typeName(@TypeOf(self.alignment)), self.alignment });
                    try list.append('}');
                }
            })._print,
        };
        return info;
    }

    pub fn print(self: *Info, list: *std.ArrayList(u8)) !void {
        try self._print(self, list);
    }
};

test "Info" {
    const TestVector = struct { x: f32 = 0, y: f32 = 0, z: f32 = 0 };

    const NestedList = struct {
        list: std.ArrayList(u8),

        pub fn init(alloc: Allocator) @This() {
            return .{
                .list = std.ArrayList(u8).init(alloc),
            };
        }
        pub fn deinit(self: *@This()) void {
            self.list.deinit();
        }
    };

    const NestedListUnmanaged = struct {
        list: std.ArrayListUnmanaged(u8),

        pub fn init() @This() {
            return .{
                .list = std.ArrayListUnmanaged(u8){},
            };
        }
        pub fn deinit(self: *@This(), alloc: Allocator) void {
            self.list.deinit(alloc);
        }
    };

    var alloc = std.testing.allocator;

    var vec_info = Info.init(.{ .name = "my_vec", .type = TestVector });
    var list_info = Info.init(.{
        .name = "unmanaged_list",
        .type = std.ArrayListUnmanaged(u8),
        // procedural functions can be optionally replaced by user-written functions
        .deinit = (struct {
            pub fn deinit(alc: Allocator, bytes: []u8) void {
                if (bytes.len == @sizeOf(std.ArrayListUnmanaged(u8))) {
                    var val: *std.ArrayListUnmanaged(u8) = @ptrCast(@alignCast(bytes.ptr));
                    val.deinit(alc);
                }
            }
        }).deinit,
    });

    var nlist_info = Info.init(.{ .name = "nested_list", .type = NestedList });
    var nlistU_info = Info.init(.{ .name = "nested_list_unmanaged", .type = NestedListUnmanaged });

    var list = try std.ArrayList(u8).initCapacity(alloc, 1024);
    defer list.deinit();

    var vec_raw = try alloc.alloc(u8, vec_info.size);
    defer alloc.free(vec_raw);
    vec_info.dynamic.init(alloc, vec_raw);
    var vec_concrete: *TestVector = @ptrCast(@alignCast(vec_raw.ptr));
    vec_concrete.x = 1.5;
    vec_concrete.y = 2.5;
    vec_concrete.z = 3.5;
    vec_info.dynamic.print(&list, 0, vec_raw);
    defer vec_info.dynamic.deinit(alloc, vec_raw);

    var list_raw = try alloc.alloc(u8, list_info.size);
    defer alloc.free(list_raw);
    list_info.dynamic.init(alloc, list_raw);
    var list_concrete: *std.ArrayListUnmanaged(u8) = @ptrCast(@alignCast(list_raw.ptr));
    try list_concrete.appendSlice(alloc, "Welcome to the jungle!");
    try list.appendSlice("\n\n");
    list_info.dynamic.print(&list, 0, list_raw);
    list_info.dynamic.deinit(alloc, list_raw);

    var nlist_raw = try alloc.alloc(u8, nlist_info.size);
    defer alloc.free(nlist_raw);
    nlist_info.dynamic.init(alloc, nlist_raw);
    var nl_concrete: *NestedList = @ptrCast(@alignCast(nlist_raw.ptr));
    try nl_concrete.list.appendSlice("We got fun and games");
    try list.appendSlice("\n\n");
    nlist_info.dynamic.print(&list, 0, nlist_raw);
    nlist_info.dynamic.deinit(alloc, nlist_raw);

    var nlistU_raw = try alloc.alloc(u8, nlistU_info.size);
    defer alloc.free(nlistU_raw);
    nlistU_info.dynamic.init(alloc, nlistU_raw);
    var nlu_concrete: *NestedListUnmanaged = @ptrCast(@alignCast(nlistU_raw));
    try nlu_concrete.list.appendSlice(alloc, "We got everything you want");
    try list.appendSlice("\n\n");
    nlistU_info.dynamic.print(&list, 0, nlistU_raw);
    nlistU_info.dynamic.deinit(alloc, nlistU_raw);

    try list.appendSlice("\n\n");
    try list.appendSlice("~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~");
    try list.appendSlice("\n\n");
    try vec_info.print(&list);
    try list.appendSlice("\n\n");
    try list_info.print(&list);
    try list.appendSlice("\n\n");
    try nlist_info.print(&list);
    try list.appendSlice("\n\n");
    try nlistU_info.print(&list);

    std.debug.print("\n\n{s}\n\n", .{list.items});
}
