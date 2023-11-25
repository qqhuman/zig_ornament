const std = @import("std");

pub const FpsCounter = struct {
    pub const Self = @This();
    timer: std.time.Timer,
    frames: u32,

    pub fn init() Self {
        return .{
            .frames = 0,
            .timer = std.time.Timer.start() catch unreachable,
        };
    }

    pub fn endFrames(self: *Self, frames: u32) void {
        self.frames += frames;
        const delta_time = @as(f64, @floatFromInt(self.timer.read())) / std.time.ns_per_s;
        if (delta_time > 1.0) {
            std.log.debug("FPS: {d}", .{@as(f64, @floatFromInt(self.frames)) / delta_time});
            self.frames = 0;
            self.timer.reset();
        }
    }
};
