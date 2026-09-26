#include "engine/framework/runtime/post_process.h"

#include "engine/framework/runtime/options.h"

#include <algorithm>
#include <cmath>
#include <limits>

namespace engine::framework::runtime {

void apply_audio_post_process(AudioBuffer &audio, const AudioPostProcessOptions &options) {
  if (audio.samples.empty()) {
    return;
  }

  // Step 1: Peak Normalization (if normalize_db is finite, i.e. not NaN)
  if (!std::isnan(options.normalize_db)) {
    float max_peak = 0.0f;
    for (float sample : audio.samples) {
      max_peak = std::max(max_peak, std::abs(sample));
    }

    if (max_peak > 1e-7f) {
      // Calculate target amplitude from dBFS: T = 10^(db / 20)
      const float target_amplitude = std::pow(10.0f, options.normalize_db / 20.0f);
      const float scale = target_amplitude / max_peak;

      for (float &sample : audio.samples) {
        sample *= scale;
      }
    }
  }

  // Step 2: Mute. volume <= 0 is an explicit request for silence -- the default
  // is 1.0f and callers only assign when the key is actually present, so a
  // non-positive value never arrives by accident.
  if (options.volume <= 0.0f) {
    std::fill(audio.samples.begin(), audio.samples.end(), 0.0f);
    return;
  }

  // Step 3: Volume Gain & Soft Limiter.
  //
  // The gain stage runs when it would change the signal (volume != 1.0f) or
  // when normalization pushed the peak past full scale (normalize_db > 0).
  // The latter case needs the limiter even at unity gain, because otherwise
  // the out-of-range samples would hard-clip in encode_pcm16_wav.
  //
  // normalize_db <= 0 at unity gain is deliberately left alone: normalize_db
  // == 0.0 means "normalize to exactly 0 dBFS", and running the soft knee
  // over it would pull the peak back down to ~0.988 instead.
  const bool boosted_past_full_scale =
      !std::isnan(options.normalize_db) && options.normalize_db > 0.0f;
  if (options.volume == 1.0f && !boosted_past_full_scale) {
    return;
  }

  const float gain = options.volume;
  constexpr float kSoftKneeThreshold = 0.95f;
  constexpr float kSoftKneeRange = 0.05f;

  for (float &sample : audio.samples) {
    float s = sample * gain;

    // Apply Soft-Limiter smoothing if amplitude exceeds threshold
    const float abs_s = std::abs(s);
    if (abs_s > kSoftKneeThreshold) {
      const float sign = (s >= 0.0f) ? 1.0f : -1.0f;
      const float excess = abs_s - kSoftKneeThreshold;
      // Non-linear compression using std::tanh
      const float compressed = kSoftKneeThreshold + kSoftKneeRange * std::tanh(excess / kSoftKneeRange);
      s = sign * compressed;
    }

    sample = s;
  }
}

AudioPostProcessOptions
take_audio_post_process_options(std::unordered_map<std::string, std::string> &options) {
  AudioPostProcessOptions out;
  if (const auto value = engine::runtime::parse_float_option(options, {"normalize_db"})) {
    out.normalize_db = *value;
  }
  if (const auto value = engine::runtime::parse_float_option(options, {"volume"})) {
    out.volume = *value;
  }
  options.erase("normalize_db");
  options.erase("volume");
  return out;
}

} // namespace engine::framework::runtime
