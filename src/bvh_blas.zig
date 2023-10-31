const std = @import("std");
const zmath = @import("zmath");
const Material = @import("materials/materials.zig").Material;
const util = @import("util.zig");
const gpu_structs = @import("gpu_structs.zig");
const geometry = @import("geometry/geometry.zig");
const Aabb = geometry.Aabb;
const Mesh = geometry.Mesh;
const Range = @import("util.zig").Range;

var prng = std.rand.DefaultPrng.init(1244);
const rand = prng.random();

// TLAS nodes count:
// shapes = meshes + mesh_instances + spheres
// nodes = shapes * 2 - 1
// BLAS nodes count of one mesh:
// nodes = triangles * 2 - 1
pub const BvhBlas = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    meshes: std.DoublyLinkedList(Mesh),

    nodes: util.ArrayList(gpu_structs.Node),
    normals: util.ArrayList(gpu_structs.Normal),
    normal_indices: util.ArrayList(u32),
    uvs: util.ArrayList(gpu_structs.Uv),
    uv_indices: util.ArrayList(u32),

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .meshes = .{},
            .nodes = util.ArrayList(gpu_structs.Node).init(allocator),
            .normals = util.ArrayList(gpu_structs.Normal).init(allocator),
            .normal_indices = util.ArrayList(u32).init(allocator),
            .uvs = util.ArrayList(gpu_structs.Uv).init(allocator),
            .uv_indices = util.ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        var it = self.meshes.first;
        while (it) |node| {
            it = node.next;
            self.allocator.destroy(node);
        }

        self.nodes.deinit();
        self.normals.deinit();
        self.normal_indices.deinit();
        self.uvs.deinit();
        self.uv_indices.deinit();
    }

    pub fn append(
        self: *Self,
        vertices: []const zmath.Vec,
        vertex_indices: []const u32,
        normals: []const zmath.Vec,
        normal_indices: []const u32,
        uvs: []const [2]f32,
        uv_indices: []const u32,
        transform: zmath.Mat,
        material: *Material,
    ) !*Mesh {
        const triangles_offset = self.normal_indices.len() / 3;
        const triangles_count = vertex_indices.len / 3;
        const indices_range = Range{ .start = self.normal_indices.len(), .end = self.normal_indices.len() + normal_indices.len };
        const normals_range = Range{ .start = self.normals.len(), .end = self.normals.len() + normals.len };
        const nodes_range = Range{ .start = self.nodes.len(), .end = self.nodes.len() + (triangles_count * 2 - 1) };
        try self.nodes.ensureUnusedCapacity(nodes_range.count());
        var leafs = try std.ArrayList(Triangle).initCapacity(self.allocator, triangles_count);
        defer leafs.deinit();

        // append normal_indices
        {
            var i: usize = 0;
            var dst_normal_indices = try self.normal_indices.addManyAsSlice(normal_indices.len);
            while (i < normal_indices.len) : (i += 1) {
                dst_normal_indices[i] = normal_indices[i] + @as(u32, @truncate(self.normals.len()));
            }
        }

        // append normals
        {
            var i: usize = 0;
            var dst_normals = try self.normals.addManyAsSlice(normals.len);
            while (i < normals.len) : (i += 1) {
                dst_normals[i] = zmath.vecToArr4(normals[i]);
            }
        }

        // append uvs/ uv_indices
        var uvs_range: Range = undefined;
        {
            if (uv_indices.len != 0) {
                var i: usize = 0;
                var dst_uv_indices = try self.uv_indices.addManyAsSlice(uv_indices.len);
                while (i < uv_indices.len) : (i += 1) {
                    dst_uv_indices[i] = uv_indices[i] + @as(u32, @truncate(self.uvs.len()));
                }
                uvs_range = Range{ .start = self.uvs.len(), .end = self.uvs.len() + uvs.len };
                try self.uvs.appendSlice(uvs);
            } else {
                var i: usize = 0;
                var dst_uv_indices = try self.uv_indices.addManyAsSlice(vertex_indices.len);
                while (i < vertex_indices.len) : (i += 1) {
                    dst_uv_indices[i] = vertex_indices[i] + @as(u32, @truncate(self.uvs.len()));
                }
                uvs_range = Range{ .start = self.uvs.len(), .end = self.uvs.len() + vertices.len };
                try self.uvs.appendNTimes(.{ 0.5, 0.5 }, vertices.len);
            }
        }

        var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
        var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);

        var mesh_triangle_index: u32 = 0;
        while (mesh_triangle_index < triangles_count) : (mesh_triangle_index += 1) {
            const global_triangle_index = @as(u32, @truncate(triangles_offset + mesh_triangle_index));
            const v0 = vertices[vertex_indices[mesh_triangle_index * 3]];
            const v1 = vertices[vertex_indices[mesh_triangle_index * 3 + 1]];
            const v2 = vertices[vertex_indices[mesh_triangle_index * 3 + 2]];
            min = zmath.min(min, zmath.min(zmath.min(v0, v1), v2));
            max = zmath.max(max, zmath.max(zmath.max(v0, v1), v2));
            try leafs.append(.{
                .v0 = v0,
                .v1 = v1,
                .v2 = v2,
                .triangle_index = global_triangle_index,
                .aabb = Aabb.init(
                    zmath.min(zmath.min(v0, v1), v2),
                    zmath.max(zmath.max(v0, v1), v2),
                ),
            });
        }
        const mesh_root = try self.buildBvh(leafs.items);
        try self.nodes.append(mesh_root);

        const not_transformed_aabb = Aabb.init(min, max);
        const aabb = geometry.transformAabb(transform, not_transformed_aabb);

        var ll_node = try self.allocator.create(std.DoublyLinkedList(Mesh).Node);
        ll_node.* = .{
            .data = .{
                .ll_owner_node = ll_node,
                .bvh_blas_nodes_range = nodes_range,
                .indices_range = indices_range,
                .normals_range = normals_range,
                .uvs_range = uvs_range,
                .material = material,
                .transform = transform,
                .aabb = aabb,
                .not_transformed_aabb = not_transformed_aabb,
            },
        };

        self.meshes.append(ll_node);
        return &ll_node.data;
    }

    pub fn release(self: *Self, mesh: *Mesh) void {
        const mesh_bvh_blas_nodes_count = mesh.bvh_blas_nodes_range.count();
        const nodes_new_len = self.nodes.len() - mesh_bvh_blas_nodes_count;
        @memcpy(
            self.nodes.get_slice_mut(mesh.bvh_blas_nodes_range.start, nodes_new_len),
            self.nodes.get_slice_from(mesh.bvh_blas_nodes_range.end),
        );
        self.nodes.shrinkRetainingCapacity(nodes_new_len);

        const mesh_normals_count = mesh.normals_range.count();
        const normals_new_len = self.normals.len() - mesh_normals_count;
        @memcpy(
            self.normals.get_slice_mut(mesh.normals_range.start, normals_new_len),
            self.normals.get_slice_from(mesh.normals_range.end),
        );
        self.normals.shrinkRetainingCapacity(normals_new_len);

        const mesh_uvs_count = mesh.uvs_range.count();
        const uvs_new_len = self.uvs.len() - mesh_uvs_count;
        @memcpy(
            self.uvs.get_slice_mut(mesh.uvs_range.start, uvs_new_len),
            self.uvs.get_slice_from(mesh.uvs_range.end),
        );
        self.uvs.shrinkRetainingCapacity(uvs_new_len);

        const mesh_indices_count = mesh.indices_range.count();
        const indices_new_len = self.normal_indices.len() - mesh_indices_count;
        var i: usize = 0;
        while (i < indices_new_len) : (i += 1) {
            self.normal_indices.set(
                mesh.indices_range.start + i,
                self.normal_indices.items.get(mesh.indices_range.end + i) - @as(u32, @truncate(mesh_normals_count)),
            );
            self.uv_indices.set(
                mesh.indices_range.start + i,
                self.uv_indices.get(mesh.indices_range.end + i) - @as(u32, @truncate(mesh_uvs_count)),
            );
        }
        self.normal_indices.shrinkRetainingCapacity(indices_new_len);
        self.uv_indices.shrinkRetainingCapacity(indices_new_len);

        var it = mesh.ll_owner_node.next;
        while (it) |node| : (it = node.next) {
            node.data.bvh_blas_nodes_range.start -= mesh_bvh_blas_nodes_count;
            node.data.bvh_blas_nodes_range.end -= mesh_bvh_blas_nodes_count;

            node.data.indices_range.start -= mesh_indices_count;
            node.data.indices_range.end -= mesh_indices_count;

            node.data.normals_range.start -= mesh_normals_count;
            node.data.normals_range.end -= mesh_normals_count;

            node.data.uvs_range.start -= mesh_uvs_count;
            node.data.uvs_range.end -= mesh_uvs_count;
        }
        self.meshes.remove(mesh.ll_owner_node);
        self.allocator.destroy(mesh.ll_owner_node);
        @panic("TODO: tlas");
    }

    fn boxCompare(axis: usize, a: Triangle, b: Triangle) bool {
        return a.aabb.min[axis] < b.aabb.min[axis];
    }

    fn calculateBoundingBox(leafs: []Triangle) Aabb {
        var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
        var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);

        for (leafs) |l| {
            min = zmath.min(min, l.aabb.min);
            max = zmath.max(max, l.aabb.max);
        }
        return Aabb.init(min, max);
    }

    fn buildBvh(self: *Self, leafs: []Triangle) !gpu_structs.Node {
        if (leafs.len == 0) {
            @panic("don't support empty bvh");
        } else if (leafs.len == 1) {
            const t = leafs[0];
            return .{
                .left_aabb_min_or_v0 = zmath.vecToArr3(t.v0),
                .left_aabb_max_or_v1 = zmath.vecToArr3(t.v1),
                .right_aabb_min_or_v2 = zmath.vecToArr3(t.v2),
                .left_or_custom_id = t.triangle_index,
                .node_type = gpu_structs.NodeType.Triangle,

                .right_or_material_index = undefined,
                .right_aabb_max_or_v3 = undefined,
                .transform_id = undefined,
            };
        } else {
            // Sort shapes based on the split axis
            const axis = rand.intRangeAtMost(usize, 0, 2);
            std.sort.heap(Triangle, leafs, axis, boxCompare);

            // Partition shapes into left and right subsets
            const mid = leafs.len / 2;
            const left_leafs = leafs[0..mid];
            const right_leafs = leafs[mid..];

            // Recursively build BVH for left and right subsets
            const left = try self.buildBvh(left_leafs);
            try self.nodes.append(left);
            const left_id = self.nodes.len() - 1;
            const left_aabb = calculateBoundingBox(left_leafs);

            const right = try self.buildBvh(right_leafs);
            try self.nodes.append(right);
            const right_id = self.nodes.len() - 1;
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
};

const Triangle = struct {
    v0: zmath.Vec,
    v1: zmath.Vec,
    v2: zmath.Vec,
    triangle_index: u32,
    aabb: Aabb,
};
