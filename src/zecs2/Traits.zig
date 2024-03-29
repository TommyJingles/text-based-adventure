const std = @import("std");
const print = std.debug.print;

pub fn hasTrait(comptime Type: type, comptime _trait: Trait) bool {
    if (@hasField(Type, _trait.name)) {
        inline for (std.meta.fields(Type)) |field| {
            if (std.mem.eql(u8, field.name, _trait.name)) {
                if (_trait.type == field.type) return true;
            }
        }
    } else if (@hasDecl(Type, _trait.name)) {
        const dt = @TypeOf(@field(Type, _trait.name));
        if (_trait.type == dt) return true;
    }
    return false;
}

pub inline fn hasTraits(comptime Type: type, comptime traits: anytype) bool {
    const traits_info = @typeInfo(@TypeOf(traits)).Struct;
    if (traits_info.is_tuple) {
        for (traits) |t| {
            if (hasTrait(Type, t) == false) return false;
        }
        return true;
    }
    return false;
}

pub const Trait = struct { name: []const u8, type: type };

fn someDuckFn(thing: anytype) void {
    comptime {
        const tuple = .{
            Trait{ .name = "my_field", .type = u32 },
            Trait{ .name = "myFunc", .type = fn ([]const u8) bool },
        };
        if (!hasTraits(@TypeOf(thing), tuple)) {
            @panic("someDucFn() 'thing' does not meet trait requirements");
        }
    }

    print("\ntype: {s}\tmy_field: {}\n", .{ @typeName(@TypeOf(thing)), thing.my_field });
}

const GoodStruct = struct {
    my_field: u32 = 123,

    pub fn myFunc(_: []const u8) bool {
        return true;
    }
};

const BadStruct = struct {
    my_field: f32 = 3.14,

    pub fn otherFunc(_: []const u8) void {}
};

test "traits_test" {
    var gs = GoodStruct{ .my_field = 111 };
    someDuckFn(gs);

    //var bs = BadStruct{ .my_field = 3.14 };
    //someDuckFn(bs);
}
