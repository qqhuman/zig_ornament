const std = @import("std");
const c = @cImport({
    @cInclude("webgpu.h");
});
const ComputeUnit = @import("compute_unit.zig").ComputeUnit;
const scene = @import("scene.zig");
const Scene = scene.Scene;

pub const Context = struct {
    state: State,
    scene: Scene,
    compute_unit: ComputeUnit,
    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, width: u32, height: u32, surface_descriptor: ?*c.WGPUSurfaceDescriptor) !Self {
        return .{ .state = State.init(width, height), .scene = Scene.init(), .compute_unit = try ComputeUnit.init(allocator, surface_descriptor) };
    }

    pub fn deinit(self: Self) void {
        self.scene.deinit();
        self.compute_unit.deinit();
    }

    pub fn setFlipY(self: *Self, flip_y: bool) void {
        self.state.setFlipY(flip_y);
    }

    pub fn getFlipY(self: Self) bool {
        return self.state.getFlipY();
    }

    pub fn setGamma(self: *Self, gamma: f32) void {
        self.state.setGamma(gamma);
    }

    pub fn getGamma(self: Self) f32 {
        return self.state.getGamma();
    }

    pub fn setDepth(self: *Self, depth: u32) void {
        self.state.setDepth(depth);
    }

    pub fn getDepth(self: Self) u32 {
        return self.state.getDepth();
    }

    pub fn setIterations(self: *Self, iterations: u32) void {
        self.state.setIterations(iterations);
    }

    pub fn getIterations(self: Self) u32 {
        return self.state.getIterations();
    }

    pub fn setResolution(self: *Self, width: u32, height: u32) void {
        self.state.setResolution(width, height);
    }

    pub fn getResolution(self: Self) struct { u32, u32 } {
        return self.state.getResolution();
    }

    pub fn setRayCastEpsilon(self: *Self, ray_cast_epsilon: f32) void {
        self.state.setRayCastEpsilon(ray_cast_epsilon);
    }

    pub fn getRayCastEpsilon(self: Self) f32 {
        return self.state.getRayCastEpsilon();
    }
};

const State = struct {
    width: u32,
    height: u32,
    depth: u32,
    flip_y: bool,
    inverted_gamma: f32,
    iterations: u32,
    ray_cast_epsilon: f32,
    dirty: bool = true,

    const Self = @This();

    pub fn init(width: u32, height: u32) Self {
        return .{
            .width = width,
            .height = height,
            .depth = 10,
            .flip_y = false,
            .inverted_gamma = 1.0,
            .iterations = 1,
            .ray_cast_epsilon = 0.001,
            .dirty = true,
        };
    }

    fn makeDirty(self: *Self) void {
        self.*.dirty = true;
    }

    pub fn setFlipY(self: *Self, flip_y: bool) void {
        self.flip_y = flip_y;
        self.makeDirty();
    }

    pub fn getFlipY(self: Self) bool {
        return self.flip_y;
    }

    pub fn setGamma(self: *Self, gamma: f32) void {
        self.inverted_gamma = 1.0 / gamma;
        self.makeDirty();
    }

    pub fn getGamma(self: Self) f32 {
        return 1.0 / self.inverted_gamma;
    }

    pub fn setDepth(self: *Self, depth: u32) void {
        self.depth = depth;
        self.makeDirty();
    }

    pub fn getDepth(self: Self) u32 {
        return self.depth;
    }

    pub fn setIterations(self: *Self, iterations: u32) void {
        self.iterations = iterations;
        self.makeDirty();
    }

    pub fn getIterations(self: Self) u32 {
        return self.iterations;
    }

    pub fn setResolution(self: *Self, width: u32, height: u32) void {
        self.width = width;
        self.height = height;
        self.makeDirty();
    }

    pub fn getResolution(self: Self) struct { u32, u32 } {
        return .{ self.width, self.height };
    }

    pub fn setRayCastEpsilon(self: *Self, ray_cast_epsilon: f32) void {
        self.ray_cast_epsilon = ray_cast_epsilon;
        self.makeDirty();
    }

    pub fn getRayCastEpsilon(self: Self) f32 {
        return self.ray_cast_epsilon;
    }
};
