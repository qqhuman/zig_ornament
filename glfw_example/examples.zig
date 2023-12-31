const std = @import("std");
const zmath = @import("zmath");
const zstbi = @import("zstbi");
const ornament = @import("ornament");
const build_options = @import("build_options");
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

pub fn init_spheres(scene: *ornament.Scene, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.1;
    const focus_dist = 10.0;
    scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try scene.attachSphere(try scene.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try scene.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    scene.lambertian(.{ .vec = randomColor() * randomColor() })
                else if (choose_mat < 0.95)
                    scene.metal(.{ .vec = randomColorBetween(0.5, 1.0) }, 0.5 * rand.float(f32))
                else
                    scene.dielectric(1.5);
                try scene.attachSphere(try scene.createSphere(center, 0.2, material));
            }
        }
    }

    try scene.attachSphere(try scene.createSphere(
        zmath.f32x4(0.0, 1.0, 0.0, 1.0),
        1.0,
        try scene.dielectric(1.5),
    ));

    try scene.attachSphere(try scene.createSphere(
        zmath.f32x4(-4.0, 1.0, 0.0, 1.0),
        1.0,
        try scene.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
    ));

    try scene.attachSphere(try scene.createSphere(
        zmath.f32x4(4.0, 1.0, 0.0, 1.0),
        1.0,
        try scene.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));
}

pub fn init_lucy_spheres_with_textures(scene: *ornament.Scene, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.0;
    const focus_dist = 10.0;
    scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try scene.attachSphere(try scene.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try scene.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    {
        var planet = try loadTexture(scene.allocator, "2k_mars.jpg", 4);
        defer planet.deinit();
        var planet_texture = try scene.createTexture(
            planet.data,
            planet.width,
            planet.height,
            planet.num_components,
            planet.bytes_per_component,
            false,
            1.0,
        );
        try scene.attachSphere(try scene.createSphere(
            zmath.f32x4(-4.0, 1.0, 0.0, 1.0),
            1.0,
            //try scene.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
            try scene.lambertian(.{ .texture = planet_texture }),
        ));
    }
    {
        var planet = try loadTexture(scene.allocator, "earthmap.jpg", 4);
        defer planet.deinit();
        var planet_texture = try scene.createTexture(
            planet.data,
            planet.width,
            planet.height,
            planet.num_components,
            planet.bytes_per_component,
            false,
            1.0,
        );

        try scene.attachMesh(try scene.createSphereMesh(
            zmath.f32x4(0.0, 1.0, 0.0, 1.0),
            1.0,
            try scene.lambertian(.{ .texture = planet_texture }),
        ));
    }

    {
        var planet = try loadTexture(scene.allocator, "2k_neptune.jpg", 4);
        defer planet.deinit();
        var planet_texture = try scene.createTexture(
            planet.data,
            planet.width,
            planet.height,
            planet.num_components,
            planet.bytes_per_component,
            false,
            1.0,
        );

        try scene.attachSphere(try scene.createSphere(
            zmath.f32x4(4.0, 1.0, 0.0, 1.0),
            1.0,
            try scene.lambertian(.{ .texture = planet_texture }),
        ));
    }

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    scene.lambertian(.{ .vec = randomColor() * randomColor() })
                else if (choose_mat < 0.95)
                    scene.metal(.{ .vec = randomColorBetween(0.5, 1.0) }, 0.5 * rand.float(f32))
                else
                    scene.dielectric(1.5);
                try scene.attachSphere(try scene.createSphere(center, 0.2, material));
            }
        }
    }

    const base_lucy_transform = zmath.mul(zmath.scalingV(zmath.f32x4s(2.0)), zmath.rotationY(std.math.pi / 2.0));
    var mesh_lucy = try loadMesh(
        scene.allocator,
        "lucy.obj",
        scene,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(0.0, 1.0, 2.0, 1.0))),
        try scene.dielectric(1.5),
    );
    try scene.attachMesh(mesh_lucy);

    try scene.attachMeshInstance(try scene.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(-4.0, 1.0, 2.0, 0.0))),
        try scene.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
    ));

    try scene.attachMeshInstance(try scene.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(4.0, 1.0, 2.0, 0.0))),
        try scene.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));
}

pub fn init_spheres_and_meshes_spheres(scene: *ornament.Scene, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.1;
    const focus_dist = 10.0;
    scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try scene.attachSphere(try scene.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try scene.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    const mesh_sphere = try scene.createSphereMesh(
        zmath.f32x4(0.0, 1.0, 0.0, 1.0),
        1.0,
        try scene.dielectric(1.5),
    );
    try scene.attachMesh(mesh_sphere);

    try scene.attachMeshInstance(try scene.createMeshInstance(
        mesh_sphere,
        zmath.translationV(zmath.f32x4(-4.0, 1.0, 0.0, 0.0)),
        try scene.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
    ));

    try scene.attachMeshInstance(try scene.createMeshInstance(
        mesh_sphere,
        zmath.translationV(zmath.f32x4(4.0, 1.0, 0.0, 0.0)),
        try scene.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    scene.lambertian(.{ .vec = randomColor() * randomColor() })
                else if (choose_mat < 0.95)
                    scene.metal(.{ .vec = randomColorBetween(0.5, 1.0) }, 0.5 * rand.float(f32))
                else
                    scene.dielectric(1.5);
                try scene.attachMeshInstance(try scene.createMeshInstance(
                    mesh_sphere,
                    zmath.mul(zmath.scaling(0.2, 0.2, 0.2), zmath.translationV(center)),
                    material,
                ));
            }
        }
    }
}

pub fn init_spheres_and_3_lucy(scene: *ornament.Scene, aspect_ratio: f32) !void {
    const vfov = 20.0;
    const lookfrom = zmath.f32x4(13.0, 2.0, 3.0, 1.0);
    const lookat = zmath.f32x4(0.0, 0.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.0;
    const focus_dist = 10.0;
    scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    try scene.attachSphere(try scene.createSphere(
        zmath.f32x4(0.0, -1000.0, 0.0, 1.0),
        1000.0,
        try scene.lambertian(.{ .vec = zmath.f32x4(0.5, 0.5, 0.5, 1.0) }),
    ));

    const base_lucy_transform = zmath.mul(zmath.scalingV(zmath.f32x4s(2.0)), zmath.rotationY(std.math.pi / 2.0));
    var mesh_lucy = try loadMesh(
        scene.allocator,
        "lucy.obj",
        scene,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(0.0, 1.0, 0.0, 1.0))),
        try scene.dielectric(1.5),
    );
    try scene.attachMesh(mesh_lucy);

    try scene.attachMeshInstance(try scene.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(-4.0, 1.0, 0.0, 0.0))),
        try scene.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 1.0) }),
    ));

    try scene.attachMeshInstance(try scene.createMeshInstance(
        mesh_lucy,
        zmath.mul(base_lucy_transform, zmath.translationV(zmath.f32x4(4.0, 1.0, 0.0, 0.0))),
        try scene.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    ));

    const range = [_]f32{ -11, -10, -9, -8, -7, -6, -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9 };
    var mesh_sphere: ?*ornament.Mesh = null;
    for (range) |a| {
        for (range) |b| {
            const choose_mat = rand.float(f32);
            const center = zmath.f32x4(a + 0.9 * rand.float(f32), 0.2, b + 0.9 * rand.float(f32), 1.0);

            if (zmath.length3(center - zmath.f32x4(4.0, 0.2, 0.0, 0.0))[0] > 0.9) {
                const material = try if (choose_mat < 0.8)
                    scene.lambertian(.{ .vec = randomColor() * randomColor() })
                else if (choose_mat < 0.95)
                    scene.metal(.{ .vec = randomColorBetween(0.5, 1.0) }, 0.5 * rand.float(f32))
                else
                    scene.dielectric(1.5);
                if (mesh_sphere) |m| {
                    try scene.attachMeshInstance(try scene.createMeshInstance(
                        m,
                        zmath.mul(zmath.scaling(0.2, 0.2, 0.2), zmath.translationV(center)),
                        material,
                    ));
                } else {
                    mesh_sphere = try scene.createSphereMesh(center, 0.2, material);
                    try scene.attachMesh(mesh_sphere.?);
                }
            }
        }
    }
}

pub fn quadCenterFromBook(q: zmath.Vec, u: zmath.Vec, v: zmath.Vec) zmath.Vec {
    return q + u * zmath.f32x4s(0.5) + v * zmath.f32x4s(0.5);
}

pub fn init_empty_cornell_box(scene: *ornament.Scene, aspect_ratio: f32) !void {
    const vfov = 40.0;
    const lookfrom = zmath.f32x4(278.0, 278.0, -800.0, 1.0);
    const lookat = zmath.f32x4(278.0, 278.0, 0.0, 1.0);
    const vup = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const aperture = 0.0;
    const focus_dist = 10.0;
    scene.camera = ornament.Camera.init(
        lookfrom,
        lookat,
        vup,
        aspect_ratio,
        vfov,
        aperture,
        focus_dist,
    );

    var red = try scene.lambertian(.{ .vec = zmath.f32x4(0.65, 0.05, 0.05, 0.0) });
    var white = try scene.lambertian(.{ .vec = zmath.f32x4(0.73, 0.73, 0.73, 0.0) });
    var green = try scene.lambertian(.{ .vec = zmath.f32x4(0.12, 0.45, 0.15, 0.0) });
    var light = try scene.diffuseLight(.{ .vec = zmath.f32x4(15.0, 15.0, 15.0, 0.0) });

    const unit_x = zmath.f32x4(1.0, 0.0, 0.0, 0.0);
    const unit_y = zmath.f32x4(0.0, 1.0, 0.0, 0.0);
    const unit_z = zmath.f32x4(0.0, 0.0, 1.0, 0.0);

    try scene.attachMesh(try scene.createPlaneMesh(
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

    try scene.attachMesh(try scene.createPlaneMesh(
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

    try scene.attachMesh(try scene.createPlaneMesh(
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

    try scene.attachMesh(try scene.createPlaneMesh(
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

    try scene.attachMesh(try scene.createPlaneMesh(
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

    try scene.attachMesh(try scene.createPlaneMesh(
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

pub fn init_cornell_box_with_lucy(scene: *ornament.Scene, aspect_ratio: f32) !void {
    try init_empty_cornell_box(scene, aspect_ratio);
    var height: f32 = 400.0;
    var mesh = try loadMesh(
        scene.allocator,
        "lucy.obj",
        scene,
        zmath.mul(
            zmath.scalingV(zmath.f32x4s(height)),
            zmath.mul(
                zmath.rotationY(std.math.pi * 1.5),
                zmath.translation(265.0 * 1.5, height / 2.0, 295.0),
            ),
        ),
        //try scene.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 0.0)}),
        try scene.metal(.{ .vec = zmath.f32x4(0.7, 0.6, 0.5, 1.0) }, 0.0),
    );
    try scene.attachMesh(mesh);

    height = 200.0;
    try scene.attachMeshInstance(try scene.createMeshInstance(
        mesh,
        zmath.mul(
            zmath.scalingV(zmath.f32x4s(height)),
            zmath.mul(
                zmath.rotationY(std.math.pi * 1.25),
                zmath.translation(130.0 * 1.5, height / 2.0, 65.0),
            ),
        ),
        //try scene.lambertian(.{ .vec = zmath.f32x4(0.4, 0.2, 0.1, 0.0)}),
        try scene.dielectric(1.5),
    ));
}

fn loadTexture(allocator: std.mem.Allocator, texturename: []const u8, forced_num_components: u32) !zstbi.Image {
    const exe_dir_path = std.fs.selfExeDirPathAlloc(allocator) catch unreachable;
    defer allocator.free(exe_dir_path);
    const texturepath = std.fs.path.joinZ(allocator, &.{
        exe_dir_path,
        build_options.textures_dir,
        texturename,
    }) catch unreachable;
    defer allocator.free(texturepath);

    return zstbi.Image.loadFromFile(texturepath, forced_num_components);
}

fn loadMesh(allocator: std.mem.Allocator, modelname: [:0]const u8, scene: *ornament.Scene, transform: zmath.Mat, material: *ornament.Material) !*ornament.Mesh {
    const exe_dir_path = std.fs.selfExeDirPathAlloc(allocator) catch unreachable;
    defer allocator.free(exe_dir_path);
    const modelpath = std.fs.path.joinZ(allocator, &.{
        exe_dir_path,
        build_options.models_dir,
        modelname,
    }) catch unreachable;
    defer allocator.free(modelpath);

    const ai_scene = c.aiImportFile(
        modelpath,
        c.aiProcess_Triangulate | c.aiProcess_JoinIdenticalVertices | c.aiProcess_SortByPType | c.aiProcess_GenSmoothNormals,
    );
    defer c.aiReleaseImport(ai_scene);

    if (ai_scene.*.mNumMeshes != 1) {
        @panic("the scene has 0 or more than 1 mesh");
    }
    const mesh: [*c]c.struct_aiMesh = ai_scene.*.mMeshes[0];

    var vertices = try std.ArrayList(zmath.Vec).initCapacity(scene.allocator, mesh.*.mNumVertices);
    defer vertices.deinit();
    var normals = try std.ArrayList(zmath.Vec).initCapacity(scene.allocator, mesh.*.mNumVertices);
    defer normals.deinit();
    var uvs = try std.ArrayList([2]f32).initCapacity(scene.allocator, mesh.*.mNumVertices);
    defer uvs.deinit();
    var indices = try std.ArrayList(u32).initCapacity(scene.allocator, mesh.*.mNumFaces * 3);
    defer indices.deinit();

    var min = zmath.f32x4(std.math.inf(f32), std.math.inf(f32), std.math.inf(f32), 1.0);
    var max = zmath.f32x4(-std.math.inf(f32), -std.math.inf(f32), -std.math.inf(f32), 1.0);
    var i: u32 = 0;
    while (i < mesh.*.mNumVertices) : (i += 1) {
        const vertex = mesh.*.mVertices[i];
        const normal = mesh.*.mNormals[i];
        const texture_coords = mesh.*.mTextureCoords[0];

        try vertices.append(zmath.f32x4(vertex.x, vertex.y, vertex.z, 1.0));
        try normals.append(zmath.normalize3(zmath.f32x4(normal.x, normal.y, normal.z, 0.0)));
        if (texture_coords != null) {
            const uv = texture_coords[i];
            try uvs.append(.{ uv.x, uv.y });
        }
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

    return scene.createMesh(
        vertices.items,
        indices.items,
        normals.items,
        indices.items,
        uvs.items,
        indices.items,
        transform,
        material,
    );
}
