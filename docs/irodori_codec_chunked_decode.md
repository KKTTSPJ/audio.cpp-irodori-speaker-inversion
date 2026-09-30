# Irodori-TTS: chunked codec encode/decode (bounded peak memory)

[English](#english) | [日本語](#日本語)

---

## English

This fork adds session options to Irodori-TTS that make the DACVAE codec
process audio in fixed-size windows:

- **decode**: turning the generated latent into a waveform
- **encode**: turning a reference WAV into a latent (only when a reference WAV
  is used)

Without the options, the memory both steps need grows with the length of the
audio, and a long request can use several GB more than a short one. With them,
short and long requests, with or without a reference WAV, peak at about the
same level.

The options are off by default, so nothing changes unless you set them.

### Where the memory goes

Buffer sizes of each stage's compute graph, measured with Irodori-TTS v4
(GGUF Q8_0), 48 steps:

| Request | Audio | Condition encoder | Generation (largest graph) | **Reference encode** | **Codec decode** |
|---|---|---|---|---|---|
| Short text, speaker embedding | 6.6 s | 54 MiB | 299 MiB | — | **1,167 MiB** |
| Long text, speaker embedding | 25.8 s | 54 MiB | 299 MiB | — | **4,542 MiB** |
| Short text, reference WAV (34.7 s) | 7.1 s | 62 MiB | 378 MiB | **3,713 MiB** | 1,245 MiB |
| Short text, no reference | 6.9 s | 54 MiB | 196 MiB | — | 1,209 MiB |

Each codec step runs as one graph over the whole audio. The decode needs about
**176 MiB per second of output**, and the reference encode about **107 MiB per
second of reference audio**. audio.cpp encodes the whole reference WAV without
trimming it. The model weights stay resident at about 1.3 GB. Everything else
is small, so these two steps set the peak of any request longer than a few
seconds.

Quantizing the model weights further (for example to 4 bits) reduces the
resident part only, by at most a few hundred MB. It does not touch the part
that grows with the audio length.

### Options

| Option | Default | Meaning |
|---|---|---|
| `irodori_tts.codec_decode_chunk_steps` | `0` (off) | Decode the latent in windows of this many latent frames (25 frames = 1 second). `0` decodes the whole sequence at once. |
| `irodori_tts.codec_decode_overlap_steps` | `16` | Latent frames of context decoded on each side of a window and then discarded. |
| `irodori_tts.codec_encode_chunk_steps` | `0` (off) | Encode a reference WAV in windows of this many latent frames (1,920 samples at 48 kHz each). `0` encodes the whole reference at once. |
| `irodori_tts.codec_encode_overlap_steps` | `16` | Latent frames of reference audio encoded as context on each side of a window and then discarded. |

**Recommended:** `codec_decode_chunk_steps=100` and
`codec_encode_chunk_steps=100` (4 seconds each), with the default overlaps.
Shorter windows (for example `50`) save little more and are slower. The two
options are independent; if you only use speaker embeddings, the encode option
has no effect.

Server config (`session_options` of the model):

```json
"session_options": {
  "irodori_tts.codec_decode_chunk_steps": "100",
  "irodori_tts.codec_encode_chunk_steps": "100"
}
```

CLI:

```bash
audiocpp_cli ... --session-option irodori_tts.codec_decode_chunk_steps=100 --session-option irodori_tts.codec_encode_chunk_steps=100
```

The options work with existing GGUF packages; their embedded model spec does
not list them, and the session accepts them anyway.

### How it works

The codec's encoder and decoder consist of convolutions, Snake activations
and a final tanh. Nothing in them looks further than a few frames: an output
sample of the decoder depends on about ±8 latent frames, and a latent frame of
the encoder on about ±6 frames (0.23 s) of audio.

- The audio or latent is cut into chunks of `chunk_steps` frames. Each chunk
  is processed together with `overlap_steps` frames of real context on both
  sides, and the context part of the output is discarded.
- Every window has the same size, so one graph is built once and reused.
  Windows at the start and end are shifted inward instead of being shortened,
  so the true edges of the audio keep the same zero padding as a
  whole-sequence pass.
- Audio shorter than one window (`chunk_steps + 2 × overlap_steps` frames:
  5.28 seconds with the recommended values) is processed in one piece exactly
  as before.
- A reference is encoded once and then cached, so encode chunking only
  affects the first request with that reference.

### Measurements

Windows 10, RTX 5060 Ti 16 GB, Irodori-TTS v4 (GGUF Q8_0), 48 steps. GPU peak
is measured with nvidia-smi and given over the GPU usage before the server
started (it includes the resident model).

Speaker embedding (no reference encode):

| Setting | Short text (6.6 s) | Long text (25.8 s) | Generation time (short / long) |
|---|---|---|---|
| Default | 2,645 MiB | 6,207 MiB | 1.21–1.35 s / 2.98–3.19 s |
| `codec_decode_chunk_steps=100` | 2,405 MiB | **2,415–2,427 MiB** | 1.32–1.42 s / 3.18–3.42 s |
| `decode_chunk_steps=100` + `codec_weight_type=f16` | 1,963–1,981 MiB | 2,079–2,081 MiB | 1.27–1.39 s / 3.30 s |
| `decode_chunk_steps=50` + `codec_weight_type=f16` | 1,911–1,963 MiB | 2,061–2,065 MiB | 1.34–1.50 s / 3.48–3.51 s |

Reference WAV of 34.7 s, short text, first request (includes the encode):

| Setting | GPU peak | Generation time |
|---|---|---|
| Default | 5,095–5,164 MiB | 2.06–2.10 s |
| `codec_encode_chunk_steps=100` | 2,763 MiB | 2.20 s |
| `codec_encode_chunk_steps=100` + `codec_decode_chunk_steps=100` | **2,409–2,419 MiB** | 2.27–2.44 s |

- With both options, every case above peaks at about 2.4 GB. Generation takes
  about 4–7% longer.
- `irodori_tts.codec_weight_type=f16` is an existing upstream option. The codec
  weights are rebuilt in F32 at load time whatever the GGUF stores, so this
  option halves them (and the codec's im2col buffers) and lowers both the
  resident size and the peak. It is independent of chunking.

### Output difference

- **Default:** bit-identical to the build without this change.
- **Chunked decode, CPU backend:** at most 1 LSB (16-bit) different from the
  whole-sequence decode; with `chunk_steps=50` bit-identical.
- **Chunked decode, CUDA backend:** SNR 67 dB against the whole-sequence
  decode, with the difference spread evenly over the audio rather than at
  chunk boundaries. The GPU matrix multiply picks a different summation order
  for a different matrix size; repeated runs of the same setting give
  identical output.
- **Chunked encode:** on the CPU backend the reference latent is bit-identical
  to the whole encode; on CUDA it differs by 1.5 × 10⁻⁴ (relative), again
  evenly. For comparison, the CPU and CUDA backends already differ by
  1.4 × 10⁻² on the same reference. The final waveform nevertheless differs
  clearly (SNR about 16 dB): the sampler turns any change of the speaker
  condition, however small, into a different realisation of the same voice.
  Adding noise of the same size (1.5 × 10⁻⁴) to a speaker embedding gives the
  same 16 dB.
- **Overlap matters:** with `overlap_steps=4` the decode differs by up to
  537 LSB, and with `0` the chunk boundaries produce audible clicks. Keep the
  default 16.
- In a listening test, the chunked decode could not be told apart from the
  default, even from the phase-inverted difference. With chunked encode the
  phase-inverted difference is clearly audible (as it is for any change of the
  speaker condition), but the outputs heard on their own sounded the same.
  The difference was judged about as large as that of
  `codec_weight_type=f16`, or slightly larger, and far smaller than switching
  the reference or the speaker embedding.

### Limitations

- Values are measured with Irodori-TTS v4 Small. v4.1 Small and v4.1 Anime
  share the architecture and codec, so the same applies; other versions were
  not measured.

---

## 日本語

このフォークは Irodori-TTS にセッションオプションを追加する。DACVAE コーデック
が音声を固定長の区間に区切って処理するようになる。対象は次の 2 つ。

- **デコード**: 生成した潜在表現を波形に戻す処理
- **エンコード**: 参照 WAV を潜在表現に変える処理（参照 WAV を使うときだけ）

オプションを使わない場合、どちらも必要なメモリが音声の長さに比例して増え、長い
リクエストは短いものより数 GB 多く使うことがある。使えば、短文・長文、参照 WAV
の有無にかかわらず、ピークはほぼ同じ水準になる。

既定では無効なので、設定しない限り動作は変わらない。

### メモリの内訳

各段階の計算グラフの作業領域（Irodori-TTS v4、GGUF Q8_0、48 ステップ）:

| リクエスト | 音声の長さ | 条件エンコーダー | 生成（最大のグラフ） | **参照のエンコード** | **コーデックのデコード** |
|---|---|---|---|---|---|
| 短文・話者埋め込み | 6.6 秒 | 54 MiB | 299 MiB | ― | **1,167 MiB** |
| 長文・話者埋め込み | 25.8 秒 | 54 MiB | 299 MiB | ― | **4,542 MiB** |
| 短文・参照 WAV（34.7 秒） | 7.1 秒 | 62 MiB | 378 MiB | **3,713 MiB** | 1,245 MiB |
| 短文・参照なし | 6.9 秒 | 54 MiB | 196 MiB | ― | 1,209 MiB |

コーデックの処理は、どちらも音声全体を 1 つのグラフで扱う。デコードは**出力 1 秒
あたり約 176 MiB**、参照のエンコードは**参照音声 1 秒あたり約 107 MiB** を使う。
audio.cpp は参照 WAV を切り詰めずに全体をエンコードする。モデルの重みは約 1.3 GB
が常駐する。それ以外は小さいので、数秒を超える音声ではこの 2 つがピークを決める。

モデルの重みをさらに量子化しても（たとえば 4-bit）、減るのは常駐分だけで、
多くても数百 MB にとどまる。音声の長さに比例して増える部分は変わらない。

### オプション

| オプション | 既定 | 意味 |
|---|---|---|
| `irodori_tts.codec_decode_chunk_steps` | `0`（無効） | 潜在表現をこのフレーム数ずつ区切ってデコードする（25 フレーム＝1 秒）。`0` は系列全体を一度にデコードする。 |
| `irodori_tts.codec_decode_overlap_steps` | `16` | 各区間の前後に付けて一緒にデコードし、出力から捨てる文脈のフレーム数。 |
| `irodori_tts.codec_encode_chunk_steps` | `0`（無効） | 参照 WAV をこのフレーム数ずつ区切ってエンコードする（1 フレーム＝48 kHz で 1,920 サンプル）。`0` は参照全体を一度にエンコードする。 |
| `irodori_tts.codec_encode_overlap_steps` | `16` | 各区間の前後に付けて一緒にエンコードし、結果から捨てる参照音声のフレーム数。 |

**推奨:** `codec_decode_chunk_steps=100` と `codec_encode_chunk_steps=100`
（どちらも 4 秒）、重なりは既定のまま。もっと短くしても（たとえば `50`）ほとんど
減らず、遅くなる。2 つは独立していて、話者埋め込みだけを使うならエンコード側の
オプションは効果がない。

サーバー設定（モデルの `session_options`）:

```json
"session_options": {
  "irodori_tts.codec_decode_chunk_steps": "100",
  "irodori_tts.codec_encode_chunk_steps": "100"
}
```

CLI:

```bash
audiocpp_cli ... --session-option irodori_tts.codec_decode_chunk_steps=100 --session-option irodori_tts.codec_encode_chunk_steps=100
```

既存の GGUF パッケージでも使える。埋め込まれたモデル仕様には載っていないが、
セッションは受け付ける。

### 仕組み

コーデックのエンコーダーとデコーダーは、畳み込み、Snake 活性化、最後の tanh
だけでできている。どれも数フレーム先までしか見ない。デコーダーの出力の 1 点が
依存するのは前後約 8 潜在フレーム、エンコーダーの潜在の 1 フレームが依存するのは
前後約 6 フレーム分（0.23 秒）の音声に限られる。

- 音声または潜在表現を `chunk_steps` フレームずつに区切り、各区間を前後
  `overlap_steps` フレームの実データと一緒に処理して、前後の分は結果から捨てる。
- 区間の大きさはすべて同じなので、グラフは 1 回作って使い回す。先頭と末尾の区間は
  短くせずに内側へずらすので、音声の本当の端は、一括処理と同じゼロ詰めのままになる。
- 1 区間（`chunk_steps + 2 × overlap_steps` フレーム。推奨値で 5.28 秒）より短い
  音声は、これまでどおり一括で処理する。
- 参照のエンコード結果はキャッシュされるので、エンコードの区切りが効くのは、その
  参照を使う最初のリクエストだけ。

### 測定結果

Windows 10、RTX 5060 Ti 16 GB、Irodori-TTS v4（GGUF Q8_0）、48 ステップ。GPU の
ピークは nvidia-smi で測り、サーバー起動前の GPU 使用量との差で示す（常駐する
モデルを含む）。

話者埋め込み（参照のエンコードなし）:

| 設定 | 短文（6.6 秒） | 長文（25.8 秒） | 生成時間（短文 / 長文） |
|---|---|---|---|
| 既定 | 2,645 MiB | 6,207 MiB | 1.21〜1.35 秒 / 2.98〜3.19 秒 |
| `codec_decode_chunk_steps=100` | 2,405 MiB | **2,415〜2,427 MiB** | 1.32〜1.42 秒 / 3.18〜3.42 秒 |
| `decode_chunk_steps=100` ＋ `codec_weight_type=f16` | 1,963〜1,981 MiB | 2,079〜2,081 MiB | 1.27〜1.39 秒 / 3.30 秒 |
| `decode_chunk_steps=50` ＋ `codec_weight_type=f16` | 1,911〜1,963 MiB | 2,061〜2,065 MiB | 1.34〜1.50 秒 / 3.48〜3.51 秒 |

参照 WAV（34.7 秒）・短文・最初のリクエスト（エンコードを含む）:

| 設定 | GPU のピーク | 生成時間 |
|---|---|---|
| 既定 | 5,095〜5,164 MiB | 2.06〜2.10 秒 |
| `codec_encode_chunk_steps=100` | 2,763 MiB | 2.20 秒 |
| `codec_encode_chunk_steps=100` ＋ `codec_decode_chunk_steps=100` | **2,409〜2,419 MiB** | 2.27〜2.44 秒 |

- 両方のオプションを使うと、上のどのケースもピークは約 2.4 GB になる。生成時間は
  約 4〜7% 延びる。
- `irodori_tts.codec_weight_type=f16` は上流に元からあるオプション。コーデックの
  重みは GGUF の型にかかわらず読み込み時に F32 で作り直されるので、このオプション
  で重み（とコーデックの im2col の作業領域）が半分になり、常駐分とピークの両方が
  下がる。区切りとは独立に使える。

### 出力の違い

- **既定:** この変更を入れる前のビルドとビット単位で一致する。
- **デコードの区切り・CPU バックエンド:** 一括デコードとの差は最大 1 LSB（16 bit）。
  `chunk_steps=50` ではビット単位で一致した。
- **デコードの区切り・CUDA バックエンド:** 一括デコードに対して SNR 67 dB。差は
  区間の境目ではなく音声全体に均一に出る。GPU の行列積が行列の大きさに応じて加算
  の順序を変えるためで、同じ設定を繰り返せば出力は毎回同じ。
- **エンコードの区切り:** CPU バックエンドでは参照の潜在表現が一括エンコードと
  ビット単位で一致する。CUDA では相対 1.5 × 10⁻⁴ の差が均一に出る。比較として、
  同じ参照でも CPU と CUDA の結果は元から相対 1.4 × 10⁻² 違う。それでも最終的な
  波形ははっきり変わる（SNR 約 16 dB）。生成の過程は、話者の条件がどれほど小さく
  変わっても、同じ声の別の揺らぎの波形を作るからである。話者埋め込みに同じ大きさ
  （1.5 × 10⁻⁴）のノイズを足しても、同じく 16 dB になる。
- **重なりは必要:** `overlap_steps=4` ではデコードの差が 537 LSB に達し、`0` では
  区間の境目でプチ音が出る。既定の 16 のまま使う。
- 聞き比べでは、デコードの区切りは逆相で重ねた差分を聞いても既定の出力と区別
  できなかった。エンコードの区切りは、逆相の差分ははっきり聞こえる（話者の条件を
  変えたときは常にそうなる）が、単体で聞くと同じに聞こえた。違いは
  `codec_weight_type=f16` と同程度か、わずかに大きい程度で、参照音声や話者埋め込み
  を替えた場合よりはるかに小さかった。

### 制限

- 数値は Irodori-TTS v4 Small で測った。v4.1 Small と v4.1 Anime は構造とコーデック
  が同じなので同様に当てはまる。それ以外の版は測っていない。
