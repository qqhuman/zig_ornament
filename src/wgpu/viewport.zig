const std = @import("std");
const wgpu = @import("zgpu").wgpu;
const util = @import("../util.zig");
const ornament = @import("../ornament.zig");
const buffers = @import("buffers.zig");
const wgsl_structs = @import("wgsl_structs.zig");
const WgpuContext = @import("wgpu_context.zig").WgpuContext;

pub const Viewport = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    ornament: *ornament.Context,
    swap_chain: ?wgpu.SwapChain,
    pipeline: ?WgpuRenderPipeline,
    shader_module: wgpu.ShaderModule,
    resolution: util.Resolution,
    dimensions_buffer: *buffers.Uniform(wgsl_structs.Resolution),

    pub fn init(allocator: std.mem.Allocator, ornament_ctx: *ornament.Context) !*Self {
        var wgsl_descriptor = wgpu.ShaderModuleWgslDescriptor{
            .code = @embedFile("shaders/viewport.wgsl"),
            .chain = .{ .next = null, .struct_type = .shader_module_wgsl_descriptor },
        };
        const shader_module = ornament_ctx.wgpu_context.device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[ornament] wgpu viewport shader module",
        });

        var resolution = ornament_ctx.getResolution();
        var self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .ornament = ornament_ctx,
            .swap_chain = null,
            .shader_module = shader_module,
            .pipeline = null,
            .resolution = resolution,
            .dimensions_buffer = try buffers.Uniform(wgsl_structs.Resolution).init(
                allocator,
                ornament_ctx.wgpu_context,
                false,
                [2]u32{ resolution.width, resolution.height },
            ),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        defer self.allocator.destroy(self);
        if (self.pipeline) |pipeline| {
            pipeline.release();
        }
        if (self.swap_chain) |swap_chain| {
            swap_chain.release();
        }
        self.shader_module.release();
        self.dimensions_buffer.deinit();
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) void {
        self.resolution = resolution;
        self.dimensions_buffer.write(self.ornament.wgpu_context.queue, [2]u32{ resolution.width, resolution.height });
        if (self.swap_chain) |swap_chain| {
            swap_chain.release();
            self.swap_chain = null;
        }
        if (self.pipeline) |pipeline| {
            pipeline.release();
            self.pipeline = null;
        }
    }

    fn createSwapChain(self: *const Self) wgpu.SwapChain {
        const surface = self.ornament.wgpu_context.surface orelse @panic("WGPUSurface is empty.");
        return self.ornament.wgpu_context.device.createSwapChain(surface, .{
            .label = "[ornament] wgpu viewport swap chain",
            .width = self.resolution.width,
            .height = self.resolution.height,
            .usage = .{ .render_attachment = true },
            .format = .bgra8_unorm,
            .present_mode = .immediate,
        });
    }

    fn createPipeline(self: *Self) !WgpuRenderPipeline {
        var targets = [_]wgpu.ColorTargetState{.{
            .format = .bgra8_unorm,
            .blend = &.{
                .color = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
                .alpha = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
            },
            .write_mask = wgpu.ColorWriteMask.all,
        }};

        const bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
            try self.ornament.targetBufferLayout(0, .{ .fragment = true }, true),
            self.dimensions_buffer.layout(1, .{ .fragment = true }),
        };
        const bind_group_layout = self.ornament.wgpu_context.device.createBindGroupLayout(.{
            .label = "[ornament] wgpu viewport render bgl",
            .entry_count = bind_group_layout_entries.len,
            .entries = &bind_group_layout_entries,
        });
        defer bind_group_layout.release();

        const bind_group_entries = [_]wgpu.BindGroupEntry{
            try self.ornament.targetBufferBinding(0),
            self.dimensions_buffer.binding(1),
        };
        const bind_group = self.ornament.wgpu_context.device.createBindGroup(.{
            .label = "[ornament] wgpu viewport render bl",
            .layout = bind_group_layout,
            .entry_count = bind_group_entries.len,
            .entries = &bind_group_entries,
        });

        const bind_group_layouts = [_]wgpu.BindGroupLayout{bind_group_layout};
        const pipeline_layout = self.ornament.wgpu_context.device.createPipelineLayout(.{
            .label = "[ornament] wgpu viewport render pl",
            .bind_group_layout_count = bind_group_layouts.len,
            .bind_group_layouts = &bind_group_layouts,
        });
        defer pipeline_layout.release();

        return .{
            .bind_group = bind_group,
            .render_pipeline = self.ornament.wgpu_context.device.createRenderPipeline(.{
                .label = "[ornament] wgpu viewport render pipeline",
                .layout = pipeline_layout,
                .vertex = .{ .entry_point = "vs_main", .module = self.shader_module },
                .fragment = &.{
                    .target_count = targets.len,
                    .targets = &targets,
                    .entry_point = "fs_main",
                    .module = self.shader_module,
                },
                .primitive = .{
                    .topology = .triangle_list,
                    .front_face = .ccw,
                    .cull_mode = .back,
                },
            }),
        };
    }

    pub fn render(self: *Self) !void {
        const swap_chain = self.swap_chain orelse blk: {
            const swap_chain = self.createSwapChain();
            self.swap_chain = swap_chain;
            break :blk swap_chain;
        };
        const pipeline = self.pipeline orelse blk: {
            const pipeline = try self.createPipeline();
            self.pipeline = pipeline;
            break :blk pipeline;
        };
        const next_texture = swap_chain.getCurrentTextureView();
        const commnad_encoder = self.ornament.wgpu_context.device.createCommandEncoder(.{ .label = "[ornament] wgpu viewport command encoder" });
        defer commnad_encoder.release();

        const color_attachments = [_]wgpu.RenderPassColorAttachment{.{
            .view = next_texture,
            .load_op = .clear,
            .store_op = .store,
            .clear_value = .{ .r = 0.9, .g = 0.1, .b = 0.2, .a = 1.0 },
        }};
        const render_pass = commnad_encoder.beginRenderPass(.{
            .label = "[ornament] wgpu viewport render pass",
            .color_attachment_count = color_attachments.len,
            .color_attachments = &color_attachments,
        });
        render_pass.setPipeline(pipeline.render_pipeline);
        render_pass.setBindGroup(0, pipeline.bind_group, null);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();
        next_texture.release();
        const command = commnad_encoder.finish(.{ .label = "[ornament] wgpu viewport command buffer" });
        defer command.release();
        const commands = [_]wgpu.CommandBuffer{command};
        self.ornament.wgpu_context.queue.submit(&commands);
        swap_chain.present();
    }
};

const WgpuRenderPipeline = struct {
    const Self = @This();
    bind_group: wgpu.BindGroup,
    render_pipeline: wgpu.RenderPipeline,

    pub fn release(self: Self) void {
        self.render_pipeline.release();
        self.bind_group.reference();
    }
};
