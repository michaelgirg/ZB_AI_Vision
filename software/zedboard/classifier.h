#pragma once

#include <stdint.h>

#define CLASSIFIER_INPUTS 784
#define CLASSIFIER_HIDDEN 64
#define CLASSIFIER_OUTPUTS 10
#define CLASSIFIER_DEFAULT_THRESHOLD 128

void classifier_threshold_image(
    const uint8_t input_image[CLASSIFIER_INPUTS],
    uint8_t thresholded_image[CLASSIFIER_INPUTS],
    uint8_t threshold
);

int classifier_predict_from_thresholded(
    const uint8_t thresholded_image[CLASSIFIER_INPUTS],
    int32_t logits[CLASSIFIER_OUTPUTS]
);

int classifier_predict_from_binary(
    const uint8_t binary_image[CLASSIFIER_INPUTS],
    int32_t logits[CLASSIFIER_OUTPUTS]
);

int classifier_argmax(const int32_t logits[CLASSIFIER_OUTPUTS]);

int classifier_compare_logits(
    const int32_t actual[CLASSIFIER_OUTPUTS],
    const int32_t expected[CLASSIFIER_OUTPUTS]
);
