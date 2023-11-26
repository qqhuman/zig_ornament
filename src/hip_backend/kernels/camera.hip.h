#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "ray.hip.h"
#include "random.hip.h"

struct Camera
{
    float3_aligned origin;
    float3_aligned lower_left_corner;
    float3_aligned horizontal;
    float3_aligned vertical;
    float3_aligned u;
    float3_aligned v;
    float3 w;
    float lens_radius;

    HOST_DEVICE INLINE Ray get_ray(RndGen* rnd, float s, float t) {
        float3 rd = lens_radius * rnd->gen_in_unit_disk();
        float3 offset = u * rd.x + v * rd.y;
        return Ray(
            origin + offset, 
            lower_left_corner + s * horizontal + t * vertical - origin - offset
        );
    }
};