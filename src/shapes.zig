const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,
    // fns
};

pub const Mat2 = struct {
    data: [6]f32 = undefined,
    // fns
};

pub const Group = struct {};
pub const Point = struct {};
pub const Circle = struct { radius: f32 };
pub const Line = struct { end: Vec2 = Vec2{ .x = 0, .y = 0 } };
pub const Triangle = struct { points: [3]Vec2 };
pub const Rectangle = struct { dimensions: Vec2 };
pub const Polygon = struct { points: std.ArrayListUnmanaged(Vec2) };

pub const ShapeType = enum {
    Group,
    Point,
    Circle,
    Line,
    Triangle,
    Rectangle,
    Polygon,
};

pub const ShapeID = struct {
    typ: ShapeType,
    index: u32,
};

pub const Common = struct {
    id: ShapeID,
    mat: Mat2,
    parent: ?ShapeID,
    children: ?std.ArrayListUnmanaged(ShapeID),
};

pub const Shapes = struct {
    allocator: std.mem.Allocator,
    common_map: std.AutoArrayHashMapUnmanaged(ShapeID, Common),
    group_list: std.ArrayListUnmanaged(Group),
    group_list: std.ArrayListUnmanaged(Point),
    group_list: std.ArrayListUnmanaged(Circle),
    group_list: std.ArrayListUnmanaged(Line),
    group_list: std.ArrayListUnmanaged(Triangle),
    group_list: std.ArrayListUnmanaged(Rectangle),
    group_list: std.ArrayListUnmanaged(Polygon),
};
