#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "ray.hip.h"
#include "random.hip.h"

struct Camera
{
    float3 origin __attribute__((aligned(16)));
    float3 lower_left_corner __attribute__((aligned(16)));
    float3 horizontal __attribute__((aligned(16)));
    float3 vertical __attribute__((aligned(16)));
    float3 u __attribute__((aligned(16)));
    float3 v __attribute__((aligned(16)));
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