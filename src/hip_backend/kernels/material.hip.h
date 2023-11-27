#pragma once

#include <hip/hip_runtime.h>
#include "common.hip.h"
#include "random.hip.h"
#include "ray.hip.h"
#include "hitrecord.hip.h"

enum MaterialType : uint32_t
{
    Lambertian = 0,
    Metal = 1,
    Dielectric = 2,
    DiffuseLight = 3,
};

struct Material 
{
    float3 albedo_vec;
    uint32_t albedo_texture_index;
    float fuzz;
    float ior;
    MaterialType material_type;
    uint32_t _padding;
    
    #define EPS 1E-8f
    #define NEAR_ZERO(e) abs(e.x) < EPS && abs(e.y) < EPS && abs(e.z) < EPS

    HOST_DEVICE INLINE float3 get_color(const float3& color, uint32_t texture_id, const float2& uv) {
        return color;
    }

    HOST_DEVICE INLINE float reflectance(float cosine, float ref_idx) {
        // Use Schlick's approximation for reflectance.
        float r0 = (1.0f - ref_idx) / (1.0f + ref_idx);
        r0 = r0 * r0;
        return r0 + (1.0f - r0) * pow((1.0f - cosine), 5.0f);
    }

    HOST_DEVICE bool lambertian_scatter(RndGen* rnd, const Ray& r, const HitRecord& hit, float3* attenuation, Ray* scattered) {
        float3 scattered_direction = hit.normal + rnd->gen_unit_vector();

        // Catch degenerate scatter direction
        if (NEAR_ZERO(scattered_direction)) {
            scattered_direction = hit.normal;
        }

        *scattered = Ray(hit.p, scattered_direction);
        *attenuation = get_color(albedo_vec, albedo_texture_index, hit.uv);
        return true;
    }

    HOST_DEVICE bool metal_scatter(RndGen* rnd, const Ray& r, const HitRecord& hit, float3* attenuation, Ray* scattered) {
        float3 scattered_direction = reflect(normalize(r.direction), hit.normal) + fuzz * rnd->gen_in_unit_sphere();
        *scattered = Ray(hit.p, scattered_direction);
        *attenuation = get_color(albedo_vec, albedo_texture_index, hit.uv);
        return true;
    }

    HOST_DEVICE bool dielectric_scatter(RndGen* rnd, const Ray& r, const HitRecord& hit, float3* attenuation, Ray* scattered) {
        *attenuation = make_float3(1.0f);
        float refraction_ratio = ior;
        if (hit.front_face) {
            refraction_ratio = 1.0f / ior;
        }

        float3 unit_direction = normalize(r.direction);
        float cos_theta = min(dot(-unit_direction, hit.normal), 1.0f);
        float sin_theta = sqrtf(1.0f - cos_theta * cos_theta);
        bool cannot_refract = refraction_ratio * sin_theta > 1.0f;
        float3 direction = cannot_refract || reflectance(cos_theta, refraction_ratio) > rnd->gen_float()
            ? reflect(unit_direction, hit.normal)
            : refract(unit_direction, hit.normal, refraction_ratio);

        *scattered = Ray(hit.p, direction);
        return true;
    }

    HOST_DEVICE bool scatter(RndGen* rnd, const Ray& r, const HitRecord& hit, float3* attenuation, Ray* scattered) {
        switch(material_type) 
        {
            case Lambertian: return lambertian_scatter(rnd, r, hit, attenuation, scattered);
            case Metal: return metal_scatter(rnd, r, hit, attenuation, scattered);
            case Dielectric: return dielectric_scatter(rnd, r, hit, attenuation, scattered);
            default: return false;
        }
    }

    HOST_DEVICE float3 emit(const HitRecord& hit) {
        switch(material_type) 
        {
            case DiffuseLight: return get_color(albedo_vec, albedo_texture_index, hit.uv);
            default: return make_float3(0.0f);
        }
    }
};