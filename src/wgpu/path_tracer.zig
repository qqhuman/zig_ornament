const std = @import("std");
const wgpu = @import("zgpu").wgpu;
const WgpuContext = @import("wgpu_context.zig").WgpuContext;
const wgsl_structs = @import("wgsl_structs.zig");
const buffers = @import("buffers.zig");
const ornament = @import("../ornament.zig");
const util = @import("../util.zig");
const Bvh = @import("../bvh.zig").Bvh;

pub const PathTracer = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    context: *const WgpuContext,

    resolution: util.Resolution,
    bvh: Bvh,
    dynamic_state: wgsl_structs.DynamicState,

    target_buffer: ?*buffers.Target,
    dynamic_state_buffer: *buffers.Uniform(wgsl_structs.DynamicState),
    constant_state_buffer: *buffers.Uniform(wgsl_structs.ConstantState),
    camera_buffer: *buffers.Uniform(wgsl_structs.Camera),

    materials_buffer: *buffers.Storage(wgsl_structs.Material),
    normals_buffer: *buffers.Storage(wgsl_structs.Normal),
    normal_indices_buffer: *buffers.Storage(u32),
    transforms_buffer: *buffers.Storage(wgsl_structs.Transform),
    nodes_buffer: *buffers.Storage(wgsl_structs.Node),

    shader_module: wgpu.ShaderModule,
    pipelines: ?WgpuPipelines,

    pub fn init(allocator: std.mem.Allocator, context: *const WgpuContext, state: *const ornament.State, scene: *const ornament.Scene) !*Self {
        const bvh = try Bvh.init(allocator, scene);
        const resolution = state.getResolution();

        const dynamic_state = wgsl_structs.DynamicState{};
        const dynamic_state_buffer = try buffers.Uniform(wgsl_structs.DynamicState).init(allocator, context, false, dynamic_state);
        const constant_state_buffer = try buffers.Uniform(wgsl_structs.ConstantState).init(allocator, context, false, wgsl_structs.ConstantState.from(state));
        const camera_buffer = try buffers.Uniform(wgsl_structs.Camera).init(allocator, context, false, wgsl_structs.Camera.from(&scene.camera));

        const materials_buffer = try buffers.Storage(wgsl_structs.Material).init(allocator, context, false, .{ .data = bvh.materials.items });
        const normals_buffer = try buffers.Storage(wgsl_structs.Normal).init(allocator, context, false, .{ .data = bvh.normals.items });
        const normal_indices_buffer = try buffers.Storage(u32).init(allocator, context, false, .{ .data = bvh.normal_indices.items });
        const transforms_buffer = try buffers.Storage(wgsl_structs.Transform).init(allocator, context, false, .{ .data = bvh.transforms.items });
        const nodes_buffer = try buffers.Storage(wgsl_structs.Node).init(allocator, context, false, .{ .data = bvh.nodes.items });

        const code = @embedFile("shaders/bvh.wgsl") ++ "\n" ++
            @embedFile("shaders/pathtracer.wgsl") ++ "\n" ++
            @embedFile("shaders/camera.wgsl") ++ "\n" ++
            @embedFile("shaders/hitrecord.wgsl") ++ "\n" ++
            @embedFile("shaders/material.wgsl") ++ "\n" ++
            @embedFile("shaders/random.wgsl") ++ "\n" ++
            @embedFile("shaders/ray.wgsl") ++ "\n" ++
            @embedFile("shaders/sphere.wgsl") ++ "\n" ++
            @embedFile("shaders/states.wgsl") ++ "\n" ++
            @embedFile("shaders/transform.wgsl") ++ "\n" ++
            @embedFile("shaders/utility.wgsl");

        const wgsl_descriptor = wgpu.ShaderModuleWgslDescriptor{
            .code = code,
            .chain = .{ .next = null, .struct_type = .shader_module_wgsl_descriptor },
        };
        const shader_module = context.device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[ornament] path tracer shader module",
        });

        var self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .context = context,

            .resolution = resolution,
            .bvh = bvh,
            .dynamic_state = dynamic_state,

            .target_buffer = null,
            .dynamic_state_buffer = dynamic_state_buffer,
            .constant_state_buffer = constant_state_buffer,
            .camera_buffer = camera_buffer,

            .materials_buffer = materials_buffer,
            .normals_buffer = normals_buffer,
            .normal_indices_buffer = normal_indices_buffer,
            .transforms_buffer = transforms_buffer,
            .nodes_buffer = nodes_buffer,

            .shader_module = shader_module,
            .pipelines = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        defer self.allocator.destroy(self);
        self.bvh.deinit();
        self.shader_module.release();
        self.dynamic_state_buffer.deinit();
        self.constant_state_buffer.deinit();
        self.camera_buffer.deinit();
        self.materials_buffer.deinit();
        self.normals_buffer.deinit();
        self.normal_indices_buffer.deinit();
        self.transforms_buffer.deinit();
        self.nodes_buffer.deinit();
        if (self.target_buffer) |tb| tb.deinit();
        if (self.pipelines) |pipelines| pipelines.release();
    }

    pub fn targetBufferLayout(self: *Self, binding: u32, visibility: wgpu.ShaderStage, read_only: bool) !wgpu.BindGroupLayoutEntry {
        const target = try self.getOrCreateTargetBuffer();
        return target.layout(binding, visibility, read_only);
    }

    pub fn targetBufferBinding(self: *Self, binding: u32) !wgpu.BindGroupEntry {
        const target = try self.getOrCreateTargetBuffer();
        return target.binding(binding);
    }

    fn getWorkGroups(self: *Self) !u32 {
        const target = try self.getOrCreateTargetBuffer();
        return target.workgroups;
    }

    fn getOrCreateTargetBuffer(self: *Self) !*buffers.Target {
        return self.target_buffer orelse {
            var tb = try buffers.Target.init(self.allocator, self.context, self.resolution);
            self.target_buffer = tb;
            std.log.debug("[ornament] target buffer was created", .{});
            return tb;
        };
    }

    fn getOrCreatePipelines(self: *Self) !WgpuPipelines {
        return self.pipelines orelse {
            const target_buffer = try self.getOrCreateTargetBuffer();
            var bind_groups: [4]wgpu.BindGroup = undefined;
            var bind_group_layouts: [4]wgpu.BindGroupLayout = undefined;
            defer for (bind_group_layouts) |bgl| bgl.release();

            {
                const layout_entries = [_]wgpu.BindGroupLayoutEntry{
                    target_buffer.buffer.layout(0, .{ .compute = true }, false),
                    target_buffer.accumulation_buffer.layout(1, .{ .compute = true }, false),
                    target_buffer.rng_state_buffer.layout(2, .{ .compute = true }, false),
                };
                const bgl = self.context.device.createBindGroupLayout(.{
                    .label = "[ornament] target bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const group_entries = [_]wgpu.BindGroupEntry{
                    target_buffer.buffer.binding(0),
                    target_buffer.accumulation_buffer.binding(1),
                    target_buffer.rng_state_buffer.binding(2),
                };
                const bg = self.context.device.createBindGroup(.{
                    .label = "[ornament] target bg",
                    .layout = bgl,
                    .entry_count = group_entries.len,
                    .entries = &group_entries,
                });
                bind_group_layouts[0] = bgl;
                bind_groups[0] = bg;
            }

            {
                const layout_entries = [_]wgpu.BindGroupLayoutEntry{
                    self.dynamic_state_buffer.layout(0, .{ .compute = true }),
                    self.constant_state_buffer.layout(1, .{ .compute = true }),
                    self.camera_buffer.layout(2, .{ .compute = true }),
                };
                const bgl = self.context.device.createBindGroupLayout(.{
                    .label = "[ornament] dynstate conststate camera bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const group_entries = [_]wgpu.BindGroupEntry{
                    self.dynamic_state_buffer.binding(0),
                    self.constant_state_buffer.binding(1),
                    self.camera_buffer.binding(2),
                };
                const bg = self.context.device.createBindGroup(.{
                    .label = "[ornament] dynstate conststate camera bg",
                    .layout = bgl,
                    .entry_count = group_entries.len,
                    .entries = &group_entries,
                });
                bind_group_layouts[1] = bgl;
                bind_groups[1] = bg;
            }

            {
                const layout_entries = [_]wgpu.BindGroupLayoutEntry{
                    self.materials_buffer.layout(0, .{ .compute = true }, true),
                    self.nodes_buffer.layout(1, .{ .compute = true }, true),
                };
                const bgl = self.context.device.createBindGroupLayout(.{
                    .label = "[ornament] materials bvhnodes bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const group_entries = [_]wgpu.BindGroupEntry{
                    self.materials_buffer.binding(0),
                    self.nodes_buffer.binding(1),
                };
                const bg = self.context.device.createBindGroup(.{
                    .label = "[ornament] materials bvhnodes bg",
                    .layout = bgl,
                    .entry_count = group_entries.len,
                    .entries = &group_entries,
                });
                bind_group_layouts[2] = bgl;
                bind_groups[2] = bg;
            }

            {
                const layout_entries = [_]wgpu.BindGroupLayoutEntry{
                    self.normals_buffer.layout(0, .{ .compute = true }, true),
                    self.normal_indices_buffer.layout(1, .{ .compute = true }, true),
                    self.transforms_buffer.layout(2, .{ .compute = true }, true),
                };
                const bgl = self.context.device.createBindGroupLayout(.{
                    .label = "[ornament] normals normal_indices transforms bgl",
                    .entry_count = layout_entries.len,
                    .entries = &layout_entries,
                });

                const group_entries = [_]wgpu.BindGroupEntry{
                    self.normals_buffer.binding(0),
                    self.normal_indices_buffer.binding(1),
                    self.transforms_buffer.binding(2),
                };
                const bg = self.context.device.createBindGroup(.{
                    .label = "[ornament] normals normal_indices transforms bg",
                    .layout = bgl,
                    .entry_count = group_entries.len,
                    .entries = &group_entries,
                });
                bind_group_layouts[3] = bgl;
                bind_groups[3] = bg;
            }

            const pipeline_layout = self.context.device.createPipelineLayout(.{
                .label = "[ornament] pipeline layout",
                .bind_group_layout_count = bind_group_layouts.len,
                .bind_group_layouts = &bind_group_layouts,
            });
            defer pipeline_layout.release();

            const pipelines = WgpuPipelines{
                .path_tracing_pipeline = self.context.device.createComputePipeline(.{
                    .label = "[ornament] path tracing pipeline",
                    .layout = pipeline_layout,
                    .compute = .{ .module = self.shader_module, .entry_point = "main_render" },
                }),
                .post_processing_pipeline = self.context.device.createComputePipeline(.{
                    .label = "[ornament] post processing pipeline",
                    .layout = pipeline_layout,
                    .compute = .{ .module = self.shader_module, .entry_point = "main_post_processing" },
                }),
                .path_tracing_and_post_processing_pipeline = self.context.device.createComputePipeline(.{
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
        if (self.target_buffer) |tb| {
            tb.deinit();
            self.target_buffer = null;
        }
        if (self.pipelines) |pipelines| {
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
            self.camera_buffer.write(self.context.queue, wgsl_structs.Camera.from(&scene.camera));
        }

        if (state.dirty) {
            dirty = true;
            state.dirty = false;
            self.constant_state_buffer.write(self.context.queue, wgsl_structs.ConstantState.from(state));
        }

        if (dirty) self.reset();
        self.dynamic_state.nextIteration();
        self.dynamic_state_buffer.write(self.context.queue, self.dynamic_state);
    }

    fn runPipeline(self: *Self, pipeline: wgpu.ComputePipeline, bind_groups: [4]wgpu.BindGroup, comptime pipeline_name: []const u8) !void {
        const encoder = self.context.device.createCommandEncoder(.{ .label = "[ornament] " ++ pipeline_name ++ "command encoder" });
        defer encoder.release();

        {
            const pass = encoder.beginComputePass(.{ .label = "[ornament] " ++ pipeline_name ++ " compute pass", .timestamp_write_count = 0, .timestamp_writes = null });
            defer pass.release();
            defer pass.end();

            pass.setPipeline(pipeline);
            inline for (bind_groups, 0..) |bg, i| {
                pass.setBindGroup(i, bg, null);
            }
            pass.dispatchWorkgroups(try self.getWorkGroups(), 1, 1);
        }

        const command = encoder.finish(.{ .label = "[ornament] " ++ pipeline_name ++ " command buffer" });
        defer command.release();

        self.context.queue.submit(&[_]wgpu.CommandBuffer{command});
        self.context.device.tick();
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
    path_tracing_pipeline: wgpu.ComputePipeline,
    post_processing_pipeline: wgpu.ComputePipeline,
    path_tracing_and_post_processing_pipeline: wgpu.ComputePipeline,
    bind_groups: [4]wgpu.BindGroup,

    pub fn release(self: Self) void {
        self.path_tracing_pipeline.release();
        self.post_processing_pipeline.release();
        self.path_tracing_and_post_processing_pipeline.release();
        for (self.bind_groups) |bg| bg.release();
    }
};
