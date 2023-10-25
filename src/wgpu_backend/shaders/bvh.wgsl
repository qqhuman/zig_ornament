struct BvhNode {
    left_aabb_min_or_v0: vec3<f32>,
    left_or_custom_id: u32, // internal left node id / mesh id / triangle id, sphere id
    left_aabb_max_or_v1: vec3<f32>,
    right_or_material_index: u32,
    right_aabb_min_or_v2: vec3<f32>,
    node_type: u32, // 0 internal node, 1 mesh, 2 triangle, 3 sphere
    right_aabb_max_or_v3: vec3<f32>,
    // inverse transform: transform_id * 2
    // model transform:  transform_id * 2 + 1
    transform_id: u32, 
}

fn bvh_hit(not_transformed_ray: Ray, 
        closest_t: ptr<function, f32>,
        closest_material_index: ptr<function, u32>,
        closest_node_type: ptr<function, u32>,
        closest_inverted_transform_id: ptr<function, u32>,
        closest_tri_id: ptr<function, u32>,
        closest_uv: ptr<function, vec2<f32>>
    ) -> bool {
    let t_min = constant_state.ray_cast_epsilon;
    var t_max = 3.40282e+38;
    
    let num_nodes = arrayLength(&bvh_tlas_nodes);
    var stack_top: i32 = 0;
    // here push top of tlas tree to the stack
    var addr = num_nodes - 1u;
    node_stack[stack_top] = addr;
    var traverse_tlas = true;

    var hit_anything = false;

    var ray = not_transformed_ray;
    var invdir = safe_invdir(ray.direction);
    var oxinvdir = -ray.origin * invdir;

    let not_transformed_invdir = invdir;
    let not_transformed_oxinvdir = oxinvdir;
    var material_index: u32;
    var inverted_transform_id: u32;
    while stack_top >= 0 {
        var node: BvhNode;
        if traverse_tlas {
            node = bvh_tlas_nodes[addr];
        } else {
            node = bvh_blas_nodes[addr];
        }
        switch node.node_type {
            // internal node
            case 0u: {
                let left = aabb_hit(node.left_aabb_min_or_v0, node.left_aabb_max_or_v1, invdir, oxinvdir, t_min, t_max);
                let right = aabb_hit(node.right_aabb_min_or_v2, node.right_aabb_max_or_v3, invdir, oxinvdir, t_min, t_max);
                
                if left.x <= left.y {
                    stack_top++;
                    node_stack[stack_top] = node.left_or_custom_id;
                }

                if right.x <= right.y {
                    stack_top++;
                    node_stack[stack_top] = node.right_or_material_index;
                }
            }
            // sphere
            case 1u: {
                inverted_transform_id = node.transform_id * 2u;
                let transformed_ray = transform_ray(inverted_transform_id, ray);
                let t = sphere_hit(transformed_ray, t_min, t_max);
                if t < t_max {
                    hit_anything = true;
                    t_max = t;
                    (*closest_t) = t;
                    (*closest_material_index) = node.right_or_material_index;
                    (*closest_node_type) = 1u;
                    (*closest_inverted_transform_id) = inverted_transform_id;
                }
            }
            // mesh
            case 2u: {
                // push signal to restore transformation after finshing mesh bvh
                traverse_tlas = false;
                stack_top++;
                node_stack[stack_top] = finished_traverse_blas;

                // push mesh bvh
                stack_top++;
                node_stack[stack_top] = node.left_or_custom_id;

                inverted_transform_id = node.transform_id * 2u;
                material_index = node.right_or_material_index;
                ray = transform_ray(inverted_transform_id, ray);
                invdir = safe_invdir(ray.direction);
                oxinvdir = -ray.origin * invdir;
            }
            // triangle
            case 3u: {
                var uv: vec2<f32>;
                let t = triangle_hit(
                    ray, 
                    node.left_aabb_min_or_v0,
                    node.left_aabb_max_or_v1,
                    node.right_aabb_min_or_v2,
                    t_min, 
                    t_max,
                    &uv
                );

                if t < t_max {
                    hit_anything = true;
                    t_max = t;
                    (*closest_t) = t;
                    (*closest_material_index) = material_index;
                    (*closest_node_type) = 2u;
                    (*closest_inverted_transform_id) = inverted_transform_id;
                    (*closest_tri_id) = node.left_or_custom_id * 3u;
                    (*closest_uv) = uv;
                }
            }
            default: { break; }
        }

        addr = node_stack[stack_top];
        stack_top--;

        if addr == finished_traverse_blas {
            traverse_tlas = true;
            ray = not_transformed_ray;
            invdir = not_transformed_invdir;
            oxinvdir = not_transformed_oxinvdir;
            addr = node_stack[stack_top];
            stack_top--;
        }
    }

    return hit_anything;
}

fn mycopysign(a: f32, b: f32) -> f32 {
    if b < 0.0 {
        return -a;
    } else {
        return a;
    }
}

fn safe_invdir(d: vec3<f32>) -> vec3<f32> {
    let dirx = d.x;
    let diry = d.y;
    let dirz = d.z;
    let ooeps = 1e-5;
    var x: f32;
    if abs(dirx) > ooeps { 
        x = dirx; 
    } else { 
        x = mycopysign(ooeps, dirx); 
    };

    var y: f32;
    if abs(diry) > ooeps {
        y = diry;
    } else {
        y = mycopysign(ooeps, diry);
    }

    var z: f32;
    if abs(dirz) > ooeps {
        z = dirz;
    } else {
        z = mycopysign(ooeps, dirz);
    }

    return vec3<f32>(1.0 / x, 1.0 / y, 1.0 / z);
}

fn min3(val: vec3<f32>) -> f32 {
    return min(min(val.x, val.y), val.z);
}

fn max3(val: vec3<f32>) -> f32 {
    return max(max(val.x, val.y), val.z);
}

fn aabb_hit(mmin: vec3<f32>, mmax: vec3<f32>, invdir: vec3<f32>, oxinvdir: vec3<f32>, t_min: f32, t_max: f32) -> vec2<f32> {
    let f = mmax * invdir + oxinvdir;
    let n = mmin * invdir + oxinvdir;
    let tmax = max(f, n);
    let tmin = min(f, n);
    let max_t = min(min3(tmax), t_max);
    let min_t = max(max3(tmin), t_min);
    return vec2<f32>(min_t, max_t);
}

const epsilon: f32 = 1e-8;
fn triangle_hit(r: Ray, v1: vec3<f32>, v2: vec3<f32>, v3: vec3<f32>, t_min: f32, t_max: f32, uv: ptr<function, vec2<f32>>) -> f32 {
    let e1 = v2 - v1;
    let e2 = v3 - v1;

    let s1 = cross(r.direction, e2);
    let determinant = dot(s1, e1);
    let invd = 1.0 / determinant;

    let d = r.origin - v1;
    let u = dot(d, s1) * invd;

    // Barycentric coordinate U is outside range
    if u < 0.0 || u > 1.0 {
        return t_max;
    }

    let s2 = cross(d, e1);
    let v = dot(r.direction, s2) * invd;

    // Barycentric coordinate V is outside range
    if v < 0.0 || u + v > 1.0 {
        return t_max;
    }

    // t
    let t = dot(e2, s2) * invd;
    if t < t_min || t > t_max {
        return t_max;
    } else {
        *uv = vec2<f32>(u, v);
        return t;
    }
}