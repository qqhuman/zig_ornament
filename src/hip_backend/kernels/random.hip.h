#pragma once

#include <hip/hip_runtime.h>
#include <hip/hip_math_constants.h>
#include "common.hip.h"
#include "vec_math.hip.h"

struct RndGen
{
    uint32_t state;

    HOST_DEVICE RndGen(uint32_t seed) : state(seed) {}

    HOST_DEVICE INLINE uint32_t gen_uint32() {
        // PCG random number generator
        // Based on https://www.shadertoy.com/view/XlGcRh
        
        // rng_state = (word >> 22u) ^ word;
        // return rng_state;
        uint32_t old_state = state + 747796405 + 2891336453;
        uint32_t word = ((old_state >> ((old_state >> 28) + 4)) ^ old_state) * 277803737;
        state = (word >> 22) ^ word;
        return state;
    }

    HOST_DEVICE INLINE float gen_float() {
        return (float)gen_uint32() * (1.0f / 4294967296.0f);
    }

    HOST_DEVICE INLINE float gen_float_between(float min, float max) {
        return min + (max - min) * gen_float();
    }

    HOST_DEVICE INLINE float3 gen_float3() {
        return make_float3(gen_float(), gen_float(), gen_float());
    }

    HOST_DEVICE INLINE float3 gen_float3_between(float min, float max) {
        return make_float3(gen_float_between(min, max), gen_float_between(min, max), gen_float_between(min, max));
    }

    HOST_DEVICE INLINE float3 gen_in_unit_sphere() {
        // for (var i = 0u; i < 10u; i++ ) {
        //     let p = random_vec3_between(-1.0, 1.0);
        //     if length_squared(p) < 1.0 {
        //         return p;
        //     }
        // }

        float r = pow(gen_float(), 0.33333f);
        float theta = HIP_PI_F * gen_float();
        float phi = 2.0f * HIP_PI_F * gen_float();

        float x = r * sin(theta) * cos(phi);
        float y = r * sin(theta) * sin(phi);
        float z = r * cos(theta);

        return make_float3(x, y, z);
    }

    HOST_DEVICE INLINE float3 gen_unit_vector() {
        return normalize(gen_in_unit_sphere());
    }

    HOST_DEVICE INLINE float3 gen_on_hemisphere(const float3& normal) {
        float3 on_unit_sphere = gen_unit_vector();
        if (dot(on_unit_sphere, normal) > 0.0f) {
            return on_unit_sphere;
        } else {
            return -on_unit_sphere;
        }
    }

    HOST_DEVICE INLINE float3 gen_in_unit_disk() {
        // for (var i = 0u; i < 10u; i++ ) {
        //     let p = vec3<f32>(random_f32_between(-1.0, 1.0), random_f32_between(-1.0, 1.0), 0.0);
        //     if length_squared(p) < 1.0 {
        //         return p;
        //     }
        // }
        // Generate numbers uniformly in a disk:
        // https://stats.stackexchange.com/a/481559

        // r^2 is distributed as U(0, 1).
        float r = sqrtf(gen_float());
        float alpha = 2.0f * HIP_PI_F * gen_float();

        float x = r * cos(alpha);
        float y = r * sin(alpha);

        return make_float3(x, y, 0.0f);
    }
};