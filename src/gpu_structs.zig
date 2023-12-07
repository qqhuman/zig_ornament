const std = @import("std");
const zmath = @import("zmath");
const ornament = @import("ornament.zig");
const State = @import("state.zig").State;

pub const TARGET_PIXEL_COMPONENTS: u32 = 4;
pub const Resolution = [2]u32;
pub const Point3 = [3]f32;
pub const Vector3 = [3]f32;
pub const Vector4 = [TARGET_PIXEL_COMPONENTS]f32;
pub const Normal = [4]f32; // 4th byte is padding
pub const Uv = [2]f32;
pub const Transform = [16]f32;

pub const BvhNodeType = enum(u32) {
    InternalNode = 0,
    Sphere = 1,
    Mesh = 2,
    Triangle = 3,
};

pub const BvhNode = extern struct {
    left_aabb_min_or_v0: [3]f32,
    left_or_custom_id: u32, // bvh node/top of mesh bvh/triangle id
    left_aabb_max_or_v1: [3]f32,
    right_or_material_index: u32,
    right_aabb_min_or_v2: [3]f32,
    node_type: BvhNodeType,
    right_aabb_max_or_v3: [3]f32,
    transform_id: u32,
};

pub const Material = extern struct {
    const Self = @This();
    albedo_vec: [3]f32,
    albedo_texture_index: u32,
    fuzz: f32,
    ior: f32,
    materia_type: ornament.MaterialType,
    _padding: u32 = undefined,

    pub fn from(material: *const ornament.Material) Self {
        var albedo_vec = zmath.f32x4(1.0, 0.0, 1.0, 1.0);
        var albedo_texture_index: u32 = std.math.maxInt(u32);

        switch (material.albedo) {
            .vec => |v| albedo_vec = v,
            .texture => |texture| albedo_texture_index = texture.texture_id.?,
        }

        return .{
            .albedo_vec = zmath.vecToArr3(albedo_vec),
            .albedo_texture_index = albedo_texture_index,
            .fuzz = material.fuzz,
            .ior = material.ior,
            .materia_type = material.materia_type,
        };
    }
};

pub const ConstantParams = extern struct {
    const Self = @This();
    camera: Camera,
    depth: u32,
    width: u32,
    height: u32,
    flip_y: u32,
    inverted_gamma: f32,
    ray_cast_epsilon: f32,
    textures_count: u32,
    current_iteration: f32 = 0.0,

    pub fn from(camera: *const ornament.Camera, state: *const State, textures_count: u32) Self {
        return .{
            .camera = Camera.from(camera),
            .depth = state.depth,
            .width = state.resolution.width,
            .height = state.resolution.height,
            .flip_y = if (state.flip_y) 1 else 0,
            .inverted_gamma = state.inverted_gamma,
            .ray_cast_epsilon = state.ray_cast_epsilon,
            .textures_count = textures_count,
            .current_iteration = state.current_iteration,
        };
    }
};

pub const Camera = extern struct {
    const Self = @This();
    origin: Point3,
    lens_radius: f32,
    lower_left_corner: Point3,
    _padding0: u32 = undefined,
    horizontal: Vector3,
    _padding1: u32 = undefined,
    vertical: Vector3,
    _padding2: u32 = undefined,
    u: Vector3,
    _padding3: u32 = undefined,
    v: Vector3,
    _padding4: u32 = undefined,
    w: Vector3,
    _padding5: u32 = undefined,

    pub fn from(camera: *const ornament.Camera) Self {
        return .{
            .origin = zmath.vecToArr3(camera.origin),
            .lower_left_corner = zmath.vecToArr3(camera.lower_left_corner),
            .horizontal = zmath.vecToArr3(camera.horizontal),
            .vertical = zmath.vecToArr3(camera.vertical),
            .u = zmath.vecToArr3(camera.u),
            .v = zmath.vecToArr3(camera.v),
            .w = zmath.vecToArr3(camera.w),
            .lens_radius = camera.lens_radius,
        };
    }
};
