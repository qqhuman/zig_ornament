#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "ray.hip.h"

enum BvhNodeType : uint32_t
{
    IndernalNode,
    Mesh,
    Triangle,
    Sphere,
};

struct BvhNode
{
    float3 left_aabb_min_or_v0;
    uint32_t left_or_custom_id; // internal left node id / mesh id / triangle id, sphere id
    float3 left_aabb_max_or_v1;
    uint32_t right_or_material_index;
    float3 right_aabb_min_or_v2;
    BvhNodeType node_type; // 0 internal node, 1 mesh, 2 triangle, 3 sphere
    float3 right_aabb_max_or_v3;
    // inverse transform: transform_id * 2
    // model transform:  transform_id * 2 + 1
    uint32_t transform_id;
};

HOST_DEVICE bool bvh_hit(const Ray& not_transformed_ray,
    float* closest_t, 
    uint32_t* closest_material_index,
    BvhNodeType* closest_bvh_node_type,
    uint32_t* closest_inverted_transform_id,
    uint32_t* closest_tri_id,
    float2* closest_uv) {
    // float t_min = constant_params.ray_cast_epsilon;
    // float t_max = 3.40282e+38;

    //uint32_t num_nodes = 
    return false;
}