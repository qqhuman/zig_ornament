const zmath = @import("zmath");
const Aabb = @import("aabb.zig").Aabb;
const Material = @import("../materials/material.zig").Material;

pub const Sphere = struct {
    material: *Material,
    transform: zmath.Mat,
    aabb: Aabb,
};
