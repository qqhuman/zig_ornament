struct Material {
    albedo_vec: vec3<f32>,
    albedo_texture_index: u32,
    fuzz: f32,
    ior: f32,
    material_type: u32
}

fn lambertian_scatter(material: Material, r_in: Ray, hit: HitRecord, attenuation: ptr<function, vec3<f32>>, scattered: ptr<function, Ray>) -> bool {
    var scatter_direction = hit.normal + random_unit_vector();

    // Catch degenerate scatter direction
    if near_zero(scatter_direction) {
        scatter_direction = hit.normal;
    }

    (*scattered) = Ray(hit.p, scatter_direction);
    (*attenuation) = material_get_color(material.albedo_vec, hit.uv, material.albedo_texture_index);
    return true;
}

fn metal_scatter(material: Material, r_in: Ray, hit: HitRecord, attenuation: ptr<function, vec3<f32>>, scattered: ptr<function, Ray>) -> bool {
    let scattered_direction = reflect(normalize(r_in.direction), hit.normal) + material.fuzz * random_in_unit_sphere();
    (*scattered) = Ray(hit.p, scattered_direction);
    (*attenuation) = material_get_color(material.albedo_vec, hit.uv, material.albedo_texture_index);
    return (dot(scattered_direction, hit.normal) > 0.0);
}

fn reflectance(cosine: f32, ref_idx: f32) -> f32 {
    // Use Schlick's approximation for reflectance.
    var r0 = (1.0 - ref_idx) / (1.0 + ref_idx);
    r0 = r0 * r0;
    return r0 + (1.0 - r0) * pow((1.0 - cosine), 5.0);
}

fn dielectric_scatter(material: Material, r_in: Ray, hit: HitRecord, attenuation: ptr<function, vec3<f32>>, scattered: ptr<function, Ray>) -> bool {
    (*attenuation) = vec3<f32>(1.0);
    var refraction_ratio = material.ior;
    if hit.front_face {
        refraction_ratio = 1.0 / material.ior;
    }

    let unit_direction = normalize(r_in.direction);
    let cos_theta = min(dot(-unit_direction, hit.normal), 1.0);
    let sin_theta = sqrt(1.0 - cos_theta * cos_theta);

    let cannot_refract = refraction_ratio * sin_theta > 1.0;
    var direction: vec3<f32>;

    if cannot_refract || reflectance(cos_theta, refraction_ratio) > random_f32() {
        direction = reflect(unit_direction, hit.normal);
    }
    else {
        direction = refract(unit_direction, hit.normal, refraction_ratio);
    }

    (*scattered) = Ray(hit.p, direction);
    return true;
}

fn material_scatter(r_in: Ray, hit: HitRecord, attenuation: ptr<function, vec3<f32>>, scattered: ptr<function, Ray>) -> bool {
    let material = materials[hit.material_index];
    switch material.material_type {
        case 0u {
            return lambertian_scatter(material, r_in, hit, attenuation, scattered);
        }
        case 1u {
            return metal_scatter(material, r_in, hit, attenuation, scattered);
        }
        case 2u {
            return dielectric_scatter(material, r_in, hit, attenuation, scattered);
        }
        default {
            return false;
        }
    }
}

fn material_emit(hit: HitRecord) -> vec3<f32> {
    let material = materials[hit.material_index];
    switch material.material_type {
        case 3u {
            return material_get_color(material.albedo_vec, hit.uv, material.albedo_texture_index);
        }
        default {
            return vec3<f32>(0.0);
        }
    }
}

fn material_get_color(color: vec3<f32>, uv: vec2<f32>, texture_id: u32) -> vec3<f32> {
    if texture_id < constant_params.textures_count {
        let t = textures[texture_id];
        let s = samplers[texture_id];
        return textureSampleLevel(t, s, uv, 0.0).xyz;
    } else {
        return color;
    }
}