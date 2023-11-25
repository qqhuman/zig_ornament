/*
Copyright (c) 2015 - 2021 Advanced Micro Devices, Inc. All rights reserved.

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.  IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
*/

#include <math.h>
#include <string.h>
#include "hip.h"

extern hipError_t hipGetDevicePropertiesWithoutArchFlags(hipDevicePropWithoutArchFlags_t* retProp, int deviceId) {
    hipDeviceProp_t prop;
    hipError_t err;

    if (retProp == NULL) {
        err = hipGetDeviceProperties(NULL, deviceId);
    } else {
        err = hipGetDeviceProperties(&prop, deviceId);
    }

    if (err == HIP_SUCCESS && retProp != NULL) {
        //retProp->name = prop.name;
        memcpy(retProp->name, prop.name, sizeof(retProp->name));
        retProp->totalGlobalMem = prop.totalGlobalMem;
        retProp->sharedMemPerBlock = prop.sharedMemPerBlock;
        retProp->regsPerBlock = prop.regsPerBlock;
        retProp->warpSize = prop.warpSize;
        retProp->maxThreadsPerBlock = prop.maxThreadsPerBlock;
        //retProp->maxThreadsDim = prop.maxThreadsDim;
        memcpy(retProp->maxThreadsDim, prop.maxThreadsDim, sizeof(retProp->maxThreadsDim));
        //retProp->maxGridSize = prop.maxGridSize;
        memcpy(retProp->maxGridSize, prop.maxGridSize, sizeof(retProp->maxGridSize));
        retProp->clockRate = prop.clockRate;
        retProp->memoryClockRate = prop.memoryClockRate;
        retProp->memoryBusWidth = prop.memoryBusWidth;
        retProp->totalConstMem = prop.totalConstMem;
        retProp->major = prop.major;
        retProp->minor = prop.minor;
        retProp->multiProcessorCount = prop.multiProcessorCount;
        retProp->l2CacheSize = prop.l2CacheSize;
        retProp->maxThreadsPerMultiProcessor = prop.maxThreadsPerMultiProcessor;
        retProp->computeMode = prop.computeMode;
        retProp->clockInstructionRate = prop.clockInstructionRate;
        retProp->concurrentKernels = prop.concurrentKernels;
        retProp->pciDomainID = prop.pciDomainID;
        retProp->pciBusID = prop.pciBusID;
        retProp->pciDeviceID = prop.pciDeviceID;
        retProp->maxSharedMemoryPerMultiProcessor = prop.maxSharedMemoryPerMultiProcessor;
        retProp->isMultiGpuBoard = prop.isMultiGpuBoard;
        retProp->canMapHostMemory = prop.canMapHostMemory;
        retProp->gcnArch = prop.gcnArch;
        //retProp->gcnArchName = prop.gcnArchName;
        memcpy(retProp->gcnArchName, prop.gcnArchName, sizeof(retProp->gcnArchName));
        retProp->integrated = prop.integrated;
        retProp->cooperativeLaunch = prop.cooperativeLaunch;
        retProp->cooperativeMultiDeviceLaunch = prop.cooperativeMultiDeviceLaunch;
        retProp->maxTexture1DLinear = prop.maxTexture1DLinear;
        retProp->maxTexture1D = prop.maxTexture1D;
        //retProp->maxTexture2D = prop.maxTexture2D;
        memcpy(retProp->maxTexture2D, prop.maxTexture2D, sizeof(retProp->maxTexture2D));
        //retProp->maxTexture3D = prop.maxTexture3D;
        memcpy(retProp->maxTexture3D, prop.maxTexture3D, sizeof(retProp->maxTexture3D));
        retProp->hdpMemFlushCntl = prop.hdpMemFlushCntl;
        retProp->hdpRegFlushCntl = prop.hdpRegFlushCntl;
        retProp->memPitch = prop.memPitch;
        retProp->textureAlignment = prop.textureAlignment;
        retProp->texturePitchAlignment = prop.texturePitchAlignment;
        retProp->kernelExecTimeoutEnabled = prop.kernelExecTimeoutEnabled;
        retProp->ECCEnabled = prop.ECCEnabled;
        retProp->tccDriver = prop.tccDriver;
        retProp->cooperativeMultiDeviceUnmatchedFunc = prop.cooperativeMultiDeviceUnmatchedFunc;
        retProp->cooperativeMultiDeviceUnmatchedGridDim = prop.cooperativeMultiDeviceUnmatchedGridDim;
        retProp->cooperativeMultiDeviceUnmatchedBlockDim = prop.cooperativeMultiDeviceUnmatchedBlockDim;
        retProp->cooperativeMultiDeviceUnmatchedSharedMem = prop.cooperativeMultiDeviceUnmatchedSharedMem;
        retProp->isLargeBar = prop.isLargeBar;
        retProp->asicRevision = prop.asicRevision;
        retProp->managedMemory = prop.managedMemory;
        retProp->directManagedMemAccessFromHost = prop.directManagedMemAccessFromHost;
        retProp->concurrentManagedAccess = prop.concurrentManagedAccess;
        retProp->pageableMemoryAccess = prop.pageableMemoryAccess;
        retProp->pageableMemoryAccessUsesHostPageTables = prop.pageableMemoryAccessUsesHostPageTables;
    }

    return err;
}