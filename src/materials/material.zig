const std = @import("std");
const Color = @import("color.zig").Color;

pub const Material = struct {
    albedo: Color,
    fuzz: f32,
    ior: f32,
    materia_type: u32,
    material_index: ?u32,
};
