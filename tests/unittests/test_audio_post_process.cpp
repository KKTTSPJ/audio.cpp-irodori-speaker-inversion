// Unit tests for the local audio post-processing stage (normalize_db / volume).
//
// These cover the behaviours the 2026-08-02 review called out:
//   - volume <= 0 mutes instead of passing the original audio through
//   - normalize_db > 0 goes through the soft limiter instead of hard-clipping
//   - normalize_db == 0.0 still lands on exactly 0 dBFS (not pulled to ~0.988)
//   - no options at all is a genuine no-op
// and the streaming split added on 2026-10-17: volume applied delta by delta
// equals volume applied to the whole signal, normalize_db is left out of it.

#include "engine/framework/runtime/post_process.h"

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <string>
#include <utility>
#include <vector>

namespace {

using engine::framework::runtime::AudioPostProcessOptions;
using engine::framework::runtime::apply_audio_post_process;
using engine::framework::runtime::audio_post_process_is_noop;
using engine::framework::runtime::streaming_delta_post_process_options;
using engine::runtime::AudioBuffer;

int g_failures = 0;

void check(bool condition, const std::string & what) {
    if (!condition) {
        std::cerr << "FAIL: " << what << "\n";
        ++g_failures;
    }
}

void check_close(float actual, float expected, float tolerance, const std::string & what) {
    if (!(std::fabs(actual - expected) <= tolerance)) {
        std::cerr << "FAIL: " << what << " (expected " << expected << " +/- " << tolerance
                  << ", got " << actual << ")\n";
        ++g_failures;
    }
}

AudioBuffer make_buffer(std::vector<float> samples) {
    AudioBuffer audio;
    audio.sample_rate = 48000;
    audio.channels = 1;
    audio.samples = std::move(samples);
    return audio;
}

float peak_of(const AudioBuffer & audio) {
    float peak = 0.0F;
    for (const float sample : audio.samples) {
        peak = std::max(peak, std::fabs(sample));
    }
    return peak;
}

// Mirrors the soft knee in post_process.cpp so the expectations below stay
// readable rather than being magic constants.
float soft_limit(float value) {
    constexpr float kThreshold = 0.95F;
    constexpr float kRange = 0.05F;
    const float magnitude = std::fabs(value);
    if (magnitude <= kThreshold) {
        return value;
    }
    const float sign = value >= 0.0F ? 1.0F : -1.0F;
    return sign * (kThreshold + kRange * std::tanh((magnitude - kThreshold) / kRange));
}

void test_no_options_is_a_noop() {
    // A peak above the soft knee must survive untouched when the caller asked
    // for nothing: the limiter is part of the gain stage, not of every request.
    const std::vector<float> original = {0.0F, 0.5F, -0.99F, 0.97F};
    AudioBuffer audio = make_buffer(original);
    apply_audio_post_process(audio, AudioPostProcessOptions{});
    check(audio.samples == original, "no options leaves the samples untouched");
}

void test_normalize_to_negative_db() {
    AudioBuffer audio = make_buffer({0.25F, -0.5F, 0.125F});
    AudioPostProcessOptions options;
    options.normalize_db = -6.0F;
    apply_audio_post_process(audio, options);
    check_close(peak_of(audio), std::pow(10.0F, -6.0F / 20.0F), 1e-6F,
                "normalize_db=-6 reaches -6 dBFS");
}

void test_normalize_to_zero_db_is_exact() {
    AudioBuffer audio = make_buffer({0.25F, -0.5F, 0.125F});
    AudioPostProcessOptions options;
    options.normalize_db = 0.0F;
    apply_audio_post_process(audio, options);
    // Must be 1.0 exactly. Running the soft knee here would give ~0.988 and
    // silently undo the fix that made normalize_db=0.0 mean full scale.
    check_close(peak_of(audio), 1.0F, 1e-6F, "normalize_db=0 reaches exactly 0 dBFS");
}

void test_normalize_above_zero_db_is_limited_not_clipped() {
    AudioBuffer audio = make_buffer({0.5F, -0.25F, 0.1F});
    AudioPostProcessOptions options;
    options.normalize_db = 6.0F;
    apply_audio_post_process(audio, options);

    for (const float sample : audio.samples) {
        check(std::fabs(sample) <= 1.0F,
              "normalize_db>0 keeps every sample inside +/-1.0");
    }
    // The loudest sample normalises to 10^(6/20) ~= 1.995 and is then squashed
    // by the knee; a hard clip would have left it at exactly 1.0.
    const float scale = std::pow(10.0F, 6.0F / 20.0F) / 0.5F;
    check_close(audio.samples[0], soft_limit(0.5F * scale), 1e-6F,
                "normalize_db>0 applies the soft limiter");
    check_close(audio.samples[2], soft_limit(0.1F * scale), 1e-6F,
                "samples below the knee scale linearly");
}

void test_volume_scales_and_limits() {
    AudioBuffer audio = make_buffer({0.4F, -0.2F});
    AudioPostProcessOptions options;
    options.volume = 0.5F;
    apply_audio_post_process(audio, options);
    check_close(audio.samples[0], 0.2F, 1e-6F, "volume=0.5 halves the signal");
    check_close(audio.samples[1], -0.1F, 1e-6F, "volume=0.5 halves negative samples");

    AudioBuffer loud = make_buffer({0.8F});
    AudioPostProcessOptions boost;
    boost.volume = 2.0F;
    apply_audio_post_process(loud, boost);
    check_close(loud.samples[0], soft_limit(1.6F), 1e-6F,
                "volume>1 goes through the soft limiter");
    check(loud.samples[0] <= 1.0F, "volume>1 stays inside +/-1.0");
}

void test_volume_zero_and_negative_mute() {
    for (const float volume : {0.0F, -1.0F}) {
        AudioBuffer audio = make_buffer({0.4F, -0.9F, 0.75F});
        AudioPostProcessOptions options;
        options.volume = volume;
        apply_audio_post_process(audio, options);
        for (const float sample : audio.samples) {
            check(sample == 0.0F, "volume<=0 mutes rather than passing audio through");
        }
    }
}

void test_mute_wins_over_normalization() {
    AudioBuffer audio = make_buffer({0.4F, -0.9F});
    AudioPostProcessOptions options;
    options.normalize_db = -3.0F;
    options.volume = 0.0F;
    apply_audio_post_process(audio, options);
    check(peak_of(audio) == 0.0F, "normalize_db then volume=0 still ends up silent");
}

void test_empty_and_silent_buffers() {
    AudioBuffer empty = make_buffer({});
    AudioPostProcessOptions options;
    options.normalize_db = -6.0F;
    apply_audio_post_process(empty, options);
    check(empty.samples.empty(), "an empty buffer stays empty");

    // Normalising pure silence must not divide by the zero peak.
    AudioBuffer silent = make_buffer({0.0F, 0.0F, 0.0F});
    apply_audio_post_process(silent, options);
    for (const float sample : silent.samples) {
        check(std::isfinite(sample) && sample == 0.0F, "silence normalises to silence");
    }
}

void test_streaming_delta_options_drop_only_normalization() {
    AudioPostProcessOptions options;
    options.normalize_db = -0.1F;
    options.volume = 0.8F;
    const auto delta = streaming_delta_post_process_options(options);
    check(std::isnan(delta.normalize_db), "delta options drop normalize_db");
    check(delta.volume == 0.8F, "delta options keep volume");

    AudioPostProcessOptions normalize_only;
    normalize_only.normalize_db = -0.1F;
    check(!audio_post_process_is_noop(normalize_only), "normalize_db alone is not a no-op");
    check(audio_post_process_is_noop(streaming_delta_post_process_options(normalize_only)),
          "normalize_db alone leaves nothing to apply per delta");
    check(audio_post_process_is_noop(AudioPostProcessOptions{}), "no options is a no-op");
}

void test_volume_per_delta_matches_whole_signal() {
    // Includes samples past the soft knee once boosted, so the limiter is covered too.
    const std::vector<float> samples = {0.1F, -0.45F, 0.6F, -0.2F, 0.9F, 0.05F, -0.7F};
    for (const float volume : {0.8F, 1.5F, 0.0F}) {
        AudioPostProcessOptions options;
        options.volume = volume;
        AudioBuffer whole = make_buffer(samples);
        apply_audio_post_process(whole, options);

        std::vector<float> joined;
        for (const auto & range : {std::pair<size_t, size_t>{0, 3}, {3, 4}, {4, 7}}) {
            engine::runtime::StreamEvent event;
            event.audio_output = make_buffer(
                std::vector<float>(samples.begin() + range.first, samples.begin() + range.second));
            apply_audio_post_process(event, streaming_delta_post_process_options(options));
            joined.insert(joined.end(), event.audio_output->samples.begin(), event.audio_output->samples.end());
        }
        check(joined == whole.samples, "volume per delta equals volume on the whole signal");
    }
}

void test_result_and_event_overloads_cover_named_outputs() {
    AudioPostProcessOptions options;
    options.volume = 0.5F;

    engine::runtime::TaskResult result;
    result.audio_output = make_buffer({0.4F});
    result.named_audio_outputs.push_back({"vocals", make_buffer({0.2F})});
    apply_audio_post_process(result, options);
    check_close(result.audio_output->samples[0], 0.2F, 1e-6F, "result audio_output is processed");
    check_close(result.named_audio_outputs[0].audio.samples[0], 0.1F, 1e-6F,
                "result named outputs are processed");

    engine::runtime::StreamEvent event;
    event.named_audio_outputs.push_back({"vocals", make_buffer({0.6F})});
    apply_audio_post_process(event, options);
    check(!event.audio_output.has_value(), "an event without audio_output stays without it");
    check_close(event.named_audio_outputs[0].audio.samples[0], 0.3F, 1e-6F,
                "event named outputs are processed");
}

}  // namespace

int main() {
    test_no_options_is_a_noop();
    test_normalize_to_negative_db();
    test_normalize_to_zero_db_is_exact();
    test_normalize_above_zero_db_is_limited_not_clipped();
    test_volume_scales_and_limits();
    test_volume_zero_and_negative_mute();
    test_mute_wins_over_normalization();
    test_empty_and_silent_buffers();
    test_streaming_delta_options_drop_only_normalization();
    test_volume_per_delta_matches_whole_signal();
    test_result_and_event_overloads_cover_named_outputs();

    if (g_failures != 0) {
        std::cerr << g_failures << " check(s) failed\n";
        return EXIT_FAILURE;
    }
    std::cout << "audio_post_process_test: all checks passed\n";
    return EXIT_SUCCESS;
}
