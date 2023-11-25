pub const std = @import("std");

pub const Resolution = struct {
    const Self = @This();
    width: u32,
    height: u32,

    pub fn pixel_count(self: *const Self) u32 {
        return self.width * self.height;
    }
};
