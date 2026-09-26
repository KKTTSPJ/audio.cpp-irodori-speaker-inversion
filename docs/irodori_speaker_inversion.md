# Irodori-TTS Speaker Inversion support (fork notes)

This branch adds support for **Speaker Inversion embeddings** to the
`irodori_tts` family of audio.cpp: a `.speaker.safetensors` file produced by
[Irodori-TTS](https://github.com/Aratako/Irodori-TTS)'s Speaker Inversion
training can be used in place of reference audio, from both the CLI and the
HTTP server.

Upstream audio.cpp does not implement this (as of v0.8.2). This is a personal
fork, published so that anyone who needs the feature can read the changes or
check out and build this branch. It is not submitted as a pull request.

## Base version

| | |
|---|---|
| Based on | audio.cpp **`release-0.5.1`** (`238ab6a`, "Add Irodori-TTS v4 release support") |
| Newer upstream | **Not ported.** Upstream has since rewritten several of the files this branch touches (`src/models/irodori_tts/session.cpp`, `rf_dit.cpp`, `app/server/runtime.cpp`, `CMakeLists.txt`). A port to a newer base, if it happens, will live on a separate branch; this one stays as it is. |

## What this branch changes

The changes are split into self-contained commits so that each part can be
reviewed or cherry-picked on its own:

1. **build: MSVC / CUDA 12.8 compatibility.** Only needed for Windows builds
   that combine a toolset newer than the CUDA release officially supports
   (tested: MSVC 14.51 with CUDA 12.8). Independent of everything else; skip it
   on other platforms. See [Build notes](#build-notes-windows-msvc--cuda).
2. **fix(irodori): keep condition/context tensors alive.** The condition graph
   gets a backend buffer for its context tensors, and the RF context graph marks
   its text/speaker/caption inputs as outputs so the allocator does not reuse
   them while the KV cache is still being built.
3. **feat(irodori): checkpoints without `duration_predictor` weights.** Those
   weights become optional. When they are missing, automatic duration
   prediction raises a clear error asking for an explicit duration instead of
   reading an uninitialised placeholder tensor.
4. **feat(irodori): Speaker Inversion embeddings.** The core of this branch.
   `VoiceReference` gains `speaker_embedding` / `speaker_embedding_path`; when
   either is set, the Irodori-TTS session injects the embedding directly as the
   speaker condition and skips reference-audio encoding.
5. **feat(cli, server): request fields for embeddings and Irodori-TTS-Server
   compatibility.** See [Usage](#usage) and
   [Request field reference](#request-field-reference).
6. **feat: output post-processing.** Optional peak normalisation
   (`normalize_db`) and gain (`volume`, with a soft limiter), applied by the CLI
   and the server after synthesis, with unit tests.
7. **docs:** this file.
8. **fix: post-processing in `--request-sequence` batches** (added after the
   first publication). Before it, `normalize_db` / `volume` in a
   `--request-sequence` JSON item failed with
   `unknown Irodori-TTS request option: normalize_db`; single CLI requests
   and the server were not affected.

## Embedding file format

- **`.safetensors`** (what Irodori-TTS writes as `*.speaker.safetensors`). The
  tensor is looked up by name, in this order: `speaker_state`,
  `speaker_embedding`, `embedding`, `speaker`. Any other name is an error that
  lists the tensors found. Dtype `F32`, `F16` or `BF16`.
- **Raw little-endian float32** (any other extension, given explicitly via
  `--speaker-embedding` / `ref_embed` / `speaker_embedding`).

The shape must be `[tokens, speaker_dim]`, flattened. The token count is
derived from the element count; a size that is not a multiple of the model's
`speaker_dim` is rejected. For the checkpoints below `speaker_dim` is 768, and
Irodori-TTS embeddings are typically `[16, 768]`.

## Usage

### CLI

```bash
audiocpp_cli --task clon --family irodori_tts \
  --model models/Irodori-TTS-v4-Small-GGUF \
  --backend cuda --language ja \
  --text "本日は晴天なり。今日はよい天気なので、公園まで歩いて出かける予定です。" \
  --speaker-embedding path/to/name.speaker.safetensors \
  --seed 42 --request-option num_inference_steps=48 \
  --out out.wav
```

Additional CLI flags: `--duration-scale <float>` (scales the predicted
duration), and `--request-option normalize_db=<dBFS>` /
`--request-option volume=<gain>` for the post-processing step.

### HTTP server (`POST /v1/audio/speech`)

```bash
curl -s http://127.0.0.1:8080/v1/audio/speech \
  -H "Content-Type: application/json" \
  --data-binary @request.json -o out.wav
```

```json
{
  "model": "irodori-tts",
  "input": "本日は晴天なり。",
  "response_format": "wav",
  "ref_embed": "voices/name.speaker.safetensors",
  "irodori": { "num_steps": 48, "seed": 42 }
}
```

On the server, `ref_embed` (and `voice_ref`, `ref_wav`, `speaker_embedding`,
`voice`) may also be a **bare name**. The server then looks for
`<name>.speaker.safetensors`, `<name>.safetensors` or `<name>.wav`, first under
`voices/` and then directly in the server's working directory. A
`.safetensors` match is used as an embedding and a `.wav` match as reference
audio.

Resolution failures behave differently depending on the field:

- `voice_ref`, `ref_wav`, `ref_embed`, `speaker_embedding` name a file
  outright. If nothing matches, the server answers **HTTP 400**
  (`invalid_request_error`) instead of silently falling back to another voice.
- `voice` keeps upstream's meaning as a fallback: if no file matches, the value
  is passed on as a cached voice id. It also accepts `{"id": "<name>"}`.

## Request field reference

These apply to the server request body and, with the exceptions noted below,
to the CLI's JSON request files (`--request-sequence`). The aliases follow the request format of
[Irodori-TTS-Server](https://github.com/Aratako/Irodori-TTS-Server), so an
existing client can be pointed at audio.cpp with few changes.

| Field | Maps to | Notes |
|---|---|---|
| `ref_embed`, `speaker_embedding` | speaker embedding | path; server also accepts a bare name |
| `voice_ref`, `ref_wav` | reference audio, or embedding if the file ends in `.safetensors` | path; server also accepts a bare name |
| `num_steps` | `num_inference_steps` | |
| `cfg_scale_text` | `text_guidance_scale` | CLI JSON: inside `irodori` only |
| `cfg_scale_speaker` | `speaker_guidance_scale` | CLI JSON: inside `irodori` only |
| `seconds`, `duration_seconds` | `duration_seconds` | |
| `duration_scale` | `duration_scale` | |
| `speed` | `duration_scale = 1 / speed` | OpenAI-style; `speed > 1` is faster |
| `normalize_db` | post-processing | peak-normalise to this dBFS |
| `volume` | post-processing | gain; `<= 0` mutes |
| `input` (CLI JSON only) | text | OpenAI-style alias for the text |

Fields can appear at the top level or inside a nested `"irodori": { ... }`
object. When the same option is given in several places, the precedence is the
same on the CLI and the server:
**top level > nested `irodori` > `options` object.**

Irodori-TTS-Server options that audio.cpp does not implement are **not**
forwarded, so they are silently ignored rather than rejected:
`t_schedule_mode`, `sway_coeff`, `lora_adapter`, `chunking_enabled`,
`chunk_min_chars`.

## Tested with

| | |
|---|---|
| OS / toolchain | Windows 10, MSVC 14.51 (Visual Studio 2026 Build Tools), Windows SDK 10.0.26100 |
| GPU backend | CUDA 12.8, NVIDIA RTX 5060 Ti (`sm_120a`) |
| CPU backend | same machine, unit test `audio_post_process_test` passes |
| Models | Irodori-TTS 500M v3 (safetensors and GGUF Q8_0), Irodori-TTS v4 Small (GGUF Q8_0 and F16) |

**v3 embeddings on v4.** An embedding trained against the 500M v3 checkpoint
loads and runs on v4 Small: both use `speaker_dim = 768`. In a listening test
with the same text, seed and embedding, v3 and v4 sounded clearly different as
models but were equally recognisable as the same speaker. Upstream
Irodori-TTS nevertheless recommends using an embedding with the base model it
was trained on, so retraining on v4 may still improve results.

## Known limitations

- **One reference only.** Irodori-TTS v4 in Python accepts several reference
  clips (`--ref-wavs`) and concatenates their codec latents. audio.cpp takes a
  single reference clip or a single embedding.
- **Linear timestep schedule only.** audio.cpp's sampler implements the same
  linear schedule as Irodori-TTS's default `--t-schedule-mode linear`. Sway
  sampling is not implemented, so output differs from a Python setup that uses
  `sway`. With more steps (48 in our tests) the difference was not audible.
- **Checkpoints without `duration_predictor` weights** need an explicit
  duration (`duration_seconds` / `seconds` / `--duration-seconds`).
- **The server reads local files named in requests.** Like upstream's
  `voice_ref`, the fields above resolve paths on the server's disk. Do not
  expose the server to untrusted clients.
- **`normalize_db > 0` does not reach the requested level.** The soft limiter
  caps samples near full scale. Use `volume` to make audio louder.
- **Irodori-TTS v4 limitation (upstream).** With reference conditioning, v4 may
  occasionally add a short extra phrase at the end of a clip. Upstream
  audio.cpp documents this in `docs/models/irodori_tts.md`, and it reproduces
  in the Python implementation too.

## Build notes (Windows, MSVC + CUDA)

Commit 1 lets nvcc accept an MSVC toolset newer than the CUDA release lists as
supported. In the CUDA branch of `CMakeLists.txt`, for MSVC only, it adds
`-allow-unsupported-compiler` and a few STL compatibility macros, and
force-includes `include/cuda_msvc_compat.h` into every nvcc host pass. It also
compiles C/C++ sources with `/utf-8`.

**Trade-off:** that header defines `static_assert(...)` to nothing **inside
nvcc compilations only** (guarded by `__CUDACC__`). This is needed because the
MSVC STL puts `static_assert(false, ...)` in primary templates, which nvcc's
front end evaluates eagerly. As a consequence, static assertions in CUDA
translation units (ggml's kernels included) are not checked. Host-only code
and CPU builds are unaffected. The header explains this in detail.

The source tree must be at a path without spaces: the force-included
header lives in it, nvcc cannot forward a path containing spaces to the host
compiler, and CMake stops with an error if it finds one.

## License and modifications

audio.cpp is licensed under the Apache License 2.0 (see `LICENSE`). This
branch is distributed under the same license.

As required by section 4(b), every upstream file changed here carries a
one-line notice at the top. The modified files are:

- `CMakeLists.txt`
- `app/cli/main.cpp`, `app/cli/request.cpp`
- `app/server/runtime.cpp`
- `app/workflow/execution.cpp`
- `include/engine/framework/runtime/session.h`
- `include/engine/models/irodori_tts/condition_encoder.h`, `include/engine/models/irodori_tts/types.h`
- `src/models/irodori_tts/assets.cpp`, `condition_encoder.cpp`, `rf_dit.cpp`, `session.cpp`

New files added by this branch: `app/server/invalid_request.h`,
`include/cuda_msvc_compat.h`, `include/engine/framework/runtime/post_process.h`,
`src/framework/runtime/post_process.cpp`,
`tests/unittests/test_audio_post_process.cpp`, and this document.

## Credits

- [audio.cpp](https://github.com/0xShug0/audio.cpp) by ShugoAI LLC, the base of this fork.
- [Irodori-TTS](https://github.com/Aratako/Irodori-TTS) by Aratako, the model family and Speaker Inversion training.
- Development was AI-assisted: the initial implementation with Antigravity (Gemini), and the later
  fixes, tests, review and this curation with Claude. Claude's involvement is also recorded in each
  commit's `Co-Authored-By` trailers.
