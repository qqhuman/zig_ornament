#pragma once

#include "constant_params.hip.h"
#include "camera.hip.h"

__constant__ Camera camera;
__constant__ ConstantParams constant_params;