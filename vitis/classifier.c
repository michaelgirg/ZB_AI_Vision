#include "classifier.h"

#include "model_weights_quantized.h"

#if MODEL_INPUTS != CLASSIFIER_INPUTS
#error "MODEL_INPUTS must match CLASSIFIER_INPUTS"
#endif

#if MODEL_HIDDEN != CLASSIFIER_HIDDEN
#error "MODEL_HIDDEN must match CLASSIFIER_HIDDEN"
#endif

#if MODEL_OUTPUTS != CLASSIFIER_OUTPUTS
#error "MODEL_OUTPUTS must match CLASSIFIER_OUTPUTS"
#endif

#if MODEL_THRESHOLD != CLASSIFIER_DEFAULT_THRESHOLD
#error "MODEL_THRESHOLD must match CLASSIFIER_DEFAULT_THRESHOLD"
#endif

static uint8_t requantize_hidden_accumulator(int32_t accumulator)
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

void classifier_threshold_image(
    const uint8_t input_image[CLASSIFIER_INPUTS],
    uint8_t thresholded_image[CLASSIFIER_INPUTS],
    uint8_t threshold
)
{
    for (int pixel = 0; pixel < CLASSIFIER_INPUTS; pixel++) {
        thresholded_image[pixel] = (input_image[pixel] >= threshold) ? 0xffu : 0x00u;
    }
}

int classifier_argmax(const int32_t logits[CLASSIFIER_OUTPUTS])
{
    int best_index = 0;
    int32_t best_value = logits[0];

    for (int index = 1; index < CLASSIFIER_OUTPUTS; index++) {
        if (logits[index] > best_value) {
            best_value = logits[index];
            best_index = index;
        }
    }

    return best_index;
}

int classifier_predict_from_binary(
    const uint8_t binary_image[CLASSIFIER_INPUTS],
    int32_t logits[CLASSIFIER_OUTPUTS]
)
{
    uint8_t hidden[CLASSIFIER_HIDDEN];

    for (int neuron = 0; neuron < CLASSIFIER_HIDDEN; neuron++) {
        int32_t accumulator = fc1_bias_q[neuron];
        const int weight_base = neuron * CLASSIFIER_INPUTS;

        for (int pixel = 0; pixel < CLASSIFIER_INPUTS; pixel++) {
            if (binary_image[pixel] != 0u) {
                accumulator += (int32_t)fc1_weights_q[weight_base + pixel];
            }
        }

        hidden[neuron] = requantize_hidden_accumulator(accumulator);
    }

    for (int output = 0; output < CLASSIFIER_OUTPUTS; output++) {
        int32_t accumulator = fc2_bias_q[output];
        const int weight_base = output * CLASSIFIER_HIDDEN;

        for (int neuron = 0; neuron < CLASSIFIER_HIDDEN; neuron++) {
            accumulator +=
                (int32_t)hidden[neuron] *
                (int32_t)fc2_weights_q[weight_base + neuron];
        }

        logits[output] = accumulator;
    }

    return classifier_argmax(logits);
}

int classifier_predict_from_thresholded(
    const uint8_t thresholded_image[CLASSIFIER_INPUTS],
    int32_t logits[CLASSIFIER_OUTPUTS]
)
{
    uint8_t binary_image[CLASSIFIER_INPUTS];

    for (int pixel = 0; pixel < CLASSIFIER_INPUTS; pixel++) {
        binary_image[pixel] = (thresholded_image[pixel] != 0u) ? 1u : 0u;
    }

    return classifier_predict_from_binary(binary_image, logits);
}

int classifier_compare_logits(
    const int32_t actual[CLASSIFIER_OUTPUTS],
    const int32_t expected[CLASSIFIER_OUTPUTS]
)
{
    int mismatches = 0;

    for (int index = 0; index < CLASSIFIER_OUTPUTS; index++) {
        if (actual[index] != expected[index]) {
            mismatches++;
        }
    }

    return mismatches;
}
