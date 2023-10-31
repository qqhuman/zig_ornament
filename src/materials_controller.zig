const std = @import("std");
const zmath = @import("zmath");
const gpu_structs = @import("gpu_structs.zig");
const materials = @import("materials/materials.zig");
const Material = materials.Material;
const Color = materials.Color;
const Texture = materials.Texture;
const util = @import("util.zig");

pub const MaterialsController = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    dirty: bool = true,
    materials: std.ArrayList(Material),
    textures: util.ArrayList(*Texture),
    gpu_materials: util.ArrayList(gpu_structs.Material),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .materials = std.ArrayList(gpu_structs.Material).init(allocator),
            .gpu_materials = util.ArrayList(gpu_structs.Material).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.textures) |t| {
            t.deinit();
            self.allocator.destroy(t);
        }
        self.textures.deinit();
        for (self.materials) |m| self.allocator.destroy(m);
        self.materials.deinit();
        self.gpu_materials.deinit();
    }

    pub fn lambertian(self: *Self, albedo: Color) !*Material {
        return self.addMaterial(.{
            .albedo = albedo,
            .materia_type = gpu_structs.MaterialType.Lambertian,

            .fuzz = undefined,
            .ior = undefined,
            .material_index = self.materials.len,
        });
    }

    pub fn metal(self: *Self, albedo: Color, fuzz: f32) !*Material {
        return self.addMaterial(.{
            .albedo = albedo,
            .fuzz = fuzz,
            .materia_type = gpu_structs.MaterialType.Metal,

            .ior = undefined,
            .material_index = self.materials.len,
        });
    }

    pub fn dielectric(self: *Self, ior: f32) !*Material {
        return self.addMaterial(.{
            .ior = ior,
            .materia_type = gpu_structs.MaterialType.Dielectric,

            .albedo = undefined,
            .fuzz = undefined,
            .material_index = self.materials.len,
        });
    }

    pub fn diffuseLight(self: *Self, albedo: Color) !*Material {
        return self.addMaterial(.{
            .albedo = albedo,
            .materia_type = gpu_structs.MaterialType.DiffuseLight,

            .fuzz = undefined,
            .ior = undefined,
            .material_index = self.materials.len,
        });
    }

    pub fn releaseMaterial(self: *Self, material: *Material) void {
        for (self.materials[material.material_index + 1 ..]) |*m| {
            m.material_index = m.material_index - 1;
        }

        self.materials.orderedRemove(material.material_index);
        self.gpu_materials.orderedRemove(material.material_index);
        self.allocator.destroy(material);
    }

    pub fn addTexture(self: *Self, data: []u8, width: u32, height: u32, num_components: u32, bytes_per_component: u32, is_hdr: bool, gamma: f32) !*Texture {
        const txt = self.allocator.create(Texture);
        txt.* = try Texture.init(
            self.allocator,
            data,
            width,
            height,
            num_components,
            bytes_per_component,
            is_hdr,
            gamma,
            self.textures.len(),
        );
        try self.textures.append(txt);
        return txt;
    }

    pub fn releaseTexture(self: *Self, texture: *Texture) void {
        for (self.textures.get_slice_mut_from(texture.texture_id + 1)) |*t| {
            t.texture_id = t.texture_id - 1;
        }
        self.textures.orderedRemove(texture.texture_id);
        self.allocator.destroy(texture);
    }

    fn addMaterial(self: *Self, material: Material) !*Material {
        var m = try self.allocator.create(Material);
        m.* = material;
        try self.materials.append(m);
        self.dirty = true;
        return m;
    }
};
