// fn transform_point(transform_id: u32, point: vec3<f32>) -> vec3<f32> {
//     let t = transforms[transform_id];
//     let p = t * vec4<f32>(point, 1.0);
//     return p.xyz;
// }

// fn transform_ray(transform_id: u32, ray: Ray) -> Ray {
//     let inversed_t = transforms[transform_id];

//     let o = inversed_t * vec4<f32>(ray.origin, 1.0);
//     let d = inversed_t * vec4<f32>(ray.direction, 0.0);

//     return Ray(o.xyz, d.xyz);
// }

// fn transform_normal(transform_id: u32, normal :vec3<f32>) -> vec3<f32> {
//     let inversed_t = transforms[transform_id];
//     let n = transpose(inversed_t) * vec4<f32>(normal, 0.0);
//     return n.xyz;
// }

#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "array.hip.h"
#include "ray.hip.h"


HOST_DEVICE INLINE float3 transform_point(const Array<float4x4>& transforms, uint32_t transform_id, const float3& point) {
    float4x4 t = transforms[transform_id];
    float4 p = t * make_float4(point.x, point.y, point.z, 1.0f);
    return make_float3(p.x, p.y, p.z);
}

HOST_DEVICE INLINE Ray transform_ray(const Array<float4x4>& transforms, uint32_t transform_id, const Ray& ray) {
    float4x4 inversed_t = transforms[transform_id];
    
    float4 o = inversed_t * make_float4(ray.origin.x, ray.origin.y, ray.origin.z, 1.0f);
    float4 d = inversed_t * make_float4(ray.direction.x, ray.direction.y, ray.direction.z, 0.0f);

    return Ray(
        make_float3(o.x, o.y, o.z),
        make_float3(d.x, d.y, d.z)
    );
}

HOST_DEVICE INLINE float3 transform_normal(const Array<float4x4>& transforms, uint32_t transform_id, const float3& normal) {
    float4x4 inversed_t = transforms[transform_id];
    float4 n = transpose(inversed_t) * make_float4(normal.x, normal.y, normal.z, 0.0f);
    return make_float3(n.x, n.y, n.z);
}