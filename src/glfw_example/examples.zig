const std = @import("std");
const zmath = @import("zmath");
const zstbi = @import("zstbi");
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

pub fn init_spheres(ornament_ctx: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.1;
    const focus_dist = 10.0;
    ornament_ctx.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    ornament_ctx.lambertian(.{ .vec = randomColor() * randomColor() })
                else if (choose_mat < 0.95)
                    ornament_ctx.metal(.{ .vec = randomColorBetween(0.5, 1.0) }, 0.5 * rand.float(f32))
                else
                    ornament_ctx.dielectric(1.5);
                try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(center, 0.2, material));
            }
        }
    }

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(0.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_ctx.dielectric(1.5),
    ));

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(-4.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
    ));

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(4.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_ctx.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));
}

pub fn init_spheres_and_textures(ornament_ctx: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.1;
    const focus_dist = 10.0;
    ornament_ctx.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(0.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_ctx.dielectric(1.5),
    ));

    {
        var image = try zstbi.Image.loadFromFile("C:\\my_space\\code\\zig\\zig_ornament\\src\\glfw_example\\assets\\textures\\earthmap.jpg", 4);
        defer image.deinit();
        var texture = try ornament_ctx.createTexture(image.data, image.width, image.height, image.num_components, image.bytes_per_component, false, 1.0);
        _ = texture;

        try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
            zmath.f32x4(-4.0, 1.0, 0.0, 1.0),
            1.0,
            try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
            //try ornament_ctx.lambertian(.{ .texture = texture }),
        ));
    }

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(4.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_ctx.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));
}

pub fn init_spheres_and_meshes_spheres(ornament_ctx: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.1;
    const focus_dist = 10.0;
    ornament_ctx.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    const mesh_sphere = try ornament_ctx.createSphereMesh(
        zmath.f32x4(0.0, 1.0, 0.0, 1.0),
        1.0,
        try ornament_ctx.dielectric(1.5),
    );
    try ornament_ctx.scene.addMesh(mesh_sphere);

    try ornament_ctx.scene.addMeshInstance(try ornament_ctx.createMeshInstance(
        mesh_sphere,
        zmath.translationV(zmath.f32x4(-4.0, 1.0, 0.0, 0.0)),
        try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
    ));

    try ornament_ctx.scene.addMeshInstance(try ornament_ctx.createMeshInstance(
        mesh_sphere,
        zmath.translationV(zmath.f32x4(4.0, 1.0, 0.0, 0.0)),
        try ornament_ctx.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    ornament_ctx.lambertian(.{ .vec = randomColor() * randomColor() })
                else if (choose_mat < 0.95)
                    ornament_ctx.metal(.{ .vec = randomColorBetween(0.5, 1.0) }, 0.5 * rand.float(f32))
                else
                    ornament_ctx.dielectric(1.5);
                try ornament_ctx.scene.addMeshInstance(try ornament_ctx.createMeshInstance(
                    mesh_sphere,
                    zmath.mul(zmath.scaling(0.2, 0.2, 0.2), zmath.translationV(center)),
                    material,
                ));
            }
        }
    }
}

pub fn init_spheres_and_3_lucy(ornament_ctx: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.0;
    const focus_dist = 10.0;
    ornament_ctx.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try ornament_ctx.scene.addSphere(try ornament_ctx.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    const base_lucy_transform = zmath.mul(zmath.scalingV(zmath.f32x4s(2.0)), zmath.rotationY(std.math.pi / 2.0));
    var mesh_lucy = try loadMesh(
        "C:\\my_space\\code\\rust\\rs_ornament\\examples\\models\\lucy.obj",
        ornament_ctx,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(0.0, 1.0, 0.0, 1.0))),
        try ornament_ctx.dielectric(1.5),
    );
    try ornament_ctx.scene.addMesh(mesh_lucy);

    try ornament_ctx.scene.addMeshInstance(try ornament_ctx.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(-4.0, 1.0, 0.0, 0.0))),
        try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
    ));

    try ornament_ctx.scene.addMeshInstance(try ornament_ctx.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(4.0, 1.0, 0.0, 0.0))),
        try ornament_ctx.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var mesh_sphere: ?*ornament.Mesh = null;
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    ornament_ctx.lambertian(.{ .vec = randomColor() * randomColor() })
                else if (choose_mat < 0.95)
                    ornament_ctx.metal(.{ .vec = randomColorBetween(0.5, 1.0) }, 0.5 * rand.float(f32))
                else
                    ornament_ctx.dielectric(1.5);
                if (mesh_sphere) |m| {
                    try ornament_ctx.scene.addMeshInstance(try ornament_ctx.createMeshInstance(
                        m,
                        zmath.mul(zmath.scaling(0.2, 0.2, 0.2), zmath.translationV(center)),
                        material,
                    ));
                } else {
                    mesh_sphere = try ornament_ctx.createSphereMesh(center, 0.2, material);
                    try ornament_ctx.scene.addMesh(mesh_sphere.?);
                }
            }
        }
    }
}

pub fn quadCenterFromBook(q: zmath.Vec, u: zmath.Vec, v: zmath.Vec) zmath.Vec {
    return q + u * zmath.f32x4s(0.5) + v * zmath.f32x4s(0.5);
}

pub fn init_empty_cornell_box(ornament_ctx: *ornament.Context, aspect_ratio: f32) !void {
    const vfov = 40.0;
    const lookfrom = zmath.f32x4(278.0, 278.0, -800.0, 1.0);
    const lookat = zmath.f32x4(278.0, 278.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.0;
    const focus_dist = 10.0;
    ornament_ctx.scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    var red = try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.65, 0.05, 0.05, 0.0) });
    var white = try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.73, 0.73, 0.73, 0.0) });
    var green = try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.12, 0.45, 0.15, 0.0) });
    var light = try ornament_ctx.diffuseLight(.{ .vec = zmath.f32x4(15.0, 15.0, 15.0, 0.0) });

    const unit_x = zmath.f32x4(1.0, 0.0, 0.0, 0.0);
    const unit_y = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const unit_z = zmath.f32x4(0.0, 0.0, 1.0, 0.0);

    try ornament_ctx.scene.addMesh(try ornament_ctx.createPlaneMesh(
        quadCenterFromBook(
            zmath.f32x4(555.0, 0.0, 0.0, 1.0),
            zmath.f32x4(0.0, 555.0, 0.0, 0.0),
            zmath.f32x4(0.0, 0.0, 555.0, 0.0),
        ),
        555.0,
        555.0,
        unit_x,
        green,
    ));

    try ornament_ctx.scene.addMesh(try ornament_ctx.createPlaneMesh(
        quadCenterFromBook(
            zmath.f32x4(0.0, 0.0, 0.0, 1.0),
            zmath.f32x4(0.0, 555.0, 0.0, 0.0),
            zmath.f32x4(0.0, 0.0, 555.0, 0.0),
        ),
        555.0,
        555.0,
        zmath.f32x4s(-1.0) * unit_x,
        red,
    ));

    try ornament_ctx.scene.addMesh(try ornament_ctx.createPlaneMesh(
        quadCenterFromBook(
            zmath.f32x4(343.0, 554.0, 332.0, 1.0),
            zmath.f32x4(-130.0, 0.0, 0.0, 0.0),
            zmath.f32x4(0.0, 0.0, -105.0, 0.0),
        ),
        130.0,
        105.0,
        zmath.f32x4s(-1.0) * unit_y,
        light,
    ));

    try ornament_ctx.scene.addMesh(try ornament_ctx.createPlaneMesh(
        quadCenterFromBook(
            zmath.f32x4(0.0, 0.0, 0.0, 1.0),
            zmath.f32x4(555.0, 0.0, 0.0, 0.0),
            zmath.f32x4(0.0, 0.0, 555.0, 0.0),
        ),
        555.0,
        555.0,
        unit_y,
        white,
    ));

    try ornament_ctx.scene.addMesh(try ornament_ctx.createPlaneMesh(
        quadCenterFromBook(
            zmath.f32x4(555.0, 555.0, 555, 1.0),
            zmath.f32x4(-555.0, 0.0, 0.0, 0.0),
            zmath.f32x4(0.0, 0.0, -555, 0.0),
        ),
        555.0,
        555.0,
        zmath.f32x4s(-1.0) * unit_y,
        white,
    ));

    try ornament_ctx.scene.addMesh(try ornament_ctx.createPlaneMesh(
        quadCenterFromBook(
            zmath.f32x4(0.0, 0.0, 555.0, 1.0),
            zmath.f32x4(555.0, 0.0, 0.0, 0.0),
            zmath.f32x4(0.0, 555.0, 0.0, 0.0),
        ),
        555.0,
        555.0,
        unit_z,
        white,
    ));
}

pub fn init_cornell_box_with_lucy(ornament_ctx: *ornament.Context, aspect_ratio: f32) !void {
    try init_empty_cornell_box(ornament_ctx, aspect_ratio);
    var height: f32 = 400.0;
    var mesh = try loadMesh(
        "C:\\my_space\\code\\rust\\rs_ornament\\examples\\models\\lucy.obj",
        ornament_ctx,
        zmath.mul(
            zmath.scalingV(zmath.f32x4s(height)),
            zmath.mul(
                zmath.rotationY(std.math.pi * 1.5),
                zmath.translation(265.0 * 1.5, height / 2.0, 295.0),
            ),
        ),
        //try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 0.0)}),
        try ornament_ctx.metal(zmath.f32x4(0.7, 0.6, 0.5, 1.0), 0.0),
    );
    try ornament_ctx.scene.addMesh(mesh);

    height = 200.0;
    try ornament_ctx.scene.addMeshInstance(try ornament_ctx.createMeshInstance(
        mesh,
        zmath.mul(
            zmath.scalingV(zmath.f32x4s(height)),
            zmath.mul(
                zmath.rotationY(std.math.pi * 1.25),
                zmath.translation(130.0 * 1.5, height / 2.0, 65.0),
            ),
        ),
        //try ornament_ctx.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 0.0)}),
        try ornament_ctx.dielectric(1.5),
    ));
}

pub fn loadMesh(path: [:0]const u8, ornament_ctx: *ornament.Context, transform: zmath.Mat, material: *ornament.Material) !*ornament.Mesh {
    const scene = c.aiImportFile(
        path,
        c.aiProcess_Triangulate | c.aiProcess_JoinIdenticalVertices | c.aiProcess_SortByPType | c.aiProcess_GenSmoothNormals,
    );
    defer c.aiReleaseImport(scene);

    if (scene.*.mNumMeshes != 1) {
        @panic("the scene has 0 or more than 1 mesh");
    }
    const mesh: [*c]c.struct_aiMesh = scene.*.mMeshes[0];

    var vertices = try std.ArrayList(zmath.Vec).initCapacity(ornament_ctx.allocator, mesh.*.mNumVertices);
    defer vertices.deinit();
    var normals = try std.ArrayList(zmath.Vec).initCapacity(ornament_ctx.allocator, mesh.*.mNumVertices);
    defer normals.deinit();
    var indices = try std.ArrayList(u32).initCapacity(ornament_ctx.allocator, mesh.*.mNumFaces * 3);
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

    return ornament_ctx.createMesh(vertices.items, indices.items, normals.items, indices.items, transform, material);
}
