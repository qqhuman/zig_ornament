const std = @import("std");
const c = @cImport({
    @cInclude("hip.h");
});

pub fn init() !void {
    std.log.debug("", .{});
    std.log.debug("[ornament] AMD ROCm HIP init", .{});
    c.run();
}
