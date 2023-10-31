pub const std = @import("std");

const geometry = @import("geometry/geometry.zig");
const materials = @import("materials/materials.zig");

pub const Resolution = struct {
    width: u32,
    height: u32,
};

pub const Range = struct {
    const Self = @This();
    start: usize,
    end: usize,

    pub inline fn count(self: *const Self) usize {
        return self.end - self.start;
    }
};

const Shape = union(enum) {
    sphere: *geometry.Sphere,
    mesh: *geometry.Mesh,
    mesh_instance: *geometry.MeshInstance,
};

const Material = union(enum) {
    lambertian: *materials.Lambertian,
    metal: *materials.Metal,
    dielectric: *materials.Dielectric,
};
