#include <hip/hip_runtime.h>

extern "C" __global__ void matrixTranspose(float* in, float* out, int width) {
    int x = blockDim.x * blockIdx.x + threadIdx.x;
    int y = blockDim.y * blockIdx.y + threadIdx.y;

    out[y * width + x] = in[x * width + y];
}
