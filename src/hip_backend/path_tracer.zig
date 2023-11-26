const std = @import("std");
const hip = @import("hip.zig");
pub const matrix_transpose_example = hip.matrixTransposeExample;

const buffers = @import("buffers.zig");
const ornament = @import("../ornament.zig");
const State = @import("../state.zig").State;
const Scene = @import("../scene.zig").Scene;
const util = @import("../util.zig");
const Bvh = @import("../bvh.zig").Bvh;
const gpu_structs = @import("../gpu_structs.zig");

pub const PathTracer = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    scene: Scene,
    state: State,
    resolution: util.Resolution,

    module: hip.c.hipModule_t,
    path_tracing_and_post_processing_kernal: hip.c.hipFunction_t,
    path_tracing_kernal: hip.c.hipFunction_t,
    post_processing_kernal: hip.c.hipFunction_t,

    target_buffer: ?buffers.Target,
    //textures: buffers.Textures,
    materials: buffers.Array(gpu_structs.Material),
    normals: buffers.Array(gpu_structs.Normal),
    normal_indices: buffers.Array(u32),
    uvs: buffers.Array(gpu_structs.Uv),
    uv_indices: buffers.Array(u32),
    transforms: buffers.Array(gpu_structs.Transform),
    tlas_nodes: buffers.Array(gpu_structs.BvhNode),
    blas_nodes: buffers.Array(gpu_structs.BvhNode),

    camera: buffers.Global(gpu_structs.Camera),
    constant_params: buffers.Global(gpu_structs.ConstantParams),

    pub fn init(allocator: std.mem.Allocator, scene: Scene) !Self {
        var device_count: c_int = 0;
        try hip.checkError(hip.c.hipGetDeviceCount(&device_count));
        try hip.checkError(hip.c.hipSetDevice(device_count - 1));
        try printDevices(device_count);

        const state = State.init();

        var bvh = try Bvh.init(allocator, &scene);
        defer bvh.deinit();

        const fileName = "./zig-out/bin/pathtracer.co";
        var module: hip.c.hipModule_t = undefined;
        try hip.checkError(hip.c.hipModuleLoad(&module, fileName));

        var path_tracing_and_post_processing_kernal: hip.c.hipFunction_t = undefined;
        try hip.checkError(hip.c.hipModuleGetFunction(&path_tracing_and_post_processing_kernal, module, "path_tracing_and_post_processing_kernal"));

        var path_tracing_kernal: hip.c.hipFunction_t = undefined;
        try hip.checkError(hip.c.hipModuleGetFunction(&path_tracing_kernal, module, "path_tracing_kernal"));

        var post_processing_kernal: hip.c.hipFunction_t = undefined;
        try hip.checkError(hip.c.hipModuleGetFunction(&post_processing_kernal, module, "post_processing_kernal"));

        return .{
            .allocator = allocator,
            .scene = scene,
            .state = state,
            .resolution = state.getResolution(),

            .module = module,
            .path_tracing_and_post_processing_kernal = path_tracing_and_post_processing_kernal,
            .path_tracing_kernal = path_tracing_kernal,
            .post_processing_kernal = post_processing_kernal,

            .target_buffer = null,
            .materials = try buffers.Array(gpu_structs.Material).init(bvh.materials.items),
            .normals = try buffers.Array(gpu_structs.Normal).init(bvh.normals.items),
            .normal_indices = try buffers.Array(u32).init(bvh.normal_indices.items),
            .uvs = try buffers.Array(gpu_structs.Uv).init(bvh.uvs.items),
            .uv_indices = try buffers.Array(u32).init(bvh.uv_indices.items),
            .transforms = try buffers.Array(gpu_structs.Transform).init(bvh.transforms.items),
            .tlas_nodes = try buffers.Array(gpu_structs.BvhNode).init(bvh.tlas_nodes.items),
            .blas_nodes = try buffers.Array(gpu_structs.BvhNode).init(bvh.blas_nodes.items),

            .camera = try buffers.Global(gpu_structs.Camera).init("camera", module),
            .constant_params = try buffers.Global(gpu_structs.ConstantParams).init("constant_params", module),
        };
    }

    pub fn deinit(self: *Self) !void {
        try hip.checkError(hip.c.hipModuleUnload(self.module));
        try self.materials.deinit();
        try self.normals.deinit();
        try self.normal_indices.deinit();
        try self.uvs.deinit();
        try self.uv_indices.deinit();
        try self.transforms.deinit();
        try self.tlas_nodes.deinit();
        try self.blas_nodes.deinit();
        if (self.target_buffer) |*tb| try tb.deinit();
        self.scene.deinit();
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) !void {
        self.resolution = resolution;
        self.state.setResolution(resolution);
        if (self.target_buffer) |*tb| {
            try tb.deinit();
            self.target_buffer = null;
        }
    }

    pub fn getFrameBuffer(self: *Self, dst: []gpu_structs.Vector4) !void {
        const tb = try self.getOrCreateTargetBuffer();
        return hip.checkError(hip.c.hipMemcpy(
            dst.ptr,
            tb.buffer,
            dst.len * @sizeOf(gpu_structs.Vector4),
            hip.c.hipMemcpyDeviceToHost,
        ));
    }

    pub fn render(self: *Self) !void {
        if (self.state.iterations > 1) {
            var i: u32 = 0;
            while (i < self.state.iterations) : (i += 1) {
                try self.update();
                try self.launchKernal(self.path_tracing_kernal);
            }
            try self.launchKernal(self.post_processing_kernal);
        } else {
            try self.update();
            try self.launchKernal(self.path_tracing_and_post_processing_kernal);
        }
    }

    fn printDevices(device_count: c_int) !void {
        var device_id: c_int = 0;
        while (device_id < device_count) : (device_id += 1) {
            try hip.printDeviceProperties(device_id);
        }
    }

    fn getOrCreateTargetBuffer(self: *Self) !*buffers.Target {
        if (self.target_buffer == null) {
            self.target_buffer = try buffers.Target.init(self.allocator, self.resolution);
        }

        return &self.target_buffer.?;
    }

    fn update(self: *Self) !void {
        var dirty = false;
        if (self.scene.camera.dirty) {
            dirty = true;
            self.scene.camera.dirty = false;
            try buffers.globalCopyHToD(gpu_structs.Camera, self.camera, gpu_structs.Camera.from(&self.scene.camera));
        }

        if (self.state.dirty) {
            dirty = true;
            self.state.dirty = false;
        }

        if (dirty) self.state.reset();
        self.state.nextIteration();
        try buffers.globalCopyHToD(
            gpu_structs.ConstantParams,
            self.constant_params,
            gpu_structs.ConstantParams.from(&self.state, @truncate(self.scene.textures.items.len)),
        );
    }

    fn launchKernal(self: *Self, kernal: hip.c.hipFunction_t) !void {
        const tb = try self.getOrCreateTargetBuffer();

        const KernalGlobals = extern struct {
            framebuffer: hip.c.hipDeviceptr_t,
            accumulation_buffer: hip.c.hipDeviceptr_t,
            rng_seed_buffer: hip.c.hipDeviceptr_t,
            pixel_count: u32,

            materials: buffers.Array(gpu_structs.Material),
            normals: buffers.Array(gpu_structs.Normal),
            normal_indices: buffers.Array(u32),
            uvs: buffers.Array(gpu_structs.Uv),
            uv_indices: buffers.Array(u32),
            transforms: buffers.Array(gpu_structs.Transform),
            tlas_nodes: buffers.Array(gpu_structs.BvhNode),
            blas_nodes: buffers.Array(gpu_structs.BvhNode),
        };

        const KernalArgs = extern struct { kg: KernalGlobals };

        var args = KernalArgs{
            .kg = .{
                .framebuffer = tb.buffer,
                .accumulation_buffer = tb.accumulation_buffer,
                .rng_seed_buffer = tb.rng_state_buffer,
                .pixel_count = tb.resolution.pixel_count(),

                .materials = self.materials,
                .normals = self.normals,
                .normal_indices = self.normal_indices,
                .uvs = self.uvs,
                .uv_indices = self.uv_indices,
                .transforms = self.transforms,
                .tlas_nodes = self.tlas_nodes,
                .blas_nodes = self.blas_nodes,
            },
        };

        var args_size = @as(u64, @sizeOf(@TypeOf(args)));
        var config = [_]?*anyopaque{
            hip.c.HIP_LAUNCH_PARAM_BUFFER_POINTER,
            @as(?*anyopaque, @ptrCast(&args)),
            hip.c.HIP_LAUNCH_PARAM_BUFFER_SIZE,
            @as(?*anyopaque, @ptrCast(&args_size)),
            hip.c.HIP_LAUNCH_PARAM_END,
        };

        try hip.checkError(hip.c.hipModuleLaunchKernel(
            kernal,
            tb.workgroups, // gridDimX
            1, // gridDimY
            1, // gridDimZ
            buffers.WORKGROUP_SIZE, // blockDimX
            1, // blockDimY
            1, // blockDimZ
            0,
            null,
            null,
            @as([*c]?*anyopaque, @ptrCast(&config)),
        ));
    }
};
