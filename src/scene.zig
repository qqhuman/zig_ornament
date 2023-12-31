const std = @import("std");
const zmath = @import("zmath");
const math = @import("math.zig");
const Camera = @import("camera.zig").Camera;
const Sphere = @import("sphere.zig").Sphere;
const Mesh = @import("mesh.zig").Mesh;
const MeshInstance = @import("mesh_instance.zig").MeshInstance;
const Material = @import("material.zig").Material;
const Texture = @import("texture.zig").Texture;
const Color = @import("color.zig").Color;
const Aabb = @import("aabb.zig").Aabb;

pub const Scene = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    camera: Camera,
    spheres: std.ArrayList(*Sphere),
    meshes: std.ArrayList(*Mesh),
    mesh_instances: std.ArrayList(*MeshInstance),
    materials: std.ArrayList(*Material),
    textures: std.ArrayList(*Texture),

    attached_spheres: std.ArrayList(*Sphere),
    attached_meshes: std.ArrayList(*Mesh),
    attached_mesh_instances: std.ArrayList(*MeshInstance),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .camera = Camera.init(
                zmath.f32x4(1.0, 1.0, 1.0, 1.0),
                zmath.f32x4(0.0, 0.0, 0.0, 1.0),
                zmath.f32x4(0.0, 1.0, 0.0, 0.0),
                1.0,
                40.0,
                0.0,
                10.0,
            ),
            .spheres = std.ArrayList(*Sphere).init(allocator),
            .meshes = std.ArrayList(*Mesh).init(allocator),
            .mesh_instances = std.ArrayList(*MeshInstance).init(allocator),
            .materials = std.ArrayList(*Material).init(allocator),
            .textures = std.ArrayList(*Texture).init(allocator),
            .attached_spheres = std.ArrayList(*Sphere).init(allocator),
            .attached_meshes = std.ArrayList(*Mesh).init(allocator),
            .attached_mesh_instances = std.ArrayList(*MeshInstance).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.attached_spheres.deinit();
        self.attached_meshes.deinit();
        self.attached_mesh_instances.deinit();

        self.destroyElements(&self.spheres);
        for (self.meshes.items) |m| m.deinit();
        self.destroyElements(&self.meshes);
        self.destroyElements(&self.mesh_instances);
        self.destroyElements(&self.materials);
        for (self.textures.items) |t| t.deinit();
        self.destroyElements(&self.textures);
    }

    pub fn lambertian(self: *Self, albedo: Color) std.mem.Allocator.Error!*Material {
        var material = try self.allocator.create(Material);
        material.* = Material{
            .albedo = albedo,
            .type = .Lambertian,

            .fuzz = undefined,
            .ior = undefined,
            .material_index = null,
        };
        try self.materials.append(material);
        return material;
    }

    pub fn metal(self: *Self, albedo: Color, fuzz: f32) std.mem.Allocator.Error!*Material {
        var material = try self.allocator.create(Material);
        material.* = Material{
            .albedo = albedo,
            .fuzz = fuzz,
            .type = .Metal,

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
            .type = .Dielectric,

            .albedo = undefined,
            .fuzz = undefined,
            .material_index = null,
        };
        try self.materials.append(material);
        return material;
    }

    pub fn diffuseLight(self: *Self, albedo: Color) std.mem.Allocator.Error!*Material {
        return self.addElement(
            Material{
                .albedo = albedo,
                .type = .DiffuseLight,

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
        var uvs = std.ArrayList([2]f32).init(self.allocator);
        defer uvs.deinit();
        var indices = std.ArrayList(u32).init(self.allocator);
        defer indices.deinit();
        const facing = 1.0;
        const h_segments: u32 = 60;
        const v_segments: u32 = 30;

        // Add the top vertex.
        try vertices.append(zmath.f32x4(0.0, 1.0, 0.0, 1.0));
        try normals.append(zmath.f32x4(0.0, facing, 0.0, 0.0));
        try uvs.append(math.getSphereTexCoord(normals.getLast()));

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
                try uvs.append(math.getSphereTexCoord(normals.getLast()));

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
        try uvs.append(math.getSphereTexCoord(normals.getLast()));

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
            vertices.items,
            indices.items,
            normals.items,
            indices.items,
            uvs.items,
            indices.items,
            transform,
            material,
        );
    }

    pub fn createPlaneMesh(self: *Self, center: zmath.Vec, side1_length: f32, side2_length: f32, normal: zmath.Vec, material: *Material) std.mem.Allocator.Error!*Mesh {
        const vertices = [_]zmath.Vec{
            zmath.f32x4(-0.5, 0.0, -0.5, 1.0),
            zmath.f32x4(-0.5, 0.0, 0.5, 1.0),
            zmath.f32x4(0.5, 0.0, 0.5, 1.0),
            zmath.f32x4(0.5, 0.0, -0.5, 1.0),
        };
        const indices = [_]u32{ 3, 1, 0, 2, 1, 3 };
        const normals = [_]zmath.Vec{ math.unit_y, math.unit_y, math.unit_y, math.unit_y };
        const rotation = math.rotationBetweenVectors(normal, math.unit_y);
        return self.createMesh(
            vertices[0..],
            indices[0..],
            normals[0..],
            indices[0..],
            &[0][2]f32{},
            &[0]u32{},
            zmath.mul(
                zmath.mul(
                    zmath.scaling(side1_length, 1.0, side2_length),
                    rotation,
                ),
                zmath.translationV(center),
            ),
            material,
        );
    }

    pub fn createMesh(
        self: *Self,
        vertices: []const zmath.Vec,
        vertex_indices: []const u32,
        normals: []const zmath.Vec,
        normal_indices: []const u32,
        uvs: []const [2]f32,
        uv_indices: []const u32,
        transform: zmath.Mat,
        material: *Material,
    ) std.mem.Allocator.Error!*Mesh {
        var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
        var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);

        var mesh_triangle_index: u32 = 0;
        while (mesh_triangle_index < vertex_indices.len / 3) : (mesh_triangle_index += 1) {
            const v0 = vertices[vertex_indices[mesh_triangle_index * 3]];
            const v1 = vertices[vertex_indices[mesh_triangle_index * 3 + 1]];
            const v2 = vertices[vertex_indices[mesh_triangle_index * 3 + 2]];
            min = zmath.min(min, zmath.min(zmath.min(v0, v1), v2));
            max = zmath.max(max, zmath.max(zmath.max(v0, v1), v2));
        }

        const not_transformed_aabb = Aabb.init(min, max);
        const aabb = Aabb.transform(transform, not_transformed_aabb);

        var mesh = try self.addElement(Mesh{
            .vertices = try std.ArrayList(zmath.Vec).initCapacity(self.allocator, vertices.len),
            .vertex_indices = try std.ArrayList(u32).initCapacity(self.allocator, vertex_indices.len),
            .normals = try std.ArrayList(zmath.Vec).initCapacity(self.allocator, normals.len),
            .normal_indices = try std.ArrayList(u32).initCapacity(self.allocator, normal_indices.len),
            .uvs = try std.ArrayList([2]f32).initCapacity(self.allocator, uvs.len),
            .uv_indices = try std.ArrayList(u32).initCapacity(self.allocator, uv_indices.len),
            .transform = transform,
            .material = material,
            .bvh_id = null,
            .aabb = aabb,
            .not_transformed_aabb = not_transformed_aabb,
        }, &self.meshes);

        if (uvs.len == 0) {
            try mesh.uvs.appendNTimes(.{ 0.5, 0.5 }, vertices.len);
            try mesh.uv_indices.appendSlice(vertex_indices);
        } else {
            try mesh.uvs.appendSlice(uvs);
            try mesh.uv_indices.appendSlice(uv_indices);
        }

        try mesh.vertices.appendSlice(vertices);
        try mesh.vertex_indices.appendSlice(vertex_indices);
        try mesh.normals.appendSlice(normals);
        try mesh.normal_indices.appendSlice(normal_indices);
        return mesh;
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
                .aabb = Aabb.transform(transform, mesh.not_transformed_aabb),
            },
            &self.mesh_instances,
        );
    }

    pub fn releaseMeshInstance(self: *Self, mesh_instance: *const MeshInstance) void {
        self.releaseElement(mesh_instance, self.mesh_instances);
    }

    pub fn createTexture(self: *Self, data: []u8, width: u32, height: u32, num_components: u32, bytes_per_component: u32, is_hdr: bool, gamma: f32) !*Texture {
        var txt = self.addElement(try Texture.init(
            self.allocator,
            data,
            width,
            height,
            num_components,
            bytes_per_component,
            is_hdr,
            gamma,
        ), &self.textures);
        return txt;
    }

    pub fn releaseTexture(self: *Self, texture: *const Texture) void {
        self.releaseElement(texture, self.textures);
    }

    pub fn attachSphere(self: *Self, sphere: *Sphere) !void {
        try self.attached_spheres.append(sphere);
    }

    pub fn attachMesh(self: *Self, mesh: *Mesh) !void {
        try self.attached_meshes.append(mesh);
    }

    pub fn attachMeshInstance(self: *Self, mesh_instance: *MeshInstance) !void {
        try self.attached_mesh_instances.append(mesh_instance);
    }

    fn addElement(self: *Self, to_add: anytype, list: *std.ArrayList(*@TypeOf(to_add))) std.mem.Allocator.Error!*@TypeOf(to_add) {
        var el = try self.allocator.create(@TypeOf(to_add));
        el.* = to_add;
        try list.append(el);
        return el;
    }

    fn destroyElements(self: *Self, list: anytype) void {
        for (list.items) |el| self.allocator.destroy(el);
        list.deinit();
    }
};
