const std = @import("std");
const wgpu = @import("zgpu").wgpu;
const util = @import("../util.zig");
const ornament = @import("../ornament.zig");
const buffers = @import("buffers.zig");
const wgsl_structs = @import("wgsl_structs.zig");
const WgpuContext = @import("wgpu_context.zig").WgpuContext;

pub const Viewport = struct {
    const Self = @This();
    device: wgpu.Device,
    queue: wgpu.Queue,
    swap_chain: wgpu.SwapChain,
    pipeline: WgpuRenderPipeline,
    shader_module: wgpu.ShaderModule,
    resolution: util.Resolution,
    dimensions_buffer: buffers.Uniform(wgsl_structs.Resolution),

    pub fn init(ornament_ctx: *ornament.Context) !Self {
        var wgsl_descriptor = wgpu.ShaderModuleWgslDescriptor{
            .code = @embedFile("shaders/viewport.wgsl"),
            .chain = .{ .next = null, .struct_type = .shader_module_wgsl_descriptor },
        };
        const shader_module = ornament_ctx.wgpu_context.device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[ornament] wgpu viewport shader module",
        });

        var resolution = ornament_ctx.getResolution();

        const surface = ornament_ctx.wgpu_context.surface orelse @panic("WGPUSurface is empty.");
        const swap_chain = ornament_ctx.wgpu_context.device.createSwapChain(surface, .{
            .label = "[ornament] wgpu viewport swap chain",
            .width = resolution.width,
            .height = resolution.height,
            .usage = .{ .render_attachment = true },
            .format = .bgra8_unorm,
            .present_mode = .immediate,
        });

        const dimensions_buffer = buffers.Uniform(wgsl_structs.Resolution).init(
            ornament_ctx.wgpu_context.device,
            false,
            [2]u32{ resolution.width, resolution.height },
        );

        const pipeline = blk: {
            var targets = [_]wgpu.ColorTargetState{.{
                .format = .bgra8_unorm,
                .blend = &.{
                    .color = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
                    .alpha = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
                },
                .write_mask = wgpu.ColorWriteMask.all,
            }};

            const bind_group_layout_entries = [_]wgpu.BindGroupLayoutEntry{
                try ornament_ctx.targetBufferLayout(0, .{ .fragment = true }, true),
                dimensions_buffer.layout(1, .{ .fragment = true }),
            };
            const bind_group_layout = ornament_ctx.wgpu_context.device.createBindGroupLayout(.{
                .label = "[ornament] wgpu viewport render bgl",
                .entry_count = bind_group_layout_entries.len,
                .entries = &bind_group_layout_entries,
            });
            defer bind_group_layout.release();

            const bind_group_entries = [_]wgpu.BindGroupEntry{
                try ornament_ctx.targetBufferBinding(0),
                dimensions_buffer.binding(1),
            };
            const bind_group = ornament_ctx.wgpu_context.device.createBindGroup(.{
                .label = "[ornament] wgpu viewport render bl",
                .layout = bind_group_layout,
                .entry_count = bind_group_entries.len,
                .entries = &bind_group_entries,
            });

            const bind_group_layouts = [_]wgpu.BindGroupLayout{bind_group_layout};
            const pipeline_layout = ornament_ctx.wgpu_context.device.createPipelineLayout(.{
                .label = "[ornament] wgpu viewport render pl",
                .bind_group_layout_count = bind_group_layouts.len,
                .bind_group_layouts = &bind_group_layouts,
            });
            defer pipeline_layout.release();

            break :blk .{
                .bind_group = bind_group,
                .render_pipeline = ornament_ctx.wgpu_context.device.createRenderPipeline(.{
                    .label = "[ornament] wgpu viewport render pipeline",
                    .layout = pipeline_layout,
                    .vertex = .{ .entry_point = "vs_main", .module = shader_module },
                    .fragment = &.{
                        .target_count = targets.len,
                        .targets = &targets,
                        .entry_point = "fs_main",
                        .module = shader_module,
                    },
                    .primitive = .{
                        .topology = .triangle_list,
                        .front_face = .ccw,
                        .cull_mode = .back,
                    },
                }),
            };
        };

        return .{
            .device = ornament_ctx.wgpu_context.device,
            .queue = ornament_ctx.wgpu_context.queue,
            .swap_chain = swap_chain,
            .shader_module = shader_module,
            .pipeline = pipeline,
            .resolution = resolution,
            .dimensions_buffer = dimensions_buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.pipeline.release();
        self.swap_chain.release();
        self.shader_module.release();
        self.dimensions_buffer.deinit();
    }

    pub fn render(self: *Self) !void {
        const next_texture = self.swap_chain.getCurrentTextureView();
        const commnad_encoder = self.device.createCommandEncoder(.{ .label = "[ornament] wgpu viewport command encoder" });
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
        render_pass.setPipeline(self.pipeline.render_pipeline);
        render_pass.setBindGroup(0, self.pipeline.bind_group, null);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();
        next_texture.release();
        const command = commnad_encoder.finish(.{ .label = "[ornament] wgpu viewport command buffer" });
        defer command.release();
        const commands = [_]wgpu.CommandBuffer{command};
        self.queue.submit(&commands);
        self.swap_chain.present();
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
