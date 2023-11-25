const std = @import("std");
const util = @import("../util.zig");
const gpu_structs = @import("../gpu_structs.zig");
const hip = @import("hip.zig");

pub const WORKGROUP_SIZE: u32 = 256;

pub const Target = struct {
    const Self = @This();
    buffer: hip.c.hipDeviceptr_t,
    accumulation_buffer: hip.c.hipDeviceptr_t,
    rng_state_buffer: hip.c.hipDeviceptr_t,
    resolution: util.Resolution,
    workgroups: u32,

    pub fn init(allocator: std.mem.Allocator, resolution: util.Resolution) !Self {
        const pixels_count = resolution.pixel_count();

        var buffer: hip.c.hipDeviceptr_t = undefined;
        var accumulation_buffer: hip.c.hipDeviceptr_t = undefined;
        var rng_state_buffer: hip.c.hipDeviceptr_t = undefined;
        try hip.checkError(hip.c.hipMalloc(&buffer, pixels_count * @sizeOf(gpu_structs.Vector4)));
        try hip.checkError(hip.c.hipMalloc(&accumulation_buffer, pixels_count * @sizeOf(gpu_structs.Vector4)));
        try hip.checkError(hip.c.hipMalloc(&rng_state_buffer, pixels_count * @sizeOf(u32)));

        var rng_seed = try allocator.alloc(u32, pixels_count);
        defer allocator.free(rng_seed);
        for (rng_seed, 0..) |*value, index| {
            value.* = @truncate(index);
        }

        try hip.checkError(hip.c.hipMemcpy(rng_state_buffer, rng_seed.ptr, pixels_count * @sizeOf(u32), hip.c.hipMemcpyHostToDevice));

        var workgroups = pixels_count / WORKGROUP_SIZE;
        if (pixels_count % WORKGROUP_SIZE > 0) {
            workgroups += 1;
        }

        return .{
            .buffer = buffer,
            .accumulation_buffer = accumulation_buffer,
            .rng_state_buffer = rng_state_buffer,
            .resolution = resolution,
            .workgroups = workgroups,
        };
    }

    pub fn deinit(self: *Self) !void {
        try hip.checkError(hip.c.hipFree(self.buffer));
        try hip.checkError(hip.c.hipFree(self.accumulation_buffer));
        try hip.checkError(hip.c.hipFree(self.rng_state_buffer));
    }
};

pub fn Array(comptime T: type) type {
    return extern struct {
        const Self = @This();
        dptr: hip.c.hipDeviceptr_t,
        len: u32,

        pub fn init(host_array: []T) !Self {
            var dptr: hip.c.hipDeviceptr_t = undefined;
            try hip.checkError(hip.c.hipMalloc(&dptr, host_array.len * @sizeOf(T)));
            try memcpyHToD(T, dptr, host_array);
            return .{
                .dptr = dptr,
                .len = @as(u32, @truncate(host_array.len)),
            };
        }

        pub fn deinit(self: *Self) !void {
            return hip.checkError(hip.c.hipFree(self.dptr));
        }
    };
}

pub fn Global(comptime T: type) type {
    return struct {
        const Self = @This();
        dptr: hip.c.hipDeviceptr_t,

        pub fn init(comptime global_mem_name: [:0]const u8, module: hip.c.hipModule_t) !Self {
            var dptr: hip.c.hipDeviceptr_t = undefined;
            var bytes: usize = undefined;

            try hip.checkError(hip.c.hipModuleGetGlobal(&dptr, &bytes, module, global_mem_name));
            if (@sizeOf(T) != bytes) @panic(global_mem_name ++ " has wrong size.");

            return .{ .dptr = dptr };
        }
    };
}

pub fn arrayCopyHToD(comptime T: type, device_dst: Array(T), host_src: []const T) !void {
    if (device_dst.len < host_src.len) @panic("host array is too big");
    return memcpyHToD(T, device_dst.dptr, host_src);
}

pub fn globalCopyHToD(comptime T: type, device_dst: Global(T), host_src: T) !void {
    return memcpyHToD(T, device_dst.dptr, &.{host_src});
}

fn memcpyHToD(comptime T: type, device_dest: hip.c.hipDeviceptr_t, host_source: []const T) !void {
    return hip.checkError(hip.c.hipMemcpy(
        device_dest,
        host_source.ptr,
        host_source.len * @sizeOf(T),
        hip.c.hipMemcpyHostToDevice,
    ));
}
