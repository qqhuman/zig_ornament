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
    target_buffer: ?ornament.wgpu_backend.buffers.Storage([4]f32),

    pub fn init(
        device_state: *const ornament.wgpu_backend.DeviceState,
        resolution: ornament.Resolution,
        optional_interop_target_buffer: ?*const ornament.wgpu_backend.buffers.Storage([4]f32),
    ) !Self {
        var wgsl_descriptor = webgpu.ShaderModuleWgslDescriptor{
            .code = @embedFile("viewport.wgsl"),
            .chain = .{ .next = null, .struct_type = .shader_module_wgsl_descriptor },
        };
        const shader_module = device_state.device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[glfw_wgpu] wgpu viewport shader module",
        });

        const surface = device_state.surface orelse @panic("WGPUSurface is empty.");
        const surface_capabilities = surface.getCapabilities(device_state.adapter);
        const format = webgpu.TextureFormat.bgra8_unorm;
        surface.configure(&.{
            .device = device_state.device,
            .width = resolution.width,
            .height = resolution.height,
            .usage = .{ .render_attachment = true },
            .format = format,
            .present_mode = surface_capabilities.present_modes.?[0],
            .alpha_mode = surface_capabilities.alpha_modes.?[0],
        });

        const dimensions_buffer = ornament.wgpu_backend.buffers.Uniform([2]u32).init(
            device_state.device,
            false,
            [2]u32{ resolution.width, resolution.height },
        );

        var target_buffer: ?ornament.wgpu_backend.buffers.Storage([4]f32) = null;
        const interop_target_buffer = optional_interop_target_buffer orelse itb: {
            target_buffer = ornament.wgpu_backend.buffers.Storage([4]f32).init(
                device_state.device,
                true,
                .{ .element_count = resolution.pixels_count() },
            );
            break :itb &target_buffer.?;
        };

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
                interop_target_buffer.layout(0, .{ .fragment = true }, true),
                dimensions_buffer.layout(1, .{ .fragment = true }),
            };
            const bind_group_layout = device_state.device.createBindGroupLayout(.{
                .label = "[glfw_wgpu] wgpu viewport render bgl",
                .entry_count = bind_group_layout_entries.len,
                .entries = &bind_group_layout_entries,
            });
            defer bind_group_layout.release();

            const bind_group_entries = [_]webgpu.BindGroupEntry{
                interop_target_buffer.binding(0),
                dimensions_buffer.binding(1),
            };
            const bind_group = device_state.device.createBindGroup(.{
                .label = "[glfw_wgpu] wgpu viewport render bl",
                .layout = bind_group_layout,
                .entry_count = bind_group_entries.len,
                .entries = &bind_group_entries,
            });

            const bind_group_layouts = [_]webgpu.BindGroupLayout{bind_group_layout};
            const pipeline_layout = device_state.device.createPipelineLayout(.{
                .label = "[glfw_wgpu] wgpu viewport render pl",
                .bind_group_layout_count = bind_group_layouts.len,
                .bind_group_layouts = &bind_group_layouts,
            });
            defer pipeline_layout.release();

            break :ppl .{
                .bind_group = bind_group,
                .render_pipeline = device_state.device.createRenderPipeline(.{
                    .label = "[glfw_wgpu] wgpu viewport render pipeline",
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
            .device = device_state.device,
            .queue = device_state.queue,
            .shader_module = shader_module,
            .render_pipeline = pipeline.render_pipeline,
            .bind_group = pipeline.bind_group,
            .resolution = resolution,
            .dimensions_buffer = dimensions_buffer,
            .target_buffer = target_buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.render_pipeline.release();
        self.bind_group.reference();
        self.shader_module.release();
        self.dimensions_buffer.deinit();
        if (self.target_buffer) |*tb| tb.deinit();
    }

    pub fn render(self: *Self) !void {
        const output = self.surface.getCurrentTexture();
        defer output.texture.release();
        if (output.status == .success) {
            const view = output.texture.createView(&.{});
            defer view.release();

            const commnad_encoder = self.device.createCommandEncoder(.{ .label = "[glfw_wgpu] wgpu viewport command encoder" });
            defer commnad_encoder.release();
            {
                const color_attachments = [_]webgpu.RenderPassColorAttachment{.{
                    .view = view,
                    .load_op = .clear,
                    .store_op = .store,
                    .clear_value = .{ .r = 0.9, .g = 0.1, .b = 0.2, .a = 1.0 },
                }};
                const render_pass = commnad_encoder.beginRenderPass(.{
                    .label = "[glfw_wgpu] wgpu viewport render pass",
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

            const command = commnad_encoder.finish(.{ .label = "[glfw_wgpu] wgpu viewport command buffer" });
            defer command.release();
            self.queue.submit(&[_]webgpu.CommandBuffer{command});
            self.surface.present();
        }
    }
};
