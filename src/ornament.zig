const util = @import("util.zig");
pub const Resolution = util.Resolution;
pub const Scene = @import("scene.zig").Scene;
pub const Camera = @import("camera.zig").Camera;
pub const Aabb = @import("aabb.zig").Aabb;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Mesh = @import("mesh.zig").Mesh;
pub const MeshInstance = @import("mesh_instance.zig").MeshInstance;
pub const material = @import("material.zig");
pub const Material = material.Material;
pub const MaterialType = material.MaterialType;
pub const Texture = @import("texture.zig").Texture;
pub const Color = @import("color.zig").Color;

pub const wgpu_backend = @import("wgpu_backend/path_tracer.zig");
pub const WgpuPathTracer = wgpu_backend.PathTracer;

pub const hip_backend = @import("hip_backend/path_tracer.zig");
pub const HipPathTracer = hip_backend.PathTracer;
