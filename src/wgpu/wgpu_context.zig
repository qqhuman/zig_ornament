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

    pub fn init(surface_descriptor: ?webgpu.SurfaceDescriptor) !Self {
        const instance = webgpu.createInstance(null);
        const surface = if (surface_descriptor) |desc| createSurface(instance, desc) else null;

        const adapter = try requestAdapter(instance, .{ .compatible_surface = surface, .power_preference = .high_performance });
        // print adapter info
        {
            var properties: webgpu.AdapterProperties = undefined;
            properties.next_in_chain = null;
            adapter.getProperties(&properties);
            std.log.debug("[ornament] adapter name: {s}", .{properties.name});
            std.log.debug("[ornament] adapter driver: {s}", .{properties.driver_description});
            std.log.debug("[ornament] adapter type: {s}", .{@tagName(properties.adapter_type)});
            std.log.debug("[ornament] adapter backend type: {s}", .{@tagName(properties.backend_type)});
        }

        const device = try requestDevice(adapter, .{ .label = "[ornament] wgpu device" });
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
