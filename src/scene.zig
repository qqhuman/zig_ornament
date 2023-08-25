pub const Scene = struct {
    const Self = @This();

    pub fn init() Self {
        return .{};
    }

    pub fn deinit(self: Self) void {
        _ = self;
    }
};
