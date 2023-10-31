const std = @import("std");
const zmath = @import("zmath");
const gpu_structs = @import("gpu_structs.zig");
const material = @import("materials/materials.zig");
const Lambertian = material.Lambertian;
const Metal = material.Metal;
const Dielectric = material.Dielectric;
const DiffuseLight = material.DiffuseLight;
const Color = material.Color;

pub const Materials = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    materials: std.DoublyLinkedList(Material),
    gpu_materials: gpu_structs.ArrayList(gpu_structs.Material),

    pub fn init(allocator: std.mem.Allocator, gpu_materials: gpu_structs.ArrayList(gpu_structs.Material)) Self {
        return .{
            .allocator = allocator,
            .materials = std.ArrayList(gpu_structs.Material).init(allocator),
            .gpu_materials = gpu_materials,
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.materials.first;
        while (it) |node| {
            it = node.next;
            self.allocator.destroy(node);
        }
    }

    pub fn lambertian(self: *Self, albedo: Color) !*Lambertian {
        var node = try self.allocator.create(std.DoublyLinkedList(Lambertian).Node);
        node.data = .{ .albedo = albedo, .ll_owner_node = node, .material_index = self.gpu_materials.len() };
        try self.gpu_materials.append(gpu_structs.Material.from(&node.data));
        try self.materials.append(node);
        return m;
    }

    pub fn metal(self: *Self, albedo: Color, fuzz: f32) !*Metal {
        var m = try self.allocator.create(Metal);
        m.* = .{ .albedo = albedo, .fuzz = fuzz };
        try self.metals.append(m);
        return m;
    }

    pub fn dielectric(self: *Self, ior: f32) !*Dielectric {
        var m = try self.allocator.create(Dielectric);
        m.* = .{ .ior = ior };
        try self.dielectrics.append(m);
        return m;
    }

    pub fn diffuseLight(self: *Self, albedo: Color) !*DiffuseLight {
        var m = try self.allocator.create(DiffuseLight);
        m.* = .{ .albedo = albedo };
        try self.diffuse_lights.append(m);
        return m;
    }
};

const Material = union(enum) {
    lambertian: *Lambertian,
    metal: *Metal,
    dielectric: *Dielectric,
};
