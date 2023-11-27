#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "ray.hip.h"
#include "vec_math.hip.h"

struct HitRecord
{
    float3 p;
    uint32_t material_index;
    float3 normal;
    float t;
    float2 uv;
    bool front_face;

    HOST_DEVICE void set_face_normal(const Ray& r, const float3& outward_normal)
    {
        if (dot(r.direction, outward_normal) > 0.0f)
        {
            normal = -outward_normal;
            front_face = false;
        } 
        else
        {
            normal = outward_normal;
            front_face = true;
        }
    }
};