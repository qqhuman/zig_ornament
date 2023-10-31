const zmath = @import("zmath");
const Aabb = @import("aabb.zig").Aabb;
const Material = @import("../materials/material.zig").Material;

pub const Sphere = struct {
    bvh_tlas_node_index: ?usize = null,
    material: *Material,
    transform: zmath.Mat,
    aabb: Aabb,
};
