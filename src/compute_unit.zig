const std = @import("std");
const c = @cImport({
    @cInclude("webgpu.h");
});

pub const WgpuError = error{ InstanceCreationFailed, SurfaceCreationFailed, AdapterRequestFailed, AllocationFailed };

pub const ComputeUnit = struct {
    allocator: *std.mem.Allocator,
    surface: c.WGPUSurface,
    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, surface_descriptor: ?*c.WGPUSurfaceDescriptor) WgpuError!Self {
        var instance_desc = c.WGPUInstanceDescriptor{ .nextInChain = null };
        var instance = c.wgpuCreateInstance(&instance_desc) orelse return WgpuError.InstanceCreationFailed;
        defer c.wgpuInstanceRelease(instance);

        var surface = if (surface_descriptor) |desc| try createSurface(instance, desc) else null;
        var adapter_options = c.WGPURequestAdapterOptions{
            .nextInChain = null,
            .compatibleSurface = surface,
            .forceFallbackAdapter = false,
            .powerPreference = c.WGPUPowerPreference_HighPerformance,
            .backendType = c.WGPUBackendType_Vulkan,
        };
        var adapter = try requestAdapter(instance, &adapter_options);

        var properties: c.WGPUAdapterProperties = undefined;
        properties.nextInChain = null;
        c.wgpuAdapterGetProperties(adapter, &properties);
        std.log.debug("[ornament] adapter name: {s}", .{properties.name});
        std.log.debug("[ornament] adapter driver: {s}", .{properties.driverDescription});
        std.log.debug("[ornament] adapter type: {d}", .{properties.adapterType});
        std.log.debug("[ornament] adapter backend type: {d}", .{properties.backendType});

        const feature_count = c.wgpuAdapterEnumerateFeatures(adapter, null);
        const features = allocator.alloc(c.WGPUFeatureName, feature_count) catch return WgpuError.AllocationFailed;
        defer allocator.free(features);
        _ = c.wgpuAdapterEnumerateFeatures(adapter, features.ptr);
        for (features) |f| {
            std.log.debug("[ornament] adapter feature: {d}", .{f});
        }

        defer releaseAdapter(adapter);
        return .{ .allocator = allocator, .surface = surface };
    }

    pub fn deinit(self: Self) void {
        if (self.surface) |surface| {
            c.wgpuSurfaceRelease(surface);
        }
    }
};

fn requestAdapter(instance: c.WGPUInstance, options: *c.WGPURequestAdapterOptions) WgpuError!c.WGPUAdapter {
    const Response = struct { status: c.WGPURequestAdapterStatus = c.WGPURequestAdapterStatus_Unknown, adapter: c.WGPUAdapter = null };
    const callback = struct {
        fn callback(status: c.WGPURequestAdapterStatus, adapter: c.WGPUAdapter, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
            _ = message;
            const responce = @as(*Response, @ptrCast(@alignCast(userdata)));
            responce.adapter = adapter;
            responce.status = status;
        }
    }.callback;

    var responce = Response{};
    c.wgpuInstanceRequestAdapter(instance, options, callback, @ptrCast(&responce));

    std.log.debug("[ornament] request adapter status = {d}", .{responce.status});
    if (responce.status != c.WGPURequestAdapterStatus_Success) {
        return WgpuError.AdapterRequestFailed;
    }

    return responce.adapter;
}

fn releaseAdapter(adapter: c.WGPUAdapter) void {
    c.wgpuAdapterRelease(adapter);
}

fn createSurface(instance: c.WGPUInstance, surface_descriptor: *c.WGPUSurfaceDescriptor) WgpuError!c.WGPUSurface {
    std.log.debug("[ornament] create surface", .{});
    return c.wgpuInstanceCreateSurface(instance, surface_descriptor) orelse WgpuError.SurfaceCreationFailed;
}
