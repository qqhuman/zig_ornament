#pragma once

template <typename T> 
struct Array
{
    T* ptr;
    uint32_t len;

    HOST_DEVICE INLINE T operator[](uint32_t index) const
    {
        return ptr[index];
    }
};