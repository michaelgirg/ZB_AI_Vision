#include <stdint.h>

#include "advanced_classifier.h"
#include "classifier.h"

#define golden_labels threshold_golden_labels
#define golden_predictions threshold_golden_predictions
#define golden_logits_q threshold_golden_logits_q
#include "model_quantized_golden.h"
#undef golden_labels
#undef golden_predictions
#undef golden_logits_q
#undef MODEL_GOLDEN_SAMPLE_COUNT
#undef MODEL_GOLDEN_LOGITS_STRIDE

#define golden_labels advanced_golden_labels
#define golden_predictions advanced_golden_predictions
#define golden_logits_q advanced_golden_logits_q
#if __has_include("../../generated/headers/model_threshold_sobel_quantized_golden.h")
#include "../../generated/headers/model_threshold_sobel_quantized_golden.h"
#elif __has_include("../generated/headers/model_threshold_sobel_quantized_golden.h")
#include "../generated/headers/model_threshold_sobel_quantized_golden.h"
#else
#error "Missing generated threshold+Sobel quantized golden header"
#endif
#undef golden_labels
#undef golden_predictions
#undef golden_logits_q

#include "preprocess_ip.h"

#if __has_include("../../generated/test_vectors/sample_000_image_data.h")
#include "../../generated/test_vectors/sample_000_image_data.h"
#include "../../generated/test_vectors/sample_001_image_data.h"
#include "../../generated/test_vectors/sample_002_image_data.h"
#include "../../generated/test_vectors/sample_003_image_data.h"
#include "../../generated/test_vectors/sample_004_image_data.h"
#include "../../generated/test_vectors/sample_005_image_data.h"
#include "../../generated/test_vectors/sample_006_image_data.h"
#include "../../generated/test_vectors/sample_007_image_data.h"
#elif __has_include("../generated/test_vectors/sample_000_image_data.h")
#include "../generated/test_vectors/sample_000_image_data.h"
#include "../generated/test_vectors/sample_001_image_data.h"
#include "../generated/test_vectors/sample_002_image_data.h"
#include "../generated/test_vectors/sample_003_image_data.h"
#include "../generated/test_vectors/sample_004_image_data.h"
#include "../generated/test_vectors/sample_005_image_data.h"
#include "../generated/test_vectors/sample_006_image_data.h"
#include "../generated/test_vectors/sample_007_image_data.h"
#else
#include "sample_000_image_data.h"
#endif

#include "xil_printf.h"
#include "xiltimer.h"
#define APP_PRINTF xil_printf

#ifndef PREPROCESS_IP_BASEADDR
#define PREPROCESS_IP_BASEADDR 0x40000000u
#endif

#define APP_SAMPLE_COUNT 8
#define EXPECTED_THRESHOLD_CYCLES 786u
#define EXPECTED_PIPELINED_SOBEL_CYCLES 898u

static void print_logits(const char *label, const int32_t logits[CLASSIFIER_OUTPUTS])
{
    APP_PRINTF("%s:", label);
    for (int index = 0; index < CLASSIFIER_OUTPUTS; index++) {
        APP_PRINTF(" %d", (int)logits[index]);
    }
    APP_PRINTF("\r\n");
}

static uint64_t elapsed_timer_counts(XTime start_time, XTime end_time)
{
    return (uint64_t)(end_time - start_time);
}

static uint64_t timer_counts_to_cpu_cycles(uint64_t timer_counts)
{
    return timer_counts * 2u;
}

static void print_speedup_x100(uint64_t arm_cycles, uint32_t fpga_cycles)
{
    if (fpga_cycles == 0u) {
        APP_PRINTF("Speedup: unavailable\r\n");
        return;
    }

    uint64_t speedup_x100 = (arm_cycles * 100u) / (uint64_t)fpga_cycles;
    APP_PRINTF(
        "Threshold preprocessing speedup: %d.%02dx\r\n",
        (int)(speedup_x100 / 100u),
        (int)(speedup_x100 % 100u)
    );
}

static void print_advanced_inference_ratio_x100(
    uint64_t advanced_cycles,
    uint64_t threshold_cycles
)
{
    if (threshold_cycles == 0u) {
        APP_PRINTF("Advanced inference ratio: unavailable\r\n");
        return;
    }

    uint64_t ratio_x100 = (advanced_cycles * 100u) / threshold_cycles;
    APP_PRINTF(
        "Advanced inference ratio: %d.%02dx threshold model\r\n",
        (int)(ratio_x100 / 100u),
        (int)(ratio_x100 % 100u)
    );
}

static const char *const sample_names[APP_SAMPLE_COUNT] = {
    "sample_000",
    "sample_001",
    "sample_002",
    "sample_003",
    "sample_004",
    "sample_005",
    "sample_006",
    "sample_007",
};

static const uint8_t *const sample_inputs[APP_SAMPLE_COUNT] = {
    sample_000_input_image,
    sample_001_input_image,
    sample_002_input_image,
    sample_003_input_image,
    sample_004_input_image,
    sample_005_input_image,
    sample_006_input_image,
    sample_007_input_image,
};

static const uint8_t *const sample_thresholds[APP_SAMPLE_COUNT] = {
    sample_000_expected_threshold,
    sample_001_expected_threshold,
    sample_002_expected_threshold,
    sample_003_expected_threshold,
    sample_004_expected_threshold,
    sample_005_expected_threshold,
    sample_006_expected_threshold,
    sample_007_expected_threshold,
};

static const uint8_t *const sample_sobels[APP_SAMPLE_COUNT] = {
    sample_000_expected_sobel,
    sample_001_expected_sobel,
    sample_002_expected_sobel,
    sample_003_expected_sobel,
    sample_004_expected_sobel,
    sample_005_expected_sobel,
    sample_006_expected_sobel,
    sample_007_expected_sobel,
};

int main(void)
{
    uint8_t fpga_output[PREPROCESS_IMAGE_PIXELS];
    uint8_t fpga_sobel_output[PREPROCESS_IMAGE_PIXELS];
    uint8_t arm_threshold_output[PREPROCESS_IMAGE_PIXELS];
    int32_t threshold_logits[CLASSIFIER_OUTPUTS];
    int32_t advanced_logits[ADV_CLASSIFIER_OUTPUTS];
    int32_t sample0_threshold_logits[CLASSIFIER_OUTPUTS];
    int32_t sample0_advanced_logits[ADV_CLASSIFIER_OUTPUTS];
    XTime arm_start_time;
    XTime arm_end_time;
    uint64_t total_arm_preprocess_cycles = 0;
    uint64_t total_fpga_threshold_cycles = 0;
    uint64_t total_fpga_sobel_cycles = 0;
    uint64_t total_threshold_inference_cycles = 0;
    uint64_t total_advanced_inference_cycles = 0;
    int pass_count = 0;
    int failures = 0;
    const uintptr_t base_addr = (uintptr_t)PREPROCESS_IP_BASEADDR;

    APP_PRINTF("ZedBoard AI Vision Pipeline\r\n");
    APP_PRINTF("Samples: %d\r\n\r\n", APP_SAMPLE_COUNT);

    uint32_t image_pixels = preprocess_read_reg(base_addr, PREPROCESS_REG_IMAGE_PIXELS);
    uint32_t pixels_per_cycle =
        preprocess_read_reg(base_addr, PREPROCESS_REG_PIXELS_PER_CYCLE);

    APP_PRINTF("IP image pixels: %d\r\n", (int)image_pixels);
    APP_PRINTF("IP pixels/cycle: %d\r\n\r\n", (int)pixels_per_cycle);

    if (image_pixels != PREPROCESS_IMAGE_PIXELS) {
        APP_PRINTF("Result: FAIL image pixel register mismatch\r\n");
        return 1;
    }

    if (pixels_per_cycle != 1u) {
        APP_PRINTF("Result: FAIL software expects 1 pixel/cycle IP\r\n");
        return 1;
    }

    APP_PRINTF("Validation Summary\r\n");
    APP_PRINTF("Sample    Label  Threshold  Advanced  Result\r\n");

    for (int sample = 0; sample < APP_SAMPLE_COUNT; sample++) {
        uint32_t fpga_cycles = 0;
        uint32_t fpga_sobel_cycles = 0;
        uint64_t arm_timer_counts;
        uint64_t arm_cycles;
        uint64_t threshold_inference_timer_counts;
        uint64_t threshold_inference_cycles;
        uint64_t advanced_inference_timer_counts;
        uint64_t advanced_inference_cycles;
        const uint8_t *input_image = sample_inputs[sample];
        const uint8_t *expected_threshold = sample_thresholds[sample];
        const uint8_t *expected_sobel = sample_sobels[sample];
        const int32_t *expected_threshold_logits =
            &threshold_golden_logits_q[sample * MODEL_GOLDEN_LOGITS_STRIDE];
        const int32_t *expected_advanced_logits =
            &advanced_golden_logits_q[sample * MODEL_GOLDEN_LOGITS_STRIDE];

        for (int pixel = 0; pixel < PREPROCESS_IMAGE_PIXELS; pixel++) {
            fpga_output[pixel] = 0u;
            fpga_sobel_output[pixel] = 0u;
            arm_threshold_output[pixel] = 0u;
        }

        XTime_GetTime(&arm_start_time);
        classifier_threshold_image(
            input_image,
            arm_threshold_output,
            CLASSIFIER_DEFAULT_THRESHOLD
        );
        XTime_GetTime(&arm_end_time);

        arm_timer_counts = elapsed_timer_counts(arm_start_time, arm_end_time);
        arm_cycles = timer_counts_to_cpu_cycles(arm_timer_counts);

        int arm_threshold_mismatches =
            preprocess_compare_image(arm_threshold_output, expected_threshold);

        int preprocess_status = preprocess_run_threshold(
            base_addr,
            input_image,
            fpga_output,
            CLASSIFIER_DEFAULT_THRESHOLD,
            &fpga_cycles
        );

        int threshold_mismatches = PREPROCESS_IMAGE_PIXELS;
        if (preprocess_status == 0) {
            threshold_mismatches =
                preprocess_compare_image(fpga_output, expected_threshold);
        }

        int sobel_status = preprocess_run_sobel(
            base_addr,
            input_image,
            fpga_sobel_output,
            &fpga_sobel_cycles
        );

        int sobel_mismatches = PREPROCESS_IMAGE_PIXELS;
        if (sobel_status == 0) {
            sobel_mismatches =
                preprocess_compare_image(fpga_sobel_output, expected_sobel);
        }

        int threshold_cycle_match = (fpga_cycles == EXPECTED_THRESHOLD_CYCLES);
        int sobel_cycle_match =
            (fpga_sobel_cycles == EXPECTED_PIPELINED_SOBEL_CYCLES);

        XTime_GetTime(&arm_start_time);
        int threshold_prediction =
            classifier_predict_from_thresholded(fpga_output, threshold_logits);
        XTime_GetTime(&arm_end_time);
        threshold_inference_timer_counts =
            elapsed_timer_counts(arm_start_time, arm_end_time);
        threshold_inference_cycles =
            timer_counts_to_cpu_cycles(threshold_inference_timer_counts);

        int threshold_logit_mismatches =
            classifier_compare_logits(threshold_logits, expected_threshold_logits);

        XTime_GetTime(&arm_start_time);
        int advanced_prediction = advanced_classifier_predict_from_threshold_sobel(
            fpga_output,
            fpga_sobel_output,
            advanced_logits
        );
        XTime_GetTime(&arm_end_time);
        advanced_inference_timer_counts =
            elapsed_timer_counts(arm_start_time, arm_end_time);
        advanced_inference_cycles =
            timer_counts_to_cpu_cycles(advanced_inference_timer_counts);

        int advanced_logit_mismatches =
            advanced_classifier_compare_logits(advanced_logits, expected_advanced_logits);

        if (sample == 0) {
            for (int index = 0; index < CLASSIFIER_OUTPUTS; index++) {
                sample0_threshold_logits[index] = threshold_logits[index];
                sample0_advanced_logits[index] = advanced_logits[index];
            }
        }

        int sample_pass =
            preprocess_status == 0 &&
            sobel_status == 0 &&
            threshold_mismatches == 0 &&
            sobel_mismatches == 0 &&
            threshold_cycle_match &&
            sobel_cycle_match &&
            arm_threshold_mismatches == 0 &&
            threshold_logit_mismatches == 0 &&
            advanced_logit_mismatches == 0 &&
            threshold_prediction == threshold_golden_predictions[sample] &&
            threshold_prediction == threshold_golden_labels[sample] &&
            advanced_prediction == advanced_golden_predictions[sample] &&
            advanced_prediction == advanced_golden_labels[sample];

        total_arm_preprocess_cycles += arm_cycles;
        total_fpga_threshold_cycles += fpga_cycles;
        total_fpga_sobel_cycles += fpga_sobel_cycles;
        total_threshold_inference_cycles += threshold_inference_cycles;
        total_advanced_inference_cycles += advanced_inference_cycles;

        if (sample_pass) {
            pass_count++;
        } else {
            failures++;
        }

        APP_PRINTF(
            "%s  %d      %d          %d         %s\r\n",
            sample_names[sample],
            (int)threshold_golden_labels[sample],
            threshold_prediction,
            advanced_prediction,
            sample_pass ? "PASS" : "FAIL"
        );

        if (!sample_pass) {
            APP_PRINTF(
                "  checks: fpga_threshold=%s fpga_sobel=%s arm_threshold=%s "
                "threshold_cycles=%s sobel_cycles=%s "
                "threshold_logits=%s advanced_logits=%s\r\n",
                (threshold_mismatches == 0) ? "PASS" : "FAIL",
                (sobel_mismatches == 0) ? "PASS" : "FAIL",
                (arm_threshold_mismatches == 0) ? "PASS" : "FAIL",
                threshold_cycle_match ? "PASS" : "FAIL",
                sobel_cycle_match ? "PASS" : "FAIL",
                (threshold_logit_mismatches == 0) ? "PASS" : "FAIL",
                (advanced_logit_mismatches == 0) ? "PASS" : "FAIL"
            );
            APP_PRINTF(
                "  cycles: arm_pre=%d fpga_threshold=%d fpga_sobel=%d "
                "threshold_inf=%d advanced_inf=%d\r\n",
                (int)(uint32_t)arm_cycles,
                (int)fpga_cycles,
                (int)fpga_sobel_cycles,
                (int)(uint32_t)threshold_inference_cycles,
                (int)(uint32_t)advanced_inference_cycles
            );
        }
    }

    APP_PRINTF("\r\nTiming Summary\r\n");
    APP_PRINTF("Samples passed: %d/%d\r\n", pass_count, APP_SAMPLE_COUNT);
    APP_PRINTF(
        "Avg ARM threshold preprocess cycles: %d\r\n",
        (int)(uint32_t)(total_arm_preprocess_cycles / APP_SAMPLE_COUNT)
    );
    APP_PRINTF(
        "Avg FPGA threshold preprocess cycles: %d\r\n",
        (int)(uint32_t)(total_fpga_threshold_cycles / APP_SAMPLE_COUNT)
    );
    APP_PRINTF(
        "Avg FPGA Sobel preprocess cycles: %d\r\n",
        (int)(uint32_t)(total_fpga_sobel_cycles / APP_SAMPLE_COUNT)
    );
    APP_PRINTF(
        "Expected pipelined Sobel cycles: %d\r\n",
        (int)EXPECTED_PIPELINED_SOBEL_CYCLES
    );
    APP_PRINTF(
        "Avg threshold model inference cycles: %d\r\n",
        (int)(uint32_t)(total_threshold_inference_cycles / APP_SAMPLE_COUNT)
    );
    APP_PRINTF(
        "Avg advanced model inference cycles: %d\r\n",
        (int)(uint32_t)(total_advanced_inference_cycles / APP_SAMPLE_COUNT)
    );
    print_speedup_x100(
        total_arm_preprocess_cycles,
        (uint32_t)total_fpga_threshold_cycles
    );
    print_advanced_inference_ratio_x100(
        total_advanced_inference_cycles,
        total_threshold_inference_cycles
    );

    APP_PRINTF("\r\nSample_000 Logits\r\n");
    print_logits("Threshold model", sample0_threshold_logits);
    print_logits("Advanced model", sample0_advanced_logits);

    if (failures == 0) {
        APP_PRINTF("\r\nResult: PASS\r\n");
        return 0;
    }

    APP_PRINTF("\r\nResult: FAIL\r\n");
    return 1;
}
