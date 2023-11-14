const c = @cImport({
    @cInclude("hip/hip_runtime.h");
});
const std = @import("std");
const ornament = @import("../ornament.zig");

pub const PathTracer = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    scene: ornament.Scene,

    pub fn init(allocator: std.mem.Allocator, scene: ornament.Scene) Self {
        return .{
            .allocator = allocator,
            .scene = scene,
        };
    }

    pub fn deinit(self: *Self) void {
        self.scene.deinit();
    }
};
