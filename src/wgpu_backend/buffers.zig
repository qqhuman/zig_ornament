const std = @import("std");
const ornament = @import("../ornament.zig");
const webgpu = @import("webgpu.zig");
const util = @import("../util.zig");
const gpu_structs = @import("../gpu_structs.zig");

pub const WORKGROUP_SIZE: u32 = 256;

pub const Target = struct {
    const Self = @This();
    buffer: Storage(gpu_structs.Vector4),
    accumulation_buffer: Storage(gpu_structs.Vector4),
    rng_state_buffer: Storage(u32),
    pixels_count: u32,
    resolution: util.Resolution,
    workgroups: u32,

    pub fn init(allocator: std.mem.Allocator, device: webgpu.Device, resolution: util.Resolution) !Self {
        const pixels_count = resolution.pixels_count();
        const buffer = Storage(gpu_structs.Vector4).init(device, true, .{ .element_count = pixels_count });
        const accumulation_buffer = Storage(gpu_structs.Vector4).init(device, false, .{ .element_count = pixels_count });

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

    pub fn layout(self: *const Self, binding_id: u32, visibility: webgpu.ShaderStage, read_only: bool) webgpu.BindGroupLayoutEntry {
        return self.buffer.layout(binding_id, visibility, read_only);
    }

    pub fn binding(self: *const Self, binding_id: u32) webgpu.BindGroupEntry {
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
        handle: webgpu.Buffer,
        padded_size_in_bytes: u64,

        pub fn init(device: webgpu.Device, copy_src: bool, init_data: union(enum) { element_count: u64, data: []const T }) Self {
            var usage = webgpu.BufferUsage{ .storage = true };
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
                        .mapped_at_creation = if (data.len > 0) .true else .false,
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

        pub fn layout(self: *const Self, binding_id: u32, visibility: webgpu.ShaderStage, read_only: bool) webgpu.BindGroupLayoutEntry {
            _ = self;
            return .{
                .binding = binding_id,
                .visibility = visibility,
                .buffer = .{ .binding_type = if (read_only) .read_only_storage else .storage },
            };
        }

        pub fn binding(self: *const Self, binding_id: u32) webgpu.BindGroupEntry {
            return .{ .binding = binding_id, .size = self.padded_size_in_bytes, .buffer = self.handle };
        }
    };
}

pub fn Uniform(comptime T: type) type {
    return struct {
        const Self = @This();
        handle: webgpu.Buffer,
        padded_size_in_bytes: u64,

        pub fn init(device: webgpu.Device, read_only: bool, data: T) Self {
            var usage = webgpu.BufferUsage{ .uniform = true };
            if (!read_only) {
                usage.copy_dst = true;
            }

            const padded_size_in_bytes = paddedBufferSize(@sizeOf(T));
            const handle = device.createBuffer(.{
                .label = "[ornament] " ++ @typeName(T) ++ " uniform",
                .usage = usage,
                .mapped_at_creation = .true,
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

        pub fn layout(self: *const Self, binding_id: u32, visibility: webgpu.ShaderStage) webgpu.BindGroupLayoutEntry {
            _ = self;
            return .{ .binding = binding_id, .visibility = visibility, .buffer = .{ .binding_type = .uniform } };
        }

        pub fn binding(self: *const Self, binding_id: u32) webgpu.BindGroupEntry {
            return .{ .binding = binding_id, .size = self.padded_size_in_bytes, .buffer = self.handle };
        }

        pub fn write(self: *const Self, queue: webgpu.Queue, data: T) void {
            queue.writeBuffer(self.handle, 0, T, &[_]T{data});
        }
    };
}

pub const Textures = struct {
    const Self = @This();
    textures: std.ArrayList(webgpu.Texture),
    texture_views: std.ArrayList(webgpu.TextureView),
    samplers: std.ArrayList(webgpu.Sampler),
    len: u32 = 0,

    pub fn init(allocator: std.mem.Allocator, textures: []const *ornament.Texture, device: webgpu.Device, queue: webgpu.Queue) !Self {
        var self = Self{
            .textures = try std.ArrayList(webgpu.Texture).initCapacity(allocator, textures.len),
            .texture_views = try std.ArrayList(webgpu.TextureView).initCapacity(allocator, textures.len),
            .samplers = try std.ArrayList(webgpu.Sampler).initCapacity(allocator, textures.len),
        };

        for (textures) |texture| {
            try self.append(device, queue, texture);
        }

        if (textures.len == 0) {
            var data = [_]u8{
                0, 0, 0, 1,
                0, 0, 0, 1,
                0, 0, 0, 1,
                0, 0, 0, 1,
            };
            var texture = try ornament.Texture.init(
                allocator,
                &data,
                2,
                2,
                4,
                1,
                false,
                1.0,
            );
            defer texture.deinit();
            try self.append(device, queue, &texture);
        }

        return self;
    }

    fn append(self: *Self, device: webgpu.Device, queue: webgpu.Queue, ornament_texture: *const ornament.Texture) !void {
        const texture = device.createTexture(.{
            .usage = .{ .texture_binding = true, .copy_dst = true },
            .size = .{
                .width = ornament_texture.width,
                .height = ornament_texture.height,
                .depth_or_array_layers = 1,
            },
            .format = imageInfoToTextureFormat(
                ornament_texture.num_components,
                ornament_texture.bytes_per_component,
                ornament_texture.is_hdr,
            ),
            .mip_level_count = 1,
        });

        queue.writeTexture(
            .{ .texture = texture },
            .{
                .offset = 0,
                .bytes_per_row = ornament_texture.bytes_per_row,
                .rows_per_image = ornament_texture.height,
            },
            .{
                .width = ornament_texture.width,
                .height = ornament_texture.height,
                .depth_or_array_layers = 1,
            },
            u8,
            ornament_texture.data.items,
        );

        try self.textures.append(texture);
        try self.texture_views.append(texture.createView(&.{}));
        try self.samplers.append(device.createSampler(.{}));
        self.len += 1;
    }

    pub fn deinit(self: *Self) void {
        for (0..self.len) |i| {
            self.samplers.items[i].release();
            self.texture_views.items[i].release();
            self.textures.items[i].release();
        }
        self.samplers.deinit();
        self.texture_views.deinit();
        self.textures.deinit();
        self.len = 0;
    }

    fn imageInfoToTextureFormat(num_components: u32, bytes_per_component: u32, is_hdr: bool) webgpu.TextureFormat {
        std.debug.assert(num_components == 1 or num_components == 2 or num_components == 4);
        std.debug.assert(bytes_per_component == 1 or bytes_per_component == 2);
        std.debug.assert(if (is_hdr and bytes_per_component != 2) false else true);

        if (is_hdr) {
            if (num_components == 1) return .r16_float;
            if (num_components == 2) return .rg16_float;
            if (num_components == 4) return .rgba16_float;
        } else {
            if (bytes_per_component == 1) {
                if (num_components == 1) return .r8_unorm;
                if (num_components == 2) return .rg8_unorm;
                if (num_components == 4) return .rgba8_unorm;
            } else {
                // TODO: Looks like wgpu does not support 16 bit unorm formats.
                unreachable;
            }
        }
        unreachable;
    }
};
