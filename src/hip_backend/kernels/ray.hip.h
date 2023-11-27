#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "vec_math.hip.h"

struct Ray
{
    float3 origin;
    float3 direction;

    HOST_DEVICE Ray() : origin(make_float3(0.0f)), direction(make_float3(0.0f)) {}
    HOST_DEVICE Ray(const float3& o, const float3& d) : origin(o), direction(d) {}

    HOST_DEVICE INLINE float3 at(float t)
    {
        return origin + t * direction;
    }
};