const std = @import("std");
const zglfw = @import("zglfw");
const wgpu = @import("zgpu").wgpu;
const util = @import("../util.zig");
const ornament = @import("../ornament.zig");
const Viewport = @import("../wgpu/viewport.zig").Viewport;

const width = 1500;
const height = 1000;
const title = "ornament";

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
    wgpu_viewport: *Viewport,

    pub fn init(allocator: std.mem.Allocator) !Self {
        std.log.debug("[glfw_example] init", .{});
        try zglfw.init();

        zglfw.WindowHint.set(.client_api, @intFromEnum(zglfw.ClientApi.no_api));
        zglfw.WindowHint.set(.resizable, 0);
        const window = try zglfw.Window.create(width, height, title, null);

        var surface_descriptor_from_windows = wgpu.SurfaceDescriptorFromWindowsHWND{
            .chain = .{ .next = null, .struct_type = .surface_descriptor_from_windows_hwnd },
            .hwnd = try zglfw.native.getWin32Window(window),
            .hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse unreachable,
        };
        var ornament_context = try ornament.Context.init(
            allocator,
            .{ .next_in_chain = @ptrCast(&surface_descriptor_from_windows) },
        );
        ornament_context.setResolution(util.Resolution{ .width = width, .height = height });
        try ornament_context.setScene(try @import("examples.zig").spheres(
            ornament_context,
            allocator,
            @as(f32, @floatCast(width)) / @as(f32, @floatCast(height)),
        ));

        return .{
            .allocator = allocator,
            .window = window,
            .ornament = ornament_context,
            .wgpu_viewport = try Viewport.init(allocator, ornament_context.wgpu_context, ornament_context.getResolution()),
        };
    }

    pub fn deinit(self: *Self) void {
        std.log.debug("[glfw_example] deinit", .{});
        self.wgpu_viewport.deinit();
        self.ornament.deinit();
        self.window.destroy();
        zglfw.terminate();
    }

    pub fn setUpCallbacks(self: *Self) void {
        std.log.debug("[glfw_example] setUpCallbacks", .{});
        self.window.setUserPointer(self);
        _ = self.window.setFramebufferSizeCallback(onFramebufferSize);
    }

    fn onFramebufferSize(window: *zglfw.Window, new_width: i32, new_height: i32) callconv(.C) void {
        var self: *Self = window.getUserPointer(Self) orelse unreachable;
        const new_resolution = util.Resolution{ .width = @intCast(new_width), .height = @intCast(new_height) };
        if (!std.meta.eql(self.ornament.getResolution(), new_resolution)) {
            std.log.debug("[glfw_example] onFramebufferSize new_width = {d}, new_height = {d}", .{ new_width, new_height });
            self.ornament.setResolution(new_resolution);
            self.wgpu_viewport.setResolution(new_resolution);
        }
    }

    pub fn renderLoop(self: *Self) !void {
        std.log.debug("[glfw_example] renderLoop", .{});
        while (!self.window.shouldClose()) {
            zglfw.pollEvents();
            self.wgpu_viewport.render();
        }
    }
};
