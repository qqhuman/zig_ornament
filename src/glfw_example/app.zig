const std = @import("std");
const zglfw = @import("zglfw");
const wgpu = @import("zgpu").wgpu;
const util = @import("../util.zig");
const ornament = @import("../ornament.zig");
const Viewport = @import("../wgpu/viewport.zig").Viewport;

const WIDTH = 1500;
const HEIGHT = 1000;
const DEPTH = 10;
const ITERATIONS = 1;
const TITLE = "ornament";

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
    ornament: *ornament.Context,
    viewport: *Viewport,

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.debug("[glfw_example] init", .{});
        try zglfw.init();

        zglfw.WindowHint.set(.client_api, @intFromEnum(zglfw.ClientApi.no_api));
        const window = try zglfw.Window.create(WIDTH, HEIGHT, TITLE, null);

        var surface_descriptor_from_windows = wgpu.SurfaceDescriptorFromWindowsHWND{
            .chain = .{ .next = null, .struct_type = .surface_descriptor_from_windows_hwnd },
            .hwnd = try zglfw.native.getWin32Window(window),
            .hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse unreachable,
        };
        var ornament_context = try ornament.Context.init(
            allocator,
            .{ .next_in_chain = @ptrCast(&surface_descriptor_from_windows) },
        );
        try @import("examples.zig").init_spheres_and_meshes_spheres(ornament_context, @as(f32, @floatCast(WIDTH)) / @as(f32, @floatCast(HEIGHT)));
        ornament_context.setFlipY(true);
        ornament_context.setDepth(DEPTH);
        ornament_context.setIterations(ITERATIONS);
        try ornament_context.setResolution(util.Resolution{ .width = WIDTH, .height = HEIGHT });
        ornament_context.setGamma(2.2);

        return .{
            .allocator = allocator,
            .window = window,
            .ornament = ornament_context,
            .viewport = try Viewport.init(allocator, ornament_context),
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.debug("[glfw_example] deinit", .{});
        self.viewport.deinit();
        self.ornament.deinit();
        self.window.destroy();
        zglfw.terminate();
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
            self.viewport.setResolution(new_resolution);
        }
    }

    pub fn renderLoop(self: *Self) !void {
        std.log.debug("[glfw_example] renderLoop", .{});
        var fps_counter = util.FpsCounter.init();
        while (!self.window.shouldClose()) {
            zglfw.pollEvents();
            try self.ornament.render();
            try self.viewport.render();
            fps_counter.endFrames(ITERATIONS);
        }
    }
};
