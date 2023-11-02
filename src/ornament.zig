const util = @import("util.zig");
pub const Resolution = util.Resolution;
pub const Scene = @import("scene.zig").Scene;
pub const Camera = @import("camera.zig").Camera;
pub const Aabb = @import("aabb.zig").Aabb;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Mesh = @import("mesh.zig").Mesh;
pub const MeshInstance = @import("mesh_instance.zig").MeshInstance;
pub const Material = @import("material.zig").Material;
pub const Texture = @import("texture.zig").Texture;
pub const Color = @import("color.zig").Color;

pub const wgpu_backend = @import("wgpu_backend/path_tracer.zig");
pub const WgpuPathTracer = @import("wgpu_backend/path_tracer.zig").PathTracer;

pub const hip = @import("hip_backend/hip.zig");
