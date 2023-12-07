pub const wgpu = @import("wgpu.zig");
pub const webgpu = @import("webgpu.zig");
pub const buffers = @import("buffers.zig");
pub const DeviceState = @import("device_state.zig").DeviceState;

const std = @import("std");
const gpu_structs = @import("../gpu_structs.zig");
const ornament = @import("../ornament.zig");
const util = @import("../util.zig");
const Bvh = @import("../bvh.zig").Bvh;
const State = @import("../state.zig").State;
const Scene = @import("../scene.zig").Scene;

pub const PathTracer = struct {
    pub const Self = @This();
    allocator: std.mem.Allocator,
    scene: Scene,
    state: State,

    device_state: DeviceState,
    shader_module: webgpu.ShaderModule,
    pipeline: ?Pipeline,

    target_buffer: ?buffers.Target,

    constant_params_buffer: buffers.Uniform(gpu_structs.ConstantParams),

    textures: buffers.Textures,
    materials_buffer: buffers.Storage(gpu_structs.Material),
    normals_buffer: buffers.Storage(gpu_structs.Normal),
    normal_indices_buffer: buffers.Storage(u32),
    uvs_buffer: buffers.Storage(gpu_structs.Uv),
    uv_indices_buffer: buffers.Storage(u32),
    transforms_buffer: buffers.Storage(gpu_structs.Transform),
    tlas_nodes_buffer: buffers.Storage(gpu_structs.BvhNode),
    blas_nodes_buffer: buffers.Storage(gpu_structs.BvhNode),

    pub fn init(allocator: std.mem.Allocator, scene: ornament.Scene, surface_descriptor: ?webgpu.SurfaceDescriptor) !Self {
        const device_state = try DeviceState.init(
            allocator,
            &.{
                .texture_binding_array,
                .sampled_texture_and_storage_buffer_array_non_uniform_indexing,
            },
            surface_descriptor,
        );

        var state = State.init();
        const constant_params_buffer = buffers.Uniform(gpu_structs.ConstantParams).init(
            device_state.device,
            false,
            gpu_structs.ConstantParams.from(&scene.camera, &state, @truncate(scene.textures.items.len)),
        );

        var bvh = try Bvh.init(allocator, &scene, false);
        defer bvh.deinit();
        const textures = try buffers.Textures.init(allocator, bvh.textures.items, device_state.device, device_state.queue);

        const materials_buffer = buffers.Storage(gpu_structs.Material).init(device_state.device, false, .{ .data = bvh.materials.items });
        const tlas_nodes_buffer = buffers.Storage(gpu_structs.BvhNode).init(device_state.device, false, .{ .data = bvh.tlas_nodes.items });
        const blas_nodes_buffer = buffers.Storage(gpu_structs.BvhNode).init(device_state.device, false, .{ .data = bvh.blas_nodes.items });
        const normals_buffer = buffers.Storage(gpu_structs.Normal).init(device_state.device, false, .{ .data = bvh.normals.items });
        const normal_indices_buffer = buffers.Storage(u32).init(device_state.device, false, .{ .data = bvh.normal_indices.items });
        const uvs_buffer = buffers.Storage(gpu_structs.Uv).init(device_state.device, false, .{ .data = bvh.uvs.items });
        const uv_indices_buffer = buffers.Storage(u32).init(device_state.device, false, .{ .data = bvh.uv_indices.items });
        const transforms_buffer = buffers.Storage(gpu_structs.Transform).init(device_state.device, false, .{ .data = bvh.transforms.items });

        log("materials_buffer", bvh.materials.items.len, materials_buffer.padded_size_in_bytes);
        log("tlas_nodes_buffer", bvh.tlas_nodes.items.len, tlas_nodes_buffer.padded_size_in_bytes);
        log("blas_nodes_buffer", bvh.blas_nodes.items.len, blas_nodes_buffer.padded_size_in_bytes);
        log("normals_buffer", bvh.normals.items.len, normals_buffer.padded_size_in_bytes);
        log("normal_indices_buffer", bvh.normal_indices.items.len, normal_indices_buffer.padded_size_in_bytes);
        log("uvs_buffer", bvh.uvs.items.len, uvs_buffer.padded_size_in_bytes);
        log("uv_indices_buffer", bvh.uv_indices.items.len, uv_indices_buffer.padded_size_in_bytes);
        log("transforms_buffer", bvh.transforms.items.len, transforms_buffer.padded_size_in_bytes);
        const bytes = materials_buffer.padded_size_in_bytes +
            tlas_nodes_buffer.padded_size_in_bytes +
            blas_nodes_buffer.padded_size_in_bytes +
            normals_buffer.padded_size_in_bytes +
            normal_indices_buffer.padded_size_in_bytes +
            uvs_buffer.padded_size_in_bytes +
            uv_indices_buffer.padded_size_in_bytes +
            transforms_buffer.padded_size_in_bytes;
        std.log.debug("[ornament], all buff bytes = {d}, mb = {d}", .{ bytes, bytes / (1024 * 1024) });

        return .{
            .allocator = allocator,
            .scene = scene,
            .state = state,

            .device_state = device_state,
            .shader_module = createShaderModule(device_state.device),
            .pipeline = null,
            .target_buffer = null,
            .constant_params_buffer = constant_params_buffer,

            .textures = textures,
            .materials_buffer = materials_buffer,
            .normals_buffer = normals_buffer,
            .normal_indices_buffer = normal_indices_buffer,
            .uvs_buffer = uvs_buffer,
            .uv_indices_buffer = uv_indices_buffer,
            .transforms_buffer = transforms_buffer,
            .tlas_nodes_buffer = tlas_nodes_buffer,
            .blas_nodes_buffer = blas_nodes_buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.pipeline) |*p| p.deinit();
        if (self.target_buffer) |*tb| tb.deinit();

        self.textures.deinit();
        self.materials_buffer.deinit();
        self.normals_buffer.deinit();
        self.normal_indices_buffer.deinit();
        self.uvs_buffer.deinit();
        self.uv_indices_buffer.deinit();
        self.transforms_buffer.deinit();
        self.tlas_nodes_buffer.deinit();
        self.blas_nodes_buffer.deinit();

        self.constant_params_buffer.deinit();
        self.shader_module.release();
        self.device_state.deinit();

        self.scene.deinit();
    }

    fn log(comptime buf_name: []const u8, elem_count: usize, buff_size: u64) void {
        std.log.debug("[ornament] {s}, elements = {d}, bytes = {d}", .{ buf_name, elem_count, buff_size });
    }

    fn createShaderModule(device: webgpu.Device) webgpu.ShaderModule {
        const code = @embedFile("shaders/pathtracer.wgsl") ++ "\n" ++
            @embedFile("shaders/bvh.wgsl") ++ "\n" ++
            @embedFile("shaders/camera.wgsl") ++ "\n" ++
            @embedFile("shaders/hitrecord.wgsl") ++ "\n" ++
            @embedFile("shaders/material.wgsl") ++ "\n" ++
            @embedFile("shaders/random.wgsl") ++ "\n" ++
            @embedFile("shaders/ray.wgsl") ++ "\n" ++
            @embedFile("shaders/states.wgsl") ++ "\n" ++
            @embedFile("shaders/transform.wgsl") ++ "\n" ++
            @embedFile("shaders/utility.wgsl");

        const wgsl_descriptor = webgpu.ShaderModuleWgslDescriptor{
            .code = code,
            .chain = .{ .next = null, .struct_type = .shader_module_wgsl_descriptor },
        };
        return device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[ornament] path tracer shader module",
        });
    }

    fn getWorkGroups(self: *Self) !u32 {
        const target = try self.getOrCreateTargetBuffer();
        return target.workgroups;
    }

    pub fn getFrameBuffer(self: *Self, dst: []gpu_structs.Vector4) !void {
        const tb = try self.getOrCreateTargetBuffer();
        try tb.getFrameBuffer(self.device_state.device, self.device_state.queue, dst);
    }

    pub fn getOrCreateTargetBuffer(self: *Self) !*buffers.Target {
        if (self.target_buffer == null) {
            self.target_buffer = try buffers.Target.init(self.allocator, self.device_state.device, self.state.resolution);
            std.log.debug("[ornament] target buffer was created", .{});
        }

        return &self.target_buffer.?;
    }

    fn getOrCreatePipeline(self: *Self) !*Pipeline {
        if (self.pipeline == null) {
            const target_buffer = try self.getOrCreateTargetBuffer();
            self.pipeline = Pipeline.init(
                self.device_state.device,
                self.shader_module,
                target_buffer,
                &self.constant_params_buffer,
                &self.materials_buffer,
                &self.textures,
                &self.normals_buffer,
                &self.normal_indices_buffer,
                &self.uvs_buffer,
                &self.uv_indices_buffer,
                &self.transforms_buffer,
                &self.tlas_nodes_buffer,
                &self.blas_nodes_buffer,
            );
        }

        return &self.pipeline.?;
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) !void {
        if (!std.meta.eql(self.state.getResolution(), resolution)) {
            self.state.setResolution(resolution);
            if (self.target_buffer) |*tb| {
                tb.deinit();
                self.target_buffer = null;
            }
            if (self.pipeline) |*p| {
                p.deinit();
                self.pipeline = null;
            }
        }
    }

    fn update(self: *Self) void {
        var dirty = false;
        if (self.scene.camera.dirty) {
            dirty = true;
            self.scene.camera.dirty = false;
        }

        if (dirty) self.state.reset();
        self.state.nextIteration();
        self.constant_params_buffer.write(
            self.device_state.queue,
            gpu_structs.ConstantParams.from(&self.scene.camera, &self.state, @truncate(self.scene.textures.items.len)),
        );
    }

    fn runPipeline(self: *Self, pipeline: webgpu.ComputePipeline, bind_groups: [4]webgpu.BindGroup, comptime pipeline_name: []const u8) !void {
        const encoder = self.device_state.device.createCommandEncoder(.{ .label = "[ornament] " ++ pipeline_name ++ "command encoder" });
        defer encoder.release();

        {
            const pass = encoder.beginComputePass(.{ .label = "[ornament] " ++ pipeline_name ++ " compute pass" });
            defer {
                pass.end();
                pass.release();
            }

            pass.setPipeline(pipeline);
            inline for (bind_groups, 0..) |bg, i| {
                pass.setBindGroup(i, bg, null);
            }
            pass.dispatchWorkgroups(try self.getWorkGroups(), 1, 1);
        }

        const command = encoder.finish(.{ .label = "[ornament] " ++ pipeline_name ++ " command buffer" });
        defer command.release();

        self.device_state.queue.submit(&[_]webgpu.CommandBuffer{command});
        _ = wgpu.wgpuDevicePoll(self.device_state.device, true, null);
    }

    pub fn render(self: *Self) !void {
        const pipeline = try self.getOrCreatePipeline();
        if (self.state.iterations > 1) {
            var i: u32 = 0;
            while (i < self.state.iterations) : (i += 1) {
                self.update();
                try self.runPipeline(pipeline.path_tracing, pipeline.bind_groups, "path tracing");
            }
            try self.runPipeline(pipeline.post_processing, pipeline.bind_groups, "post processing");
        } else {
            self.update();
            try self.runPipeline(pipeline.path_tracing_and_post_processing, pipeline.bind_groups, "path tracing and post processing");
        }
    }
};

pub const Pipeline = struct {
    pub const Self = @This();
    path_tracing: webgpu.ComputePipeline,
    post_processing: webgpu.ComputePipeline,
    path_tracing_and_post_processing: webgpu.ComputePipeline,
    bind_groups: [4]webgpu.BindGroup,

    pub fn init(
        device: webgpu.Device,
        shader_module: webgpu.ShaderModule,
        target_buffer: *const buffers.Target,
        constant_params_buffer: *const buffers.Uniform(gpu_structs.ConstantParams),
        materials_buffer: *const buffers.Storage(gpu_structs.Material),
        textures: *const buffers.Textures,
        normals_buffer: *const buffers.Storage(gpu_structs.Normal),
        normal_indices_buffer: *const buffers.Storage(u32),
        uvs_buffer: *const buffers.Storage(gpu_structs.Uv),
        uv_indices_buffer: *const buffers.Storage(u32),
        transforms_buffer: *const buffers.Storage(gpu_structs.Transform),
        tlas_nodes_buffer: *const buffers.Storage(gpu_structs.BvhNode),
        blas_nodes_buffer: *const buffers.Storage(gpu_structs.BvhNode),
    ) Self {
        const compute_visibility: webgpu.ShaderStage = .{ .compute = true };
        var bind_groups: [4]webgpu.BindGroup = undefined;
        var bind_group_layouts: [4]webgpu.BindGroupLayout = undefined;
        defer for (bind_group_layouts) |bgl| bgl.release();

        {
            const layout_entries = [_]webgpu.BindGroupLayoutEntry{
                target_buffer.buffer.layout(0, compute_visibility, false),
                target_buffer.accumulation_buffer.layout(1, compute_visibility, false),
                target_buffer.rng_state_buffer.layout(2, compute_visibility, false),
            };
            const bgl = device.createBindGroupLayout(.{
                .label = "[ornament] target bgl",
                .entry_count = layout_entries.len,
                .entries = &layout_entries,
            });

            const group_entries = [_]webgpu.BindGroupEntry{
                target_buffer.buffer.binding(0),
                target_buffer.accumulation_buffer.binding(1),
                target_buffer.rng_state_buffer.binding(2),
            };
            const bg = device.createBindGroup(.{
                .label = "[ornament] target bg",
                .layout = bgl,
                .entry_count = group_entries.len,
                .entries = &group_entries,
            });
            bind_group_layouts[0] = bgl;
            bind_groups[0] = bg;
        }

        {
            const layout_entries = [_]webgpu.BindGroupLayoutEntry{
                constant_params_buffer.layout(0, compute_visibility),
            };
            const bgl = device.createBindGroupLayout(.{
                .label = "[ornament] dynstate conststate bgl",
                .entry_count = layout_entries.len,
                .entries = &layout_entries,
            });

            const group_entries = [_]webgpu.BindGroupEntry{
                constant_params_buffer.binding(0),
            };
            const bg = device.createBindGroup(.{
                .label = "[ornament] dynstate constantparams bg",
                .layout = bgl,
                .entry_count = group_entries.len,
                .entries = &group_entries,
            });
            bind_group_layouts[1] = bgl;
            bind_groups[1] = bg;
        }

        {
            const layout_entries = [_]webgpu.BindGroupLayoutEntry{
                materials_buffer.layout(0, compute_visibility, true),
                normals_buffer.layout(1, compute_visibility, true),
                normal_indices_buffer.layout(2, compute_visibility, true),
                uvs_buffer.layout(3, compute_visibility, true),
                uv_indices_buffer.layout(4, compute_visibility, true),
                transforms_buffer.layout(5, compute_visibility, true),
                tlas_nodes_buffer.layout(6, compute_visibility, true),
                blas_nodes_buffer.layout(7, compute_visibility, true),
            };
            const bgl = device.createBindGroupLayout(.{
                .label = "[ornament] materials bvhnodes bgl",
                .entry_count = layout_entries.len,
                .entries = &layout_entries,
            });

            const group_entries = [_]webgpu.BindGroupEntry{
                materials_buffer.binding(0),
                normals_buffer.binding(1),
                normal_indices_buffer.binding(2),
                uvs_buffer.binding(3),
                uv_indices_buffer.binding(4),
                transforms_buffer.binding(5),
                tlas_nodes_buffer.binding(6),
                blas_nodes_buffer.binding(7),
            };
            const bg = device.createBindGroup(.{
                .label = "[ornament] materials bvhnodes bg",
                .layout = bgl,
                .entry_count = group_entries.len,
                .entries = &group_entries,
            });
            bind_group_layouts[2] = bgl;
            bind_groups[2] = bg;
        }

        {
            const bgl_entry_extras = wgpu.BindGroupLayoutEntryExtras{
                .chain = .{ .next = null, .struct_type = webgpu.StructType.bind_group_layout_entry_extras },
                .count = textures.len,
            };
            const layout_entries = [_]webgpu.BindGroupLayoutEntry{
                .{
                    .binding = 0,
                    .visibility = compute_visibility,
                    .texture = .{ .sample_type = .float },
                    .next_in_chain = @ptrCast(&bgl_entry_extras),
                },
                .{
                    .binding = 1,
                    .visibility = compute_visibility,
                    .sampler = .{ .binding_type = .filtering },
                    .next_in_chain = @ptrCast(&bgl_entry_extras),
                },
            };
            const bgl = device.createBindGroupLayout(.{
                .label = "[ornament] normals normal_indices transforms bgl",
                .entry_count = layout_entries.len,
                .entries = &layout_entries,
            });

            const bge_textures = wgpu.BindGroupEntryExtras{
                .chain = .{ .next = null, .struct_type = webgpu.StructType.bind_group_entry_extras },
                .texture_views = textures.texture_views.items.ptr,
                .texture_view_count = textures.len,
            };
            const bge_samplers = wgpu.BindGroupEntryExtras{
                .chain = .{ .next = null, .struct_type = webgpu.StructType.bind_group_entry_extras },
                .samplers = textures.samplers.items.ptr,
                .sampler_count = textures.len,
            };
            const group_entries = [_]webgpu.BindGroupEntry{
                .{ .binding = 0, .next_in_chain = @ptrCast(&bge_textures) },
                .{ .binding = 1, .next_in_chain = @ptrCast(&bge_samplers) },
            };
            const bg = device.createBindGroup(.{
                .label = "[ornament] normals normal_indices transforms bg",
                .layout = bgl,
                .entry_count = group_entries.len,
                .entries = &group_entries,
            });
            bind_group_layouts[3] = bgl;
            bind_groups[3] = bg;
        }

        const pipeline_layout = device.createPipelineLayout(.{
            .label = "[ornament] pipeline layout",
            .bind_group_layout_count = bind_group_layouts.len,
            .bind_group_layouts = &bind_group_layouts,
        });
        defer pipeline_layout.release();

        const self = .{
            .path_tracing = device.createComputePipeline(.{
                .label = "[ornament] path tracing pipeline",
                .layout = pipeline_layout,
                .compute = .{ .module = shader_module, .entry_point = "main_render" },
            }),
            .post_processing = device.createComputePipeline(.{
                .label = "[ornament] post processing pipeline",
                .layout = pipeline_layout,
                .compute = .{ .module = shader_module, .entry_point = "main_post_processing" },
            }),
            .path_tracing_and_post_processing = device.createComputePipeline(.{
                .label = "[ornament] post processing pipeline",
                .layout = pipeline_layout,
                .compute = .{ .module = shader_module, .entry_point = "main" },
            }),
            .bind_groups = bind_groups,
        };
        std.log.debug("[ornament] pipelines were created", .{});
        return self;
    }

    pub fn deinit(self: *Self) void {
        self.path_tracing.release();
        self.post_processing.release();
        self.path_tracing_and_post_processing.release();
        for (self.bind_groups) |bg| bg.release();
    }
};
