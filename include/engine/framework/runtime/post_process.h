#pragma once

#include "engine/framework/runtime/session.h"

#include <limits>
#include <string>
#include <unordered_map>

namespace engine::framework::runtime {

using engine::runtime::AudioBuffer;

struct AudioPostProcessOptions {
  float normalize_db = std::numeric_limits<float>::quiet_NaN(); // NaN = disabled (no normalization); any finite value enables Peak Normalization to that dBFS (e.g. -1.0f, 0.0f)
  float volume = 1.0f;       // != 1.0f enables Volume Gain scaling (with Soft-Limiter)
};

void apply_audio_post_process(AudioBuffer &audio, const AudioPostProcessOptions &options);

// Applies `options` to every audio buffer a result or a stream event carries
// (audio_output and each of named_audio_outputs).
void apply_audio_post_process(engine::runtime::TaskResult &result, const AudioPostProcessOptions &options);
void apply_audio_post_process(engine::runtime::StreamEvent &event, const AudioPostProcessOptions &options);

// True when apply_audio_post_process would leave every sample as it is.
bool audio_post_process_is_noop(const AudioPostProcessOptions &options);

// The part of `options` that can be applied to each delta of a stream on its
// own. volume and the limiter behind it work sample by sample, so applying them
// delta by delta gives the same samples as applying them to the whole signal.
// normalize_db needs the peak of the whole signal, which is not known until the
// audio has already been sent, so it is dropped.
AudioPostProcessOptions streaming_delta_post_process_options(const AudioPostProcessOptions &options);

// Reads normalize_db / volume out of a request option map and removes them.
//
// These are output-stage options handled by the CLI and the HTTP server, not
// by any model. Since the schema-v1 migration a session rejects every request
// option its model spec does not declare, so leaving them in the map makes the
// request fail with "unknown ... request option". Take them before dispatching.
AudioPostProcessOptions
take_audio_post_process_options(std::unordered_map<std::string, std::string> &options);

} // namespace engine::framework::runtime
