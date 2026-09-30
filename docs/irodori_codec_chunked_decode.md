# Irodori-TTS: chunked codec decode (bounded peak memory)

[English](#english) | [日本語](#日本語)

---

## English

This fork adds two session options to Irodori-TTS that make the DACVAE codec
decode the latent in fixed-size windows. Without them, the memory needed to turn
the latent into a waveform grows with the length of the output, and a long
request can use several GB more than a short one. With them, short and long
requests peak at about the same level.

The options are off by default, so nothing changes unless you set them.

### Where the memory goes

Buffer sizes of each stage's compute graph, measured with Irodori-TTS v4
(GGUF Q8_0), 48 steps:

| Request | Audio | Condition encoder | Generation (largest graph) | Reference encode | **Codec decode** |
|---|---|---|---|---|---|
| Short text, speaker embedding | 6.6 s | 54 MiB | 299 MiB | — | **1,167 MiB** |
| Long text, speaker embedding | 25.8 s | 54 MiB | 299 MiB | — | **4,542 MiB** |
| Short text, reference WAV | 7.1 s | 62 MiB | 378 MiB | 3,713 MiB | 1,245 MiB |
| Short text, no reference | 6.9 s | 54 MiB | 196 MiB | — | 1,209 MiB |

The codec decode runs as one graph over the whole sequence and needs about
**176 MiB per second of audio**. The model weights stay resident at about
1.3 GB. Everything else is small, so the decode sets the peak of any request
longer than a few seconds.

Quantizing the model weights further (for example to 4 bits) reduces the
resident part only, by at most a few hundred MB. It does not touch the part
that grows with the audio length.

### Options

| Option | Default | Meaning |
|---|---|---|
| `irodori_tts.codec_decode_chunk_steps` | `0` (off) | Decode the latent in windows of this many latent frames (25 frames = 1 second). `0` decodes the whole sequence at once. |
| `irodori_tts.codec_decode_overlap_steps` | `16` | Latent frames of context decoded on each side of a window and then discarded. |

**Recommended:** `codec_decode_chunk_steps=100` (4 seconds), with the default
overlap. Shorter windows (for example `50`) save little more and are slower.

Server config (`session_options` of the model):

```json
"session_options": {
  "irodori_tts.codec_decode_chunk_steps": "100"
}
```

CLI:

```bash
audiocpp_cli ... --session-option irodori_tts.codec_decode_chunk_steps=100
```

The options work with existing GGUF packages; their embedded model spec does
not list them, and the session accepts them anyway.

### How it works

The decoder consists of convolutions, Snake activations and a final tanh.
Nothing in it looks further than a few frames, so an output sample depends on
about ±8 latent frames around it.

- The latent is cut into chunks of `chunk_steps` frames. Each chunk is decoded
  together with `overlap_steps` frames of real context on both sides, and the
  context part of the output is discarded.
- Every window has the same size, so one decode graph is built once and
  reused. Windows at the start and end are shifted inward instead of being
  shortened, so the true edges of the sequence keep the same zero padding as a
  whole-sequence decode.
- Outputs shorter than one window (`chunk_steps + 2 × overlap_steps` frames:
  5.28 seconds with the recommended values) are decoded in one piece exactly as
  before.

### Measurements

Windows 10, RTX 5060 Ti 16 GB, Irodori-TTS v4 (GGUF Q8_0), 48 steps, speaker
embedding. GPU peak is measured with nvidia-smi and given over the GPU usage
before the server started (it includes the resident model).

| Setting | Short text (6.6 s) | Long text (25.8 s) | Generation time (short / long) |
|---|---|---|---|
| Default | 2,645 MiB | 6,207 MiB | 1.21–1.35 s / 2.98–3.19 s |
| `codec_decode_chunk_steps=100` | 2,405 MiB | **2,415–2,427 MiB** | 1.32–1.42 s / 3.18–3.42 s |
| `chunk_steps=100` + `codec_weight_type=f16` | 1,963–1,981 MiB | 2,079–2,081 MiB | 1.27–1.39 s / 3.30 s |
| `chunk_steps=50` + `codec_weight_type=f16` | 1,911–1,963 MiB | 2,061–2,065 MiB | 1.34–1.50 s / 3.48–3.51 s |

- The long-text peak drops from 6.2 GB to 2.4 GB, and short and long requests
  now peak at about the same level. Generation takes about 4–7% longer.
- `irodori_tts.codec_weight_type=f16` is an existing upstream option. The codec
  weights are rebuilt in F32 at load time whatever the GGUF stores, so this
  option halves them (and the codec's im2col buffers) and lowers both the
  resident size and the peak. It is independent of chunking.

### Output difference

- **Default:** bit-identical to the build without this change.
- **Chunked, CPU backend:** at most 1 LSB (16-bit) different from the
  whole-sequence decode; with `chunk_steps=50` bit-identical.
- **Chunked, CUDA backend:** SNR 67 dB against the whole-sequence decode, with
  the difference spread evenly over the audio rather than at chunk boundaries.
  The GPU matrix multiply picks a different summation order for a different
  matrix size; repeated runs of the same setting give identical output.
- **Overlap matters:** with `overlap_steps=4` the difference reaches 537 LSB,
  and with `0` the chunk boundaries produce audible clicks. Keep the default 16.
- In a listening test (including the waveform difference by phase
  inversion), the chunked output could not be told apart from the default.
  `codec_weight_type=f16` differs more (SNR about 51 dB) but was also not
  distinguishable in normal listening.

### Limitations

- Only the codec **decode** is chunked. Encoding a reference WAV still runs
  as one graph over the whole reference (3.7 GB for the 7.1 s case above,
  first request only, since the result is cached). Speaker embeddings skip
  this step.
- Values are measured with Irodori-TTS v4 Small. v4.1 Small and v4.1 Anime
  share the architecture and codec, so the same applies; other versions were
  not measured.

---

## 日本語

このフォークは Irodori-TTS に 2 つのセッションオプションを追加する。DACVAE
コーデックが潜在表現を固定長の区間に区切ってデコードするようになる。これを
使わない場合、潜在表現を波形に戻すのに必要なメモリは出力の長さに比例して増え、
長文では短文より数 GB 多く使うことがある。使えば、短文でも長文でもピークは
ほぼ同じ水準になる。

既定では無効なので、設定しない限り動作は変わらない。

### メモリの内訳

各段階の計算グラフの作業領域（Irodori-TTS v4、GGUF Q8_0、48 ステップ）:

| リクエスト | 音声の長さ | 条件エンコーダー | 生成（最大のグラフ） | 参照のエンコード | **コーデックのデコード** |
|---|---|---|---|---|---|
| 短文・話者埋め込み | 6.6 秒 | 54 MiB | 299 MiB | ― | **1,167 MiB** |
| 長文・話者埋め込み | 25.8 秒 | 54 MiB | 299 MiB | ― | **4,542 MiB** |
| 短文・参照 WAV | 7.1 秒 | 62 MiB | 378 MiB | 3,713 MiB | 1,245 MiB |
| 短文・参照なし | 6.9 秒 | 54 MiB | 196 MiB | ― | 1,209 MiB |

コーデックのデコードは系列全体を 1 つのグラフで処理し、**音声 1 秒あたり約
176 MiB** を使う。モデルの重みは約 1.3 GB が常駐する。それ以外は小さいので、
数秒を超える出力ではデコードがピークを決める。

モデルの重みをさらに量子化しても（たとえば 4-bit）、減るのは常駐分だけで、
多くても数百 MB にとどまる。音声の長さに比例して増える部分は変わらない。

### オプション

| オプション | 既定 | 意味 |
|---|---|---|
| `irodori_tts.codec_decode_chunk_steps` | `0`（無効） | 潜在表現をこのフレーム数ずつ区切ってデコードする（25 フレーム＝1 秒）。`0` は系列全体を一度にデコードする。 |
| `irodori_tts.codec_decode_overlap_steps` | `16` | 各区間の前後に付けて一緒にデコードし、出力から捨てる前後の文脈のフレーム数。 |

**推奨:** `codec_decode_chunk_steps=100`（4 秒）、重なりは既定のまま。
もっと短くしても（たとえば `50`）ほとんど減らず、遅くなる。

サーバー設定（モデルの `session_options`）:

```json
"session_options": {
  "irodori_tts.codec_decode_chunk_steps": "100"
}
```

CLI:

```bash
audiocpp_cli ... --session-option irodori_tts.codec_decode_chunk_steps=100
```

既存の GGUF パッケージでも使える。埋め込まれたモデル仕様には載っていないが、
セッションは受け付ける。

### 仕組み

デコーダーは畳み込み、Snake 活性化、最後の tanh だけでできている。どれも数
フレーム先までしか見ないので、出力の 1 点が依存するのは前後約 8 潜在フレーム
の範囲に限られる。

- 潜在表現を `chunk_steps` フレームずつに区切り、各区間を前後 `overlap_steps`
  フレームの実データと一緒にデコードして、前後の分は出力から捨てる。
- 区間の大きさはすべて同じなので、デコードのグラフは 1 回作って使い回す。先頭
  と末尾の区間は短くせずに内側へずらすので、系列の本当の端は、一括デコードと
  同じゼロ詰めのままになる。
- 1 区間（`chunk_steps + 2 × overlap_steps` フレーム。推奨値で 5.28 秒）より
  短い出力は、これまでどおり一括でデコードする。

### 測定結果

Windows 10、RTX 5060 Ti 16 GB、Irodori-TTS v4（GGUF Q8_0）、48 ステップ、
話者埋め込み。GPU のピークは nvidia-smi で測り、サーバー起動前の GPU 使用量との
差で示す（常駐するモデルを含む）。

| 設定 | 短文（6.6 秒） | 長文（25.8 秒） | 生成時間（短文 / 長文） |
|---|---|---|---|
| 既定 | 2,645 MiB | 6,207 MiB | 1.21〜1.35 秒 / 2.98〜3.19 秒 |
| `codec_decode_chunk_steps=100` | 2,405 MiB | **2,415〜2,427 MiB** | 1.32〜1.42 秒 / 3.18〜3.42 秒 |
| `chunk_steps=100` ＋ `codec_weight_type=f16` | 1,963〜1,981 MiB | 2,079〜2,081 MiB | 1.27〜1.39 秒 / 3.30 秒 |
| `chunk_steps=50` ＋ `codec_weight_type=f16` | 1,911〜1,963 MiB | 2,061〜2,065 MiB | 1.34〜1.50 秒 / 3.48〜3.51 秒 |

- 長文のピークが 6.2 GB から 2.4 GB に下がり、短文と長文のピークがほぼそろう。
  生成時間は約 4〜7% 延びる。
- `irodori_tts.codec_weight_type=f16` は上流に元からあるオプション。コーデックの
  重みは GGUF の型にかかわらず読み込み時に F32 で作り直されるので、このオプション
  で重み（とコーデックの im2col の作業領域）が半分になり、常駐分とピークの両方が
  下がる。区切りとは独立に使える。

### 出力の違い

- **既定:** この変更を入れる前のビルドとビット単位で一致する。
- **区切りあり・CPU バックエンド:** 一括デコードとの差は最大 1 LSB（16 bit）。
  `chunk_steps=50` ではビット単位で一致した。
- **区切りあり・CUDA バックエンド:** 一括デコードに対して SNR 67 dB。差は区間の
  境目ではなく音声全体に均一に出る。GPU の行列積が行列の大きさに応じて加算の順序
  を変えるためで、同じ設定を繰り返せば出力は毎回同じ。
- **重なりは必要:** `overlap_steps=4` では差が 537 LSB に達し、`0` では区間の
  境目でプチ音が出る。既定の 16 のまま使う。
- 聞き比べ（逆相で重ねた差分を含む）では、区切った出力を既定の出力と区別でき
  なかった。`codec_weight_type=f16` は差がやや大きい（SNR 約 51 dB）が、通常の
  聴取では区別できなかった。

### 制限

- 区切るのはコーデックの**デコード**だけ。参照 WAV のエンコードは、今も参照全体
  を 1 つのグラフで処理する（上の 7.1 秒の例で 3.7 GB。結果はキャッシュされるので
  初回のみ）。話者埋め込みを使う場合、この処理は行わない。
- 数値は Irodori-TTS v4 Small で測った。v4.1 Small と v4.1 Anime は構造とコーデック
  が同じなので同様に当てはまる。それ以外の版は測っていない。
