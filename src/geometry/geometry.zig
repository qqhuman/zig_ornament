const std = @import("std");
const zmath = @import("zmath");
pub const Camera = @import("camera.zig").Camera;
pub const Sphere = @import("sphere.zig").Sphere;
pub const Mesh = @import("mesh.zig").Mesh;
pub const MeshInstance = @import("mesh_instance.zig").MeshInstance;
const aabb = @import("aabb.zig");
pub const Aabb = aabb.Aabb;
pub const transformAabb = aabb.transformAabb;
const Shape = @import("../util.zig").Shape;

pub const Scene = struct {
    const Self = @This();
    allocator: std.mem.Allocator,
    camera: Camera,
    shapes: std.ArrayList(Shape),
    dirty: bool = true,

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
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
            .shapes = std.ArrayList(Shape).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.shapes.deinit();
    }

    pub fn appendSphere(self: *Self, sphere: *Sphere) !void {
        try self.shapes.append(.{ .sphere = sphere });
        self.dirty = true;
    }

    pub fn removeSphere(self: *Self, sphere: *Sphere) void {
        self.removeShape(.{ .sphere = sphere });
    }

    pub fn appendMesh(self: *Self, mesh: *Mesh) !void {
        try self.shapes.append(.{ .mesh = mesh });
        self.dirty = true;
    }

    pub fn removeMesh(self: *Self, mesh: *Mesh) void {
        self.removeShape(.{ .mesh = mesh });
    }

    pub fn appendMeshInstance(self: *Self, mesh_instance: *MeshInstance) !void {
        try self.shapes.append(.{ .mesh_instance = mesh_instance });
        self.dirty = true;
    }

    pub fn removeMeshInstance(self: *Self, mesh_instance: *MeshInstance) void {
        self.removeShape(.{ .mesh_instance = mesh_instance });
    }

    fn removeShape(self: *Self, shape: Shape) void {
        for (self.shapes.items, 0..) |s, i| {
            if (s == shape) {
                self.shapes.swapRemove(i);
                self.dirty = true;
                break;
            }
        }
    }
};
