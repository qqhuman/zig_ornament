const std = @import("std");
const Color = @import("color.zig").Color;
const MaterialType = @import("../gpu_structs.zig").MaterialType;

pub const Material = struct {
    albedo: Color,
    fuzz: f32,
    ior: f32,
    materia_type: MaterialType,
    material_index: u32,
};

pub const Lambertian = struct {
    const Self = @This();
    ll_owner_node: *std.DoublyLinkedList(Self).Node,
    material_index: u32,
    albedo: Color,
};

pub const Metal = struct {
    const Self = @This();
    ll_owner_node: *std.DoublyLinkedList(Self).Node,
    material_index: u32,
    albedo: Color,
    fuzz: f32,
};

pub const Dielectric = struct {
    const Self = @This();
    ll_owner_node: *std.DoublyLinkedList(Self).Node,
    material_index: u32,
    ior: f32,
};

pub const DiffuseLight = struct {
    const Self = @This();
    ll_owner_node: *std.DoublyLinkedList(Self).Node,
    material_index: u32,
    albedo: Color,
};
