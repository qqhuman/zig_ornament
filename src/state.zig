const Resolution = @import("util.zig").Resolution;

pub const State = struct {
    const Self = @This();
    resolution: Resolution,
    depth: u32,
    flip_y: bool,
    inverted_gamma: f32,
    iterations: u32,
    ray_cast_epsilon: f32,
    textures_count: u32,
    dirty: bool,

    pub fn init() Self {
        return .{
            .resolution = .{ .width = 500, .height = 500 },
            .depth = 10,
            .flip_y = false,
            .inverted_gamma = 1.0,
            .iterations = 1,
            .ray_cast_epsilon = 0.001,
            .textures_count = 0,
            .dirty = true,
        };
    }

    fn makeDirty(self: *Self) void {
        self.dirty = true;
    }

    pub fn setFlipY(self: *Self, flip_y: bool) void {
        self.flip_y = flip_y;
        self.makeDirty();
    }

    pub fn getFlipY(self: *const Self) bool {
        return self.flip_y;
    }

    pub fn setGamma(self: *Self, gamma: f32) void {
        self.inverted_gamma = 1.0 / gamma;
        self.makeDirty();
    }

    pub fn getGamma(self: *const Self) f32 {
        return 1.0 / self.inverted_gamma;
    }

    pub fn setDepth(self: *Self, depth: u32) void {
        self.depth = depth;
        self.makeDirty();
    }

    pub fn getDepth(self: *const Self) u32 {
        return self.depth;
    }

    pub fn setIterations(self: *Self, iterations: u32) void {
        self.iterations = iterations;
        self.makeDirty();
    }

    pub fn getIterations(self: *const Self) u32 {
        return self.iterations;
    }

    pub fn setResolution(self: *Self, resolution: Resolution) void {
        self.resolution = resolution;
        self.makeDirty();
    }

    pub fn getResolution(self: *const Self) Resolution {
        return self.resolution;
    }

    pub fn setRayCastEpsilon(self: *Self, ray_cast_epsilon: f32) void {
        self.ray_cast_epsilon = ray_cast_epsilon;
        self.makeDirty();
    }

    pub fn getRayCastEpsilon(self: *const Self) f32 {
        return self.ray_cast_epsilon;
    }

    pub fn setTexturesCount(self: *Self, count: u32) void {
        self.textures_count = count;
        self.makeDirty();
    }

    pub fn getTexturesCount(self: *const Self) u32 {
        return self.textures_count;
    }
};
