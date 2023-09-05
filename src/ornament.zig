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
        self.spheres.deinit();
        self.destroyElements(&self.meshes);
        self.meshes.deinit();
        self.destroyElements(&self.mesh_instances);
        self.mesh_instances.deinit();
        self.destroyElements(&self.materials);
        self.materials.deinit();
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
        return self.addEleemnt(
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
        return self.addEleemnt(
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

    fn addEleemnt(self: *Self, to_add: anytype, list: *std.ArrayList(*@TypeOf(to_add))) std.mem.Allocator.Error!*@TypeOf(to_add) {
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
