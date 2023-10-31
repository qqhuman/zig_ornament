pub const wgpu = @import("wgpu.zig");
pub const webgpu = @import("webgpu.zig");
pub const buffers = @import("buffers.zig");
pub const DeviceState = @import("device_state.zig").DeviceState;
const BvhBlas = @import("../bvh_blas.zig").BvhBlas;
const BvhTlas = @import("../bvh_tlas.zig").BvhTlas;
const std = @import("std");
const gpu_structs = @import("../gpu_structs.zig");
const ornament = @import("../ornament.zig");
const util = @import("../util.zig");

pub const Backend = struct {
    pub const Self = @This();
    allocator: std.mem.Allocator,
    dynamic_state: gpu_structs.DynamicState,
    resolution: util.Resolution,

    device_state: DeviceState,
    shader_module: webgpu.ShaderModule,
    pipeline: ?Pipeline,

    target_buffer: ?buffers.Target,

    dynamic_state_buffer: buffers.Uniform(gpu_structs.DynamicState),
    constant_state_buffer: buffers.Uniform(gpu_structs.ConstantState),
    camera_buffer: buffers.Uniform(gpu_structs.Camera),

    blas_nodes: *buffers.ArrayList(gpu_structs.Node),
    normals: *buffers.ArrayList(gpu_structs.Normal),
    normal_indices: *buffers.ArrayList(u32),
    uvs: *buffers.ArrayList(gpu_structs.Uv),
    uv_indices: *buffers.ArrayList(u32),

    tlas_nodes: *buffers.ArrayList(gpu_structs.Node),
    transforms: *buffers.ArrayList(gpu_structs.Transform),

    bvh_blas: BvhBlas,
    bvh_tlas: BvhTlas,

    pub fn init(allocator: std.mem.Allocator, surface_descriptor: ?webgpu.SurfaceDescriptor, scene: *const ornament.Scene, state: *const ornament.State) !Self {
        const device_state = try DeviceState.init(allocator, surface_descriptor);

        const dynamic_state = gpu_structs.DynamicState{};
        const dynamic_state_buffer = buffers.Uniform(gpu_structs.DynamicState).init(device_state.device, false, dynamic_state);
        const constant_state_buffer = buffers.Uniform(gpu_structs.ConstantState).init(device_state.device, false, gpu_structs.ConstantState.from(state));
        const camera_buffer = buffers.Uniform(gpu_structs.Camera).init(device_state.device, false, gpu_structs.Camera.from(&scene.camera));

        const tlas_nodes = buffers.ArrayList(gpu_structs.Node).init(allocator, device_state.device, device_state.queue);
        const transforms = buffers.ArrayList(gpu_structs.Transform).init(allocator, device_state.device, device_state.queue);

        const blas_nodes = buffers.ArrayList(gpu_structs.Node).init(allocator, device_state.device, device_state.queue);
        const normals = buffers.ArrayList(gpu_structs.Normal).init(allocator, device_state.device, device_state.queue);
        const normal_indices = buffers.ArrayList(gpu_structs.u32).init(allocator, device_state.device, device_state.queue);
        const uvs = buffers.ArrayList(gpu_structs.Uv).init(allocator, device_state.device, device_state.queue);
        const uv_indices = buffers.ArrayList(u32).init(allocator, device_state.device, device_state.queue);

        return .{
            .allocator = allocator,
            .dynamic_state = dynamic_state,
            .resolution = state.getResolution(),
            .device_state = device_state,
            .shader_module = createShaderModule(device_state.device),
            .pipeline = null,
            .target_buffer = null,
            .storage_buffers = null,
            .dynamic_state_buffer = dynamic_state_buffer,
            .constant_state_buffer = constant_state_buffer,
            .camera_buffer = camera_buffer,

            .tlas_nodes = tlas_nodes,
            .transforms = transforms,

            .blas_nodes = blas_nodes,
            .normals = normals,
            .normal_indices = normal_indices,
            .uvs = uvs,
            .uv_indices = uv_indices,

            .bvh_tlas = BvhTlas.init(
                allocator,
                tlas_nodes.to_general_interface(),
                transforms.to_general_interface(),
            ),
            .bvh_blas = BvhBlas.init(
                allocator,
                blas_nodes.to_general_interface(),
                normals.to_general_interface(),
                normal_indices.to_general_interface(),
                uvs.to_general_interface(),
                uv_indices.to_general_interface(),
            ),
        };
    }

    pub fn deinit(self: *Self) void {
        if (self.pipeline) |*p| p.deinit();
        if (self.storage_buffers) |*sb| sb.deinit();
        if (self.target_buffer) |*tb| tb.deinit();
        self.bvh_tlas.deinit();
        self.bvh_blas.deinit();

        self.tlas_nodes.deinit();
        self.transforms.deinit();

        self.blas_nodes.deinit();
        self.normals.deinit();
        self.normal_indices.deinit();
        self.uvs.deinit();
        self.uv_indices.deinit();

        self.dynamic_state_buffer.deinit();
        self.constant_state_buffer.deinit();
        self.camera_buffer.deinit();
        self.shader_module.release();
        self.device_state.deinit();
    }

    fn createShaderModule(device: webgpu.Device) webgpu.ShaderModule {
        const code = @embedFile("shaders/pathtracer.wgsl") ++ "\n" ++
            @embedFile("shaders/bvh.wgsl") ++ "\n" ++
            @embedFile("shaders/camera.wgsl") ++ "\n" ++
            @embedFile("shaders/hitrecord.wgsl") ++ "\n" ++
            @embedFile("shaders/material.wgsl") ++ "\n" ++
            @embedFile("shaders/random.wgsl") ++ "\n" ++
            @embedFile("shaders/ray.wgsl") ++ "\n" ++
            @embedFile("shaders/sphere.wgsl") ++ "\n" ++
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

    pub fn getOrCreateTargetBuffer(self: *Self) !*buffers.Target {
        if (self.target_buffer == null) {
            self.target_buffer = try buffers.Target.init(self.allocator, self.device_state.device, self.resolution);
            std.log.debug("[ornament] target buffer was created", .{});
        }

        return &self.target_buffer.?;
    }

    fn getOrCreatePipeline(self: *Self, ornament_ctx: *const ornament.Ornament) !*Pipeline {
        if (self.pipeline == null) {
            const storage_buffers = try self.getOrCreateStorageBuffers(ornament_ctx);
            const target_buffer = try self.getOrCreateTargetBuffer();
            self.pipeline = Pipeline.init(
                self.device_state.device,
                self.shader_module,
                target_buffer,
                &self.dynamic_state_buffer,
                &self.constant_state_buffer,
                &self.camera_buffer,
                &storage_buffers.materials_buffer,
                &storage_buffers.textures,
                &storage_buffers.normals_buffer,
                &storage_buffers.normal_indices_buffer,
                &storage_buffers.uvs_buffer,
                &storage_buffers.uv_indices_buffer,
                &storage_buffers.transforms_buffer,
                &storage_buffers.tlas_nodes_buffer,
                &storage_buffers.blas_nodes_buffer,
            );
        }

        return &self.pipeline.?;
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) void {
        self.resolution = resolution;
        if (self.target_buffer) |*tb| {
            tb.deinit();
            self.target_buffer = null;
        }
        if (self.pipeline) |*p| {
            p.deinit();
            self.pipeline = null;
        }
    }

    pub fn reset(self: *Self) void {
        self.dynamic_state.reset();
    }

    pub fn update(self: *Self, ornament_ctx: *ornament.Ornament) void {
        var dirty = false;
        if (ornament_ctx.scene.camera.dirty) {
            dirty = true;
            ornament_ctx.scene.camera.dirty = false;
            self.camera_buffer.write(self.device_state.queue, gpu_structs.Camera.from(&ornament_ctx.scene.camera));
        }

        if (ornament_ctx.state.dirty) {
            dirty = true;
            ornament_ctx.state.dirty = false;
            self.constant_state_buffer.write(self.device_state.queue, gpu_structs.ConstantState.from(&ornament_ctx.state));
        }

        if (dirty) self.reset();
        self.dynamic_state.nextIteration();
        self.dynamic_state_buffer.write(self.device_state.queue, self.dynamic_state);
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

    pub fn render(self: *Self, ornament_ctx: *ornament.Ornament) !void {
        const pipeline = try self.getOrCreatePipeline(ornament_ctx);
        if (ornament_ctx.state.iterations > 1) {
            var i: u32 = 0;
            while (i < ornament_ctx.state.iterations) : (i += 1) {
                self.update(ornament_ctx);
                try self.runPipeline(pipeline.path_tracing, pipeline.bind_groups, "path tracing");
            }
            try self.runPipeline(pipeline.post_processing, pipeline.bind_groups, "post processing");
        } else {
            self.update(ornament_ctx);
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
        dynamic_state_buffer: *const buffers.Uniform(gpu_structs.DynamicState),
        constant_state_buffer: *const buffers.Uniform(gpu_structs.ConstantState),
        camera_buffer: *const buffers.Uniform(gpu_structs.Camera),
        materials_buffer: *const buffers.Storage(gpu_structs.Material),
        textures: *const buffers.Textures,
        normals_buffer: *const buffers.Storage(gpu_structs.Normal),
        normal_indices_buffer: *const buffers.Storage(u32),
        uvs_buffer: *const buffers.Storage(gpu_structs.Uv),
        uv_indices_buffer: *const buffers.Storage(u32),
        transforms_buffer: *const buffers.Storage(gpu_structs.Transform),
        tlas_nodes_buffer: *const buffers.Storage(gpu_structs.Node),
        blas_nodes_buffer: *const buffers.Storage(gpu_structs.Node),
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
                dynamic_state_buffer.layout(0, compute_visibility),
                constant_state_buffer.layout(1, compute_visibility),
                camera_buffer.layout(2, compute_visibility),
            };
            const bgl = device.createBindGroupLayout(.{
                .label = "[ornament] dynstate conststate camera bgl",
                .entry_count = layout_entries.len,
                .entries = &layout_entries,
            });

            const group_entries = [_]webgpu.BindGroupEntry{
                dynamic_state_buffer.binding(0),
                constant_state_buffer.binding(1),
                camera_buffer.binding(2),
            };
            const bg = device.createBindGroup(.{
                .label = "[ornament] dynstate conststate camera bg",
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
