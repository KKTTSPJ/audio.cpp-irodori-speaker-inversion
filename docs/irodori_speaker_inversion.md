# Irodori-TTS Speaker Inversion support (fork notes)

This branch adds support for **Speaker Inversion embeddings** to the
`irodori_tts` family of audio.cpp: a `.speaker.safetensors` file produced by
[Irodori-TTS](https://github.com/Aratako/Irodori-TTS)'s Speaker Inversion
training can be used in place of reference audio, from both the CLI and the
HTTP server.

Since 2026-10-08 upstream audio.cpp has the core of this itself: four pull
requests from this fork were merged after v0.9.1 and released in **v0.9.2**
(2026-10-15):

- [#829](https://github.com/0xShug0/audio.cpp/pull/829) Speaker Inversion
  embeddings as the speaker condition: request option `speaker_embedding_file`
  (`speaker_embedding_path` before v0.9.2, still accepted), or a voice id
  naming `<model dir>/embeddings/<name>.safetensors`.
- [#832](https://github.com/0xShug0/audio.cpp/pull/832) checkpoints without a
  duration predictor (500M v2).
- [#835](https://github.com/0xShug0/audio.cpp/pull/835) the opt-in chunked codec
  decode and reference encode
  ([irodori_codec_chunked_decode.md](irodori_codec_chunked_decode.md)).
- [#854](https://github.com/0xShug0/audio.cpp/pull/854) the reference length
  cap: references longer than the checkpoint's `ref_max_seconds` are trimmed
  like Python by default, and the request option `reference_duration_sec`
  (`max_ref_sec` before v0.9.2, still accepted) sets another length.

This branch builds on those and keeps what upstream does not have: the
Irodori-TTS-Server compatible request fields and embeddings in the server's
voice library, output post-processing (`normalize_db` / `volume`), the old
session option of the reference length cap (`irodori_tts.max_ref_seconds`,
kept so existing configs still load), `session_option_defaults`, and the
Windows launcher. It is a personal fork, published so that anyone who needs
these can read the changes or check out and build this branch.

## Base version

| | |
|---|---|
| Based on | audio.cpp **`v0.9.2`**, the first release with the merged pull requests above. See [Port to v0.9.2](#port-to-v092). |
| Older bases | The working branch on upstream `main` between v0.9.1 and v0.9.2 was not published; see [Port to upstream main](#port-to-upstream-main-after-v091). Branch `irodori-speaker-inversion/v0.9.0` (tag `irodori-speaker-inversion-v0.9.0`) carries the same feature on `v0.9.0`, with this fork's own implementation of the parts that are now upstream. Branch `irodori-speaker-inversion/v0.8.2` (tags `irodori-speaker-inversion-v0.8.2` to `-r4`) carries the same feature on `v0.8.2`, and `irodori-speaker-inversion/v0.5.1` on `release-0.5.1`. They stay as they are; this branch is a port, not a replacement of their history. See [Port to v0.9.1](#port-to-v091) (not published) and [Port to v0.9.0](#port-to-v090). |

## What this branch changes

The changes are split into self-contained commits so that each part can be
reviewed or cherry-picked on its own:

1. **build: MSVC / CUDA 12.8 compatibility.** Only needed for Windows builds.
   It lets nvcc accept an MSVC toolset newer than the CUDA release officially
   supports (tested: MSVC 14.51 with CUDA 12.8), and compiles C/C++ with
   `/utf-8`. Independent of everything else. See
   [Build notes](#build-notes-windows-msvc--cuda).
2. *(Up to the v0.9.1 branch only:)* **fix(irodori): keep condition-encoder
   context tensors alive**, **feat(irodori): checkpoints without
   `duration_predictor` weights** and **feat(irodori): Speaker Inversion
   embeddings** (the core, which added fields to the framework's
   `VoiceReference`). Upstream now has these as #829 and #832, so this branch
   no longer carries them; see
   [Port to upstream main](#port-to-upstream-main-after-v091).
3. **feat(cli, server): request fields for embeddings and Irodori-TTS-Server
   compatibility.** Embeddings can also live in the server's voice library.
   They reach the model as upstream's `speaker_embedding_file` option.
   See [Usage](#usage) and [Request field reference](#request-field-reference).
4. **feat: output post-processing.** Optional peak normalisation
   (`normalize_db`) and gain (`volume`, with a soft limiter), applied by the CLI
   (single requests and `--request-sequence` batches) and the server after
   synthesis, with unit tests.
5. **docs:** this file.

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

### Port to v0.9.2

This branch is a port to upstream `v0.9.2`. The commits of the working branch
on upstream `main` (see the next section) were cherry-picked onto the `v0.9.2`
tag. Between the two, upstream reorganised its HTTP server (#886, #893, #918,
#919): the request handling of the default runtime and of the experimental
`--parallel-jobs` runtime was unified, and the speech request parsing moved out
of `app/server/runtime.cpp` into `build_speech_request()` in the new
`app/server/server_protocol.cpp`, which both runtimes call. The five commits
that changed `runtime.cpp` were therefore reworked:

- **Request fields and the voice library** (commit 3 and the nested `irodori`
  fix) now live in `server_protocol.cpp`. The 400 answer for a speaker field
  that cannot be resolved uses upstream's new
  `engine::runtime::InvalidRequestError`, which the shared dispatcher already
  maps to 400 `invalid_request_error`; this fork's `app/server/invalid_request.h`
  is gone.
- **Post-processing, the embeddings in the voice list and
  `session_option_defaults` for WebUI-loaded models** go into both
  `runtime.cpp` and `parallel_runtime.cpp`, which upstream still keeps as
  separate copies for model loading and execution.

As a result, **all of this fork's server changes now also apply with
`--parallel-jobs`**, which lifts the old known limitation.

Upstream also renamed request options in v0.9.2 (#875), and still reads the
old names: `speaker_embedding_path` is now `speaker_embedding_file`,
`max_ref_sec` is `reference_duration_sec`, and `instruction` is `instruct`. A
new commit makes this fork's CLI and server set `speaker_embedding_file`. When
they do, they remove a `speaker_embedding_path` from the same request's
`options`: upstream rejects a request whose two names carry different values,
and a resolved speaker field (`voice`, `ref_embed`, ...) has always won over
`options`.

Added on top of the port:

- **feat(cli, server): forward `t_schedule_mode` and `sway_coeff`.** Upstream
  v0.9.2 implements sway sampling (request options `t_schedule_mode`, `linear`
  by default, and `sway_coeff`). The Irodori-TTS-Server compatible fields now
  pass them on like the other aliases, at the top level or inside `irodori`.
  Before, they were dropped.
- **packaging: more models in the Windows launcher.** With WebUI model
  management on, the v0.9.2 WebUI no longer lists the server's voices at all,
  so the launcher now covers what users would otherwise do there.
  `download_model.bat` offers a numbered list: Irodori-TTS v4.1 Small Q8_0 (the
  default), v4.1 Anime, 500M v3, 600M v3 VoiceDesign, Qwen3-ASR 0.6B / 1.7B,
  CrisperWhisper 2.0 (non-commercial license, accepted by typing `agree`),
  MeanVC2, Seed-VC and MioCodec 25Hz 44.1kHz v2 (added after the v0.9.2
  release; the only one of the three that returns 44.1 kHz rather than 16 or
  22.05 kHz). Files go where upstream's model manager puts the same
  packages, except v4.1 Anime: the WebUI names a model after the upstream
  catalog entry it matches, so Anime gets a folder of its own rather than show
  under the name of v4.1 Small. `start_server.bat` adds every downloaded model to
  `server_config.json` (on later runs it appends new ones and keeps a backup),
  with `lazy_load` and `max_loaded_models: 1` once there is more than one, so
  the WebUI switches between them with model management off and the voice
  list intact. The model ids follow upstream's WebUI catalog.
- **packaging: `soxr.dll` in the binary packages.** audio.cpp loads libsoxr at
  run time when it finds it, and several models resample with it (otherwise
  linearly); CrisperWhisper accepts audio other than 16 kHz only with it. The
  packages now include `soxr.dll` built from the unmodified libsoxr 0.1.3
  source (LGPL-2.1-or-later; source and build script attached to the release).
  Irodori-TTS does not use it, so its output is unchanged; MeanVC2 and Seed-VC
  output changes with the better resampling.

What changes for users of this fork:

- **New option names** (above). Old names keep working, so existing clients
  and configs need no change. The compatibility session option
  `irodori_tts.max_ref_seconds` now sets the default for
  `reference_duration_sec`, with the same values as before.
- **Sway sampling.** `t_schedule_mode: "sway"` (with `sway_coeff`, default
  `-1.0`) now changes the output, in `options` and in the compatibility
  fields. The working branch on upstream `main` rejected both options in
  `options` as unknown, and dropped them as compatibility fields.
- **Streaming output** (#881): an Irodori-TTS model configured with
  `"mode": "streaming"` can send audio as it is decoded (request option
  `stream_frames_per_event`). This fork's `normalize_db` / `volume` work on
  such a model too: a WAV request gets both on the whole result, and a
  stream (`stream: true` / `stream_format`) gets `volume` on every audio delta
  but not `normalize_db`; see [Known limitations](#known-limitations).
- **`--parallel-jobs`** carries this fork's server changes (above).

Upstream changed the Irodori-TTS sources between `2209425` and v0.9.2 for the
option normalisation, sway and streaming. With the default `linear` schedule
in offline mode the output is bit-identical to the working branch on upstream
`main` (see [Tested with](#tested-with)).

### Port to upstream main (after v0.9.1)

This working branch was rebuilt on upstream `main` at `2209425`, which
contains the four merged pull requests, before they reached a release tag. It
was not published: its commits are the ones ported to v0.9.2 above. The v0.9.1
working branch was not published either; the v0.9.0 branch was the latest
published one until v0.9.2.

From the v0.9.1 branch:

- **Dropped, because upstream now has them:** the Speaker Inversion core, the
  support for checkpoints without `duration_predictor` weights, the two
  condition-encoder allocation fixes (upstream no longer builds the duration
  inputs that needed them), and the chunked codec decode and encode (#835 is
  the same code, with the same option names and defaults). This fork no
  longer changes `include/engine/framework/runtime/session.h` or any
  Irodori-TTS source except `session.cpp`.
- **Rewritten:** the CLI and server request fields now pass an embedding as
  the `speaker_embedding_path` request option instead of the removed
  `VoiceReference` fields. They resolve paths and the voice library as before.
- **Replaced by upstream's #854:** the reference length cap. Only the
  session option `irodori_tts.max_ref_seconds` remains, as the default for
  upstream's `max_ref_sec` request option, so existing configs still load
  (`checkpoint` or unset: upstream's default; `none` / `0`: whole reference; a
  number: that many seconds). The launcher no longer writes it.
- Everything else (post-processing, voice listing, `session_option_defaults`,
  `--version`, the launcher, the docs) is cherry-picked unchanged.

What changes for users of this fork:

- **Embedding file format** follows upstream (and Python Irodori-TTS): only a
  tensor named `speaker_embedding` is read, and raw float32 files are no
  longer accepted. Files written by Irodori-TTS are unaffected.
- **A checkpoint without a duration predictor** now generates 30 seconds and
  trims the trailing silence when no duration is given, as Python does,
  instead of stopping with an error.
- **Long references are trimmed by default** (over 120 s on v4, over 30 s on
  v3), as in Python and upstream. Configs that set
  `"irodori_tts.max_ref_seconds": "checkpoint"` (the launcher's setting) see no
  change. To keep the whole reference, set the option to `none`, or send
  `max_ref_sec: 0` in the request's `options`.
- **New from upstream:** a voice id that names
  `<model dir>/embeddings/<name>.safetensors` selects that embedding, and
  `speed: 1.0` is accepted (v0.9.1).

The branch was first rebuilt on `c7f5743` (2026-10-09) and again on
`2209425` after #854 (2026-10-10). The second rebuild had one conflict, from
upstream's #844 (input artifacts in server and CLI requests), resolved by
keeping both sides in `app/cli/request.cpp` and `app/server/runtime.cpp`.
Upstream moved `base64.h` to `app/common/` in the same change.

Upstream's #801 (CUDA transpose convolution, merged right after #835) does not
affect Irodori-TTS: its codec takes the `col2im` path on CUDA, not the changed
kernel; outputs and timing were unchanged in a before/after build.

### Port to v0.9.1

This branch is a port to upstream `v0.9.1`. The commits of the v0.9.0 branch
were cherry-picked onto the `v0.9.1` tag; the v0.9.0 branch and its tag stay as
they are. Three commits needed a conflict resolution, all keeping both sides:

- `app/server/runtime.cpp` (commit 5): the `invalid_request.h` include next to
  upstream's new `live_speech_input.h`.
- `CMakeLists.txt` (commit 6): the `audio_post_process_test` registration next
  to upstream's new CrisperWhisper alignment test.
- `app/server/config.h` (`session_option_defaults`): the declaration next to
  upstream's new `load_server_config(path, parallel_jobs)` overload. Both
  overloads go through the same loader, so the defaults apply either way.

Upstream did not change the Irodori-TTS sources between v0.9.0 and v0.9.1, and
its ggml changes are limited to the SSM operators, which Irodori-TTS does not
use. The audio output is bit-identical to v0.9.0 (see
[Tested with](#tested-with)).

What v0.9.1 brings that matters here:

- **`speed: 1.0` is accepted.** Upstream now treats a neutral `speed` like an
  omitted field for every model, so clients that always send the OpenAI
  default no longer fail with Irodori-TTS. Any other value is still rejected;
  use `duration_scale`.
- **An experimental parallel runtime** (`--parallel-jobs`). Up to the working
  branch on upstream `main`, this fork's server changes lived in the default
  runtime only. From v0.9.2 on they apply to both; see
  [Port to v0.9.2](#port-to-v092).

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
- **Windows launcher:** for a v0.9.0 package `start_server` writes the memory
  options as `session_option_defaults` and `"ui_management": false`, and points
  the model entry at the `.gguf` file (so another Irodori-TTS package that
  upstream's package list puts into the same folder does not stop it, and the
  path matches what the WebUI loads). Model management stays off by default so
  that the WebUI keeps listing the voice-library embeddings; switching it to
  `true` is enough to use it, with the memory options kept. Configs from older
  launchers keep working; the launcher prints what to change. A config that
  turns management on for a build without the manager stops with a clear
  message.

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
  `duration_scale` instead. From v0.9.1 on, `speed: 1.0` is accepted and
  ignored.
- `normalize_db` / `volume` now also work in `--request-sequence` JSON items.
  On the v0.5.1 branch they fail there with
  `unknown Irodori-TTS request option: normalize_db`.

## Embedding file format

- **`.safetensors`** as Irodori-TTS writes it (`*.speaker.safetensors`), with one
  tensor named `speaker_embedding` (upstream's loader, as in Python). Dtype
  `F32`, `F16` or `BF16`.

The shape must be `[tokens, speaker_dim]` (or `[1, tokens, speaker_dim]`).
Branches up to v0.9.1 also accepted the tensor names `speaker_state`,
`embedding` and `speaker`, and raw little-endian float32 files.

For the checkpoints below `speaker_dim` is 768, and
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
| `seconds`, `duration_seconds` | `duration_seconds` | upstream reads it as `duration_sec` |
| `duration_scale` | `duration_scale` | `> 1` is slower |
| `t_schedule_mode` | `t_schedule_mode` | `linear` (default) or `sway`; from v0.9.2 |
| `sway_coeff` | `sway_coeff` | default `-1.0`; from v0.9.2 |
| `normalize_db` | post-processing | peak-normalise to this dBFS |
| `volume` | post-processing | gain; `<= 0` mutes |
| `input` (CLI JSON only) | text | OpenAI-style alias for the text |

Fields can appear at the top level or inside a nested `"irodori": { ... }`
object, the speaker fields (`ref_embed`, `speaker_embedding`, `voice_ref`,
`ref_wav`) included. When the same option is given in several places, the
precedence is the same on the CLI and the server:
**top level > nested `irodori` > `options` object.**
Irodori-TTS-Server lets the nested object win instead, so give each field in
one place only. Branches up to v0.9.1 read the speaker fields at the top level
only; inside `irodori` they were ignored and the request ran without a
reference.

Irodori-TTS-Server options that audio.cpp does not implement are **not**
forwarded, so they are silently ignored rather than rejected: `lora_adapter`,
`chunking_enabled`, `chunk_min_chars`. Up to the working branch on upstream
`main`, `t_schedule_mode` and `sway_coeff` were in this list too. `speed` is
the exception: upstream's server rejects it for Irodori-TTS unless it is
`1.0` (see above).

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

**v0.9.1.** Built the same way, this branch gives bit-identical output to
v0.9.0 (and so to v0.8.2-r4) for the same CUDA and CPU requests.
`audio_post_process_test` passes. With `ui_management` on and the memory
options only in `session_option_defaults`, reloading `irodori-tts` through
`POST /v1/models/load` (as the WebUI does) still gives the output of the
configured options.

**Upstream main (`c7f5743`).** Built the same way, with this fork's request
fields now passing embeddings to upstream's loader, the output is bit-identical
to v0.9.0 and v0.9.1 for the same CUDA requests (default and the four memory
options) and CPU requests. The embedding resolves to the same output whether it
is given by path, `voice_ref`, `ref_embed` / `speaker_embedding`, or a voice
library name. `audio_post_process_test` passes, and the WebUI reload check of
`session_option_defaults` gives the same result as before.

**v0.9.2.** Built the same way, the output is bit-identical to the working
branch on upstream `main` (and so to v0.9.0) for the same CUDA requests
(default options, the four memory options, and the production-style config)
and CPU requests, and for the WebUI reload check of `session_option_defaults`,
also with `--parallel-jobs`. The compatibility fields give the same outputs
and the same 400 answers as before, in both server runtimes. The old and new
option names give the same output (`speaker_embedding_path` /
`speaker_embedding_file`, `max_ref_sec` / `reference_duration_sec`), and a
resolved speaker field still wins over an embedding named in `options` under
either name. `t_schedule_mode: "linear"` gives the default output; `sway`
changes it, identically whether it is given in `options`, at the top level or
inside `irodori`, on the server and in the CLI. The Windows launcher passes its
end-to-end check, and the WebUI lists a voice-library embedding under
"Configured voices" and generates with it. `audio_post_process_test` passes.
On a `"mode": "streaming"` model with `stream_frames_per_event: 100` (the
window of `codec_decode_chunk_steps: 100`), a WAV request gives the same
output as the offline model with `normalize_db`, `volume` and both, an SSE or
raw-PCM stream with `volume` gives the same samples, and a stream with
`normalize_db` gives the samples of the request without it, in both server
runtimes (fix of 2026-10-17).
Every model of the launcher's list downloaded, was added to the config, and
answered a request: the Irodori-TTS models generated speech (the same output
with and without `soxr.dll`), the three ASR models transcribed a generated
Japanese sentence correctly, and the VC models converted it.

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
  in the model's `session_options`. In this mode the WebUI does not offer the
  server's voice list (v0.9.0 showed only upstream's demo voices there; from
  v0.9.2 on there is no list, only reference audio files and voices saved in
  the browser), so voice-library embeddings cannot be picked in the WebUI (the
  API still accepts their names; with `ui_management` off they appear under
  "Configured voices").
- **One reference only.** Irodori-TTS v4 in Python accepts several reference
  clips (`--ref-wavs`) and concatenates their codec latents. audio.cpp takes a
  single reference clip or a single embedding.
- **No `normalize_db` on streamed audio.** Peak normalisation needs the peak
  of the whole signal, which is not known while the audio is still being sent.
  A request that streams the audio from a `"mode": "streaming"` model
  (`stream: true` or `stream_format`) is answered without it, and the server
  logs one line saying so; `volume` is still applied to every delta. A WAV
  request on the same model is normalised as in offline mode. (The first v0.9.2
  build passed both options to Irodori-TTS on a streaming model, which rejected
  them as unknown options.)
- **Checkpoints without `duration_predictor` weights** generate 30 seconds and
  trim the trailing silence unless a duration is given (`duration_seconds` /
  `seconds` / `--duration-seconds`); pass one when the length is known.
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
- **`--parallel-jobs` stays experimental upstream.** From v0.9.2 on this
  fork's server changes apply to it (see [Port to v0.9.2](#port-to-v092)),
  but the Windows launcher never passes it.

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
- `app/server/config.cpp`, `app/server/config.h`, `app/server/main.cpp`,
  `app/server/parallel_runtime.cpp`, `app/server/runtime.cpp`, `app/server/server_protocol.cpp`
- `app/workflow/execution.cpp`
- `src/models/irodori_tts/session.cpp` (the `irodori_tts.max_ref_seconds` compatibility option)
- `model_specs/irodori_tts.json` (JSON has no comments, so this file carries
  no notice; it declares the `irodori_tts.max_ref_seconds` session option)

New files added by this branch: `include/cuda_msvc_compat.h`, `include/engine/framework/runtime/post_process.h`,
`src/framework/runtime/post_process.cpp`,
`tests/unittests/test_audio_post_process.cpp`,
`docs/irodori_codec_chunked_decode.md`, `packaging/windows/` (launcher), and this document.

## Credits

- [audio.cpp](https://github.com/0xShug0/audio.cpp) by ShugoAI LLC, the base of this fork.
- [Irodori-TTS](https://github.com/Aratako/Irodori-TTS) by Aratako, the model family and Speaker Inversion training.
- Development was AI-assisted: the initial implementation with Antigravity (Gemini), and the later
  fixes, tests, review, curation, the ports to v0.8.2, v0.9.0, v0.9.1, upstream main and v0.9.2, and the upstream pull requests with Claude. Claude's involvement is also
  recorded in each commit's `Co-Authored-By` trailers.
