const std = @import("std");
const zmath = @import("zmath");
const zglfw = @import("zglfw");
const zstbi = @import("zstbi");
const ornament = @import("ornament");
const Viewport = @import("viewport.zig").Viewport;
const app_config = @import("app_config.zig");

pub fn run() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer if (gpa.deinit() == .leak) @panic("[glfw_wgpu] memory leak");

    var app = try App.init(gpa.allocator());
    defer app.deinit();
    app.setUpCallbacks();
    try app.renderLoop();
}

const App = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    window: *zglfw.Window,
    resolution: ornament.Resolution,
    viewport: ?Viewport,
    wgpu_device_state: ornament.wgpu_backend.DeviceState,

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.debug("[glfw_wgpu] init", .{});
        zstbi.init(allocator);
        zstbi.setFlipVerticallyOnLoad(true);
        try zglfw.init();

        zglfw.WindowHint.set(.client_api, @intFromEnum(zglfw.ClientApi.no_api));
        const window = try zglfw.Window.create(app_config.WIDTH, app_config.HEIGHT, app_config.TITLE, null);
        // var scene = ornament.Scene.init(allocator);
        // try @import("examples.zig").init_lucy_spheres_with_textures(&scene, @as(f32, @floatCast(app_config.WIDTH)) / @as(f32, @floatCast(app_config.HEIGHT)));
        var surface_descriptor_from_windows = ornament.wgpu_backend.webgpu.SurfaceDescriptorFromWindowsHWND{
            .chain = .{ .next = null, .struct_type = .surface_descriptor_from_windows_hwnd },
            .hwnd = try zglfw.native.getWin32Window(window),
            .hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse unreachable,
        };
        const wgpu_device_state = try ornament.wgpu_backend.DeviceState.init(
            allocator,
            &.{},
            .{ .next_in_chain = @ptrCast(&surface_descriptor_from_windows) },
        );
        const resolution = ornament.Resolution{ .width = app_config.WIDTH, .height = app_config.HEIGHT };
        const viewport = try Viewport.init(&wgpu_device_state, resolution, null);
        return .{
            .allocator = allocator,
            .window = window,
            .resolution = resolution,
            .viewport = viewport,
            .wgpu_device_state = wgpu_device_state,
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.debug("[glfw_wgpu] deinit", .{});
        if (self.viewport) |*v| v.deinit();
        self.wgpu_device_state.deinit();
        self.window.destroy();
        zglfw.terminate();
        zstbi.deinit();
    }

    pub fn setUpCallbacks(self: *Self) void {
        std.log.debug("[glfw_wgpu] setUpCallbacks", .{});
        self.window.setUserPointer(self);
        _ = self.window.setFramebufferSizeCallback(onFramebufferSize);
    }

    fn onFramebufferSize(window: *zglfw.Window, width: i32, height: i32) callconv(.C) void {
        var self: *Self = window.getUserPointer(Self) orelse unreachable;
        const new_resolution = ornament.Resolution{ .width = @intCast(width), .height = @intCast(height) };
        if (!std.meta.eql(self.resolution, new_resolution)) {
            std.log.debug("[glfw_wgpu] onFramebufferSize width = {d}, height = {d}", .{ width, height });
            self.resolution = new_resolution;
            if (self.viewport) |*v| {
                v.deinit();
                self.viewport = null;
            }
        }
    }

    pub fn update(self: *Self, scene: *ornament.Scene) void {
        // WSDA
        {
            const w_pressed = self.window.getKey(.w) == .press;
            const s_pressed = self.window.getKey(.s) == .press;
            const d_pressed = self.window.getKey(.d) == .press;
            const a_pressed = self.window.getKey(.a) == .press;

            if (w_pressed or s_pressed or d_pressed or a_pressed) {
                const target = scene.camera.getLookAt();
                var eye = scene.camera.getLookFrom();
                const up = scene.camera.getVUp();
                var forward = target - eye;
                const forward_norm = zmath.normalize3(forward);
                var forward_mag = zmath.length3(forward);

                if (w_pressed and forward_mag[0] > app_config.CAMERA_SPEED[0]) {
                    eye += forward_norm * app_config.CAMERA_SPEED;
                }

                if (s_pressed) {
                    eye -= forward_norm * app_config.CAMERA_SPEED;
                }

                const right = zmath.cross3(forward_norm, up);
                // Redo radius calc in case the fowrard/backward is pressed.
                forward = target - eye;
                forward_mag = zmath.length3(forward);

                if (d_pressed) {
                    // Rescale the distance between the target and eye so
                    // that it doesn't change. The eye therefore still
                    // lies on the circle made by the target and eye.
                    eye = target - zmath.normalize3((forward - right * app_config.CAMERA_SPEED)) * forward_mag;
                }

                if (a_pressed) {
                    eye = target - zmath.normalize3((forward + right * app_config.CAMERA_SPEED)) * forward_mag;
                }
                scene.camera.setLookAt(eye, target, up);
            }
        }
    }

    pub fn renderLoop(self: *Self) !void {
        std.log.debug("[glfw_wgpu] renderLoop", .{});
        var fps_counter = FpsCounter.init();
        while (!self.window.shouldClose() and self.window.getKey(.escape) != .press) {
            zglfw.pollEvents();
            //self.update();
            if (self.viewport == null) {
                self.viewport = try Viewport.init(&self.wgpu_device_state, self.resolution, null);
                std.log.debug("[glfw_wgpu] viewport was created", .{});
            }
            try self.viewport.?.render();
            fps_counter.endFrames(app_config.ITERATIONS);
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
