const std = @import("std");
const zmath = @import("zmath");
const Material = @import("../materials/material.zig").Material;
const Range = @import("../util.zig").Range;
const Aabb = @import("aabb.zig").Aabb;

pub const Mesh = struct {
    const Self = @This();
    bvh_tlas_node_index: ?usize = null,
    ll_owner_node: *std.DoublyLinkedList(Self).Node,
    bvh_blas_nodes_range: Range,
    indices_range: Range,
    normals_range: Range,
    uvs_range: Range,
    material: *const Material,
    transform: zmath.Mat,
    aabb: Aabb,
    not_transformed_aabb: Aabb,

    pub inline fn bvh_blas_mesh_top_index(self: *const Self) usize {
        return self.bvh_blas_nodes_range.end - 1;
    }
};
