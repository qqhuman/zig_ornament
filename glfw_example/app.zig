const std = @import("std");
const zmath = @import("zmath");
const zglfw = @import("zglfw");
const zstbi = @import("zstbi");
const ornament = @import("ornament");
const Viewport = @import("viewport.zig").Viewport;

const WIDTH = 1000;
const HEIGHT = 1000;
const DEPTH = 10;
const ITERATIONS = 1;
const TITLE = "ornament";
const CAMERA_SPEED = zmath.f32x4s(0.2);

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("[glfw_example] memory leak");

    var app = try App.init(gpa.allocator());
    defer app.deinit();
    app.setUpCallbacks();
    try app.renderLoop();
}

const App = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    path_tracer: ornament.WgpuPathTracer,
    viewport: ?Viewport,

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.debug("[glfw_example] init", .{});
        zstbi.init(allocator);
        zstbi.setFlipVerticallyOnLoad(true);
        try zglfw.init();

        zglfw.WindowHint.set(.client_api, @intFromEnum(zglfw.ClientApi.no_api));
        const window = try zglfw.Window.create(WIDTH, HEIGHT, TITLE, null);

        var surface_descriptor_from_windows = ornament.wgpu_backend.webgpu.SurfaceDescriptorFromWindowsHWND{
            .chain = .{ .next = null, .struct_type = .surface_descriptor_from_windows_hwnd },
            .hwnd = try zglfw.native.getWin32Window(window),
            .hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse unreachable,
        };
        var scene = ornament.Scene.init(allocator);
        try @import("examples.zig").init_lucy_spheres_with_textures(&scene, @as(f32, @floatCast(WIDTH)) / @as(f32, @floatCast(HEIGHT)));
        var path_tracer = try ornament.WgpuPathTracer.init(
            allocator,
            scene,
            .{ .next_in_chain = @ptrCast(&surface_descriptor_from_windows) },
        );
        path_tracer.state.setGamma(2.2);
        path_tracer.state.setFlipY(true);
        path_tracer.state.setDepth(DEPTH);
        path_tracer.state.setIterations(ITERATIONS);
        path_tracer.setResolution(ornament.Resolution{ .width = WIDTH, .height = HEIGHT });

        const viewport = try Viewport.init(&path_tracer);
        return .{
            .allocator = allocator,
            .window = window,
            .path_tracer = path_tracer,
            .viewport = viewport,
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.debug("[glfw_example] deinit", .{});
        if (self.viewport) |*v| v.deinit();
        self.path_tracer.deinit();
        self.window.destroy();
        zglfw.terminate();
        zstbi.deinit();
    }

    pub fn setUpCallbacks(self: *Self) void {
        std.log.debug("[glfw_example] setUpCallbacks", .{});
        self.window.setUserPointer(self);
        _ = self.window.setFramebufferSizeCallback(onFramebufferSize);
    }

    fn onFramebufferSize(window: *zglfw.Window, width: i32, height: i32) callconv(.C) void {
        var self: *Self = window.getUserPointer(Self) orelse unreachable;
        const new_resolution = ornament.Resolution{ .width = @intCast(width), .height = @intCast(height) };
        if (!std.meta.eql(self.path_tracer.state.getResolution(), new_resolution)) {
            std.log.debug("[glfw_example] onFramebufferSize width = {d}, height = {d}", .{ width, height });
            self.path_tracer.scene.camera.setAspectRatio(@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)));
            self.path_tracer.setResolution(new_resolution);
            if (self.viewport) |*v| {
                v.deinit();
                self.viewport = null;
            }
        }
    }

    pub fn update(self: *Self) void {
        // WSDA
        {
            const w_pressed = self.window.getKey(.w) == .press;
            const s_pressed = self.window.getKey(.s) == .press;
            const d_pressed = self.window.getKey(.d) == .press;
            const a_pressed = self.window.getKey(.a) == .press;

            if (w_pressed or s_pressed or d_pressed or a_pressed) {
                const target = self.path_tracer.scene.camera.getLookAt();
                var eye = self.path_tracer.scene.camera.getLookFrom();
                const up = self.path_tracer.scene.camera.getVUp();
                var forward = target - eye;
                const forward_norm = zmath.normalize3(forward);
                var forward_mag = zmath.length3(forward);

                if (w_pressed and forward_mag[0] > CAMERA_SPEED[0]) {
                    eye += forward_norm * CAMERA_SPEED;
                }

                if (s_pressed) {
                    eye -= forward_norm * CAMERA_SPEED;
                }

                const right = zmath.cross3(forward_norm, up);
                // Redo radius calc in case the fowrard/backward is pressed.
                forward = target - eye;
                forward_mag = zmath.length3(forward);

                if (d_pressed) {
                    // Rescale the distance between the target and eye so
                    // that it doesn't change. The eye therefore still
                    // lies on the circle made by the target and eye.
                    eye = target - zmath.normalize3((forward - right * CAMERA_SPEED)) * forward_mag;
                }

                if (a_pressed) {
                    eye = target - zmath.normalize3((forward + right * CAMERA_SPEED)) * forward_mag;
                }
                self.path_tracer.scene.camera.setLookAt(eye, target, up);
            }
        }
    }

    pub fn renderLoop(self: *Self) !void {
        std.log.debug("[glfw_example] renderLoop", .{});
        var fps_counter = FpsCounter.init();
        while (!self.window.shouldClose() and self.window.getKey(.escape) != .press) {
            zglfw.pollEvents();
            self.update();
            try self.path_tracer.render();
            if (self.viewport == null) {
                self.viewport = try Viewport.init(&self.path_tracer);
                std.log.debug("[glfw_example] viewport was created", .{});
            }
            try self.viewport.?.render();
            fps_counter.endFrames(ITERATIONS);
        }
    }
};

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
