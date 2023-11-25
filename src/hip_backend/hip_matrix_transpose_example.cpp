#include <iostream>
#include "hip/hip_runtime.h"

#define checkHipErrors(err) __checkHipErrors(err, __FILE__, __LINE__)
inline void __checkHipErrors(hipError_t err, const char *file, const int line) {
  if (HIP_SUCCESS != err) {
    const char *errorStr = hipGetErrorString(err);
    fprintf(stderr,
            "checkHipErrors() HIP API error = %04d \"%s\" from file <%s>, "
            "line %i.\n",
            err, errorStr, file, line);
    hipDeviceReset();
    exit(EXIT_FAILURE);
  }
}

// Matrix Transpose example
#define WIDTH 1024
#define NUM (WIDTH * WIDTH)

#define THREADS_PER_BLOCK_X 4
#define THREADS_PER_BLOCK_Y 4
#define THREADS_PER_BLOCK_Z 1

// CPU implementation of matrix transpose
void matrixTransposeCPUReference(float* output, float* input, const unsigned int width) {
    for (unsigned int j = 0; j < width; j++) {
        for (unsigned int i = 0; i < width; i++) {
            output[i * width + j] = input[j * width + i];
        }
    }
}

extern "C" void matrixTransposeExample(void) {
    float* Matrix;
    float* TransposeMatrix;
    float* cpuTransposeMatrix;

    float* gpuMatrix;
    float* gpuTransposeMatrix;

    int deviceCount = 0;
    checkHipErrors(hipGetDeviceCount(&deviceCount));
    for (int deviceId = 0; deviceId < deviceCount; deviceId++) {
        hipDeviceProp_t devProp;
        checkHipErrors(hipGetDeviceProperties(&devProp, deviceId));
        std::cout << "Device" << deviceId << std::endl;
        std::cout << "      " << " name " << devProp.name << std::endl;
        std::cout << "      " << " warpSize " << devProp.warpSize << std::endl;
        std::cout << "      " << " totalGlobalMem " << devProp.totalGlobalMem / (1024.0 * 1024.0 * 1024.0) << "GB" << std::endl;
        std::cout << "      " << " sharedMemPerBlock " << devProp.sharedMemPerBlock / (1024.0) << "KB" << std::endl;
        std::cout << "      " << " regsPerBlock " << devProp.regsPerBlock << std::endl;
        std::cout << "      " << " maxThreadsPerBlock " << devProp.maxThreadsPerBlock << std::endl;
        std::cout << "      " << " integrated " << devProp.integrated << std::endl;
        std::cout << "      " << " gcnArchName " << devProp.gcnArchName << std::endl;
    }
    checkHipErrors(hipSetDevice(deviceCount - 1));

    int i;
    int errors;

    Matrix = (float*)malloc(NUM * sizeof(float));
    TransposeMatrix = (float*)malloc(NUM * sizeof(float));
    cpuTransposeMatrix = (float*)malloc(NUM * sizeof(float));

    // initialize the input data
    for (i = 0; i < NUM; i++) {
        Matrix[i] = (float)i * 10.0f;
    }

    // allocate the memory on the device side
    checkHipErrors(hipMalloc((void**)&gpuMatrix, NUM * sizeof(float)));
    checkHipErrors(hipMalloc((void**)&gpuTransposeMatrix, NUM * sizeof(float)));

    // Memory transfer from host to device
    checkHipErrors(hipMemcpy(gpuMatrix, Matrix, NUM * sizeof(float), hipMemcpyHostToDevice));

    {
        #define fileName "./zig-out/bin/pathtracer.co"

        hipModule_t module;
        checkHipErrors(hipModuleLoad(&module, fileName));

        hipFunction_t kernel;
        checkHipErrors(hipModuleGetFunction(&kernel, module, "matrixTranspose"));

        struct { void *in; void *out; int width; } args;
        args.in = (void*) gpuMatrix;
        args.out = (void*) gpuTransposeMatrix;
        args.width = WIDTH;

        size_t sizeTemp = sizeof(args);

        void *config[] = { HIP_LAUNCH_PARAM_BUFFER_POINTER, &args, HIP_LAUNCH_PARAM_BUFFER_SIZE, &sizeTemp, HIP_LAUNCH_PARAM_END };

        checkHipErrors(hipModuleLaunchKernel(
            kernel, 
            WIDTH / THREADS_PER_BLOCK_X, 
            WIDTH / THREADS_PER_BLOCK_Y, 
            1, 
            THREADS_PER_BLOCK_X, 
            THREADS_PER_BLOCK_Y, 
            1, 
            0, 
            NULL, 
            NULL, 
            config
        ));

        checkHipErrors(hipModuleUnload(module));
    }

    // Memory transfer from device to host
    checkHipErrors(hipMemcpy(TransposeMatrix, gpuTransposeMatrix, NUM * sizeof(float), hipMemcpyDeviceToHost));

    // CPU MatrixTranspose computation
    matrixTransposeCPUReference(cpuTransposeMatrix, Matrix, WIDTH);

    // verify the results
    errors = 0;
    double eps = 1.0E-6;
    for (i = 0; i < NUM; i++) {
        if (std::abs(TransposeMatrix[i] - cpuTransposeMatrix[i]) > eps) {
            errors++;
        }
    }
    if (errors != 0) {
        printf("FAILED: %d errors\n", errors);
    } else {
        printf("PASSED!\n");
    }

    // free the resources on device side
    checkHipErrors(hipFree(gpuMatrix));
    checkHipErrors(hipFree(gpuTransposeMatrix));
    checkHipErrors(hipDeviceReset());

    // free the resources on host side
    free(Matrix);
    free(TransposeMatrix);
    free(cpuTransposeMatrix);
}