#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "array.hip.h"
#include "ray.hip.h"


HOST_DEVICE INLINE float3 transform_point(const Array<float4x4>& transforms, uint32_t transform_id, const float3& point)
{
    float4x4 t = transforms[transform_id];
    float4 p = t * make_float4(point, 1.0f);
    return make_float3(p);
}

HOST_DEVICE INLINE Ray transform_ray(const Array<float4x4>& transforms, uint32_t transform_id, const Ray& ray)
{
    float4x4 inversed_t = transforms[transform_id];
    
    float4 o = inversed_t * make_float4(ray.origin, 1.0f);
    float4 d = inversed_t * make_float4(ray.direction, 0.0f);

    return Ray(
        make_float3(o),
        make_float3(d)
    );
}

HOST_DEVICE INLINE float3 transform_normal(const Array<float4x4>& transforms, uint32_t transform_id, const float3& normal)
{
    float4x4 inversed_t = transforms[transform_id];
    return make_float3(transpose(inversed_t) * make_float4(normal, 0.0f));
}