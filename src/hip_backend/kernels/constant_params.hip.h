#pragma once

struct ConstantParams
{
    uint32_t depth;
    uint32_t width;
    uint32_t height;
    uint32_t flip_y;
    float inverted_gamma;
    float ray_cast_epsilon;
    uint32_t textures_count;
    float current_iteration;
};