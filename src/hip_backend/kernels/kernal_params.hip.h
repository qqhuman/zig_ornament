#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "bvh.hip.h"
#include "material.hip.h"
#include "random.hip.h"
#include "array.hip.h"

struct KernalGlobals
{
    float4* framebuffer;
    float4* accumulation_buffer;
    uint32_t* rng_seed_buffer;
    uint32_t pixel_count;
    Array<Material> materials;
    Array<float4> normals;
    Array<uint32_t> normal_indices;
    Array<float2> uvs;
    Array<uint32_t> uv_indices;
    Array<float4x4> transforms;
    Array<BvhNode> tlas_nodes;
    Array<BvhNode> blas_nodes;
};

struct KernalLocalState
{
    KernalGlobals kg;
    uint2 xy;
    uint32_t global_invocation_id;
    RndGen rnd;

    HOST_DEVICE KernalLocalState(const KernalGlobals& kg, uint2 resolution, uint32_t global_invocation_id) : kg(kg),
        xy(make_uint2(global_invocation_id % resolution.x, global_invocation_id / resolution.y)),
        global_invocation_id(global_invocation_id), 
        rnd(kg.rng_seed_buffer[global_invocation_id])
    {}

    HOST_DEVICE INLINE void save_rng_seed() {
        kg.rng_seed_buffer[global_invocation_id] = rnd.state;
    }
};