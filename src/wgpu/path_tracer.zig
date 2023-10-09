const std = @import("std");
const webgpu = @import("webgpu.zig");
const wgpu = @import("wgpu.zig");
const WgpuContext = @import("wgpu_context.zig").WgpuContext;
const wgsl_structs = @import("wgsl_structs.zig");
const buffers = @import("buffers.zig");
const ornament = @import("../ornament.zig");
const util = @import("../util.zig");
const Bvh = @import("../bvh.zig").Bvh;

pub const PathTracer = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    device: webgpu.Device,
    queue: webgpu.Queue,

    resolution: util.Resolution,
    bvh: Bvh,
    dynamic_state: wgsl_structs.DynamicState,

    target_buffer: ?buffers.Target,
    dynamic_state_buffer: buffers.Uniform(wgsl_structs.DynamicState),
    constant_state_buffer: buffers.Uniform(wgsl_structs.ConstantState),
    camera_buffer: buffers.Uniform(wgsl_structs.Camera),

    materials_buffer: buffers.Storage(wgsl_structs.Material),
    textures: buffers.Textures,
    normals_buffer: buffers.Storage(wgsl_structs.Normal),
    normal_indices_buffer: buffers.Storage(u32),
    uvs_buffer: buffers.Storage(wgsl_structs.Uv),
    uv_indices_buffer: buffers.Storage(u32),
    transforms_buffer: buffers.Storage(wgsl_structs.Transform),
    tlas_nodes_buffer: buffers.Storage(wgsl_structs.Node),
    blas_nodes_buffer: buffers.Storage(wgsl_structs.Node),

    shader_module: webgpu.ShaderModule,
    pipelines: ?WgpuPipelines,

    pub fn init(allocator: std.mem.Allocator, device: webgpu.Device, queue: webgpu.Queue, ornament_ctx: *const ornament.Context) !Self {
        const bvh = try Bvh.init(allocator, ornament_ctx);
        const resolution = ornament_ctx.state.getResolution();

        const textures = try buffers.Textures.init(allocator, bvh.textures.items, device, queue);
        const dynamic_state = wgsl_structs.DynamicState{};
        const dynamic_state_buffer = buffers.Uniform(wgsl_structs.DynamicState).init(device, false, dynamic_state);
        const constant_state_buffer = buffers.Uniform(wgsl_structs.ConstantState).init(device, false, wgsl_structs.ConstantState.from(&ornament_ctx.state, textures.len));
        const camera_buffer = buffers.Uniform(wgsl_structs.Camera).init(device, false, wgsl_structs.Camera.from(&ornament_ctx.scene.camera));

        const materials_buffer = buffers.Storage(wgsl_structs.Material).init(device, false, .{ .data = bvh.materials.items });
        const tlas_nodes_buffer = buffers.Storage(wgsl_structs.Node).init(device, false, .{ .data = bvh.tlas_nodes.items });
        const blas_nodes_buffer = buffers.Storage(wgsl_structs.Node).init(device, false, .{ .data = bvh.blas_nodes.items });
        const normals_buffer = buffers.Storage(wgsl_structs.Normal).init(device, false, .{ .data = bvh.normals.items });
        const normal_indices_buffer = buffers.Storage(u32).init(device, false, .{ .data = bvh.normal_indices.items });
        const uvs_buffer = buffers.Storage(wgsl_structs.Uv).init(device, false, .{ .data = bvh.uvs.items });
        const uv_indices_buffer = buffers.Storage(u32).init(device, false, .{ .data = bvh.uv_indices.items });
        const transforms_buffer = buffers.Storage(wgsl_structs.Transform).init(device, false, .{ .data = bvh.transforms.items });

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
        const shader_module = device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[ornament] path tracer shader module",
        });

        return .{
            .allocator = allocator,
            .device = device,
            .queue = queue,

            .resolution = resolution,
            .bvh = bvh,
            .dynamic_state = dynamic_state,

            .target_buffer = null,
            .dynamic_state_buffer = dynamic_state_buffer,
            .constant_state_buffer = constant_state_buffer,
            .camera_buffer = camera_buffer,

            .materials_buffer = materials_buffer,
            .textures = textures,
            .normals_buffer = normals_buffer,
            .normal_indices_buffer = normal_indices_buffer,
            .uvs_buffer = uvs_buffer,
            .uv_indices_buffer = uv_indices_buffer,
            .transforms_buffer = transforms_buffer,
            .tlas_nodes_buffer = tlas_nodes_buffer,
            .blas_nodes_buffer = blas_nodes_buffer,

            .shader_module = shader_module,
            .pipelines = null,
        };
    }

    pub fn deinit(self: *Self) void {
        self.bvh.deinit();
        self.shader_module.release();
        self.dynamic_state_buffer.deinit();
        self.constant_state_buffer.deinit();
        self.camera_buffer.deinit();
        self.materials_buffer.deinit();
        self.textures.deinit();
        self.normals_buffer.deinit();
        self.normal_indices_buffer.deinit();
        self.uvs_buffer.deinit();
        self.uv_indices_buffer.deinit();
        self.transforms_buffer.deinit();
        self.tlas_nodes_buffer.deinit();
        self.blas_nodes_buffer.deinit();
        if (self.target_buffer) |*tb| tb.deinit();
        if (self.pipelines) |*pipelines| pipelines.release();
    }

    pub fn targetBufferLayout(self: *Self, binding: u32, visibility: webgpu.ShaderStage, read_only: bool) !webgpu.BindGroupLayoutEntry {
        const target = try self.getOrCreateTargetBuffer();
        return target.layout(binding, visibility, read_only);
    }

    pub fn targetBufferBinding(self: *Self, binding: u32) !webgpu.BindGroupEntry {
        const target = try self.getOrCreateTargetBuffer();
        return target.binding(binding);
    }

    fn getWorkGroups(self: *Self) !u32 {
        const target = try self.getOrCreateTargetBuffer();
        return target.workgroups;
    }

    fn getOrCreateTargetBuffer(self: *Self) !*buffers.Target {
        if (self.target_buffer == null) {
            var tb = try buffers.Target.init(self.allocator, self.device, self.resolution);
            self.target_buffer = tb;
            std.log.debug("[ornament] target buffer was created", .{});
        }

        return &self.target_buffer.?;
    }

    fn getOrCreatePipelines(self: *Self) !WgpuPipelines {
        return self.pipelines orelse {
            const target_buffer = try self.getOrCreateTargetBuffer();
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
                const bgl = self.device.createBindGroupLayout(.{
                    .label = "[ornament] target bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const group_entries = [_]webgpu.BindGroupEntry{
                    target_buffer.buffer.binding(0),
                    target_buffer.accumulation_buffer.binding(1),
                    target_buffer.rng_state_buffer.binding(2),
                };
                const bg = self.device.createBindGroup(.{
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
                    self.dynamic_state_buffer.layout(0, compute_visibility),
                    self.constant_state_buffer.layout(1, compute_visibility),
                    self.camera_buffer.layout(2, compute_visibility),
                };
                const bgl = self.device.createBindGroupLayout(.{
                    .label = "[ornament] dynstate conststate camera bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const group_entries = [_]webgpu.BindGroupEntry{
                    self.dynamic_state_buffer.binding(0),
                    self.constant_state_buffer.binding(1),
                    self.camera_buffer.binding(2),
                };
                const bg = self.device.createBindGroup(.{
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
                    self.materials_buffer.layout(0, compute_visibility, true),
                    self.normals_buffer.layout(1, compute_visibility, true),
                    self.normal_indices_buffer.layout(2, compute_visibility, true),
                    self.uvs_buffer.layout(3, compute_visibility, true),
                    self.uv_indices_buffer.layout(4, compute_visibility, true),
                    self.transforms_buffer.layout(5, compute_visibility, true),
                    self.tlas_nodes_buffer.layout(6, compute_visibility, true),
                    self.blas_nodes_buffer.layout(7, compute_visibility, true),
                };
                const bgl = self.device.createBindGroupLayout(.{
                    .label = "[ornament] materials bvhnodes bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const group_entries = [_]webgpu.BindGroupEntry{
                    self.materials_buffer.binding(0),
                    self.normals_buffer.binding(1),
                    self.normal_indices_buffer.binding(2),
                    self.uvs_buffer.binding(3),
                    self.uv_indices_buffer.binding(4),
                    self.transforms_buffer.binding(5),
                    self.tlas_nodes_buffer.binding(6),
                    self.blas_nodes_buffer.binding(7),
                };
                const bg = self.device.createBindGroup(.{
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
                    .count = self.textures.len,
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
                const bgl = self.device.createBindGroupLayout(.{
                    .label = "[ornament] normals normal_indices transforms bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const bge_textures = wgpu.BindGroupEntryExtras{
                    .chain = .{ .next = null, .struct_type = webgpu.StructType.bind_group_entry_extras },
                    .texture_views = self.textures.texture_views.items.ptr,
                    .texture_view_count = self.textures.len,
                };
                const bge_samplers = wgpu.BindGroupEntryExtras{
                    .chain = .{ .next = null, .struct_type = webgpu.StructType.bind_group_entry_extras },
                    .samplers = self.textures.samplers.items.ptr,
                    .sampler_count = self.textures.len,
                };
                const group_entries = [_]webgpu.BindGroupEntry{
                    .{ .binding = 0, .next_in_chain = @ptrCast(&bge_textures) },
                    .{ .binding = 1, .next_in_chain = @ptrCast(&bge_samplers) },
                };
                const bg = self.device.createBindGroup(.{
                    .label = "[ornament] normals normal_indices transforms bg",
                    .layout = bgl,
                    .entry_count = group_entries.len,
                    .entries = &group_entries,
                });
                bind_group_layouts[3] = bgl;
                bind_groups[3] = bg;
            }

            const pipeline_layout = self.device.createPipelineLayout(.{
                .label = "[ornament] pipeline layout",
                .bind_group_layout_count = bind_group_layouts.len,
                .bind_group_layouts = &bind_group_layouts,
            });
            defer pipeline_layout.release();

            const pipelines = WgpuPipelines{
                .path_tracing_pipeline = self.device.createComputePipeline(.{
                    .label = "[ornament] path tracing pipeline",
                    .layout = pipeline_layout,
                    .compute = .{ .module = self.shader_module, .entry_point = "main_render" },
                }),
                .post_processing_pipeline = self.device.createComputePipeline(.{
                    .label = "[ornament] post processing pipeline",
                    .layout = pipeline_layout,
                    .compute = .{ .module = self.shader_module, .entry_point = "main_post_processing" },
                }),
                .path_tracing_and_post_processing_pipeline = self.device.createComputePipeline(.{
                    .label = "[ornament] post processing pipeline",
                    .layout = pipeline_layout,
                    .compute = .{ .module = self.shader_module, .entry_point = "main" },
                }),
                .bind_groups = bind_groups,
            };
            self.pipelines = pipelines;
            std.log.debug("[ornament] pipelines were created", .{});
            return pipelines;
        };
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) void {
        self.resolution = resolution;
        if (self.target_buffer) |*tb| {
            tb.deinit();
            self.target_buffer = null;
        }
        if (self.pipelines) |*pipelines| {
            pipelines.release();
            self.pipelines = null;
        }
    }

    pub fn reset(self: *Self) void {
        self.dynamic_state.reset();
    }

    pub fn update(self: *Self, state: *ornament.State, scene: *ornament.Scene) void {
        var dirty = false;
        if (scene.camera.dirty) {
            dirty = true;
            scene.camera.dirty = false;
            self.camera_buffer.write(self.queue, wgsl_structs.Camera.from(&scene.camera));
        }

        if (state.dirty) {
            dirty = true;
            state.dirty = false;
            self.constant_state_buffer.write(self.queue, wgsl_structs.ConstantState.from(state, self.textures.len));
        }

        if (dirty) self.reset();
        self.dynamic_state.nextIteration();
        self.dynamic_state_buffer.write(self.queue, self.dynamic_state);
    }

    fn runPipeline(self: *Self, pipeline: webgpu.ComputePipeline, bind_groups: [4]webgpu.BindGroup, comptime pipeline_name: []const u8) !void {
        const encoder = self.device.createCommandEncoder(.{ .label = "[ornament] " ++ pipeline_name ++ "command encoder" });
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

        self.queue.submit(&[_]webgpu.CommandBuffer{command});
        _ = @import("wgpu.zig").wgpuDevicePoll(self.device, true, null);
    }

    pub fn render(self: *Self) !void {
        const pipelines = try self.getOrCreatePipelines();
        return self.runPipeline(pipelines.path_tracing_pipeline, pipelines.bind_groups, "path tracing");
    }

    pub fn post_processing(self: *Self) !void {
        const pipelines = try self.getOrCreatePipelines();
        return self.runPipeline(pipelines.post_processing_pipeline, pipelines.bind_groups, "post processing");
    }

    pub fn render_and_apply_post_processing(self: *Self) !void {
        const pipelines = try self.getOrCreatePipelines();
        return self.runPipeline(pipelines.path_tracing_and_post_processing_pipeline, pipelines.bind_groups, "path tracing and post processing");
    }
};

pub const WgpuPipelines = struct {
    pub const Self = @This();
    path_tracing_pipeline: webgpu.ComputePipeline,
    post_processing_pipeline: webgpu.ComputePipeline,
    path_tracing_and_post_processing_pipeline: webgpu.ComputePipeline,
    bind_groups: [4]webgpu.BindGroup,

    pub fn release(self: Self) void {
        self.path_tracing_pipeline.release();
        self.post_processing_pipeline.release();
        self.path_tracing_and_post_processing_pipeline.release();
        for (self.bind_groups) |bg| bg.release();
    }
};
