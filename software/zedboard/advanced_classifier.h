#pragma once

#include <stdint.h>

#define ADV_CLASSIFIER_IMAGE_PIXELS 784
#define ADV_CLASSIFIER_INPUTS 1568
#define ADV_CLASSIFIER_HIDDEN 96
#define ADV_CLASSIFIER_OUTPUTS 10
#define ADV_CLASSIFIER_DEFAULT_THRESHOLD 128

int advanced_classifier_predict_from_threshold_sobel(
    const uint8_t thresholded_image[ADV_CLASSIFIER_IMAGE_PIXELS],
    const uint8_t sobel_image[ADV_CLASSIFIER_IMAGE_PIXELS],
    int32_t logits[ADV_CLASSIFIER_OUTPUTS]
);

int advanced_classifier_argmax(const int32_t logits[ADV_CLASSIFIER_OUTPUTS]);

int advanced_classifier_compare_logits(
    const int32_t actual[ADV_CLASSIFIER_OUTPUTS],
    const int32_t expected[ADV_CLASSIFIER_OUTPUTS]
);
