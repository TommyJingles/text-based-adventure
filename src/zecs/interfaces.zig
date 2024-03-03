const std = @import("std");
const print = std.debug.print;

// This is our runtime interface. A simple struct.
pub const ISystem = struct {
    ptr: *anyopaque, // type-erased pointer to whatever implements this interface, could be anything
    run_ptr: *const fn (*anyopaque) void, // fn ptr to a 'relay' ISystem.run invokation. The fn casts 'ptr' to the correct type ptr, then invokes it's respective fn

    // a function to invoke the implementor's function through the 'relay' fn
    pub inline fn run(self: *ISystem) void {
        return self.run_ptr(self.ptr);
    }
};

// this is a type that implements our interface
pub const TestSystem = struct {
    name: []const u8,
    ref: *u32,
    val: u32 = 0,

    // this is the function we'd like to call from our interface
    pub fn run(self: *TestSystem) void {
        const before = self.ref.*;
        self.ref.* += self.val;
        std.debug.print("\nTestSystem.run() >> from name: {s}, before: {}, now: {}\n", .{ self.name, before, self.ref.* });
    }

    // this is our actual implementation of our interface
    pub fn iSystem(self: *TestSystem) ISystem {
        // Zig doesn't support inline functions directly. We need to wrap them in a utility struct.
        // could inline like this, but I find it ugly: ( struct { pub fn run(opaq) {...} } ).run
        const Mappings = struct {
            // our interface's 'relay' fn points to this, the actual definition of the 'relay' fn for this type
            pub fn run(opaq: *anyopaque) void {
                const imp: *TestSystem = @ptrCast(@alignCast(opaq));
                return imp.run();
            }
        };
        return ISystem{ .ptr = self, .run_ptr = Mappings.run };
    }
};

test "Interfaces" {
    const alloc = std.testing.allocator;
    var iSystemList = std.ArrayList(ISystem).init(alloc);
    defer iSystemList.deinit();

    // both implementor instances reference the same value to demonstrate all pointers are correct and there's no struct copying between fn calls
    var ref: u32 = 0;

    // create an implementor
    var sys1 = TestSystem{ .name = "sys 1", .ref = &ref, .val = 1 };
    // get the interface instance's implementation from the implementor
    try iSystemList.append(sys1.iSystem());

    var sys2 = TestSystem{ .name = "sys 2", .ref = &ref, .val = 2 };
    try iSystemList.append(sys2.iSystem());

    for (iSystemList.items) |*sys| {
        sys.run(); // invoke the interface fn to invoke the implementor function through the 'relay'
        // ISystem.run(*ISystem) -> ISystem.fn_ptr(ISystem.ptr) ==> TestSystem.iSystem.Mappings.run(ISystem.ptr) -> TestSystem.run(self)
    }
    print("\nref = {}\n", .{ref});
}
