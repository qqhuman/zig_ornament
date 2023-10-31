const Mesh = @import("mesh.zig").Mesh;
const zmath = @import("zmath");
const Material = @import("../materials/material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;

pub const MeshInstance = struct {
    bvh_tlas_node_index: ?usize = null,
    mesh: *const Mesh,
    material: *Material,
    transform: zmath.Mat,
    aabb: Aabb,
};
