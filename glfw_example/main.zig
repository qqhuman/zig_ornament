pub fn main() !void {
    //try @import("app_wgpu_path_tracer.zig").run();
    try @import("app_hip_path_tracer.zig").run();
    //@import("ornament").hip_backend.matrix_transpose_example();
}
