const std = @import("std");
const c = @cImport({
    @cInclude("glfw3.h");
    @cInclude("webgpu.h");
    @cInclude("wgpu.h");
});
const ornament = @import("../ornament.zig");

const width: i32 = 1000;
const height: i32 = 1000;
const title: [*c]const u8 = "ornament";

pub fn run() !void {
    var app = try App.init();
    defer app.deinit();
    app.event_loop();
}

pub const GlfwError = error{ IntializationFailed, WindowCreationFailed };
extern fn glfwGetWin32Window(window: ?*c.GLFWwindow) ?*anyopaque;

const App = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    allocator: std.mem.Allocator,
    window: *c.GLFWwindow,
    ornament: ornament.Context,

    const Self = @This();

    pub fn init() !Self {
        if (c.glfwInit() == c.GLFW_FALSE) {
            return GlfwError.IntializationFailed;
        }

        const window = c.glfwCreateWindow(width, height, title, null, null) orelse return GlfwError.WindowCreationFailed;
        const hwnd = glfwGetWin32Window(window) orelse unreachable;
        const hinstance = std.os.windows.kernel32.GetModuleHandleW(null) orelse unreachable;

        const surface_descriptor_from_windows = c.WGPUSurfaceDescriptorFromWindowsHWND{
            .chain = c.WGPUChainedStruct{ .next = null, .sType = c.WGPUSType_SurfaceDescriptorFromWindowsHWND },
            .hinstance = hinstance,
            .hwnd = hwnd,
        };
        var surface_descriptor = c.WGPUSurfaceDescriptor{
            .label = null,
            .nextInChain = @ptrCast(&surface_descriptor_from_windows),
        };

        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        var allocator = gpa.allocator();
        return .{ .gpa = gpa, .allocator = allocator, .window = window, .ornament = try ornament.Context.init(&allocator, width, height, @ptrCast(&surface_descriptor)) };
    }

    pub fn deinit(self: *Self) void {
        self.ornament.deinit();
        c.glfwDestroyWindow(self.window);
        c.glfwTerminate();
        const deinit_status = self.gpa.deinit();
        if (deinit_status == .leak) {
            //@panic("TEST FAIL")
            std.log.err("[glfw_example] Memory leak", .{});
        }
    }

    pub fn event_loop(self: Self) void {
        while (c.glfwWindowShouldClose(self.window) == c.GLFW_FALSE) {
            c.glfwPollEvents();
        }
    }
};
