const std = @import("std");
const ornament = @import("../ornament.zig");
const zgpu = @import("zgpu");
const wgpu = zgpu.wgpu;
const WgpuContext = @import("wgpu_context.zig").WgpuContext;
const util = @import("../util.zig");
const wgsl_structs = @import("wgsl_structs.zig");

pub const WORKGROUP_SIZE: u32 = 256;

pub const Target = struct {
    const Self = @This();
    buffer: Storage(wgsl_structs.Vector4),
    accumulation_buffer: Storage(wgsl_structs.Vector4),
    rng_state_buffer: Storage(u32),
    pixels_count: u32,
    resolution: util.Resolution,
    workgroups: u32,

    pub fn init(allocator: std.mem.Allocator, device: wgpu.Device, resolution: util.Resolution) !Self {
        const pixels_count = resolution.width * resolution.height;
        const buffer = Storage(wgsl_structs.Vector4).init(device, true, .{ .element_count = pixels_count });
        const accumulation_buffer = Storage(wgsl_structs.Vector4).init(device, false, .{ .element_count = pixels_count });

        var rng_seed = try allocator.alloc(u32, pixels_count);
        defer allocator.free(rng_seed);
        for (rng_seed, 0..) |*value, index| {
            value.* = @truncate(index);
        }
        const rng_state_buffer = Storage(u32).init(device, false, .{ .data = rng_seed });

        var workgroups = pixels_count / WORKGROUP_SIZE;
        if (pixels_count % WORKGROUP_SIZE > 0) {
            workgroups += 1;
        }

        return .{
            .buffer = buffer,
            .accumulation_buffer = accumulation_buffer,
            .rng_state_buffer = rng_state_buffer,
            .pixels_count = pixels_count,
            .resolution = resolution,
            .workgroups = workgroups,
        };
    }
    pub fn deinit(self: *Self) void {
        self.buffer.deinit();
        self.accumulation_buffer.deinit();
        self.rng_state_buffer.deinit();
    }

    pub fn layout(self: Self, binding_id: u32, visibility: wgpu.ShaderStage, read_only: bool) wgpu.BindGroupLayoutEntry {
        return self.buffer.layout(binding_id, visibility, read_only);
    }

    pub fn binding(self: Self, binding_id: u32) wgpu.BindGroupEntry {
        return self.buffer.binding(binding_id);
    }
};

fn paddedBufferSize(unpadded_size: u64) u64 {
    const COPY_BUFFER_ALIGNMENT: u64 = 4;
    const align_mask = COPY_BUFFER_ALIGNMENT - 1;
    return @max((unpadded_size + align_mask) & ~align_mask, COPY_BUFFER_ALIGNMENT);
}

pub fn Storage(comptime T: type) type {
    return struct {
        const Self = @This();
        handle: wgpu.Buffer,
        padded_size_in_bytes: u64,

        pub fn init(device: wgpu.Device, copy_src: bool, init_data: union(enum) { element_count: u64, data: []const T }) Self {
            var usage = wgpu.BufferUsage{ .storage = true };
            if (copy_src) {
                usage.copy_src = true;
            }

            const label = "[ornament] []" ++ @typeName(T) ++ " storage";
            const count = switch (init_data) {
                .element_count => |count| count,
                .data => |data| data.len,
            };
            // storage cannot be empty so we allocate at least one element
            const padded_size_in_bytes = paddedBufferSize(@max(count, 1) * @sizeOf(T));
            const handle = switch (init_data) {
                .element_count => device.createBuffer(.{
                    .label = label,
                    .usage = usage,
                    .size = padded_size_in_bytes,
                }),
                .data => |data| blk: {
                    const handle = device.createBuffer(.{
                        .label = label,
                        .usage = usage,
                        .mapped_at_creation = data.len > 0,
                        .size = padded_size_in_bytes,
                    });

                    if (handle.getMappedRange(T, 0, data.len)) |dst| {
                        std.mem.copy(T, dst, data);
                        handle.unmap();
                    }

                    break :blk handle;
                },
            };

            return .{ .handle = handle, .padded_size_in_bytes = padded_size_in_bytes };
        }

        pub fn deinit(self: *Self) void {
            self.handle.release();
        }

        pub fn layout(self: Self, binding_id: u32, visibility: wgpu.ShaderStage, read_only: bool) wgpu.BindGroupLayoutEntry {
            _ = self;
            return .{
                .binding = binding_id,
                .visibility = visibility,
                .buffer = .{ .binding_type = if (read_only) .read_only_storage else .storage },
            };
        }

        pub fn binding(self: Self, binding_id: u32) wgpu.BindGroupEntry {
            return .{ .binding = binding_id, .size = self.padded_size_in_bytes, .buffer = self.handle };
        }
    };
}

pub fn Uniform(comptime T: type) type {
    return struct {
        const Self = @This();
        handle: wgpu.Buffer,
        padded_size_in_bytes: u64,

        pub fn init(device: wgpu.Device, read_only: bool, data: T) Self {
            var usage = wgpu.BufferUsage{ .uniform = true };
            if (!read_only) {
                usage.copy_dst = true;
            }

            const padded_size_in_bytes = paddedBufferSize(@sizeOf(T));
            const handle = device.createBuffer(.{
                .label = "[ornament] " ++ @typeName(T) ++ " uniform",
                .usage = usage,
                .mapped_at_creation = true,
                .size = padded_size_in_bytes,
            });
            var dst = handle.getMappedRange(T, 0, 1) orelse unreachable;
            std.mem.copy(T, dst, &[_]T{data});
            handle.unmap();

            return .{ .handle = handle, .padded_size_in_bytes = padded_size_in_bytes };
        }

        pub fn deinit(self: *Self) void {
            self.handle.release();
        }

        pub fn layout(self: Self, binding_id: u32, visibility: wgpu.ShaderStage) wgpu.BindGroupLayoutEntry {
            _ = self;
            return .{ .binding = binding_id, .visibility = visibility, .buffer = .{ .binding_type = .uniform } };
        }

        pub fn binding(self: Self, binding_id: u32) wgpu.BindGroupEntry {
            return .{ .binding = binding_id, .size = self.padded_size_in_bytes, .buffer = self.handle };
        }

        pub fn write(self: Self, queue: wgpu.Queue, data: T) void {
            queue.writeBuffer(self.handle, 0, T, &[_]T{data});
        }
    };
}

pub const Texture = struct {
    const Self = @This();
    txt: wgpu.Texture,
    txtv: wgpu.TextureView,

    pub fn init(device: wgpu.Device, texture: *ornament.Texture) Self {
        _ = texture;
        _ = device;
        @panic("TODO");
        // return .{
        //     .txt = device.createTexture(.{
        //         .usage = .{ .texture_binding = true, .copy_dst = true },
        //         .size = .{
        //             .width = texture.width,
        //             .height = texture.height,
        //             .depth_or_array_layers = 1,
        //         },
        //         .format = zgpu.imageInfoToTextureFormat(
        //             texture.num_components,
        //             texture.bytes_per_component,
        //             texture.is_hdr,
        //         ),
        //         .mip_level_count = 1,
        //     }),
        //     .txtv = null,
        // };
    }

    pub fn deinit(self: *Self) void {
        self.txtv.release();
        self.txt.release();
    }
};
