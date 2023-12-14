const std = @import("std");
const util = @import("../util.zig");
const gpu_structs = @import("../gpu_structs.zig");
const hip = @import("hip.zig");
const ornament = @import("../ornament.zig");

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

        pub fn init(host_array: []const T) !Self {
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

pub const Textures = struct {
    const Self = @This();
    texture_objects: std.ArrayList(hip.c.hipTextureObject_t),
    texture_data: std.ArrayList(hip.c.hipDeviceptr_t),
    device_texture_objects: Array(hip.c.hipTextureObject_t),

    pub fn init(allocator: std.mem.Allocator, textures: []const *ornament.Texture, pitch_alignment: usize) !Self {
        var texture_objects = try std.ArrayList(hip.c.hipTextureObject_t).initCapacity(allocator, textures.len);
        var texture_data = try std.ArrayList(hip.c.hipDeviceptr_t).initCapacity(allocator, textures.len);

        for (textures) |txt| {
            const format = if (txt.is_hdr) hip.c.HIP_AD_FORMAT_FLOAT else hip.c.HIP_AD_FORMAT_UNSIGNED_INT8;
            const filter_mode = hip.c.hipFilterModePoint;
            const src_pitch = txt.bytes_per_row;
            const dst_pitch = alignUp(src_pitch, pitch_alignment);

            var dptr: hip.c.hipDeviceptr_t = undefined;
            try hip.checkError(hip.c.hipMalloc(&dptr, dst_pitch * txt.height));
            try texture_data.append(dptr);
            const param = std.mem.zeroInit(hip.c.hip_Memcpy2D, .{
                .dstMemoryType = hip.c.hipMemoryTypeDevice,
                .dstDevice = dptr,
                .dstPitch = dst_pitch,
                .srcMemoryType = hip.c.hipMemoryTypeHost,
                .srcHost = txt.data.items.ptr,
                .srcPitch = src_pitch,
                .WidthInBytes = src_pitch,
                .Height = txt.height,
            });
            try hip.checkError(hip.c.hipDrvMemcpy2DUnaligned(&param));

            var res_desc = std.mem.zeroInit(hip.c.HIP_RESOURCE_DESC, .{});
            res_desc.resType = hip.c.hipResourceTypePitch2D;
            res_desc.res.pitch2D.devPtr = dptr;
            res_desc.res.pitch2D.format = @as(c_uint, @intCast(format));
            res_desc.res.pitch2D.numChannels = txt.num_components;
            res_desc.res.pitch2D.height = txt.height;
            res_desc.res.pitch2D.width = txt.width;
            res_desc.res.pitch2D.pitchInBytes = dst_pitch;

            var tex_desc = std.mem.zeroInit(hip.c.HIP_TEXTURE_DESC, .{});
            tex_desc.addressMode[0] = hip.c.hipAddressModeWrap;
            tex_desc.addressMode[1] = hip.c.hipAddressModeWrap;
            tex_desc.addressMode[2] = hip.c.hipAddressModeWrap;
            tex_desc.filterMode = filter_mode;
            tex_desc.flags = hip.c.HIP_TRSF_NORMALIZED_COORDINATES;

            var tex_obj: hip.c.hipTextureObject_t = undefined;
            try hip.checkError(hip.c.hipTexObjectCreate(&tex_obj, &res_desc, &tex_desc, null));
            try texture_objects.append(tex_obj);
        }
        return .{
            .texture_objects = texture_objects,
            .texture_data = texture_data,
            .device_texture_objects = try Array(hip.c.hipTextureObject_t).init(texture_objects.items),
        };
    }

    pub fn deinit(self: *Self) !void {
        for (self.texture_objects.items) |to| try hip.checkError(hip.c.hipTexObjectDestroy(to));
        self.texture_objects.deinit();
        for (self.texture_data.items) |td| try hip.checkError(hip.c.hipFree(td));
        self.texture_data.deinit();
        try self.device_texture_objects.deinit();
    }

    inline fn alignUp(offset: usize, alignment: usize) usize {
        return (offset + alignment - 1) & ~(alignment - 1);
    }
};

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
        //host_source.ptr,
        @as(?*const anyopaque, @ptrCast(host_source.ptr)),
        host_source.len * @sizeOf(T),
        hip.c.hipMemcpyHostToDevice,
    ));
}
