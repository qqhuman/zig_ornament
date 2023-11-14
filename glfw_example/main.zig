pub fn main() !void {
    //try @import("app_wgpu_path_tracer.zig").run();
    try @import("app_hip_path_tracer.zig").run();
    //try @import("hip_app.zig").run();
    //try @import("ornament").hip.init();
}
