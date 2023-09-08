const std = @import("std");
const wgpu = @import("zgpu").wgpu;
const zmath = @import("zmath");
const util = @import("util.zig");
const WgpuContext = @import("wgpu/wgpu_context.zig").WgpuContext;
const PathTracer = @import("wgpu/path_tracer.zig").PathTracer;
const materials = @import("materials/material.zig");
pub const Material = materials.Material;
const geometry = @import("geometry/geometry.zig");
pub const Scene = geometry.Scene;
pub const Camera = geometry.Camera;
pub const Aabb = geometry.Aabb;
pub const Sphere = geometry.Sphere;
pub const Mesh = geometry.Mesh;
pub const MeshInstance = geometry.MeshInstance;

pub const Context = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    state: State,
    scene: *Scene,
    materials: std.ArrayList(*Material),
    spheres: std.ArrayList(*Sphere),
    meshes: std.ArrayList(*Mesh),
    mesh_instances: std.ArrayList(*MeshInstance),
    path_tracer: ?*PathTracer,
    wgpu_context: *WgpuContext,

    pub fn init(allocator: std.mem.Allocator, surface_descriptor: ?wgpu.SurfaceDescriptor) !*Self {
        var self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .state = State.init(),
            .scene = try Scene.init(allocator),
            .materials = std.ArrayList(*Material).init(allocator),
            .spheres = std.ArrayList(*Sphere).init(allocator),
            .meshes = std.ArrayList(*Mesh).init(allocator),
            .mesh_instances = std.ArrayList(*MeshInstance).init(allocator),
            .wgpu_context = try WgpuContext.init(allocator, surface_descriptor),
            .path_tracer = null,
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        defer self.allocator.destroy(self);
        self.scene.deinit();
        if (self.path_tracer) |pt| pt.deinit();
        self.destroyElements(&self.spheres);
        for (self.meshes.items) |m| m.deinit();
        self.destroyElements(&self.meshes);
        self.destroyElements(&self.mesh_instances);
        self.destroyElements(&self.materials);
        self.wgpu_context.deinit();
    }

    pub fn setFlipY(self: *Self, flip_y: bool) void {
        self.state.setFlipY(flip_y);
    }

    pub fn getFlipY(self: Self) bool {
        return self.state.getFlipY();
    }

    pub fn setGamma(self: *Self, gamma: f32) void {
        self.state.setGamma(gamma);
    }

    pub fn getGamma(self: Self) f32 {
        return self.state.getGamma();
    }

    pub fn setDepth(self: *Self, depth: u32) void {
        self.state.setDepth(depth);
    }

    pub fn getDepth(self: Self) u32 {
        return self.state.getDepth();
    }

    pub fn setIterations(self: *Self, iterations: u32) void {
        self.state.setIterations(iterations);
    }

    pub fn getIterations(self: Self) u32 {
        return self.state.getIterations();
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) !void {
        self.state.setResolution(resolution);
        var pt = try self.getOrCreatePathTracer();
        pt.setResolution(resolution);
    }

    pub fn getResolution(self: Self) util.Resolution {
        return self.state.getResolution();
    }

    pub fn setRayCastEpsilon(self: *Self, ray_cast_epsilon: f32) void {
        self.state.setRayCastEpsilon(ray_cast_epsilon);
    }

    pub fn getRayCastEpsilon(self: Self) f32 {
        return self.state.getRayCastEpsilon();
    }

    fn getOrCreatePathTracer(self: *Self) !*PathTracer {
        return self.path_tracer orelse blk: {
            var pt = try PathTracer.init(self.allocator, self.wgpu_context, &self.state, self.scene);
            self.path_tracer = pt;
            std.log.debug("[ornament] path tracer was created", .{});
            break :blk pt;
        };
    }

    pub fn targetBufferLayout(self: *Self, binding: u32, visibility: wgpu.ShaderStage, read_only: bool) !wgpu.BindGroupLayoutEntry {
        var path_tracer = try self.getOrCreatePathTracer();
        return path_tracer.targetBufferLayout(binding, visibility, read_only);
    }

    pub fn targetBufferBinding(self: *Self, binding: u32) !wgpu.BindGroupEntry {
        var path_tracer = try self.getOrCreatePathTracer();
        return path_tracer.targetBufferBinding(binding);
    }

    pub fn render(self: *Self) !void {
        var path_tracer = try self.getOrCreatePathTracer();
        if (self.state.iterations > 1) {
            var i: u32 = 0;
            while (i < self.state.iterations) : (i += 1) {
                path_tracer.update(&self.state, self.scene);
                try path_tracer.render();
            }
            try path_tracer.post_processing();
        } else {
            path_tracer.update(&self.state, self.scene);
            try path_tracer.render_and_apply_post_processing();
        }
    }

    pub fn lambertian(self: *Self, albedo: zmath.Vec) std.mem.Allocator.Error!*Material {
        var material = try self.allocator.create(Material);
        material.* = Material{
            .albedo = albedo,
            .materia_type = 0,

            .fuzz = undefined,
            .ior = undefined,
            .material_index = null,
        };
        try self.materials.append(material);
        return material;
    }

    pub fn metal(self: *Self, albedo: zmath.Vec, fuzz: f32) std.mem.Allocator.Error!*Material {
        var material = try self.allocator.create(Material);
        material.* = Material{
            .albedo = albedo,
            .fuzz = fuzz,
            .materia_type = 1,

            .ior = undefined,
            .material_index = null,
        };
        try self.materials.append(material);
        return material;
    }

    pub fn dielectric(self: *Self, ior: f32) std.mem.Allocator.Error!*Material {
        var material = try self.allocator.create(Material);
        material.* = Material{
            .ior = ior,
            .materia_type = 2,

            .albedo = undefined,
            .fuzz = undefined,
            .material_index = null,
        };
        try self.materials.append(material);
        return material;
    }

    pub fn diffuseLight(self: *Self, albedo: zmath.Vec) std.mem.Allocator.Error!*Material {
        return self.addElement(
            Material{
                .albedo = albedo,
                .materia_type = 3,

                .albedo = undefined,
                .fuzz = undefined,
                .ior = undefined,
                .material_index = null,
            },
            &self.materials,
        );
    }

    pub fn releaseMaterial(self: *Self, material: *const Material) void {
        self.releaseElement(material, &self.materials);
    }

    pub fn createSphere(self: *Self, center: zmath.Vec, radius: f32, material: *Material) std.mem.Allocator.Error!*Sphere {
        const radius_v = zmath.f32x4(radius, radius, radius, 0.0);
        return self.addElement(
            Sphere{
                .transform = zmath.mul(zmath.scalingV(radius_v), zmath.translationV(center)),
                .material = material,
                .aabb = Aabb.init(center - radius_v, center + radius_v),
            },
            &self.spheres,
        );
    }

    pub fn releaseSphere(self: *Self, sphere: *const Sphere) void {
        self.releaseElement(sphere, &self.spheres);
    }

    pub fn createSphereMesh(self: *Self, center: zmath.Vec, radius: f32, material: *Material) std.mem.Allocator.Error!*Mesh {
        var vertices = std.ArrayList(zmath.Vec).init(self.allocator);
        defer vertices.deinit();
        var normals = std.ArrayList(zmath.Vec).init(self.allocator);
        defer normals.deinit();
        var indices = std.ArrayList(u32).init(self.allocator);
        defer indices.deinit();
        const facing = 1.0;
        const h_segments: u32 = 60;
        const v_segments: u32 = 30;

        // Add the top vertex.
        try vertices.append(zmath.f32x4(0.0, 1.0, 0.0, 1.0));
        try normals.append(zmath.f32x4(0.0, facing, 0.0, 0.0));

        var v: u32 = 0;
        while (v < v_segments) : (v += 1) {
            if (v == 0) {
                continue;
            }

            const theta = @as(f32, @floatFromInt(v)) / v_segments * std.math.pi;
            const sin_theta = std.math.sin(theta);

            var h: u32 = 0;
            while (h < h_segments) : (h += 1) {
                const phi = @as(f32, @floatFromInt(h)) / h_segments * std.math.pi * 2.0;
                const x = sin_theta * std.math.sin(phi) * 1.0;
                const z = sin_theta * std.math.cos(phi) * 1.0;
                const y = std.math.cos(theta) * 1.0;

                try vertices.append(zmath.f32x4(x, y, z, 1.0));
                try normals.append(zmath.normalize3(zmath.f32x4(x, y, z, 0.0) * zmath.f32x4s(facing)));

                // Top triangle fan.
                if (v == 1) {
                    try indices.append(0);
                    try indices.append(h + 1);
                    if (h < h_segments - 1) {
                        try indices.append(h + 2);
                    } else {
                        try indices.append(1);
                    }
                }
                // Vertical slice.
                else {
                    const i = h + ((v - 1) * h_segments) + 1;
                    const j = i - h_segments;
                    const k = if (h < h_segments - 1) j + 1 else j - (h_segments - 1);
                    const l = if (h < h_segments - 1) i + 1 else i - (h_segments - 1);

                    try indices.append(j);
                    try indices.append(i);
                    try indices.append(k);
                    try indices.append(k);
                    try indices.append(i);
                    try indices.append(l);
                }
            }
        }

        // Bottom vertex.
        try vertices.append(zmath.f32x4(0.0, -1.0, 0.0, 1.0));
        try normals.append(zmath.f32x4(0.0, -facing, 0.0, 0.0));

        // Bottom triangle fan.
        const vertex_count: u32 = @truncate(vertices.items.len);
        const end = vertex_count - 1;

        var h: u32 = 0;
        while (h < h_segments) : (h += 1) {
            const i = end - h_segments + h;
            try indices.append(i);
            try indices.append(end);
            try indices.append(if (h < h_segments - 1) i + 1 else end - h_segments);
        }

        const transform = zmath.mul(zmath.scaling(radius, radius, radius), zmath.translationV(center));
        return self.createMesh(
            vertices,
            indices,
            normals,
            indices,
            transform,
            material,
        );
    }

    pub fn createMesh(
        self: *Self,
        vertices: std.ArrayList(zmath.Vec),
        vertex_indices: std.ArrayList(u32),
        normals: std.ArrayList(zmath.Vec),
        normal_indices: std.ArrayList(u32),
        transform: zmath.Mat,
        material: *Material,
    ) std.mem.Allocator.Error!*Mesh {
        var min = zmath.f32x4(std.math.floatMax(f32), std.math.floatMax(f32), std.math.floatMax(f32), 1.0);
        var max = zmath.f32x4(std.math.floatMin(f32), std.math.floatMin(f32), std.math.floatMin(f32), 1.0);

        var mesh_triangle_index: u32 = 0;
        while (mesh_triangle_index < vertex_indices.items.len / 3) : (mesh_triangle_index += 1) {
            const v0 = vertices.items[vertex_indices.items[mesh_triangle_index * 3]];
            const v1 = vertices.items[vertex_indices.items[mesh_triangle_index * 3 + 1]];
            const v2 = vertices.items[vertex_indices.items[mesh_triangle_index * 3 + 2]];
            min = zmath.min(min, zmath.min(zmath.min(v0, v1), v2));
            max = zmath.max(max, zmath.max(zmath.max(v0, v1), v2));
        }

        const not_transformed_aabb = Aabb.init(min, max);
        const aabb = geometry.transformAabb(transform, not_transformed_aabb);
        return self.addElement(Mesh{
            .vertices = try vertices.clone(),
            .vertex_indices = try vertex_indices.clone(),
            .normals = try normals.clone(),
            .normal_indices = try normal_indices.clone(),
            .transform = transform,
            .material = material,
            .bvh_id = null,
            .aabb = aabb,
            .not_transformed_aabb = not_transformed_aabb,
        }, &self.meshes);
    }

    pub fn releaseMesh(self: *Self, mesh: *const Mesh) void {
        self.releaseElement(mesh, self.meshes);
        mesh.deinit();
    }

    pub fn createMeshInstance(self: *Self, mesh: *const Mesh, transform: zmath.Mat, material: *Material) std.mem.Allocator.Error!*MeshInstance {
        return self.addElement(
            MeshInstance{
                .mesh = mesh,
                .material = material,
                .transform = transform,
                .aabb = geometry.transformAabb(transform, mesh.not_transformed_aabb),
            },
            &self.mesh_instances,
        );
    }

    pub fn releaseMeshInstance(self: *Self, mesh_instance: *const MeshInstance) void {
        self.releaseElement(mesh_instance, self.mesh_instances);
    }

    fn addElement(self: *Self, to_add: anytype, list: *std.ArrayList(*@TypeOf(to_add))) std.mem.Allocator.Error!*@TypeOf(to_add) {
        var el = try self.allocator.create(@TypeOf(to_add));
        el.* = to_add;
        try list.append(el);
        return el;
    }

    fn releaseElement(self: *Self, to_remove: anytype, list: *std.ArrayList(@TypeOf(to_remove))) void {
        for (list.items, 0..) |el, index| {
            if (el == to_remove) {
                _ = list.swapRemove(index);
                self.allocator.destroy(to_remove);
            }
        }
    }

    fn destroyElements(self: *Self, list: anytype) void {
        for (list.items) |el| self.allocator.destroy(el);
        list.deinit();
    }
};

pub const State = struct {
    const Self = @This();
    resolution: util.Resolution,
    depth: u32,
    flip_y: bool,
    inverted_gamma: f32,
    iterations: u32,
    ray_cast_epsilon: f32,
    dirty: bool = true,

    pub fn init() Self {
        return .{
            .resolution = .{ .width = 500, .height = 500 },
            .depth = 10,
            .flip_y = false,
            .inverted_gamma = 1.0,
            .iterations = 1,
            .ray_cast_epsilon = 0.001,
            .dirty = true,
        };
    }

    fn makeDirty(self: *Self) void {
        self.dirty = true;
    }

    pub fn setFlipY(self: *Self, flip_y: bool) void {
        self.flip_y = flip_y;
        self.makeDirty();
    }

    pub fn getFlipY(self: Self) bool {
        return self.flip_y;
    }

    pub fn setGamma(self: *Self, gamma: f32) void {
        self.inverted_gamma = 1.0 / gamma;
        self.makeDirty();
    }

    pub fn getGamma(self: Self) f32 {
        return 1.0 / self.inverted_gamma;
    }

    pub fn setDepth(self: *Self, depth: u32) void {
        self.depth = depth;
        self.makeDirty();
    }

    pub fn getDepth(self: Self) u32 {
        return self.depth;
    }

    pub fn setIterations(self: *Self, iterations: u32) void {
        self.iterations = iterations;
        self.makeDirty();
    }

    pub fn getIterations(self: Self) u32 {
        return self.iterations;
    }

    pub fn setResolution(self: *Self, resolution: util.Resolution) void {
        self.resolution = resolution;
        self.makeDirty();
    }

    pub fn getResolution(self: Self) util.Resolution {
        return self.resolution;
    }

    pub fn setRayCastEpsilon(self: *Self, ray_cast_epsilon: f32) void {
        self.ray_cast_epsilon = ray_cast_epsilon;
        self.makeDirty();
    }

    pub fn getRayCastEpsilon(self: Self) f32 {
        return self.ray_cast_epsilon;
    }
};
