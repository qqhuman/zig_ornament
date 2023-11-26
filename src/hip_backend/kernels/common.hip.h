#pragma once

#if ( defined( __CUDACC__ ) || defined( __HIPCC__ ) )
#define __KERNELCC__
#endif

#if !defined( __KERNELCC__ )
#define HOST
#define DEVICE
#define HOST_DEVICE
#else
#define HOST __host__
#define DEVICE __device__
#define HOST_DEVICE __host__ __device__
#endif

#ifdef __CUDACC__
#define INLINE __forceinline__
#else
#define INLINE inline
#endif

#include <hiprt/hiprt_vec.h>

typedef float3 float3_aligned __attribute__((aligned(16)));