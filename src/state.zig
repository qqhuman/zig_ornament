const Resolution = @import("util.zig").Resolution;

pub const State = struct {
    const Self = @This();
    resolution: Resolution,
    depth: u32,
    flip_y: bool,
    inverted_gamma: f32,
    iterations: u32,
    ray_cast_epsilon: f32,
    current_iteration: f32,

    pub fn init() Self {
        return .{
            .resolution = .{ .width = 500, .height = 500 },
            .depth = 10,
            .flip_y = false,
            .inverted_gamma = 1.0,
            .iterations = 1,
            .ray_cast_epsilon = 0.001,
            .current_iteration = 0.0,
        };
    }

    pub fn setFlipY(self: *Self, flip_y: bool) void {
        self.flip_y = flip_y;
    }

    pub fn getFlipY(self: *const Self) bool {
        return self.flip_y;
    }

    pub fn setGamma(self: *Self, gamma: f32) void {
        self.inverted_gamma = 1.0 / gamma;
    }

    pub fn getGamma(self: *const Self) f32 {
        return 1.0 / self.inverted_gamma;
    }

    pub fn setDepth(self: *Self, depth: u32) void {
        self.depth = depth;
    }

    pub fn getDepth(self: *const Self) u32 {
        return self.depth;
    }

    pub fn setIterations(self: *Self, iterations: u32) void {
        self.iterations = iterations;
    }

    pub fn getIterations(self: *const Self) u32 {
        return self.iterations;
    }

    pub fn setResolution(self: *Self, resolution: Resolution) void {
        self.resolution = resolution;
    }

    pub fn getResolution(self: *const Self) Resolution {
        return self.resolution;
    }

    pub fn setRayCastEpsilon(self: *Self, ray_cast_epsilon: f32) void {
        self.ray_cast_epsilon = ray_cast_epsilon;
    }

    pub fn getRayCastEpsilon(self: *const Self) f32 {
        return self.ray_cast_epsilon;
    }

    pub fn nextIteration(self: *Self) void {
        self.current_iteration += 1.0;
    }

    pub fn reset(self: *Self) void {
        self.current_iteration = 0.0;
    }
};
