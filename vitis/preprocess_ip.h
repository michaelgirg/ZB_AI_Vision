#pragma once

#include <stdint.h>

#define PREPROCESS_IMAGE_PIXELS 784
#define PREPROCESS_DEFAULT_THRESHOLD 128

#define PREPROCESS_REG_CTRL              0x00u
#define PREPROCESS_REG_STATUS            0x04u
#define PREPROCESS_REG_THRESHOLD         0x08u
#define PREPROCESS_REG_IMAGE_PIXELS      0x0cu
#define PREPROCESS_REG_PIXELS_PER_CYCLE  0x10u
#define PREPROCESS_REG_PROCESSING_CYCLES 0x14u
#define PREPROCESS_REG_INPUT_ADDR        0x18u
#define PREPROCESS_REG_INPUT_WDATA       0x1cu
#define PREPROCESS_REG_INPUT_WMASK       0x20u
#define PREPROCESS_REG_OUTPUT_ADDR       0x24u
#define PREPROCESS_REG_OUTPUT_RDATA      0x28u
#define PREPROCESS_REG_MODE              0x2cu

#define PREPROCESS_MODE_THRESHOLD 0u
#define PREPROCESS_MODE_SOBEL     1u

#define PREPROCESS_CTRL_START      0x00000001u
#define PREPROCESS_CTRL_CLEAR_DONE 0x00000002u

#define PREPROCESS_STATUS_BUSY 0x00000001u
#define PREPROCESS_STATUS_DONE 0x00000002u

#define PREPROCESS_INPUT_WMASK_ONE_PIXEL 0x00000001u

#ifndef PREPROCESS_POLL_TIMEOUT
#define PREPROCESS_POLL_TIMEOUT 1000000u
#endif

uint32_t preprocess_read_reg(uintptr_t base_addr, uint32_t offset);
void preprocess_write_reg(uintptr_t base_addr, uint32_t offset, uint32_t value);

void preprocess_write_input_image(
    uintptr_t base_addr,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS]
);

void preprocess_read_output_image(
    uintptr_t base_addr,
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS]
);

int preprocess_run_threshold(
    uintptr_t base_addr,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t threshold,
    uint32_t *processing_cycles
);

int preprocess_run_sobel(
    uintptr_t base_addr,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS],
    uint32_t *processing_cycles
);

int preprocess_run_mode(
    uintptr_t base_addr,
    uint32_t mode,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t threshold,
    uint32_t *processing_cycles
);

int preprocess_compare_image(
    const uint8_t actual[PREPROCESS_IMAGE_PIXELS],
    const uint8_t expected[PREPROCESS_IMAGE_PIXELS]
);
