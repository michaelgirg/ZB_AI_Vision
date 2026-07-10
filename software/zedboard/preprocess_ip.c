#include "preprocess_ip.h"

uint32_t preprocess_read_reg(uintptr_t base_addr, uint32_t offset)
{
    volatile uint32_t *reg = (volatile uint32_t *)(base_addr + (uintptr_t)offset);
    return *reg;
}

void preprocess_write_reg(uintptr_t base_addr, uint32_t offset, uint32_t value)
{
    volatile uint32_t *reg = (volatile uint32_t *)(base_addr + (uintptr_t)offset);
    *reg = value;
}

void preprocess_write_input_image(
    uintptr_t base_addr,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS]
)
{
    preprocess_write_reg(base_addr, PREPROCESS_REG_INPUT_WMASK, PREPROCESS_INPUT_WMASK_ONE_PIXEL);

    for (uint32_t pixel = 0; pixel < PREPROCESS_IMAGE_PIXELS; pixel++) {
        preprocess_write_reg(base_addr, PREPROCESS_REG_INPUT_ADDR, pixel);
        preprocess_write_reg(base_addr, PREPROCESS_REG_INPUT_WDATA, (uint32_t)input_image[pixel]);
    }
}

void preprocess_read_output_image(
    uintptr_t base_addr,
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS]
)
{
    for (uint32_t pixel = 0; pixel < PREPROCESS_IMAGE_PIXELS; pixel++) {
        preprocess_write_reg(base_addr, PREPROCESS_REG_OUTPUT_ADDR, pixel);
        output_image[pixel] =
            (uint8_t)(preprocess_read_reg(base_addr, PREPROCESS_REG_OUTPUT_RDATA) & 0xffu);
    }
}

int preprocess_run_mode(
    uintptr_t base_addr,
    uint32_t mode,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t threshold,
    uint32_t *processing_cycles
)
{
    preprocess_write_reg(base_addr, PREPROCESS_REG_CTRL, PREPROCESS_CTRL_CLEAR_DONE);
    preprocess_write_reg(base_addr, PREPROCESS_REG_MODE, mode);
    preprocess_write_reg(base_addr, PREPROCESS_REG_THRESHOLD, (uint32_t)threshold);
    preprocess_write_input_image(base_addr, input_image);
    preprocess_write_reg(base_addr, PREPROCESS_REG_CTRL, PREPROCESS_CTRL_START);

    for (uint32_t poll = 0; poll < PREPROCESS_POLL_TIMEOUT; poll++) {
        uint32_t status = preprocess_read_reg(base_addr, PREPROCESS_REG_STATUS);
        if ((status & PREPROCESS_STATUS_DONE) != 0u) {
            if (processing_cycles != 0) {
                *processing_cycles =
                    preprocess_read_reg(base_addr, PREPROCESS_REG_PROCESSING_CYCLES);
            }

            preprocess_read_output_image(base_addr, output_image);
            return 0;
        }
    }

    return -1;
}

int preprocess_run_threshold(
    uintptr_t base_addr,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t threshold,
    uint32_t *processing_cycles
)
{
    return preprocess_run_mode(
        base_addr,
        PREPROCESS_MODE_THRESHOLD,
        input_image,
        output_image,
        threshold,
        processing_cycles
    );
}

int preprocess_run_sobel(
    uintptr_t base_addr,
    const uint8_t input_image[PREPROCESS_IMAGE_PIXELS],
    uint8_t output_image[PREPROCESS_IMAGE_PIXELS],
    uint32_t *processing_cycles
)
{
    return preprocess_run_mode(
        base_addr,
        PREPROCESS_MODE_SOBEL,
        input_image,
        output_image,
        PREPROCESS_DEFAULT_THRESHOLD,
        processing_cycles
    );
}

int preprocess_compare_image(
    const uint8_t actual[PREPROCESS_IMAGE_PIXELS],
    const uint8_t expected[PREPROCESS_IMAGE_PIXELS]
)
{
    int mismatches = 0;

    for (int pixel = 0; pixel < PREPROCESS_IMAGE_PIXELS; pixel++) {
        if (actual[pixel] != expected[pixel]) {
            mismatches++;
        }
    }

    return mismatches;
}
