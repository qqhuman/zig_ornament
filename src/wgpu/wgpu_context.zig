const std = @import("std");
const webgpu = @import("webgpu.zig");

pub const WgpuError = error{
    AdapterRequestFailed,
    DeviceRequestFailed,
};

pub const WgpuContext = struct {
    const Self = @This();
    instance: webgpu.Instance,
    surface: ?webgpu.Surface,
    adapter: webgpu.Adapter,
    device: webgpu.Device,
    queue: webgpu.Queue,

    pub fn init(allocator: std.mem.Allocator, surface_descriptor: ?webgpu.SurfaceDescriptor) !Self {
        const instance = webgpu.createInstance(null);
        const surface = if (surface_descriptor) |desc| createSurface(instance, desc) else null;

        const adapter = try requestAdapter(instance, .{
            .compatible_surface = surface,
            .power_preference = .high_performance,
            // Vulkan backend has artifacts with binding_array of textures
            //.backend_type = .vulkan,
            .backend_type = .d3d12,
        });

        // print adapter info
        const properties = adapter.getProperties();
        std.log.debug("[ornament] adapter name: {s}", .{properties.name});
        std.log.debug("[ornament] adapter driver: {s}", .{properties.driver_description});
        std.log.debug("[ornament] adapter type: {s}", .{@tagName(properties.adapter_type)});
        std.log.debug("[ornament] adapter backend type: {s}", .{@tagName(properties.backend_type)});

        // get features
        const features_count = adapter.enumerateFeatures(null);
        var features = try allocator.alloc(webgpu.FeatureName, features_count);
        defer allocator.free(features);
        _ = adapter.enumerateFeatures(features.ptr);
        var has_texture_binding_array_feature = false;
        var has_sampled_texture_and_storage_buffer_array_non_uniform_indexing_feature = false;
        for (features) |f| {
            std.log.debug("[ornament] adapter feature: {any}", .{f});
            switch (f) {
                .texture_binding_array => has_texture_binding_array_feature = true,
                .sampled_texture_and_storage_buffer_array_non_uniform_indexing => has_sampled_texture_and_storage_buffer_array_non_uniform_indexing_feature = true,
                else => {},
            }
        }

        if (adapter.getLimits()) |limits| {
            std.log.debug("[ornament] supported limit max_bind_groups: {any}", .{limits.limits.max_bind_groups});
            std.log.debug("[ornament] supported limit max_bindings_per_bind_group: {any}", .{limits.limits.max_bindings_per_bind_group});
            std.log.debug("[ornament] supported limit max_dynamic_uniform_buffers_per_pipeline_layout: {any}", .{limits.limits.max_dynamic_uniform_buffers_per_pipeline_layout});
            std.log.debug("[ornament] supported limit max_dynamic_storage_buffers_per_pipeline_layout: {any}", .{limits.limits.max_dynamic_storage_buffers_per_pipeline_layout});
            std.log.debug("[ornament] supported limit max_uniform_buffer_binding_size: {any}", .{limits.limits.max_uniform_buffer_binding_size});
            std.log.debug("[ornament] supported limit max_storage_buffer_binding_size: {any}", .{limits.limits.max_storage_buffer_binding_size});
            std.log.debug("[ornament] supported limit max_storage_buffers_per_shader_stage: {any}", .{limits.limits.max_storage_buffers_per_shader_stage});
            std.log.debug("[ornament] supported limit max_uniform_buffers_per_shader_stage: {any}", .{limits.limits.max_uniform_buffers_per_shader_stage});
            std.log.debug("[ornament] supported limit max_sampled_textures_per_shader_stage: {any}", .{limits.limits.max_sampled_textures_per_shader_stage});
            std.log.debug("[ornament] supported limit max_samplers_per_shader_stage: {any}", .{limits.limits.max_samplers_per_shader_stage});
        }

        if (!has_texture_binding_array_feature) {
            @panic("Adapter doesn't support texture_binding_array feature.");
        }

        if (!has_sampled_texture_and_storage_buffer_array_non_uniform_indexing_feature) {
            @panic("Adapter doesn't support sampled_texture_and_storage_buffer_array_non_uniform_indexing feature.");
        }

        const required_features = [_]webgpu.FeatureName{
            .texture_binding_array,
            .sampled_texture_and_storage_buffer_array_non_uniform_indexing,
        };
        const device = try requestDevice(adapter, .{
            .label = "[ornament] wgpu device",
            .required_feature_count = required_features.len,
            .required_features = &required_features,
        });
        device.setUncapturedErrorCallback(onUncapturedError, null);

        return .{
            .instance = instance,
            .surface = surface,
            .adapter = adapter,
            .device = device,
            .queue = device.getQueue(),
        };
    }

    pub fn deinit(self: *Self) void {
        self.queue.release();
        self.device.release();
        self.adapter.release();
        if (self.surface) |surface| surface.release();
        self.instance.release();
    }
};

fn createSurface(instance: webgpu.Instance, surface_descriptor: webgpu.SurfaceDescriptor) webgpu.Surface {
    std.log.debug("[ornament] create surface", .{});
    return instance.createSurface(surface_descriptor);
}

fn requestAdapter(instance: webgpu.Instance, options: webgpu.RequestAdapterOptions) WgpuError!webgpu.Adapter {
    var response = AdapterResponse{};
    instance.requestAdapter(options, onRequestAdapter, @ptrCast(&response));

    std.log.debug("[ornament] request adapter status = {s}", .{@tagName(response.status)});
    if (response.status != .success) {
        return WgpuError.AdapterRequestFailed;
    }

    return response.adapter orelse WgpuError.AdapterRequestFailed;
}

const AdapterResponse = struct { status: webgpu.RequestAdapterStatus = .unknown, adapter: ?webgpu.Adapter = null };
fn onRequestAdapter(status: webgpu.RequestAdapterStatus, adapter: ?webgpu.Adapter, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = message;
    const response = @as(*AdapterResponse, @ptrCast(@alignCast(userdata)));
    response.adapter = adapter;
    response.status = status;
}

fn requestDevice(adapter: webgpu.Adapter, descriptor: webgpu.DeviceDescriptor) WgpuError!webgpu.Device {
    var response = DeviceResponse{};
    adapter.requestDevice(descriptor, onRequestDevice, @ptrCast(&response));

    std.log.debug("[ornament] request device status = {s}", .{@tagName(response.status)});
    if (response.status != .success) {
        return WgpuError.DeviceRequestFailed;
    }

    return response.device orelse WgpuError.DeviceRequestFailed;
}

const DeviceResponse = struct { status: webgpu.RequestDeviceStatus = .unknown, device: ?webgpu.Device = null };
fn onRequestDevice(status: webgpu.RequestDeviceStatus, device: ?webgpu.Device, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = message;
    const response = @as(*DeviceResponse, @ptrCast(@alignCast(userdata)));
    response.device = device;
    response.status = status;
}

fn onUncapturedError(error_type: webgpu.ErrorType, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;

    std.log.err("[ornament] onUncapturedError type: {s}", .{@tagName(error_type)});
    if (message) |msg| {
        std.log.err("[ornament] onUncapturedError message: {s}", .{msg});
    }

    @panic("uncaptured error");
}
