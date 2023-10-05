const std = @import("std");

pub const Texture = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    data: std.ArrayList(u8),
    width: u32,
    height: u32,
    num_components: u32,
    bytes_per_component: u32,
    bytes_per_row: u32,
    is_hdr: bool,
    gamma: f32,
    texture_id: ?u32 = null,

    pub fn init(
        allocator: std.mem.Allocator,
        data: []u8,
        width: u32,
        height: u32,
        num_components: u32,
        bytes_per_component: u32,
        is_hdr: bool,
        gamma: f32,
    ) !Self {
        const bytes_per_row = width * num_components * bytes_per_component;
        var self = Self{
            .allocator = allocator,
            .data = try std.ArrayList(u8).initCapacity(allocator, bytes_per_row * height),
            .width = width,
            .height = height,
            .num_components = num_components,
            .bytes_per_component = bytes_per_component,
            .bytes_per_row = bytes_per_row,
            .is_hdr = is_hdr,
            .gamma = gamma,
        };
        try self.data.appendSlice(data);
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.data.deinit();
    }
};
