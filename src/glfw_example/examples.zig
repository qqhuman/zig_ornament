const std = @import("std");
const zmath = @import("zmath");
const ornament = @import("../ornament.zig");
const c = @cImport({
    @cInclude("assimp/cimport.h");
    @cInclude("assimp/scene.h");
    @cInclude("assimp/postprocess.h");
});

var prng = std.rand.DefaultPrng.init(100);
const rand = prng.random();

fn randomColor() zmath.Vec {
    return zmath.f32x4(
        rand.float(f32),
        rand.float(f32),
        rand.float(f32),
        1.0,
    );
}

fn randomColorBetween(min: f32, max: f32) zmath.Vec {
    return zmath.f32x4(
        min + (max - min) * rand.float(f32),
        min + (max - min) * rand.float(f32),
        min + (max - min) * rand.float(f32),
        1.0,
    );
}

pub fn init_spheres(ornament_context: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.1;
    const focus_dist = 10.0;
    ornament_context.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try ornament_context.scene.addSphere(try ornament_context.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try ornament_context.lambertian(zmath.f32x4(0.5, 0.5, 0.5, 1.0)),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    ornament_context.lambertian(randomColor() * randomColor())
                else if (choose_mat < 0.95)
                    ornament_context.metal(randomColorBetween(0.5, 1.0), 0.5 * rand.float(f32))
                else
                    ornament_context.dielectric(1.5);
                try ornament_context.scene.addSphere(try ornament_context.createSphere(center, 0.2, material));
            }
        }
    }

    try ornament_context.scene.addSphere(try ornament_context.createSphere(
        zmath.f32x4(0.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_context.dielectric(1.5),
    ));

    try ornament_context.scene.addSphere(try ornament_context.createSphere(
        zmath.f32x4(-4.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_context.lambertian(zmath.f32x4(0.4, 0.2, 0.1, 1.0)),
    ));

    try ornament_context.scene.addSphere(try ornament_context.createSphere(
        zmath.f32x4(4.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_context.metal(zmath.f32x4(0.7, 0.6, 0.5, 1.0), 0.0),
    ));
}

pub fn init_spheres_and_meshes_spheres(ornament_context: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.1;
    const focus_dist = 10.0;
    ornament_context.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try ornament_context.scene.addSphere(try ornament_context.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try ornament_context.lambertian(zmath.f32x4(0.5, 0.5, 0.5, 1.0)),
    ));

    const mesh_sphere = try ornament_context.createSphereMesh(
        zmath.f32x4(0.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_context.dielectric(1.5),
    );
    try ornament_context.scene.addMesh(mesh_sphere);

    try ornament_context.scene.addMeshInstance(try ornament_context.createMeshInstance(
        mesh_sphere,
        zmath.translationV(zmath.f32x4(-4.0, 1.0, 0.0, 0.0)),
        try ornament_context.lambertian(zmath.f32x4(0.4, 0.2, 0.1, 1.0)),
    ));

    try ornament_context.scene.addMeshInstance(try ornament_context.createMeshInstance(
        mesh_sphere,
        zmath.translationV(zmath.f32x4(4.0, 1.0, 0.0, 0.0)),
        try ornament_context.metal(zmath.f32x4(0.7, 0.6, 0.5, 1.0), 0.0),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    ornament_context.lambertian(randomColor() * randomColor())
                else if (choose_mat < 0.95)
                    ornament_context.metal(randomColorBetween(0.5, 1.0), 0.5 * rand.float(f32))
                else
                    ornament_context.dielectric(1.5);
                try ornament_context.scene.addMeshInstance(try ornament_context.createMeshInstance(
                    mesh_sphere,
                    zmath.mul(zmath.scaling(0.2, 0.2, 0.2), zmath.translationV(center)),
                    material,
                ));
            }
        }
    }
}

pub fn init_spheres_and_3_lucy(ornament_context: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.0;
    const focus_dist = 10.0;
    ornament_context.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try ornament_context.scene.addSphere(try ornament_context.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try ornament_context.lambertian(zmath.f32x4(0.5, 0.5, 0.5, 1.0)),
    ));

    const base_lucy_transform = zmath.mul(zmath.scalingV(zmath.f32x4s(2.0)), zmath.rotationY(std.math.pi / 2.0));
    var mesh_lucy = try loadMesh(
        "C:\\my_space\\code\\rust\\rs_ornament\\examples\\models\\lucy.obj",
        ornament_context,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(0.0, 1.0, 0.0, 1.0))),
        try ornament_context.dielectric(1.5),
    );
    try ornament_context.scene.addMesh(mesh_lucy);

    try ornament_context.scene.addMeshInstance(try ornament_context.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(-4.0, 1.0, 0.0, 0.0))),
        try ornament_context.lambertian(zmath.f32x4(0.4, 0.2, 0.1, 1.0)),
    ));

    try ornament_context.scene.addMeshInstance(try ornament_context.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(4.0, 1.0, 0.0, 0.0))),
        try ornament_context.metal(zmath.f32x4(0.7, 0.6, 0.5, 1.0), 0.0),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var mesh_sphere: ?*ornament.Mesh = null;
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    ornament_context.lambertian(randomColor() * randomColor())
                else if (choose_mat < 0.95)
                    ornament_context.metal(randomColorBetween(0.5, 1.0), 0.5 * rand.float(f32))
                else
                    ornament_context.dielectric(1.5);
                if (mesh_sphere) |m| {
                    try ornament_context.scene.addMeshInstance(try ornament_context.createMeshInstance(
                        m,
                        zmath.mul(zmath.scaling(0.2, 0.2, 0.2), zmath.translationV(center)),
                        material,
                    ));
                } else {
                    mesh_sphere = try ornament_context.createSphereMesh(center, 0.2, material);
                    try ornament_context.scene.addMesh(mesh_sphere.?);
                }
            }
        }
    }
}

pub fn loadMesh(path: [:0]const u8, ornament_context: *ornament.Context, transform: zmath.Mat, material: *ornament.Material) !*ornament.Mesh {
    const scene = c.aiImportFile(
        path,
        c.aiProcess_Triangulate | c.aiProcess_JoinIdenticalVertices | c.aiProcess_SortByPType | c.aiProcess_GenSmoothNormals,
    );
    defer c.aiReleaseImport(scene);

    if (scene.*.mNumMeshes != 1) {
        @panic("the scene has 0 or more than 1 mesh");
    }
    const mesh: [*c]c.struct_aiMesh = scene.*.mMeshes[0];

    var vertices = try std.ArrayList(zmath.Vec).initCapacity(ornament_context.allocator, mesh.*.mNumVertices);
    defer vertices.deinit();
    var normals = try std.ArrayList(zmath.Vec).initCapacity(ornament_context.allocator, mesh.*.mNumVertices);
    defer normals.deinit();
    var indices = try std.ArrayList(u32).initCapacity(ornament_context.allocator, mesh.*.mNumFaces * 3);
    defer indices.deinit();

    var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
    var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);
    var i: u32 = 0;
    while (i < mesh.*.mNumVertices) : (i += 1) {
        const vertex = mesh.*.mVertices[i];
        const normal = mesh.*.mNormals[i];
        try vertices.append(zmath.f32x4(vertex.x, vertex.y, vertex.z, 1.0));
        try normals.append(zmath.normalize3(zmath.f32x4(normal.x, normal.y, normal.z, 0.0)));
        min = zmath.min(min, vertices.getLast());
        max = zmath.max(max, vertices.getLast());
    }

    i = 0;
    while (i < mesh.*.mNumFaces) : (i += 1) {
        const face = mesh.*.mFaces[i];
        try indices.append(face.mIndices[0]);
        try indices.append(face.mIndices[1]);
        try indices.append(face.mIndices[2]);
    }

    const t = (min - zmath.f32x4s(0.0)) + (max - min) * zmath.f32x4s(0.5);
    const normalize_matrix = zmath.mul(zmath.inverse(zmath.translationV(t)), zmath.scalingV(zmath.f32x4s(1.0 / (max[1] - min[1]))));
    for (vertices.items) |*v| {
        v.* = zmath.mul(v.*, normalize_matrix);
    }

    return ornament_context.createMesh(vertices.items, indices.items, normals.items, indices.items, transform, material);
}
