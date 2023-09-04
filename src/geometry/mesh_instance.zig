const Mesh = @import("mesh.zig").Mesh;
const zmath = @import("zmath");
const Material = @import("../materials/material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;

pub const MeshInstance = struct {
    mesh: *const Mesh,
    material: *Material,
    transform: zmath.Mat,
    aabb: Aabb,
};
