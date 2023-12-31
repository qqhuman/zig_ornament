#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "ray.hip.h"
#include "random.hip.h"

struct Camera
{
    float3 origin;
    float lens_radius;
    float3 lower_left_corner;
    uint32_t _padding0;
    float3 horizontal;
    uint32_t _padding1;
    float3 vertical;
    uint32_t _padding2;
    float3 u;
    uint32_t _padding3;
    float3 v;
    uint32_t _padding4;
    float3 w;
    uint32_t _padding5;

    HOST_DEVICE INLINE Ray get_ray(RndGen* rnd, float s, float t)
    {
        float3 rd = lens_radius * rnd->gen_in_unit_disk();
        float3 offset = u * rd.x + v * rd.y;
        return Ray(
            origin + offset, 
            lower_left_corner + s * horizontal + t * vertical - origin - offset
        );
    }
};