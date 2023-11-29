#pragma once

#include <hip/hip_runtime.h>
#include <hip/hip_math_constants.h>
#include "common.hip.h"
#include "vec_math.hip.h"

struct RndGen
{
    uint32_t state;

    HOST_DEVICE RndGen(uint32_t seed) : state(seed) {}

    HOST_DEVICE INLINE uint32_t gen_uint32()
    {
        // PCG random number generator
        // Based on https://www.shadertoy.com/view/XlGcRh
        
        // rng_state = (word >> 22u) ^ word;
        // return rng_state;
        uint32_t old_state = state + 747796405 + 2891336453;
        uint32_t word = ((old_state >> ((old_state >> 28) + 4)) ^ old_state) * 277803737;
        state = (word >> 22) ^ word;
        return state;
    }

    HOST_DEVICE INLINE float gen_float()
    {
        return (float)gen_uint32() * (1.0f / 4294967296.0f);
    }

    HOST_DEVICE INLINE float gen_float_between(float min, float max)
    {
        return min + (max - min) * gen_float();
    }

    HOST_DEVICE INLINE float3 gen_float3()
    {
        return make_float3(gen_float(), gen_float(), gen_float());
    }

    HOST_DEVICE INLINE float3 gen_float3_between(float min, float max)
    {
        return make_float3(gen_float_between(min, max), gen_float_between(min, max), gen_float_between(min, max));
    }

    HOST_DEVICE INLINE float3 gen_in_unit_sphere()
    {
        float r = pow(gen_float(), 0.33333f);
        float theta = HIP_PI_F * gen_float();
        float phi = 2.0f * HIP_PI_F * gen_float();

        float sin_theta, cos_theta;
        sincosf(theta, &sin_theta, &cos_theta);
        float sin_phi, cos_phi;
        sincosf(phi, &sin_phi, &cos_phi);

        float x = r * sin_theta * cos_phi;
        float y = r * sin_theta * sin_phi;
        float z = r * cos_theta;

        return make_float3(x, y, z);
    }

    HOST_DEVICE INLINE float3 gen_unit_vector()
    {
        return normalize(gen_in_unit_sphere());
    }

    HOST_DEVICE INLINE float3 gen_on_hemisphere(const float3& normal)
    {
        float3 on_unit_sphere = gen_unit_vector();
        if (dot(on_unit_sphere, normal) > 0.0f)
        {
            return on_unit_sphere;
        } 
        else
        {
            return -on_unit_sphere;
        }
    }

    HOST_DEVICE INLINE float3 gen_in_unit_disk()
    {
        // r^2 is distributed as U(0, 1).
        float r = sqrtf(gen_float());
        float alpha = 2.0f * HIP_PI_F * gen_float();

        float sin_alpha, cos_alpha;
        sincosf(alpha, &sin_alpha, &cos_alpha);
        float x = r * cos_alpha;
        float y = r * sin_alpha;

        return make_float3(x, y, 0.0f);
    }
};