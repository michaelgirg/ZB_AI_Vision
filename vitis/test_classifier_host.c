#include <stdint.h>
#include <stdio.h>

#include "classifier.h"
#include "model_quantized_golden.h"
#include "sample_000_image_data.h"
#include "sample_001_image_data.h"
#include "sample_002_image_data.h"
#include "sample_003_image_data.h"
#include "sample_004_image_data.h"
#include "sample_005_image_data.h"
#include "sample_006_image_data.h"
#include "sample_007_image_data.h"

static const uint8_t *const raw_images[MODEL_GOLDEN_SAMPLE_COUNT] = {
    sample_000_input_image,
    sample_001_input_image,
    sample_002_input_image,
    sample_003_input_image,
    sample_004_input_image,
    sample_005_input_image,
    sample_006_input_image,
    sample_007_input_image,
};

static const uint8_t *const thresholded_images[MODEL_GOLDEN_SAMPLE_COUNT] = {
    sample_000_expected_threshold,
    sample_001_expected_threshold,
    sample_002_expected_threshold,
    sample_003_expected_threshold,
    sample_004_expected_threshold,
    sample_005_expected_threshold,
    sample_006_expected_threshold,
    sample_007_expected_threshold,
};

static int compare_thresholded_image(
    const uint8_t actual[CLASSIFIER_INPUTS],
    const uint8_t expected[CLASSIFIER_INPUTS]
)
{
    int mismatches = 0;

    for (int pixel = 0; pixel < CLASSIFIER_INPUTS; pixel++) {
        if (actual[pixel] != expected[pixel]) {
            mismatches++;
        }
    }

    return mismatches;
}

int main(void)
{
    int failures = 0;

    printf("ZedBoard AI Vision fixed-point classifier host test\n");

    for (int sample = 0; sample < MODEL_GOLDEN_SAMPLE_COUNT; sample++) {
        uint8_t thresholded[CLASSIFIER_INPUTS];
        int32_t logits[CLASSIFIER_OUTPUTS];
        const int32_t *expected_logits =
            &golden_logits_q[sample * MODEL_GOLDEN_LOGITS_STRIDE];

        classifier_threshold_image(
            raw_images[sample],
            thresholded,
            CLASSIFIER_DEFAULT_THRESHOLD
        );

        int threshold_mismatches =
            compare_thresholded_image(thresholded, thresholded_images[sample]);
        int prediction =
            classifier_predict_from_thresholded(thresholded_images[sample], logits);
        int logit_mismatches = classifier_compare_logits(logits, expected_logits);

        if (threshold_mismatches != 0 ||
            logit_mismatches != 0 ||
            prediction != golden_predictions[sample] ||
            prediction != golden_labels[sample]) {
            printf(
                "FAIL sample_%03d: threshold_mismatches=%d "
                "logit_mismatches=%d prediction=%d expected=%d\n",
                sample,
                threshold_mismatches,
                logit_mismatches,
                prediction,
                (int)golden_predictions[sample]
            );
            failures++;
        } else {
            printf(
                "PASS sample_%03d: prediction=%d label=%d\n",
                sample,
                prediction,
                (int)golden_labels[sample]
            );
        }
    }

    if (failures != 0) {
        printf("classifier host test failed with %d issue(s)\n", failures);
        return 1;
    }

    printf("classifier host test passed\n");
    return 0;
}
