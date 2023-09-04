const std = @import("std");
const zmath = @import("zmath");
const Material = @import("../materials/material.zig").Material;
const Aabb = @import("aabb.zig").Aabb;

pub const Mesh = struct {
    vertices: std.ArrayList(zmath.Vec),
    vertex_indices: std.ArrayList(u32),
    normals: std.ArrayList(zmath.Vec),
    normal_indices: std.ArrayList(u32),
    transform: zmath.Mat,
    material: *Material,
    bvh_id: ?u32,
    aabb: Aabb,
    not_transformed_aabb: Aabb,
};
