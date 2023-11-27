const std = @import("std");
const zmath = @import("zmath");
const Material = @import("material.zig").Material;
const gpu_structs = @import("gpu_structs.zig");
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
    tlas_nodes: std.ArrayList(gpu_structs.BvhNode),
    blas_nodes: std.ArrayList(gpu_structs.BvhNode),
    normals: std.ArrayList(gpu_structs.Normal),
    normal_indices: std.ArrayList(u32),
    uvs: std.ArrayList(gpu_structs.Uv),
    uv_indices: std.ArrayList(u32),
    transforms: std.ArrayList(gpu_structs.Transform),
    materials: std.ArrayList(gpu_structs.Material),
    textures: std.ArrayList(*ornament.Texture),
    row_major_transforms: bool,

    pub fn init(allocator: std.mem.Allocator, scene: *const ornament.Scene, row_major_transforms: bool) std.mem.Allocator.Error!Self {
        const shapes_count = scene.spheres.items.len + scene.meshes.items.len + scene.mesh_instances.items.len;
        if (shapes_count == 0) {
            @panic("[ornament] scene cannot be empty.");
        }
        const tlas_nodes_count = shapes_count * 2 - 1;
        var blas_nodes_count: usize = 0;
        var normals_count: usize = 0;
        var normal_indices_count: usize = 0;
        var uvs_count: usize = 0;
        var uv_indices_count: usize = 0;
        for (scene.meshes.items) |m| {
            const triangles = m.vertex_indices.items.len / 3;
            blas_nodes_count += triangles * 2 - 1;
            normals_count += m.normals.items.len;
            normal_indices_count += m.normal_indices.items.len;
            uvs_count += m.uvs.items.len;
            uv_indices_count += m.uv_indices.items.len;
        }
        var self = Self{
            .tlas_nodes = try std.ArrayList(gpu_structs.BvhNode).initCapacity(allocator, tlas_nodes_count),
            .blas_nodes = try std.ArrayList(gpu_structs.BvhNode).initCapacity(allocator, blas_nodes_count),
            .normals = try std.ArrayList(gpu_structs.Normal).initCapacity(allocator, normals_count),
            .normal_indices = try std.ArrayList(u32).initCapacity(allocator, normal_indices_count),
            .uvs = try std.ArrayList(gpu_structs.Uv).initCapacity(allocator, uvs_count),
            .uv_indices = try std.ArrayList(u32).initCapacity(allocator, uv_indices_count),
            .transforms = try std.ArrayList(gpu_structs.Transform).initCapacity(allocator, shapes_count),
            .materials = std.ArrayList(gpu_structs.Material).init(allocator),
            .textures = std.ArrayList(*ornament.Texture).init(allocator),
            .row_major_transforms = row_major_transforms,
        };
        std.log.debug("[ornament] bvh building.", .{});
        try build(allocator, &self, scene);
        std.log.debug("[ornament] spheres: {d}", .{scene.spheres.items.len});
        std.log.debug("[ornament] meshes: {d}", .{scene.meshes.items.len});
        std.log.debug("[ornament] mesh_instances: {d}", .{scene.mesh_instances.items.len});
        std.log.debug("[ornament] textures: {d}", .{self.textures.items.len});
        std.log.debug("[ornament] expected bvh.tlas_nodes: {d}", .{tlas_nodes_count});
        std.log.debug("[ornament] actual bvh.tlas_nodes: {d}", .{self.tlas_nodes.items.len});
        std.log.debug("[ornament] expected bvh.blas_nodes: {d}", .{blas_nodes_count});
        std.log.debug("[ornament] actual bvh.blas_nodes: {d}", .{self.blas_nodes.items.len});
        std.debug.assert(tlas_nodes_count == self.tlas_nodes.items.len);
        std.debug.assert(blas_nodes_count == self.blas_nodes.items.len);

        return self;
    }

    pub fn deinit(self: *Self) void {
        self.tlas_nodes.deinit();
        self.blas_nodes.deinit();
        self.normals.deinit();
        self.normal_indices.deinit();
        self.uvs.deinit();
        self.uv_indices.deinit();
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
        for (scene.mesh_instances.items) |mi| try leafs.append(.{ .mesh_instance = mi });
        for (scene.meshes.items) |m| {
            try leafs.append(.{ .mesh = m });
            try buildMeshBvhRecursive(allocator, bvh, m);
        }

        const root = try buildBvhTlasRecursive(allocator, bvh, leafs.items);
        try bvh.tlas_nodes.append(root);
    }
};

const NodeType = enum(u32) {
    InternalNode = 0,
    Sphere = 1,
    Mesh = 2,
    Triangle = 3,
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
};

fn boxCompare(axis: usize, a: Leaf, b: Leaf) bool {
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

fn boxCompareBlas(axis: usize, a: Triangle, b: Triangle) bool {
    return a.aabb.min[axis] < b.aabb.min[axis];
}

fn calculateBoundingBox(leafs: []Leaf) Aabb {
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

fn calculateBoundingBoxBlas(leafs: []Triangle) Aabb {
    var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
    var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);

    for (leafs) |l| {
        min = zmath.min(min, l.aabb.min);
        max = zmath.max(max, l.aabb.max);
    }
    return Aabb.init(min, max);
}

fn buildMeshBvhRecursive(allocator: std.mem.Allocator, bvh: *Bvh, mesh: *Mesh) std.mem.Allocator.Error!void {
    var leafs = try std.ArrayList(Triangle).initCapacity(allocator, mesh.vertex_indices.items.len / 3);
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
        try leafs.append(.{
            .v0 = v0,
            .v1 = v1,
            .v2 = v2,
            .triangle_index = global_triangle_index,
            .aabb = aabb,
        });
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

    i = 0;
    var uv_indices = try bvh.uv_indices.addManyAsSlice(mesh.uv_indices.items.len);
    while (i < mesh.uv_indices.items.len) : (i += 1) {
        uv_indices[i] = mesh.uv_indices.items[i] + @as(u32, @truncate(bvh.uvs.items.len));
    }

    try bvh.uvs.appendSlice(mesh.uvs.items);

    const mesh_root = try buildBvhBlasRecursive(allocator, bvh, leafs.items);
    try bvh.blas_nodes.append(mesh_root);
    const mesh_top_id = @as(u32, @truncate(bvh.blas_nodes.items.len - 1));
    mesh.bvh_id = mesh_top_id;
}

fn buildBvhBlasRecursive(allocator: std.mem.Allocator, bvh: *Bvh, leafs: []Triangle) std.mem.Allocator.Error!gpu_structs.BvhNode {
    if (leafs.len == 0) {
        @panic("don't support empty bvh");
    } else if (leafs.len == 1) {
        const t = leafs[0];
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
    } else {
        // Sort shapes based on the split axis
        const axis = rand.intRangeAtMost(usize, 0, 2);
        std.sort.heap(Triangle, leafs, axis, boxCompareBlas);

        // Partition shapes into left and right subsets
        const mid = leafs.len / 2;
        const left_leafs = leafs[0..mid];
        const right_leafs = leafs[mid..];

        // Recursively build BVH for left and right subsets
        const left = try buildBvhBlasRecursive(allocator, bvh, left_leafs);
        try bvh.blas_nodes.append(left);
        const left_id = bvh.blas_nodes.items.len - 1;
        const left_aabb = calculateBoundingBoxBlas(left_leafs);

        const right = try buildBvhBlasRecursive(allocator, bvh, right_leafs);
        try bvh.blas_nodes.append(right);
        const right_id = bvh.blas_nodes.items.len - 1;
        const right_aabb = calculateBoundingBoxBlas(right_leafs);

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

fn buildBvhTlasRecursive(allocator: std.mem.Allocator, bvh: *Bvh, leafs: []Leaf) std.mem.Allocator.Error!gpu_structs.BvhNode {
    if (leafs.len == 0) {
        @panic("don't support empty bvh");
    } else if (leafs.len == 1) {
        switch (leafs[0]) {
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
                const transform = m.transform;
                try appendTransform(bvh, zmath.inverse(transform));
                try appendTransform(bvh, transform);
                const transform_id = bvh.transforms.items.len / 2 - 1;
                return .{
                    .left_aabb_min_or_v0 = zmath.vecToArr3(m.aabb.min),
                    .left_aabb_max_or_v1 = zmath.vecToArr3(m.aabb.max),
                    .left_or_custom_id = m.bvh_id orelse unreachable,
                    .right_or_material_index = try getMaterialIndex(bvh, m.material),
                    .node_type = @intFromEnum(NodeType.Mesh),
                    .transform_id = @as(u32, @truncate(transform_id)),

                    .right_aabb_min_or_v2 = undefined,
                    .right_aabb_max_or_v3 = undefined,
                };
            },
            .mesh_instance => |mi| {
                const transform = mi.transform;
                try appendTransform(bvh, zmath.inverse(transform));
                try appendTransform(bvh, transform);
                const transform_id = bvh.transforms.items.len / 2 - 1;
                return .{
                    .left_aabb_min_or_v0 = zmath.vecToArr3(mi.aabb.min),
                    .left_aabb_max_or_v1 = zmath.vecToArr3(mi.aabb.max),
                    .right_or_material_index = try getMaterialIndex(bvh, mi.material),
                    .node_type = @intFromEnum(NodeType.Mesh),
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
        std.sort.heap(Leaf, leafs, axis, boxCompare);

        // Partition shapes into left and right subsets
        const mid = leafs.len / 2;
        const left_leafs = leafs[0..mid];
        const right_leafs = leafs[mid..];

        // Recursively build BVH for left and right subsets
        const left = try buildBvhTlasRecursive(allocator, bvh, left_leafs);
        try bvh.tlas_nodes.append(left);
        const left_id = bvh.tlas_nodes.items.len - 1;
        const left_aabb = calculateBoundingBox(left_leafs);

        const right = try buildBvhTlasRecursive(allocator, bvh, right_leafs);
        try bvh.tlas_nodes.append(right);
        const right_id = bvh.tlas_nodes.items.len - 1;
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
    const t = if (bvh.row_major_transforms) zmath.transpose(transform) else transform;
    try bvh.transforms.append(zmath.matToArr(t));
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
        try bvh.materials.append(gpu_structs.Material.from(material));
        const material_id = @as(u32, @truncate(bvh.materials.items.len - 1));
        material.material_index = material_id;
        return material_id;
    };
}
