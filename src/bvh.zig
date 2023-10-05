const std = @import("std");
const zmath = @import("zmath");
const Material = @import("materials/material.zig").Material;
const wgsl_structs = @import("wgpu/wgsl_structs.zig");
const ornament = @import("ornament.zig");
const Scene = ornament.Scene;
const Aabb = ornament.Aabb;
const Sphere = ornament.Sphere;
const Mesh = ornament.Mesh;
const MeshInstance = ornament.MeshInstance;

var prng = std.rand.DefaultPrng.init(1244);
const rand = prng.random();

pub const Bvh = struct {
    const Self = @This();
    // TLAS nodes count:
    // shapes = meshes + mesh_instances + spheres
    // nodes = shapes * 2 - 1
    // BLAS nodes count of one mesh:
    // nodes = triangles * 2 - 1
    nodes: std.ArrayList(wgsl_structs.Node),
    normals: std.ArrayList(wgsl_structs.Normal),
    normal_indices: std.ArrayList(u32),
    transforms: std.ArrayList(wgsl_structs.Transform),
    materials: std.ArrayList(wgsl_structs.Material),
    textures: std.ArrayList(*ornament.Texture),

    pub fn init(allocator: std.mem.Allocator, ornament_ctx: *const ornament.Context) std.mem.Allocator.Error!Self {
        const shapes_count = ornament_ctx.scene.spheres.items.len + ornament_ctx.scene.meshes.items.len + ornament_ctx.scene.mesh_instances.items.len;
        if (shapes_count == 0) {
            @panic("[ornament] scene cannot be empty.");
        }
        const tlas_nodes = shapes_count * 2 - 1;
        var blas_nodes: usize = 0;
        var normals_count: usize = 0;
        var normal_indices_count: usize = 0;
        for (ornament_ctx.scene.meshes.items) |m| {
            const triangles = m.vertex_indices.items.len / 3;
            blas_nodes += triangles * 2 - 1;
            normals_count += m.normals.items.len;
            normal_indices_count += m.normal_indices.items.len;
        }
        const expected_nodes = tlas_nodes + blas_nodes;
        var self = Self{
            .nodes = try std.ArrayList(wgsl_structs.Node).initCapacity(allocator, expected_nodes),
            .normals = try std.ArrayList(wgsl_structs.Normal).initCapacity(allocator, normals_count),
            .normal_indices = try std.ArrayList(u32).initCapacity(allocator, normal_indices_count),
            .transforms = try std.ArrayList(wgsl_structs.Transform).initCapacity(allocator, shapes_count),
            .materials = try std.ArrayList(wgsl_structs.Material).initCapacity(allocator, ornament_ctx.materials.items.len),
            .textures = try std.ArrayList(*ornament.Texture).initCapacity(allocator, ornament_ctx.textures.items.len),
        };
        std.log.debug("[ornament] bvh building.", .{});
        try build(allocator, &self, &ornament_ctx.scene);
        std.log.debug("[ornament] spheres: {d}", .{ornament_ctx.scene.spheres.items.len});
        std.log.debug("[ornament] meshes: {d}", .{ornament_ctx.scene.meshes.items.len});
        std.log.debug("[ornament] mesh_instances: {d}", .{ornament_ctx.scene.mesh_instances.items.len});
        std.log.debug("[ornament] expected bvh.nodes (tlas_nodes): {d}", .{tlas_nodes});
        std.log.debug("[ornament] expected bvh.nodes (blas_nodes): {d}", .{blas_nodes});
        std.log.debug("[ornament] expected bvh.nodes (tlas_nodes + blas_nodes): {d}", .{expected_nodes});
        std.log.debug("[ornament] actual bvh.nodes: {d}", .{self.nodes.items.len});
        std.debug.assert(expected_nodes == self.nodes.items.len);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.nodes.deinit();
        self.normals.deinit();
        self.normal_indices.deinit();
        self.transforms.deinit();
        self.materials.deinit();
        self.textures.deinit();
    }

    fn build(allocator: std.mem.Allocator, bvh: *Bvh, scene: *const Scene) std.mem.Allocator.Error!void {
        var leafs = try std.ArrayList(Leaf).initCapacity(
            allocator,
            scene.spheres.items.len + scene.meshes.items.len + scene.mesh_instances.items.len,
        );
        defer leafs.deinit();

        for (scene.spheres.items) |s| try leafs.append(.{ .sphere = s });
        for (scene.meshes.items) |m| try leafs.append(.{ .mesh = m });
        for (scene.mesh_instances.items) |mi| try leafs.append(.{ .mesh_instance = mi });

        var isntances_to_resolve = std.AutoHashMap(u32, *const MeshInstance).init(allocator);
        defer isntances_to_resolve.deinit();

        const root = try buildBvhRecursive(allocator, bvh, leafs.items, &isntances_to_resolve);
        try bvh.nodes.append(root);

        var iterator = isntances_to_resolve.iterator();
        while (iterator.next()) |entry| {
            bvh.nodes.items[entry.key_ptr.*].left_or_custom_id = entry.value_ptr.*.mesh.bvh_id orelse unreachable;
        }
    }
};

const NodeType = enum(u32) {
    InternalNode = 0,
    Sphere = 1,
    Mesh = 2,
    MeshInstance = 3,
    Triangle = 4,
};

const Triangle = struct {
    v0: zmath.Vec,
    v1: zmath.Vec,
    v2: zmath.Vec,
    triangle_index: u32,
    aabb: Aabb,
};

const Leaf = union(enum) {
    sphere: *Sphere,
    mesh: *Mesh,
    mesh_instance: *MeshInstance,
    triangle: Triangle,
};

fn boxCompare(axis: usize, a: Leaf, b: Leaf) bool {
    const box_a = switch (a) {
        .triangle => |t| t.aabb,
        .sphere => |s| s.aabb,
        .mesh => |m| m.aabb,
        .mesh_instance => |mi| mi.aabb,
    };

    const box_b = switch (b) {
        .triangle => |t| t.aabb,
        .sphere => |s| s.aabb,
        .mesh => |m| m.aabb,
        .mesh_instance => |mi| mi.aabb,
    };

    return box_a.min[axis] < box_b.min[axis];
}

fn calculateBoundingBox(leafs: []Leaf) Aabb {
    var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
    var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);

    for (leafs) |l| {
        const aabb = switch (l) {
            .triangle => |t| t.aabb,
            .sphere => |s| s.aabb,
            .mesh => |m| m.aabb,
            .mesh_instance => |mi| mi.aabb,
        };
        min = zmath.min(min, aabb.min);
        max = zmath.max(max, aabb.max);
    }
    return Aabb.init(min, max);
}

fn buildBvhRecursive(allocator: std.mem.Allocator, bvh: *Bvh, leafs: []Leaf, isntances_to_resolve: *std.AutoHashMap(u32, *const MeshInstance)) std.mem.Allocator.Error!wgsl_structs.Node {
    if (leafs.len == 0) {
        @panic("don't support empty bvh");
    } else if (leafs.len == 1) {
        switch (leafs[0]) {
            .triangle => |t| {
                return .{
                    .left_aabb_min_or_v0 = zmath.vecToArr3(t.v0),
                    .left_aabb_max_or_v1 = zmath.vecToArr3(t.v1),
                    .right_aabb_min_or_v2 = zmath.vecToArr3(t.v2),
                    .left_or_custom_id = t.triangle_index,
                    .node_type = @intFromEnum(NodeType.Triangle),

                    .right_or_material_index = undefined,
                    .right_aabb_max_or_v3 = undefined,
                    .transform_id = undefined,
                };
            },
            .sphere => |s| {
                const transform = s.transform;
                try appendTransform(bvh, zmath.inverse(transform));
                try appendTransform(bvh, transform);
                const transform_id = bvh.transforms.items.len / 2 - 1;
                return .{
                    .left_aabb_min_or_v0 = zmath.vecToArr3(s.aabb.min),
                    .left_aabb_max_or_v1 = zmath.vecToArr3(s.aabb.max),
                    .right_or_material_index = try getMaterialIndex(bvh, s.material),
                    .node_type = @intFromEnum(NodeType.Sphere),
                    .transform_id = @as(u32, @truncate(transform_id)),

                    .left_or_custom_id = undefined,
                    .right_aabb_min_or_v2 = undefined,
                    .right_aabb_max_or_v3 = undefined,
                };
            },
            .mesh => |m| {
                const mesh_top = try fromMesh(allocator, bvh, m, isntances_to_resolve);

                try bvh.nodes.append(mesh_top);
                const mesh_top_id = @as(u32, @truncate(bvh.nodes.items.len - 1));
                m.bvh_id = mesh_top_id;

                const transform = m.transform;
                try appendTransform(bvh, zmath.inverse(transform));
                try appendTransform(bvh, transform);
                const transform_id = bvh.transforms.items.len / 2 - 1;
                return .{
                    .left_aabb_min_or_v0 = zmath.vecToArr3(m.aabb.min),
                    .left_aabb_max_or_v1 = zmath.vecToArr3(m.aabb.max),
                    .left_or_custom_id = mesh_top_id,
                    .right_or_material_index = try getMaterialIndex(bvh, m.material),
                    .node_type = @intFromEnum(NodeType.Mesh),
                    .transform_id = @as(u32, @truncate(transform_id)),

                    .right_aabb_min_or_v2 = undefined,
                    .right_aabb_max_or_v3 = undefined,
                };
            },
            .mesh_instance => |mi| {
                const left_or_custom_id = blk: {
                    if (mi.mesh.bvh_id) |bvh_id| {
                        break :blk bvh_id;
                    } else {
                        try isntances_to_resolve.put(@as(u32, @truncate(bvh.nodes.items.len)), mi);
                        break :blk undefined;
                    }
                };
                const transform = mi.transform;
                try appendTransform(bvh, zmath.inverse(transform));
                try appendTransform(bvh, transform);
                const transform_id = bvh.transforms.items.len / 2 - 1;
                return .{
                    .left_aabb_min_or_v0 = zmath.vecToArr3(mi.aabb.min),
                    .left_aabb_max_or_v1 = zmath.vecToArr3(mi.aabb.max),
                    .right_or_material_index = try getMaterialIndex(bvh, mi.material),
                    .node_type = @intFromEnum(NodeType.MeshInstance),
                    .transform_id = @as(u32, @truncate(transform_id)),

                    .left_or_custom_id = left_or_custom_id,

                    .right_aabb_min_or_v2 = undefined,
                    .right_aabb_max_or_v3 = undefined,
                };
            },
        }
    } else {
        // Sort shapes based on the split axis
        const axis = rand.intRangeAtMost(usize, 0, 2);
        std.sort.heap(Leaf, leafs, axis, boxCompare);

        // Partition shapes into left and right subsets
        const mid = leafs.len / 2;
        const left_leafs = leafs[0..mid];
        const right_leafs = leafs[mid..];

        // Recursively build BVH for left and right subsets
        const left = try buildBvhRecursive(allocator, bvh, left_leafs, isntances_to_resolve);
        try bvh.nodes.append(left);
        const left_id = bvh.nodes.items.len - 1;
        const left_aabb = calculateBoundingBox(left_leafs);

        const right = try buildBvhRecursive(allocator, bvh, right_leafs, isntances_to_resolve);
        try bvh.nodes.append(right);
        const right_id = bvh.nodes.items.len - 1;
        const right_aabb = calculateBoundingBox(right_leafs);

        return .{
            .left_aabb_min_or_v0 = zmath.vecToArr3(left_aabb.min),
            .left_or_custom_id = @as(u32, @truncate(left_id)),
            .left_aabb_max_or_v1 = zmath.vecToArr3(left_aabb.max),
            .right_or_material_index = @as(u32, @truncate(right_id)),
            .right_aabb_min_or_v2 = zmath.vecToArr3(right_aabb.min),
            .node_type = @intFromEnum(NodeType.InternalNode),
            .right_aabb_max_or_v3 = zmath.vecToArr3(right_aabb.max),

            .transform_id = undefined,
        };
    }
}

fn appendTransform(bvh: *Bvh, transform: zmath.Mat) !void {
    try bvh.transforms.append(transform);
}

fn fromMesh(allocator: std.mem.Allocator, bvh: *Bvh, mesh: *Mesh, isntances_to_resolve: *std.AutoHashMap(u32, *const MeshInstance)) std.mem.Allocator.Error!wgsl_structs.Node {
    var leafs = try std.ArrayList(Leaf).initCapacity(allocator, mesh.vertex_indices.items.len / 3);
    defer leafs.deinit();

    var mesh_triangle_index: usize = 0;
    while (mesh_triangle_index < mesh.vertex_indices.items.len / 3) : (mesh_triangle_index += 1) {
        const v0 = mesh.vertices.items[mesh.vertex_indices.items[mesh_triangle_index * 3]];
        const v1 = mesh.vertices.items[mesh.vertex_indices.items[mesh_triangle_index * 3 + 1]];
        const v2 = mesh.vertices.items[mesh.vertex_indices.items[mesh_triangle_index * 3 + 2]];
        const aabb = Aabb.init(
            zmath.min(zmath.min(v0, v1), v2),
            zmath.max(zmath.max(v0, v1), v2),
        );
        const global_triangle_index = @as(u32, @truncate(bvh.normal_indices.items.len / 3 + mesh_triangle_index));
        try leafs.append(.{ .triangle = .{
            .v0 = v0,
            .v1 = v1,
            .v2 = v2,
            .triangle_index = global_triangle_index,
            .aabb = aabb,
        } });
    }

    var i: usize = 0;
    var normal_indices = try bvh.normal_indices.addManyAsSlice(mesh.normal_indices.items.len);
    while (i < mesh.normal_indices.items.len) : (i += 1) {
        normal_indices[i] = mesh.normal_indices.items[i] + @as(u32, @truncate(bvh.normals.items.len));
    }

    i = 0;
    var normals = try bvh.normals.addManyAsSlice(mesh.normals.items.len);
    while (i < mesh.normals.items.len) : (i += 1) {
        normals[i] = zmath.vecToArr4(mesh.normals.items[i]);
    }
    return try buildBvhRecursive(allocator, bvh, leafs.items, isntances_to_resolve);
}

fn getMaterialIndex(bvh: *Bvh, material: *Material) std.mem.Allocator.Error!u32 {
    return material.material_index orelse {
        switch (material.albedo) {
            .texture => |texture| {
                try bvh.textures.append(texture);
                texture.texture_id = @as(u32, @truncate(bvh.textures.items.len - 1));
            },
            else => {},
        }
        try bvh.materials.append(wgsl_structs.Material.from(material));
        const material_id = @as(u32, @truncate(bvh.materials.items.len - 1));
        material.material_index = material_id;
        return material_id;
    };
}
