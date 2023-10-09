const std = @import("std");
const zmath = @import("zmath");
const zglfw = @import("zglfw");
const zstbi = @import("zstbi");
const webgpu = @import("../wgpu/webgpu.zig");
const util = @import("../util.zig");
const ornament = @import("../ornament.zig");
const Viewport = @import("../wgpu/viewport.zig").Viewport;

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
    ornament: ornament.Context,
    viewport: ?Viewport,

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.debug("[glfw_example] init", .{});
        zstbi.init(allocator);
        zstbi.setFlipVerticallyOnLoad(true);
        try zglfw.init();

        zglfw.WindowHint.set(.client_api, @intFromEnum(zglfw.ClientApi.no_api));
        const window = try zglfw.Window.create(WIDTH, HEIGHT, TITLE, null);

        var surface_descriptor_from_windows = webgpu.SurfaceDescriptorFromWindowsHWND{
            .chain = .{ .next = null, .struct_type = .surface_descriptor_from_windows_hwnd },
            .hwnd = try zglfw.native.getWin32Window(window),
            .hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse unreachable,
        };
        var ornament_context = try ornament.Context.init(
            allocator,
            .{ .next_in_chain = @ptrCast(&surface_descriptor_from_windows) },
        );
        ornament_context.setGamma(2.2);
        ornament_context.setFlipY(true);
        ornament_context.setDepth(DEPTH);
        ornament_context.setIterations(ITERATIONS);
        try ornament_context.setResolution(util.Resolution{ .width = WIDTH, .height = HEIGHT });
        try @import("examples.zig").init_cornell_box_with_lucy(&ornament_context, @as(f32, @floatCast(WIDTH)) / @as(f32, @floatCast(HEIGHT)));

        const viewport = try Viewport.init(&ornament_context);
        return .{
            .allocator = allocator,
            .window = window,
            .ornament = ornament_context,
            .viewport = viewport,
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.debug("[glfw_example] deinit", .{});
        if (self.viewport) |*v| v.deinit();
        self.ornament.deinit();
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
        const new_resolution = util.Resolution{ .width = @intCast(width), .height = @intCast(height) };
        if (!std.meta.eql(self.ornament.getResolution(), new_resolution)) {
            std.log.debug("[glfw_example] onFramebufferSize width = {d}, height = {d}", .{ width, height });
            self.ornament.scene.camera.setAspectRatio(@as(f32, @floatFromInt(width)) / @as(f32, @floatFromInt(height)));
            self.ornament.setResolution(new_resolution) catch unreachable;
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
                const target = self.ornament.scene.camera.getLookAt();
                var eye = self.ornament.scene.camera.getLookFrom();
                const up = self.ornament.scene.camera.getVUp();
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
                self.ornament.scene.camera.setLookAt(eye, target, up);
            }
        }
    }

    pub fn renderLoop(self: *Self) !void {
        std.log.debug("[glfw_example] renderLoop", .{});
        var fps_counter = util.FpsCounter.init();
        while (!self.window.shouldClose() and self.window.getKey(.escape) != .press) {
            zglfw.pollEvents();
            self.update();
            try self.ornament.render();
            if (self.viewport == null) {
                self.viewport = try Viewport.init(&self.ornament);
                std.log.debug("[glfw_example] viewport was created", .{});
            }
            try self.viewport.?.render();
            fps_counter.endFrames(ITERATIONS);
        }
    }
};
