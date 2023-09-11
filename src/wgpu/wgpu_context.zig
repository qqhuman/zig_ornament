const std = @import("std");
const wgpu = @import("zgpu").wgpu;

pub const WgpuError = error{
    AdapterRequestFailed,
    DeviceRequestFailed,
};

// Defined in dawn.cpp
const DawnNativeInstance = ?*opaque {};
const DawnProcsTable = ?*opaque {};
extern fn dniCreate() DawnNativeInstance;
extern fn dniDestroy(dni: DawnNativeInstance) void;
extern fn dniGetWgpuInstance(dni: DawnNativeInstance) ?wgpu.Instance;
extern fn dniDiscoverDefaultAdapters(dni: DawnNativeInstance) void;
extern fn dnGetProcs() DawnProcsTable;

// Defined in Dawn codebase
extern fn dawnProcSetProcs(procs: DawnProcsTable) void;

pub const WgpuContext = struct {
    const Self = @This();
    native_instance: DawnNativeInstance,
    instance: wgpu.Instance,
    surface: ?wgpu.Surface,
    adapter: wgpu.Adapter,
    device: wgpu.Device,
    queue: wgpu.Queue,

    pub fn init(surface_descriptor: ?wgpu.SurfaceDescriptor) !Self {
        dawnProcSetProcs(dnGetProcs());
        const native_instance = dniCreate().?;
        dniDiscoverDefaultAdapters(native_instance);

        const instance = dniGetWgpuInstance(native_instance).?;
        const surface = if (surface_descriptor) |desc| createSurface(instance, desc) else null;

        const adapter = try requestAdapter(instance, .{ .compatible_surface = surface, .power_preference = .high_performance });
        // print adapter info
        {
            var properties: wgpu.AdapterProperties = undefined;
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
            .native_instance = native_instance,
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
        dniDestroy(self.native_instance);
    }
};

fn createSurface(instance: wgpu.Instance, surface_descriptor: wgpu.SurfaceDescriptor) wgpu.Surface {
    std.log.debug("[ornament] create surface", .{});
    return instance.createSurface(surface_descriptor);
}

fn requestAdapter(instance: wgpu.Instance, options: wgpu.RequestAdapterOptions) WgpuError!wgpu.Adapter {
    var response = AdapterResponse{};
    instance.requestAdapter(options, onRequestAdapter, @ptrCast(&response));

    std.log.debug("[ornament] request adapter status = {s}", .{@tagName(response.status)});
    if (response.status != .success) {
        return WgpuError.AdapterRequestFailed;
    }

    return response.adapter orelse WgpuError.AdapterRequestFailed;
}

const AdapterResponse = struct { status: wgpu.RequestAdapterStatus = .unknown, adapter: ?wgpu.Adapter = null };
fn onRequestAdapter(status: wgpu.RequestAdapterStatus, adapter: ?wgpu.Adapter, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = message;
    const response = @as(*AdapterResponse, @ptrCast(@alignCast(userdata)));
    response.adapter = adapter;
    response.status = status;
}

fn requestDevice(adapter: wgpu.Adapter, descriptor: wgpu.DeviceDescriptor) WgpuError!wgpu.Device {
    var response = DeviceResponse{};
    adapter.requestDevice(descriptor, onRequestDevice, @ptrCast(&response));

    std.log.debug("[ornament] request device status = {s}", .{@tagName(response.status)});
    if (response.status != .success) {
        return WgpuError.DeviceRequestFailed;
    }

    return response.device orelse WgpuError.DeviceRequestFailed;
}

const DeviceResponse = struct { status: wgpu.RequestDeviceStatus = .unknown, device: ?wgpu.Device = null };
fn onRequestDevice(status: wgpu.RequestDeviceStatus, device: ?wgpu.Device, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = message;
    const response = @as(*DeviceResponse, @ptrCast(@alignCast(userdata)));
    response.device = device;
    response.status = status;
}

fn onUncapturedError(error_type: wgpu.ErrorType, message: ?[*:0]const u8, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;

    std.log.err("[ornament] onUncapturedError type: {s}", .{@tagName(error_type)});
    if (message) |msg| {
        std.log.err("[ornament] onUncapturedError message: {s}", .{msg});
    }
}

fn onSubmittedWorkDone(status: wgpu.QueueWorkDoneStatus, userdata: ?*anyopaque) callconv(.C) void {
    _ = userdata;

    if (status != .Success) {
        std.log.err("[ornament] onSubmittedWorkDone with status: {s}", .{@tagName(status)});
    }
}
