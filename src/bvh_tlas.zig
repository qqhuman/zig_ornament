const std = @import("std");
const zmath = @import("zmath");
const buffers = @import("buffers.zig");
const util = @import("util.zig");
const gpu_structs = @import("gpu_structs.zig");
const Material = @import("materials/materials.zig").Material;
const geometry = @import("geometry/geometry.zig");
const Aabb = geometry.Aabb;
const Sphere = geometry.Sphere;
const Mesh = geometry.Mesh;
const MeshInstance = geometry.MeshInstance;
const Shape = @import("util.zig").Shape;

var prng = std.rand.DefaultPrng.init(1244);
const rand = prng.random();

pub const BvhTlas = struct {
    const Self = @This();
    nodes: util.ArrayList(gpu_structs.Node),
    transforms: util.ArrayList(gpu_structs.Transform),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .nodes = util.ArrayList(gpu_structs.Node).init(allocator),
            .transforms = util.ArrayList(gpu_structs.Transform).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.shapes.deinit();
        self.nodes.deinit();
        self.transforms.deinit();
    }

    pub fn rebuild(self: *Self) !void {
        const nodes_count = self.shapes.items.len * 2 - 1;
        std.log.debug("[ornament] bvh building tlas.", .{});
        std.log.debug("[ornament] shapes: {d}", .{self.shapes.items.len});
        std.log.debug("[ornament] expected bvhtlas.nodes: {d}", .{nodes_count});
        self.nodes.ensureTotalCapacity(nodes_count);
        self.nodes.clearRetainingCapacity();
        self.transforms.ensureTotalCapacity(self.shapes.items.len);
        self.transforms.clearRetainingCapacity();
        const root = try self.buildBvh(self.shapes);
        try self.nodes.append(root);
        std.log.debug("[ornament] actual bvhtlas.nodes: {d}", .{self.nodes.items.len});
        std.debug.assert(nodes_count == self.nodes.items.len);
    }

    fn buildBvh(self: *Self, leafs: []Shape) !gpu_structs.Node {
        if (leafs.len == 0) {
            @panic("don't support empty bvh");
        } else if (leafs.len == 1) {
            switch (leafs[0]) {
                .sphere => |s| {
                    const transform = s.transform;
                    try self.appendTransform(zmath.inverse(transform));
                    try self.appendTransform(transform);
                    const transform_id = self.transforms.items.len / 2 - 1;
                    return .{
                        .left_aabb_min_or_v0 = zmath.vecToArr3(s.aabb.min),
                        .left_aabb_max_or_v1 = zmath.vecToArr3(s.aabb.max),
                        .right_or_material_index = try s.material.material_index,
                        .node_type = gpu_structs.NodeType.Sphere,
                        .transform_id = @as(u32, @truncate(transform_id)),

                        .left_or_custom_id = undefined,
                        .right_aabb_min_or_v2 = undefined,
                        .right_aabb_max_or_v3 = undefined,
                    };
                },
                .mesh => |m| {
                    const transform = m.transform;
                    try self.appendTransform(zmath.inverse(transform));
                    try self.appendTransform(transform);
                    const transform_id = self.transforms.items.len / 2 - 1;
                    return .{
                        .left_aabb_min_or_v0 = zmath.vecToArr3(m.aabb.min),
                        .left_aabb_max_or_v1 = zmath.vecToArr3(m.aabb.max),
                        .left_or_custom_id = m.bvh_id orelse unreachable,
                        .right_or_material_index = try m.material.material_index,
                        .node_type = gpu_structs.NodeType.Mesh,
                        .transform_id = @as(u32, @truncate(transform_id)),

                        .right_aabb_min_or_v2 = undefined,
                        .right_aabb_max_or_v3 = undefined,
                    };
                },
                .mesh_instance => |mi| {
                    const transform = mi.transform;
                    try self.appendTransform(zmath.inverse(transform));
                    try self.appendTransform(transform);
                    const transform_id = self.transforms.items.len / 2 - 1;
                    return .{
                        .left_aabb_min_or_v0 = zmath.vecToArr3(mi.aabb.min),
                        .left_aabb_max_or_v1 = zmath.vecToArr3(mi.aabb.max),
                        .right_or_material_index = mi.material.material_index,
                        .node_type = gpu_structs.NodeType.Mesh,
                        .transform_id = @as(u32, @truncate(transform_id)),
                        .left_or_custom_id = mi.mesh.bvh_id orelse unreachable,

                        .right_aabb_min_or_v2 = undefined,
                        .right_aabb_max_or_v3 = undefined,
                    };
                },
            }
        } else {
            // Sort shapes based on the split axis
            const axis = rand.intRangeAtMost(usize, 0, 2);
            std.sort.heap(Shape, leafs, axis, boxCompare);

            // Partition shapes into left and right subsets
            const mid = leafs.len / 2;
            const left_leafs = leafs[0..mid];
            const right_leafs = leafs[mid..];

            // Recursively build BVH for left and right subsets
            const left = try self.buildBvh(left_leafs);
            try self.tlas_nodes.append(left);
            const left_id = self.tlas_nodes.items.len - 1;
            const left_aabb = calculateBoundingBox(left_leafs);

            const right = try self.buildBvh(right_leafs);
            try self.tlas_nodes.append(right);
            const right_id = self.tlas_nodes.items.len - 1;
            const right_aabb = calculateBoundingBox(right_leafs);

            return .{
                .left_aabb_min_or_v0 = zmath.vecToArr3(left_aabb.min),
                .left_or_custom_id = @as(u32, @truncate(left_id)),
                .left_aabb_max_or_v1 = zmath.vecToArr3(left_aabb.max),
                .right_or_material_index = @as(u32, @truncate(right_id)),
                .right_aabb_min_or_v2 = zmath.vecToArr3(right_aabb.min),
                .node_type = gpu_structs.NodeType.InternalNode,
                .right_aabb_max_or_v3 = zmath.vecToArr3(right_aabb.max),

                .transform_id = undefined,
            };
        }
    }

    fn appendTransform(self: *Self, transform: zmath.Mat) !void {
        try self.transforms.append(zmath.matToArr(transform));
    }

    fn boxCompare(axis: usize, a: Shape, b: Shape) bool {
        const box_a = switch (a) {
            .sphere => |s| s.aabb,
            .mesh => |m| m.aabb,
            .mesh_instance => |mi| mi.aabb,
        };

        const box_b = switch (b) {
            .sphere => |s| s.aabb,
            .mesh => |m| m.aabb,
            .mesh_instance => |mi| mi.aabb,
        };

        return box_a.min[axis] < box_b.min[axis];
    }

    fn calculateBoundingBox(leafs: []Shape) Aabb {
        var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
        var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);

        for (leafs) |l| {
            const aabb = switch (l) {
                .sphere => |s| s.aabb,
                .mesh => |m| m.aabb,
                .mesh_instance => |mi| mi.aabb,
            };
            min = zmath.min(min, aabb.min);
            max = zmath.max(max, aabb.max);
        }
        return Aabb.init(min, max);
    }
};
