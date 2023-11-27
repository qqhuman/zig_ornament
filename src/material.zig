const std = @import("std");
const Color = @import("color.zig").Color;

pub const MaterialType = enum(u32) {
    Lambertian = 0,
    Metal = 1,
    Dielectric = 2,
    DiffuseLight = 3,
};

pub const Material = struct {
    albedo: Color,
    fuzz: f32,
    ior: f32,
    materia_type: MaterialType,
    material_index: ?u32,
};
