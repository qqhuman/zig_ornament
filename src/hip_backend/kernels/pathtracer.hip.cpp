#include <hip/hip_runtime.h>
#include <hip/hip_math_constants.h>
#include "common.hip.h"
#include "kernal_params.hip.h"
#include "constants.hip.h"
#include "hitrecord.hip.h"
#include "bvh.hip.h"
#include "transform.hip.h"
#include "vec_math.hip.h"

HOST_DEVICE float4 path_tracing(KernalLocalState *kls);
HOST_DEVICE float4 post_processing(uint32_t* fb_index, KernalLocalState* kls, float4 accumulated_rgba);


extern "C" __global__ void path_tracing_and_post_processing_kernal(KernalGlobals kg) {
    uint32_t global_id = blockDim.x * blockIdx.x + threadIdx.x;
    if (global_id >= kg.pixel_count) {
        return;
    }
    KernalLocalState kls(kg, make_uint2(constant_params.width, constant_params.height), global_id);

    float4 accumulated_rgba = path_tracing(&kls);
    kls.kg.accumulation_buffer[kls.global_invocation_id] = accumulated_rgba;
    uint32_t fb_index = kls.global_invocation_id;
    kls.kg.framebuffer[fb_index] = post_processing(&fb_index, &kls, accumulated_rgba);

    kls.save_rng_seed();
}

extern "C" __global__ void path_tracing_kernal(KernalGlobals kg) {
    uint32_t global_id = blockDim.x * blockIdx.x + threadIdx.x;
    if (global_id >= kg.pixel_count) {
        return;
    }

    KernalLocalState kls(kg, make_uint2(constant_params.width, constant_params.height), global_id);
    
    float4 accumulated_rgba = path_tracing(&kls);
    kls.kg.accumulation_buffer[kls.global_invocation_id] = accumulated_rgba;

    kls.save_rng_seed();
}

extern "C" __global__ void post_processing_kernal(KernalGlobals kg) {
    uint32_t global_id = blockDim.x * blockIdx.x + threadIdx.x;
    if (global_id >= kg.pixel_count) {
        return;
    }

    KernalLocalState kls(kg, make_uint2(constant_params.width, constant_params.height), global_id);

    uint32_t fb_index = kls.global_invocation_id;
    kls.kg.framebuffer[fb_index] = post_processing(&fb_index, &kls, kls.kg.accumulation_buffer[kls.global_invocation_id]);

    kls.save_rng_seed();
}

HOST_DEVICE float4 post_processing(uint32_t* fb_index, KernalLocalState* kls, float4 accumulated_rgba) {
    float4 rgba = clamp(accumulated_rgba / constant_params.current_iteration, 0.0f, 1.0f);
    rgba.x = pow(rgba.x, constant_params.inverted_gamma);
    rgba.y = pow(rgba.y, constant_params.inverted_gamma);
    rgba.z = pow(rgba.z, constant_params.inverted_gamma);

    if (constant_params.flip_y != 0) {
        uint32_t y_flipped = constant_params.height - kls->xy.y - 1;
        *fb_index = constant_params.width * y_flipped + kls->xy.x;
    }

    return rgba;
}

HOST_DEVICE float4 path_tracing(KernalLocalState *kls) {
    float u = ((float)kls->xy.x + kls->rnd.gen_float()) / (constant_params.width - 1);
    float v = ((float)kls->xy.y + kls->rnd.gen_float()) / (constant_params.height - 1);

    Ray ray = constant_params.camera.get_ray(&kls->rnd, u, v);
    float3 final_color = make_float3(1.0f);

    for (int i = 0; i < constant_params.depth; i += 1)
    {
        float t;
        uint32_t material_index;
        BvhNodeType bvh_node_type;
        uint32_t inverted_transform_id;
        uint32_t tri_id;
        float2 uv;
        if (!kls->kg.bvh.hit(ray, &t, &material_index, &bvh_node_type, &inverted_transform_id, &tri_id, &uv)) {
            float3 unit_direction = normalize(ray.direction);
            float tt = 0.5f * (unit_direction.y + 1.0f);
            final_color = final_color * ((1.0f - tt) * make_float3(1.0f) + tt * make_float3(0.5f, 0.7f, 1.0f));
            //final_color = make_float3(0.0f);
            break;
        }

        uint32_t transform_id = inverted_transform_id + 1;
        HitRecord hit;
        hit.t = t;
        hit.p = ray.at(t);
        hit.material_index = material_index;
        switch (bvh_node_type)
        {
            case Sphere: 
            {
                float3 center = transform_point(kls->kg.bvh.transforms, transform_id, make_float3(0.0f));
                float3 outward_normal = normalize(hit.p - center);
                float theta = acos(-outward_normal.y);
                float phi = atan2(-outward_normal.z, outward_normal.x) + HIP_PI_F;
                hit.uv = make_float2(phi / (2.0f * HIP_PI_F), theta / HIP_PI_F);
                hit.set_face_normal(ray, outward_normal);
                break;
            }
            case Mesh: 
            {
                float4 n0 = kls->kg.bvh.normals[kls->kg.bvh.normal_indices[tri_id]];
                float4 n1 = kls->kg.bvh.normals[kls->kg.bvh.normal_indices[tri_id + 1]];
                float4 n2 = kls->kg.bvh.normals[kls->kg.bvh.normal_indices[tri_id + 2]];

                float2 uv0 = kls->kg.bvh.uvs[kls->kg.bvh.uv_indices[tri_id]];
                float2 uv1 = kls->kg.bvh.uvs[kls->kg.bvh.uv_indices[tri_id + 1]];
                float2 uv2 = kls->kg.bvh.uvs[kls->kg.bvh.uv_indices[tri_id + 2]];

                float w = 1.0f - uv.x - uv.y;
                float4 normal = w * n0 + uv.x * n1 + uv.y * n2;
                hit.uv = w * uv0 + uv.x * uv1 + uv.y * uv2;
                float3 outward_normal = normalize(transform_normal(
                    kls->kg.bvh.transforms,
                    inverted_transform_id, 
                    make_float3(normal)
                ));
                hit.set_face_normal(ray, outward_normal);
                break;
            }
            default: { break; }
        }

        float3 attenuation;
        Ray scattered;
        Material material = kls->kg.materials[hit.material_index];
        if (material.scatter(&kls->rnd, ray, hit, &attenuation, &scattered)) {
            ray = scattered;
            final_color = final_color * attenuation;
        } else {
            final_color = final_color * material.emit(hit);
            break;
        }
    }
    
    float4 accumulated_rgba = make_float4(final_color, 1.0f);
    if (constant_params.current_iteration > 1.0f) {
        accumulated_rgba = kls->kg.accumulation_buffer[kls->global_invocation_id] + accumulated_rgba;
    }

    return accumulated_rgba;
}

extern "C" __global__ void matrixTranspose(float* in, float* out, int width) {
    int x = blockDim.x * blockIdx.x + threadIdx.x;
    int y = blockDim.y * blockIdx.y + threadIdx.y;

    out[y * width + x] = in[x * width + y];
}