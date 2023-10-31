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
        const pixels_count = resolution.width * resolution.height;
        const buffer = Storage(gpu_structs.Vector4).init(device, .{ .element_count = pixels_count }, true, false);
        const accumulation_buffer = Storage(gpu_structs.Vector4).init(device, .{ .element_count = pixels_count }, true, false);

        var rng_seed = try allocator.alloc(u32, pixels_count);
        defer allocator.free(rng_seed);
        for (rng_seed, 0..) |*value, index| {
            value.* = @truncate(index);
        }
        const rng_state_buffer = Storage(u32).init(device, .{ .data = rng_seed }, false, false);

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
        len: u64,

        pub fn init(device: webgpu.Device, init_data: union(enum) { element_count: u64, data: []const T }, copy_src: bool, copy_dst: bool) Self {
            var usage = webgpu.BufferUsage{
                .storage = true,
                .copy_src = copy_src,
                .copy_dst = copy_dst,
            };

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

            return .{
                .handle = handle,
                .padded_size_in_bytes = padded_size_in_bytes,
                .len = count,
            };
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

pub fn ArrayList(comptime T: type) type {
    return struct {
        const Self = @This();
        dirty: bool = true,
        allocator: std.mem.Allocator,
        device: webgpu.Device,
        queue: webgpu.Queue,
        host_storage: std.ArrayList(T),
        device_storage: Storage(T),

        pub fn init(allocator: std.mem.Allocator, device: webgpu.Device, queue: webgpu.Queue) *Self {
            var self = allocator.create(ArrayList(T));
            self.* = .{
                .allocator = allocator,
                .device = device,
                .queue = queue,
                .host_storage = std.ArrayList(T).init(allocator),
                .device_storage = Storage(T).init(device, .{ .element_count = 0 }, true, true),
            };
            return self;
        }

        pub fn deinit(self: *Self) void {
            self.host_storage.deinit();
            self.device_storage.deinit();
            self.allocator.destroy(self);
        }

        pub fn to_general_interface(self: *Self) gpu_structs.ArrayList(T) {
            return .{
                .ptr = self,
                .vtable = &comptime .{
                    .flush_to_device = Self.flush_to_device,
                    .len = Self.len,
                    .get = Self.get,
                    .set = Self.set,
                    .get_slice_mut = Self.get_slice_mut,
                    .get_slice = Self.get_slice,
                    .get_slice_from = Self.get_slice_from,
                    .ensureUnusedCapacity = Self.ensureUnusedCapacity,
                    .ensureTotalCapacity = Self.ensureTotalCapacity,
                    .append = Self.append,
                    .addManyAsSlice = Self.addManyAsSlice,
                    .appendSlice = Self.appendSlice,
                    .appendNTimes = Self.appendNTimes,
                    .shrinkRetainingCapacity = Self.shrinkRetainingCapacity,
                    .clearRetainingCapacity = Self.clearRetainingCapacity,
                },
            };
        }

        pub fn flush_to_device(ctx: *anyopaque) void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            if (self.host_storage.items.len > self.device_storage.len) {
                self.device_storage.deinit();
                self.device_storage = Storage(T).init(self.device, .{ .data = self.host_storage.items }, true, true);
            } else {
                self.queue.writeBuffer(self.device_storage.handle, 0, T, self.host_storage.items);
            }
            self.dirty = false;
        }

        pub fn len(ctx: *const anyopaque) usize {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.host_storage.items.len;
        }

        pub fn get(ctx: *anyopaque, i: usize) T {
            var self: *Self = @ptrCast(@alignCast(ctx));
            return self.host_storage.items[i];
        }

        pub fn set(ctx: *anyopaque, i: usize, item: T) void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            self.host_storage.items[i] = item;
            self.dirty = true;
        }

        pub fn get_slice_mut(ctx: *anyopaque, start: usize, end: usize) []T {
            var self: *Self = @ptrCast(@alignCast(ctx));
            var slice = self.host_storage.items[start..end];
            self.dirty = true;
            return slice;
        }

        pub fn get_slice(ctx: *const anyopaque, start: usize, end: usize) []const T {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.host_storage.items[start..end];
        }

        pub fn get_slice_from(ctx: *const anyopaque, start: usize) []const T {
            const self: *Self = @ptrCast(@alignCast(ctx));
            return self.host_storage.items[start..];
        }

        pub fn ensureUnusedCapacity(ctx: *anyopaque, additional_count: usize) !void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            return self.host_storage.ensureUnusedCapacity(additional_count);
        }

        pub fn ensureTotalCapacity(ctx: *anyopaque, new_capacity: usize) !void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            return self.host_storage.ensureTotalCapacity(new_capacity);
        }

        pub fn append(ctx: *anyopaque, item: T) !void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            try self.host_storage.append(item);
            self.dirty = true;
        }

        pub fn addManyAsSlice(ctx: *anyopaque, n: usize) ![]T {
            var self: *Self = @ptrCast(@alignCast(ctx));
            var slice = try self.host_storage.addManyAsSlice(n);
            self.dirty = true;
            return slice;
        }

        pub fn appendSlice(ctx: *anyopaque, items: []const T) !void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            try self.host_storage.appendSlice(items);
            self.dirty = true;
        }

        pub fn appendNTimes(ctx: *anyopaque, value: T, n: usize) !void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            try self.host_storage.appendNTimes(value, n);
            self.dirty = true;
        }

        pub fn shrinkRetainingCapacity(ctx: *anyopaque, new_len: usize) void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            self.host_storage.shrinkRetainingCapacity(new_len);
            self.dirty = true;
        }

        pub fn clearRetainingCapacity(ctx: *anyopaque) void {
            var self: *Self = @ptrCast(@alignCast(ctx));
            self.host_storage.clearRetainingCapacity();
            self.dirty = true;
        }
    };
}
