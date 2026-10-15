// Modified by KKTTSPJ, 2026: Irodori-TTS Speaker Inversion support. See docs/irodori_speaker_inversion.md.
#include "execution.h"

#include "engine/framework/runtime/post_process.h"

#include <chrono>
#include <stdexcept>

namespace minitts::app {
namespace {

engine::runtime::AudioBuffer concat_audio_outputs(
    const std::vector<AppRequestResult> & results,
    std::vector<AudioChapter> & chapters) {
    engine::runtime::AudioBuffer merged;
    for (const auto & item : results) {
        if (!item.result.audio_output.has_value()) {
            continue;
        }
        const auto & audio = *item.result.audio_output;
        if (merged.sample_rate == 0) {
            merged.sample_rate = audio.sample_rate;
            merged.channels = audio.channels;
        }
        if (audio.sample_rate != merged.sample_rate || audio.channels != merged.channels) {
            throw std::runtime_error("cannot merge batch audio outputs with different sample rates or channel counts");
        }
        const int64_t start = static_cast<int64_t>(merged.samples.size() / static_cast<size_t>(merged.channels));
        merged.samples.insert(merged.samples.end(), audio.samples.begin(), audio.samples.end());
        const int64_t end = static_cast<int64_t>(merged.samples.size() / static_cast<size_t>(merged.channels));
        chapters.push_back(AudioChapter{item.id, start, end});
    }
    if (merged.sample_rate == 0) {
        throw std::runtime_error("batch audio merge requested but no request produced a primary audio output");
    }
    return merged;
}

}  // namespace

AudioMergeMode parse_audio_merge_mode(const std::string & value) {
    if (value == "none") {
        return AudioMergeMode::None;
    }
    if (value == "concat") {
        return AudioMergeMode::Concat;
    }
    throw std::runtime_error("--batch-merge-audio must be none or concat");
}

AppBatchResult run_offline_batch(
    engine::runtime::IVoiceTaskSession & session,
    engine::runtime::IOfflineVoiceTaskSession & offline,
    const AppBatchRequest & batch,
    AudioMergeMode audio_merge_mode,
    const std::function<void(size_t, const AppRequestResult &)> & on_result) {
    if (batch.requests.empty()) {
        throw std::runtime_error("offline batch requires at least one request");
    }
    using Clock = std::chrono::steady_clock;
    const auto to_ms = [](Clock::duration d) {
        return std::chrono::duration<double, std::milli>(d).count();
    };
    const auto session_start = Clock::now();

    const auto prepare_start = Clock::now();
    // normalize_db / volume belong to the application, not to the model: a
    // schema-v1 session rejects request options its spec does not declare, so
    // they come out of each request before the session sees it (as in the
    // single-request path) and are applied to the result afterwards.
    auto prepare_request = batch.requests.front().request;
    (void) engine::framework::runtime::take_audio_post_process_options(prepare_request.options);
    session.prepare(engine::runtime::build_preparation_request(prepare_request));
    AppBatchResult out;
    out.prepare_ms = to_ms(Clock::now() - prepare_start);
    out.results.reserve(batch.requests.size());
    for (const auto & item : batch.requests) {
        const auto run_start = Clock::now();
        auto request = item.request;
        const auto post_opts =
            engine::framework::runtime::take_audio_post_process_options(request.options);
        auto result = offline.run(request);
        if (result.audio_output.has_value()) {
            engine::framework::runtime::apply_audio_post_process(*result.audio_output, post_opts);
        }
        for (auto & named : result.named_audio_outputs) {
            engine::framework::runtime::apply_audio_post_process(named.audio, post_opts);
        }
        const double wall_ms = to_ms(Clock::now() - run_start);
        out.results.push_back(AppRequestResult{
            item.id,
            std::move(result),
            wall_ms,
        });
        if (on_result) {
            on_result(out.results.size() - 1, out.results.back());
        }
    }
    out.session_wall_ms = to_ms(Clock::now() - session_start);
    if (audio_merge_mode == AudioMergeMode::Concat) {
        out.merged_audio = concat_audio_outputs(out.results, out.chapters);
    }
    return out;
}

}  // namespace minitts::app
