const zmath = @import("zmath");

pub const Material = struct {
    albedo: zmath.Vec,
    fuzz: f32,
    ior: f32,
    materia_type: u32,
    material_index: ?u32,
};
