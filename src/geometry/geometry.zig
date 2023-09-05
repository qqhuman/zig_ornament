const std = @import("std");
const zmath = @import("zmath");
pub const Camera = @import("camera.zig").Camera;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Mesh = @import("mesh.zig").Mesh;
pub const MeshInstance = @import("mesh_instance.zig").MeshInstance;
pub const Aabb = @import("aabb.zig").Aabb;

pub const Scene = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    camera: Camera,
    spheres: std.ArrayList(*Sphere),
    meshes: std.ArrayList(*Mesh),
    mesh_instances: std.ArrayList(*MeshInstance),

    pub fn init(allocator: std.mem.Allocator) std.mem.Allocator.Error!*Self {
        var self = try allocator.create(Self);
        self.* = .{
            .allocator = allocator,
            .camera = Camera.init(
                zmath.f32x4(1.0, 1.0, 1.0, 1.0),
                zmath.f32x4(0.0, 0.0, 0.0, 1.0),
                zmath.f32x4(0.0, 1.0, 0.0, 0.0),
                1.0,
                40.0,
                0.0,
                10.0,
            ),
            .spheres = std.ArrayList(*Sphere).init(allocator),
            .meshes = std.ArrayList(*Mesh).init(allocator),
            .mesh_instances = std.ArrayList(*MeshInstance).init(allocator),
        };
        return self;
    }

    pub fn deinit(self: *Self) void {
        defer self.allocator.destroy(self);
        self.spheres.deinit();
        self.meshes.deinit();
        self.mesh_instances.deinit();
    }

    pub fn addSphere(self: *Self, sphere: *Sphere) std.mem.Allocator.Error!void {
        try self.spheres.append(sphere);
    }

    pub fn addMesh(self: *Self, mesh: *Mesh) std.mem.Allocator.Error!void {
        try self.meshes.append(mesh);
    }

    pub fn addMeshInstance(self: *Self, mesh_instance: *MeshInstance) std.mem.Allocator.Error!void {
        try self.mesh_instances.append(mesh_instance);
    }
};
