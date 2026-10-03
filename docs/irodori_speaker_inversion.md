# Irodori-TTS Speaker Inversion support (fork notes)

This branch adds support for **Speaker Inversion embeddings** to the
`irodori_tts` family of audio.cpp: a `.speaker.safetensors` file produced by
[Irodori-TTS](https://github.com/Aratako/Irodori-TTS)'s Speaker Inversion
training can be used in place of reference audio, from both the CLI and the
HTTP server.

Upstream audio.cpp does not implement this (as of v0.9.0). This is a personal
fork, published so that anyone who needs the feature can read the changes or
check out and build this branch. It is not submitted as a pull request.

## Base version

| | |
|---|---|
| Based on | audio.cpp **`v0.9.0`** (`795c45f`, "Release v0.9.0") |
| Older bases | Branch `irodori-speaker-inversion/v0.8.2` (tags `irodori-speaker-inversion-v0.8.2` to `-r4`) carries the same feature on `v0.8.2`, and `irodori-speaker-inversion/v0.5.1` on `release-0.5.1`. They stay as they are; this branch is a port, not a replacement of their history. See [Port to v0.9.0](#port-to-v090). |

## What this branch changes

The changes are split into self-contained commits so that each part can be
reviewed or cherry-picked on its own:

1. **build: MSVC / CUDA 12.8 compatibility.** Only needed for Windows builds.
   It lets nvcc accept an MSVC toolset newer than the CUDA release officially
   supports (tested: MSVC 14.51 with CUDA 12.8), and compiles C/C++ with
   `/utf-8`. Independent of everything else. See
   [Build notes](#build-notes-windows-msvc--cuda).
2. **fix(irodori): keep condition-encoder context tensors alive.** The
   condition graph gets a backend buffer for its context tensors. As first
   ported this buffer covered the whole graph, costing about 4 GB per request;
   see [Fixes after v0.8.2](#fixes-after-v082).
3. **feat(irodori): checkpoints without `duration_predictor` weights.** Those
   weights become optional. When they are missing, automatic duration
   prediction raises a clear error asking for an explicit duration instead of
   reading an uninitialised placeholder tensor.
4. **feat(irodori): Speaker Inversion embeddings.** The core of this branch.
   `VoiceReference` gains `speaker_embedding` / `speaker_embedding_path`; when
   either is set, the Irodori-TTS session injects the embedding directly as the
   speaker condition and skips reference-audio encoding.
5. **feat(cli, server): request fields for embeddings and Irodori-TTS-Server
   compatibility.** Embeddings can also live in the server's voice library.
   See [Usage](#usage) and [Request field reference](#request-field-reference).
6. **feat: output post-processing.** Optional peak normalisation
   (`normalize_db`) and gain (`volume`, with a soft limiter), applied by the CLI
   (single requests and `--request-sequence` batches) and the server after
   synthesis, with unit tests.
7. **docs:** this file.

### Fixes after v0.8.2

Tag `irodori-speaker-inversion-v0.8.2-r2` adds one fix on top of the commits
above:

- **fix(irodori): back only leftover condition inputs instead of the whole
  graph.** Commit 2 allocated every tensor of the condition-encoder context
  before gallocr ran. That context holds the whole graph, so each request
  reserved about 4.1 GB (Irodori-TTS v4) for intermediates that gallocr would
  otherwise reuse, in VRAM on CUDA and in RAM on the CPU backend. On a 12 GB
  card shared with other programs this ended in `cudaMalloc failed: out of
  memory`. The buffer is now allocated after gallocr and only for inputs the
  graph does not reach. Output is bit-identical; the peak for a short v4
  request drops by about 2.8 GB, and CUDA requests got 3–13% faster
  (RTX 5060 Ti; the gain is largest for short requests).

### Additions in r3

Tag `irodori-speaker-inversion-v0.8.2-r3` adds optional settings on top of r2.
None of them is on by default, so without them the output is identical to r2:

- **feat(irodori): optional chunked codec decode and reference encode.**
  Session options `irodori_tts.codec_decode_chunk_steps` /
  `codec_decode_overlap_steps` and `irodori_tts.codec_encode_chunk_steps` /
  `codec_encode_overlap_steps` make the DACVAE codec process audio in
  fixed-size windows. Otherwise the decode needs about 176 MiB per second of
  output and the reference encode about 107 MiB per second of reference,
  which set the peak of long requests. With both set to 100 the peak for 25.8 s
  of output drops from 6.2 GB to 2.4 GB, and for the first request with a
  34.7 s reference from 5.1 GB to 2.4 GB (v4, RTX 5060 Ti). Off by default.
  Details, measurements and output differences:
  [irodori_codec_chunked_decode.md](irodori_codec_chunked_decode.md).
- **feat(irodori): optional reference length cap.** Session option
  `irodori_tts.max_ref_seconds` (`none` by default, `checkpoint`, or a number
  of seconds) trims a reference WAV before encoding it, as Python Irodori-TTS
  does with the checkpoint's `ref_max_seconds` (120 s for v4, 30 s for v3).
  audio.cpp keeps the whole reference unless it is set. See
  [irodori_codec_chunked_decode.md](irodori_codec_chunked_decode.md#related-reference-length-cap).

### Additions in r4

Tag `irodori-speaker-inversion-v0.8.2-r4` adds the following on top of r3.
Audio output is identical to r3:

- **feat(server): list Speaker Inversion embeddings as voices.** For an
  Irodori-TTS model, `GET /v1/audio/voices` now also returns the voice-library
  embeddings (`<voice_dir>/<name>.speaker.safetensors` or `<name>.safetensors`,
  listed as `<name>`), so the WebUI shows them under "Configured voices" next to
  the WAV references and sends the chosen name as `voice`. Other families still
  list WAV files only.
- **Windows launcher sources** in `packaging/windows/launcher/` (see
  [packaging/windows/README.md](../packaging/windows/README.md)): scripts that
  download the model, create a server config with the memory options on, and
  start the server with the WebUI. Also published as a release asset of r3 and r4.

### Port to v0.9.0

This branch is a port to upstream `v0.9.0`. The commits of the v0.8.2 branch
(up to r4) were cherry-picked onto the `v0.9.0` tag, so they still read as
self-contained changes on top of upstream; the v0.8.2 branch and its tags stay
as they are. Two commits needed a conflict resolution, both keeping both sides:

- `CMakeLists.txt` (commit 6): `post_process.cpp` next to upstream's relocated
  `src/framework/audio/utilities/zipenhancer.cpp`.
- `app/server/runtime.cpp` (commit 5): the `InvalidRequestError` → 400 handler
  comes before upstream's new handler that keeps the CORS header on error
  responses.

Between v0.8.2 and v0.9.0 upstream changed the Irodori-TTS sources only by
renames, and ggml is unchanged. The audio output is bit-identical to
v0.8.2-r4 (see [Tested with](#tested-with)).

What v0.9.0 brings that matters here:

- **Japanese WebUI** (`webui/native/lang/lang_ja.json`). Choose 日本語 as the
  interface language; a browser set to Japanese gets it automatically.
- **Model management in the WebUI** (download, switch and delete model
  packages). Upstream added it before v0.9.0. It needs a build with
  `AUDIOCPP_BUILD_NATIVE_MODEL_MANAGER=ON` (`build_windows.ps1
  -NativeModelManager`) and `--ui-management` or `"ui_management": true`.
  Upstream's release binaries are built with it, and so are this fork's Windows
  binaries from v0.9.0 on (the v0.8.2 packages were not). The manager links
  BoringSSL statically; CMake downloads it at configure time unless
  `AUDIOCPP_BORINGSSL_ARCHIVE` points to a local copy. See also
  [Known limitations](#known-limitations) (WebUI model management).

Added on top of the port:

- **feat(server): `session_option_defaults` in the server config.** A
  top-level object of family-qualified session options, for example
  `"irodori_tts.codec_decode_chunk_steps": "100"`. They are added to every model
  of that family that does not set them itself: the models of the config, and
  the models the WebUI loads through `POST /v1/models/load`. Without it, model
  management loses the memory options (the WebUI loads upstream's catalog
  entries, whose session options are empty for Irodori-TTS, and reloads a
  configured model of the same id that way).

  ```json
  {
    "ui": true,
    "ui_management": true,
    "session_option_defaults": {
      "irodori_tts.codec_decode_chunk_steps": "100",
      "irodori_tts.codec_encode_chunk_steps": "100"
    },
    "models": [ { "id": "irodori-tts", "family": "irodori_tts", "path": "models/Irodori-TTS-v4-Small-GGUF/irodori-tts-v4-small-q8_0.gguf" } ]
  }
  ```

- **feat(server): `audiocpp_server --version` prints `model manager: yes|no`,**
  so a script can tell whether `ui_management` is usable before it starts the
  server.
- **Windows launcher:** for a v0.9.0 package `start_server` turns WebUI model
  management on, writes the memory options as `session_option_defaults`, and
  points the model entry at the `.gguf` file (so another Irodori-TTS package
  that upstream's package list puts into the same folder does not stop it, and
  the path matches what the WebUI loads). Configs from older launchers keep
  working; the launcher prints what to change. A config that turns management
  on for a build without the manager stops with a clear message.

### Differences from the v0.5.1 branch

- Upstream rebuilt the RF sampler's context graph (`ggml_set_input` and
  gallocr), so the v0.5.1 fix that kept its inputs alive is no longer carried.
  This branch still produces bit-identical audio to the v0.5.1 branch for the
  same embedding, text, seed and step count (see [Tested with](#tested-with)).
- The server resolves bare names through upstream's **voice library**
  (`voice_dir` / `--voice-dir`) instead of searching `voices/` and the working
  directory on its own. See [HTTP server](#http-server-post-v1audiospeech).
- `speed` is no longer mapped to `duration_scale`. Upstream now handles
  `speed` itself and rejects it for models whose spec declares neither
  `speed` nor `speaking_rate`, which includes Irodori-TTS. Use
  `duration_scale` instead.
- `normalize_db` / `volume` now also work in `--request-sequence` JSON items.
  On the v0.5.1 branch they fail there with
  `unknown Irodori-TTS request option: normalize_db`.

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

Start the server with a voice library, for example
`audiocpp_server --config server.json --voice-dir voices` (or `"voice_dir"`
in the server config), and put embeddings in it as
`voices/<name>.speaker.safetensors`.

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
  "ref_embed": "name",
  "irodori": { "num_steps": 48, "seed": 42 }
}
```

How the server resolves a speaker:

- **`voice`** names a voice library entry. Upstream looks up
  `<voice_dir>/<name>.wav`; this branch first looks for
  `<name>.speaker.safetensors` and then `<name>.safetensors`, so an embedding
  wins over a same-named WAV. If nothing matches, `voice` keeps upstream's
  meaning and is passed on as a cached voice id. It also accepts
  `{"id": "<name>"}`.
- **`voice_ref`** (a string, or `{"type": "path", "path": ...}`) and the
  aliases **`ref_wav`**, **`ref_embed`**, **`speaker_embedding`** take a path
  relative to the server's working directory. If no such file exists, the
  value is looked up as a voice library entry name (same order as above).
  Library names are bare names: anything containing a path separator or `..`
  is never looked up there.
- A resolved `.safetensors` file is used as an embedding and anything else as
  reference audio (WAV). `voice_ref` also keeps upstream's
  `{"type": "base64", "data": ...}` form for inline reference audio.
- When one of these four fields cannot be resolved, the server answers
  **HTTP 400** (`invalid_request_error`) instead of silently generating with
  another voice.

## Request field reference

These apply to the server request body and, with the exceptions noted below,
to the CLI's JSON request files (`--request-sequence`). The aliases follow the
request format of
[Irodori-TTS-Server](https://github.com/Aratako/Irodori-TTS-Server), so an
existing client can be pointed at audio.cpp with few changes.

| Field | Maps to | Notes |
|---|---|---|
| `ref_embed`, `speaker_embedding` | speaker embedding | path; server also accepts a voice library name |
| `voice_ref`, `ref_wav` | reference audio, or embedding if the file ends in `.safetensors` | path; server also accepts a voice library name |
| `num_steps` | `num_inference_steps` | |
| `cfg_scale_text` | `text_guidance_scale` | CLI JSON: inside `irodori` only |
| `cfg_scale_speaker` | `speaker_guidance_scale` | CLI JSON: inside `irodori` only |
| `seconds`, `duration_seconds` | `duration_seconds` | |
| `duration_scale` | `duration_scale` | `> 1` is slower |
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
`chunk_min_chars`. `speed` is the exception: upstream's server rejects it for
Irodori-TTS (see above).

## Tested with

| | |
|---|---|
| OS / toolchain | Windows 10, MSVC 14.51 (Visual Studio 2026 Build Tools), Windows SDK 10.0.26100 |
| GPU backend | CUDA 12.8, NVIDIA RTX 5060 Ti (`sm_120a`) |
| CPU backend | same machine, unit test `audio_post_process_test` passes |
| Models | Irodori-TTS v4 Small (GGUF Q8_0), Irodori-TTS 500M v3 (GGUF Q8_0) |

With the same embedding, text, seed and step count, the output of this branch
is bit-identical to that of the v0.5.1 branch: on the CPU backend for both
models, and on CUDA for v4 Small (the only one compared there). Reference-audio and
no-reference generation give bit-identical output to upstream v0.8.2 built
with commit 1 only, so the other commits do not change upstream's paths.

**v0.9.0.** Built with the native model manager on the same machine, this
branch gives bit-identical output to v0.8.2-r4: on CUDA for an embedding, a
long text and a reference WAV, with the default options and with the four
memory options; on the CPU backend for two embedding requests.
`audio_post_process_test` passes.

**v3 embeddings on v4.** An embedding trained against the 500M v3 checkpoint
loads and runs on v4 Small: both use `speaker_dim = 768`. In a listening test
on the v0.5.1 branch with the same text, seed and embedding, v3 and v4 sounded
clearly different as models but were equally recognisable as the same speaker.
Upstream Irodori-TTS nevertheless recommends using an embedding with the base
model it was trained on, so retraining on v4 may still improve results.

## Known limitations

- **WebUI model management: session options and the voice list.** With
  `ui_management` on, the WebUI lists upstream's model catalog instead of the
  models in the server config, and loads its choice with the catalog's session
  options, which are empty for Irodori-TTS. The catalog's Irodori-TTS v4.1
  Small entry has the id `irodori-tts`; when the server config uses the same id
  (the Windows launcher does), the WebUI reloads that model with those empty
  options, and API requests for `irodori-tts` then use them too. Put options
  that must survive this, such as the memory options of
  [irodori_codec_chunked_decode.md](irodori_codec_chunked_decode.md), in
  `session_option_defaults` (see [Port to v0.9.0](#port-to-v090)) rather than
  in the model's `session_options`. In this mode the WebUI's voice list offers
  only upstream's demo voices, so voice-library embeddings cannot be picked in
  the WebUI (the API still accepts their names; with `ui_management` off they
  appear under "Configured voices").
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
- **One GGUF per model directory.** A directory is loaded from its GGUF only
  when it holds `model.gguf` or exactly one `*.gguf` (upstream behaviour).
  Upstream's package list (also used by the WebUI's model manager) installs
  the v4.1 Anime GGUF into the same
  `Irodori-TTS-v4-Small-GGUF` directory as the Small one; keep them in separate
  directories, or pass the `.gguf` file itself as `--model`.
- **Irodori-TTS v4 limitation (upstream).** With reference conditioning, v4 may
  occasionally add a short extra phrase at the end of a clip. Upstream
  audio.cpp documents this in `docs/models/irodori_tts.md`, and it reproduces
  in the Python implementation too.

## Build notes (Windows, MSVC + CUDA)

Commit 1 lets nvcc accept an MSVC toolset newer than the CUDA release lists as
supported. In the CUDA branch of `CMakeLists.txt`, for MSVC only, it adds
`-allow-unsupported-compiler` and a few STL compatibility macros, and
force-includes `include/cuda_msvc_compat.h` into every nvcc host pass.

It also compiles all C/C++ sources with `/utf-8`. Upstream adds `/utf-8` to
some targets only; on a Windows system whose code page is not UTF-8 (tested:
Japanese, code page 932), unmodified v0.8.2 stops at
`src/models/moss_transcribe_diarize/runtime.cpp` with
`error C2001: newline in constant`, because MSVC reads the UTF-8 source in the
system code page. This affects CPU builds as well.

**Trade-off:** `cuda_msvc_compat.h` defines `static_assert(...)` to nothing
**inside nvcc compilations only** (guarded by `__CUDACC__`). This is needed
because the MSVC STL puts `static_assert(false, ...)` in primary templates,
which nvcc's front end evaluates eagerly. As a consequence, static assertions
in CUDA translation units (ggml's kernels included) are not checked.
Host-only code and CPU builds are unaffected. The header explains this in
detail.

The source tree must be at a path without spaces: the force-included
header lives in it, nvcc cannot forward a path containing spaces to the host
compiler, and CMake stops with an error if it finds one.

## License and modifications

audio.cpp is licensed under the Apache License 2.0 (see `LICENSE`). This
branch is distributed under the same license.

As required by section 4(b), every upstream file changed here carries a
one-line notice at the top. The modified files are:

- `CMakeLists.txt`
- `README.md` (a note at the top pointing to this fork's documents)
- `app/cli/main.cpp`, `app/cli/request.cpp`
- `app/server/config.cpp`, `app/server/config.h`, `app/server/main.cpp`, `app/server/runtime.cpp`
- `app/workflow/execution.cpp`
- `include/engine/framework/runtime/session.h`
- `include/engine/models/irodori_tts/codec.h`, `include/engine/models/irodori_tts/condition_encoder.h`, `include/engine/models/irodori_tts/types.h`
- `src/models/irodori_tts/assets.cpp`, `codec.cpp`, `condition_encoder.cpp`, `rf_dit.cpp`, `session.cpp`
- `model_specs/irodori_tts.json` (JSON has no comments, so this file carries
  no notice; it declares the chunked encode/decode session options)

New files added by this branch: `app/server/invalid_request.h`,
`include/cuda_msvc_compat.h`, `include/engine/framework/runtime/post_process.h`,
`src/framework/runtime/post_process.cpp`,
`tests/unittests/test_audio_post_process.cpp`,
`docs/irodori_codec_chunked_decode.md`, `packaging/windows/` (launcher), and this document.

## Credits

- [audio.cpp](https://github.com/0xShug0/audio.cpp) by ShugoAI LLC, the base of this fork.
- [Irodori-TTS](https://github.com/Aratako/Irodori-TTS) by Aratako, the model family and Speaker Inversion training.
- Development was AI-assisted: the initial implementation with Antigravity (Gemini), and the later
  fixes, tests, review, curation and the ports to v0.8.2 and v0.9.0 with Claude. Claude's involvement is also
  recorded in each commit's `Co-Authored-By` trailers.
