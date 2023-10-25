@group(0) @binding(0) var<storage, read_write> framebuffer : array<vec4<f32>>;
@group(0) @binding(1) var<storage, read_write> accumulation_buffer: array<vec4<f32>>;
@group(0) @binding(2) var<storage, read_write> rng_state_buffer: array<u32>;

@group(1) @binding(0) var<uniform> dynamic_state: DynamicState;
@group(1) @binding(1) var<uniform> constant_state: ConstantState;
@group(1) @binding(2) var<uniform> camera: Camera;

@group(2) @binding(0) var<storage, read> materials: array<Material>;
@group(2) @binding(1) var<storage, read> normals: array<vec3<f32>>;
@group(2) @binding(2) var<storage, read> normal_indices: array<u32>;
@group(2) @binding(3) var<storage, read> uvs: array<vec2<f32>>;
@group(2) @binding(4) var<storage, read> uv_indices: array<u32>;
@group(2) @binding(5) var<storage, read> transforms: array<mat4x4<f32>>;
@group(2) @binding(6) var<storage, read> bvh_tlas_nodes: array<BvhNode>;
@group(2) @binding(7) var<storage, read> bvh_blas_nodes: array<BvhNode>;

@group(3) @binding(0) var textures: binding_array<texture_2d<f32>>;
@group(3) @binding(1) var samplers: binding_array<sampler>;

const finished_traverse_blas: u32 = 0xffffffffu;
const max_bvh_depth = 64;
var<private> node_stack: array<u32, max_bvh_depth>;

@compute @workgroup_size(256, 1, 1)
fn main_render(@builtin(global_invocation_id) inv_id: vec3<u32>) {
    let inv_id_x = inv_id.x;
    if inv_id_x >= arrayLength(&accumulation_buffer) {
        return;
    }

    init_rng_state(inv_id_x);
    let xy = vec2<u32>(inv_id_x % constant_state.width, inv_id_x / constant_state.width);
    accumulation_buffer[inv_id_x] = render(inv_id_x, xy);
    save_rng_state(inv_id_x);
}

@compute @workgroup_size(256, 1, 1)
fn main_post_processing(@builtin(global_invocation_id) inv_id: vec3<u32>) {
    let inv_id_x = inv_id.x;
    if inv_id_x >= arrayLength(&accumulation_buffer) {
        return;
    }

    init_rng_state(inv_id_x);
    let xy = vec2<u32>(inv_id_x % constant_state.width, inv_id_x / constant_state.width);
    post_processing(inv_id_x, xy, accumulation_buffer[inv_id_x]);
    save_rng_state(inv_id_x);
}

@compute @workgroup_size(256, 1, 1)
fn main(@builtin(global_invocation_id) inv_id: vec3<u32>) {
    let inv_id_x = inv_id.x;
    if inv_id_x >= arrayLength(&accumulation_buffer) {
        return;
    }

    init_rng_state(inv_id_x);
    let xy = vec2<u32>(inv_id_x % constant_state.width, inv_id_x / constant_state.width);
    let accumulated_rgba = render(inv_id_x, xy);
    accumulation_buffer[inv_id_x] = accumulated_rgba;
    post_processing(inv_id_x, xy, accumulated_rgba);
    save_rng_state(inv_id_x);
}

fn render(inv_id_x: u32, xy: vec2<u32>) -> vec4<f32> {
    let u = (f32(xy.x) + random_f32()) / f32(constant_state.width - 1u);
    let v = (f32(xy.y) + random_f32()) / f32(constant_state.height - 1u);
    // mock tracing
    // var rgb = vec3<f32>(u, v, 0.0);
    // var accumulated_rgba = vec4<f32>(rgb, 1.0);
    let r = camera_get_ray(u, v);
    var rgb = ray_color(r);
    var accumulated_rgba = vec4<f32>(rgb, 1.0);
    
    if dynamic_state.current_iteration > 1.0 {
        accumulated_rgba = accumulation_buffer[inv_id_x] + accumulated_rgba;
    }

    return accumulated_rgba;
}

fn post_processing(inv_id_x: u32, xy: vec2<u32>, accumulated_rgba: vec4<f32>) {
    var rgba = accumulated_rgba / dynamic_state.current_iteration;
    rgba = clamp(rgba, vec4<f32>(0.0), vec4<f32>(1.0));
    rgba.x = pow(rgba.x, constant_state.inverted_gamma);
    rgba.y = pow(rgba.y, constant_state.inverted_gamma);
    rgba.z = pow(rgba.z, constant_state.inverted_gamma);
    if constant_state.flip_y < 1u {
        framebuffer[inv_id_x] = rgba;
    } else {
        let y_flipped = constant_state.height - xy.y - 1u;
        framebuffer[constant_state.width * y_flipped + xy.x] = rgba;
    }
}

fn ray_color(first_ray: Ray) -> vec3<f32> {
    var ray = first_ray;
    var final_color = vec3<f32>(1.0);

    for (var i = 0u; i < constant_state.depth; i = i + 1u) {
        var t: f32;
        var material_index: u32;
        var node_type: u32;
        var inverted_transform_id: u32;
        var tri_id: u32;
        var uv: vec2<f32>;
        if !bvh_hit(ray, &t, &material_index, &node_type, &inverted_transform_id, &tri_id, &uv) {
            // var unit_direction = normalize(ray.direction);
            // var tt = 0.5 * (unit_direction.y + 1.0);
            // final_color *= (1.0 - tt) * vec3<f32>(1.0) + tt * vec3<f32>(0.5, 0.7, 1.0);
            final_color = vec3<f32>(0.0);
            break;
        } 

        let transform_id = inverted_transform_id + 1u;
        var hit: HitRecord;
        hit.t = t;
        hit.p = ray_at(ray, t);
        hit.material_index = material_index;
        switch node_type {
            // sphere
            case 1u: {
                // outward_normal = hit - center
                let center = transform_point(transform_id, vec3<f32>(0.0));
                let outward_normal = normalize(hit.p - center);
                let theta = acos(-outward_normal.y);
                let phi = atan2(-outward_normal.z, outward_normal.x) + pi;
                hit.uv = vec2<f32>(phi / (2.0 * pi), theta / pi);
                hit_record_set_face_normal(&hit, ray, outward_normal);
            }
            // mesh
            case 2u: {
                let n0 = normals[normal_indices[tri_id]];
                let n1 = normals[normal_indices[tri_id + 1u]];
                let n2 = normals[normal_indices[tri_id + 2u]];

                let uv0 = uvs[uv_indices[tri_id]];
                let uv1 = uvs[uv_indices[tri_id + 1u]];
                let uv2 = uvs[uv_indices[tri_id + 2u]];

                let w = 1.0 - uv.x - uv.y;
                let normal = w * n0 + uv.x * n1 + uv.y * n2;
                hit.uv = w * uv0 + uv.x * uv1 + uv.y * uv2;
                let outward_normal = normalize(transform_normal(inverted_transform_id, normal));
                hit_record_set_face_normal(&hit, ray, outward_normal);
            }
            default: { break; }
        }

        var attenuation: vec3<f32>;
        var scattered: Ray;
        if material_scatter(ray, hit, &attenuation, &scattered) {
            ray = scattered;
            final_color *= attenuation;
        } else {
            final_color *= material_emit(hit);
            break;
        }
    }

    return final_color;
}