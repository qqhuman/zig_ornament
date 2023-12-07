struct Camera {
    origin: vec3<f32>,
    lens_radius: f32,
    lower_left_corner: vec3<f32>,
    horizontal: vec3<f32>,
    vertical: vec3<f32>,
    u: vec3<f32>,
    v: vec3<f32>,
    w: vec3<f32>
}

fn camera_get_ray(s: f32, t: f32) -> Ray {
    let rd = constant_params.camera.lens_radius * random_in_unit_disk();
    let offset = constant_params.camera.u * rd.x + constant_params.camera.v * rd.y;
    return Ray(
        constant_params.camera.origin + offset,
        constant_params.camera.lower_left_corner
            + s * constant_params.camera.horizontal
            + t * constant_params.camera.vertical
            - constant_params.camera.origin
            - offset
    );
}