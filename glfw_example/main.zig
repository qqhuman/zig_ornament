pub fn main() !void {
    //try @import("app_wgpu_interop.zig").run();
    try @import("app_no_interop.zig").run();
}
