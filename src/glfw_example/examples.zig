const std = @import("std");
const zmath = @import("zmath");
const ornament = @import("../ornament.zig");

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
