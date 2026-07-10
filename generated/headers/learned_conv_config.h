#pragma once

#include <stdint.h>

#define LEARNED_CONV_KERNEL_SIZE 9
#define LEARNED_CONV_BIAS -128
#define LEARNED_CONV_SHIFT 3
#define LEARNED_CONV_RELU_EN 1

static const int8_t learned_conv_kernel[LEARNED_CONV_KERNEL_SIZE] = { -2, -1, 0, -1, 6, 1, 0, 1, 2 };
