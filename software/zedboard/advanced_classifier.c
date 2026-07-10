#include "advanced_classifier.h"

#if __has_include("../../generated/headers/model_weights_threshold_sobel_quantized.h")
#include "../../generated/headers/model_weights_threshold_sobel_quantized.h"
#elif __has_include("../generated/headers/model_weights_threshold_sobel_quantized.h")
#include "../generated/headers/model_weights_threshold_sobel_quantized.h"
#else
#error "Missing generated threshold+Sobel quantized model header"
#endif

#if MODEL_INPUTS != ADV_CLASSIFIER_INPUTS
#error "MODEL_INPUTS must match ADV_CLASSIFIER_INPUTS"
#endif

#if MODEL_HIDDEN != ADV_CLASSIFIER_HIDDEN
#error "MODEL_HIDDEN must match ADV_CLASSIFIER_HIDDEN"
#endif

#if MODEL_OUTPUTS != ADV_CLASSIFIER_OUTPUTS
#error "MODEL_OUTPUTS must match ADV_CLASSIFIER_OUTPUTS"
#endif

#if MODEL_THRESHOLD != ADV_CLASSIFIER_DEFAULT_THRESHOLD
#error "MODEL_THRESHOLD must match ADV_CLASSIFIER_DEFAULT_THRESHOLD"
#endif

static uint8_t advanced_requantize_hidden_accumulator(int32_t accumulator)
{
    if (accumulator <= 0) {
        return 0;
    }

    int64_t scaled =
        ((int64_t)accumulator * (int64_t)MODEL_HIDDEN_REQUANT_MULTIPLIER) +
        ((int64_t)1 << (MODEL_HIDDEN_REQUANT_SHIFT - 1));
    int32_t quantized = (int32_t)(scaled >> MODEL_HIDDEN_REQUANT_SHIFT);

    if (quantized > 127) {
        return 127;
    }

    return (uint8_t)quantized;
}

int advanced_classifier_argmax(const int32_t logits[ADV_CLASSIFIER_OUTPUTS])
{
    int best_index = 0;
    int32_t best_value = logits[0];

    for (int index = 1; index < ADV_CLASSIFIER_OUTPUTS; index++) {
        if (logits[index] > best_value) {
            best_value = logits[index];
            best_index = index;
        }
    }

    return best_index;
}

int advanced_classifier_predict_from_threshold_sobel(
    const uint8_t thresholded_image[ADV_CLASSIFIER_IMAGE_PIXELS],
    const uint8_t sobel_image[ADV_CLASSIFIER_IMAGE_PIXELS],
    int32_t logits[ADV_CLASSIFIER_OUTPUTS]
)
{
    uint8_t hidden[ADV_CLASSIFIER_HIDDEN];

    for (int neuron = 0; neuron < ADV_CLASSIFIER_HIDDEN; neuron++) {
        int32_t accumulator = fc1_bias_q[neuron];
        const int weight_base = neuron * ADV_CLASSIFIER_INPUTS;

        for (int pixel = 0; pixel < ADV_CLASSIFIER_IMAGE_PIXELS; pixel++) {
            uint8_t threshold_q =
                (thresholded_image[pixel] != 0u) ? (uint8_t)MODEL_INPUT_Q_MAX : 0u;

            accumulator +=
                (int32_t)threshold_q *
                (int32_t)fc1_weights_q[weight_base + pixel];
        }

        for (int pixel = 0; pixel < ADV_CLASSIFIER_IMAGE_PIXELS; pixel++) {
            accumulator +=
                (int32_t)sobel_image[pixel] *
                (int32_t)fc1_weights_q[weight_base + ADV_CLASSIFIER_IMAGE_PIXELS + pixel];
        }

        hidden[neuron] = advanced_requantize_hidden_accumulator(accumulator);
    }

    for (int output = 0; output < ADV_CLASSIFIER_OUTPUTS; output++) {
        int32_t accumulator = fc2_bias_q[output];
        const int weight_base = output * ADV_CLASSIFIER_HIDDEN;

        for (int neuron = 0; neuron < ADV_CLASSIFIER_HIDDEN; neuron++) {
            accumulator +=
                (int32_t)hidden[neuron] *
                (int32_t)fc2_weights_q[weight_base + neuron];
        }

        logits[output] = accumulator;
    }

    return advanced_classifier_argmax(logits);
}

int advanced_classifier_compare_logits(
    const int32_t actual[ADV_CLASSIFIER_OUTPUTS],
    const int32_t expected[ADV_CLASSIFIER_OUTPUTS]
)
{
    int mismatches = 0;

    for (int index = 0; index < ADV_CLASSIFIER_OUTPUTS; index++) {
        if (actual[index] != expected[index]) {
            mismatches++;
        }
    }

    return mismatches;
}
