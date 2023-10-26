const std = @import("std");
const ornament = @import("ornament");
const webgpu = ornament.wgpu_backend.webgpu;

pub const Viewport = struct {
    const Self = @This();
    surface: webgpu.Surface,
    device: webgpu.Device,
    queue: webgpu.Queue,
    render_pipeline: webgpu.RenderPipeline,
    bind_group: webgpu.BindGroup,
    shader_module: webgpu.ShaderModule,
    resolution: ornament.Resolution,
    dimensions_buffer: ornament.wgpu_backend.buffers.Uniform([2]u32),

    pub fn init(ornament_ctx: *ornament.Ornament) !Self {
        var wgsl_descriptor = webgpu.ShaderModuleWgslDescriptor{
            .code = @embedFile("viewport.wgsl"),
            .chain = .{ .next = null, .struct_type = .shader_module_wgsl_descriptor },
        };
        const shader_module = ornament_ctx.backend_context.device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[glfw_example] wgpu viewport shader module",
        });

        var resolution = ornament_ctx.getResolution();

        const surface = ornament_ctx.backend_context.surface orelse @panic("WGPUSurface is empty.");
        const surface_capabilities = surface.getCapabilities(ornament_ctx.backend_context.adapter);
        const format = webgpu.TextureFormat.bgra8_unorm;
        surface.configure(&.{
            .device = ornament_ctx.backend_context.device,
            .width = resolution.width,
            .height = resolution.height,
            .usage = .{ .render_attachment = true },
            .format = format,
            .present_mode = surface_capabilities.present_modes.?[0],
            .alpha_mode = surface_capabilities.alpha_modes.?[0],
        });

        const dimensions_buffer = ornament.wgpu_backend.buffers.Uniform([2]u32).init(
            ornament_ctx.backend_context.device,
            false,
            [2]u32{ resolution.width, resolution.height },
        );

        const pipeline = ppl: {
            var targets = [_]webgpu.ColorTargetState{.{
                .format = format,
                .blend = &.{
                    .color = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
                    .alpha = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
                },
                .write_mask = webgpu.ColorWriteMask.all,
            }};

            const bind_group_layout_entries = [_]webgpu.BindGroupLayoutEntry{
                try ornament_ctx.targetBufferLayout(0, .{ .fragment = true }, true),
                dimensions_buffer.layout(1, .{ .fragment = true }),
            };
            const bind_group_layout = ornament_ctx.backend_context.device.createBindGroupLayout(.{
                .label = "[glfw_example] wgpu viewport render bgl",
                .entry_count = bind_group_layout_entries.len,
                .entries = &bind_group_layout_entries,
            });
            defer bind_group_layout.release();

            const bind_group_entries = [_]webgpu.BindGroupEntry{
                try ornament_ctx.targetBufferBinding(0),
                dimensions_buffer.binding(1),
            };
            const bind_group = ornament_ctx.backend_context.device.createBindGroup(.{
                .label = "[glfw_example] wgpu viewport render bl",
                .layout = bind_group_layout,
                .entry_count = bind_group_entries.len,
                .entries = &bind_group_entries,
            });

            const bind_group_layouts = [_]webgpu.BindGroupLayout{bind_group_layout};
            const pipeline_layout = ornament_ctx.backend_context.device.createPipelineLayout(.{
                .label = "[glfw_example] wgpu viewport render pl",
                .bind_group_layout_count = bind_group_layouts.len,
                .bind_group_layouts = &bind_group_layouts,
            });
            defer pipeline_layout.release();

            break :ppl .{
                .bind_group = bind_group,
                .render_pipeline = ornament_ctx.backend_context.device.createRenderPipeline(.{
                    .label = "[glfw_example] wgpu viewport render pipeline",
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
            .surface = surface,
            .device = ornament_ctx.backend_context.device,
            .queue = ornament_ctx.backend_context.queue,
            .shader_module = shader_module,
            .render_pipeline = pipeline.render_pipeline,
            .bind_group = pipeline.bind_group,
            .resolution = resolution,
            .dimensions_buffer = dimensions_buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.render_pipeline.release();
        self.bind_group.reference();
        self.shader_module.release();
        self.dimensions_buffer.deinit();
    }

    pub fn render(self: *Self) !void {
        const output = self.surface.getCurrentTexture();
        defer output.texture.release();
        if (output.status == .success) {
            const view = output.texture.createView(&.{});
            defer view.release();

            const commnad_encoder = self.device.createCommandEncoder(.{ .label = "[glfw_example] wgpu viewport command encoder" });
            defer commnad_encoder.release();
            {
                const color_attachments = [_]webgpu.RenderPassColorAttachment{.{
                    .view = view,
                    .load_op = .clear,
                    .store_op = .store,
                    .clear_value = .{ .r = 0.9, .g = 0.1, .b = 0.2, .a = 1.0 },
                }};
                const render_pass = commnad_encoder.beginRenderPass(.{
                    .label = "[glfw_example] wgpu viewport render pass",
                    .color_attachment_count = color_attachments.len,
                    .color_attachments = &color_attachments,
                });
                defer {
                    render_pass.end();
                    render_pass.release();
                }
                render_pass.setPipeline(self.render_pipeline);
                render_pass.setBindGroup(0, self.bind_group, null);
                render_pass.draw(3, 1, 0, 0);
            }

            const command = commnad_encoder.finish(.{ .label = "[glfw_example] wgpu viewport command buffer" });
            defer command.release();
            self.queue.submit(&[_]webgpu.CommandBuffer{command});
            self.surface.present();
        }
    }
};
