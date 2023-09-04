const std = @import("std");
const wgpu = @import("zgpu").wgpu;
const util = @import("../util.zig");
const WgpuContext = @import("wgpu_context.zig").WgpuContext;

pub const Viewport = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    context: *const WgpuContext,
    swap_chain: ?wgpu.SwapChain,
    pipeline: ?wgpu.RenderPipeline,
    shader_module: wgpu.ShaderModule,
    resolution: util.Resolution,

    pub fn init(allocator: std.mem.Allocator, context: *const WgpuContext, resolution: util.Resolution) !*Self {
        var wgsl_descriptor = wgpu.ShaderModuleWgslDescriptor{
            .code = @embedFile("shaders/viewport.wgsl"),
            .chain = .{ .next = null, .struct_type = .shader_module_wgsl_descriptor },
        };
        const shader_module = context.device.createShaderModule(.{
            .next_in_chain = @ptrCast(&wgsl_descriptor),
            .label = "[ornament] wgpu viewport shader module",
        });

        var self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .context = context,
            .swap_chain = null,
            .shader_module = shader_module,
            .pipeline = null,
            .resolution = resolution,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        defer self.allocator.destroy(self);
        if (self.pipeline) |pipeline| {
            pipeline.release();
        }
        self.shader_module.release();
        if (self.swap_chain) |swap_chain| {
            swap_chain.release();
        }
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) void {
        self.resolution = resolution;
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
        const surface = self.context.surface orelse @panic("WGPUSurface is empty.");
        return self.context.device.createSwapChain(surface, .{
            .label = "[ornament] wgpu viewport swap chain",
            .width = self.resolution.width,
            .height = self.resolution.height,
            .usage = .{ .render_attachment = true },
            .format = .bgra8_unorm,
            .present_mode = .immediate,
        });
    }

    fn createPipeline(self: *Self) wgpu.RenderPipeline {
        var targets = [_]wgpu.ColorTargetState{.{
            .format = .bgra8_unorm,
            .blend = &.{
                .color = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
                .alpha = .{ .src_factor = .one, .dst_factor = .zero, .operation = .add },
            },
            .write_mask = wgpu.ColorWriteMask.all,
        }};
        return self.context.device.createRenderPipeline(.{
            .label = "[ornament] wgpu viewport render pipeline",
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
        });
    }

    pub fn render(self: *Self) void {
        const swap_chain = self.swap_chain orelse blk: {
            const swap_chain = self.createSwapChain();
            self.swap_chain = swap_chain;
            break :blk swap_chain;
        };
        const pipeline = self.pipeline orelse blk: {
            const pipeline = self.createPipeline();
            self.pipeline = pipeline;
            break :blk pipeline;
        };
        const next_texture = swap_chain.getCurrentTextureView();
        const commnad_encoder = self.context.device.createCommandEncoder(.{ .label = "[ornament] wgpu viewport command encoder" });
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
        render_pass.setPipeline(pipeline);
        render_pass.draw(3, 1, 0, 0);
        render_pass.end();
        next_texture.release();
        const command = commnad_encoder.finish(.{ .label = "[ornament] wgpu viewport command buffer" });
        defer command.release();
        const commands = [_]wgpu.CommandBuffer{command};
        self.context.queue.submit(&commands);
        swap_chain.present();
    }
};
