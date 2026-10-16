audio.cpp - Irodori-TTS Speaker Inversion fork - launcher for Windows
=====================================================================

Scripts that start audiocpp_server.exe with Irodori-TTS and its WebUI without
writing a config by hand. Unofficial; see README.txt of the binary package and
https://github.com/KKTTSPJ/audio.cpp-irodori-speaker-inversion

Quick start
-----------
1. Extract the binary package (cpu-avx2, or cuda12.8 + cudart) into a folder,
   then extract this launcher zip into the SAME folder. Use a path with ASCII
   characters only, for example C:\audiocpp.
2. Run download_model.bat
     Shows the models it can download (see "Models" below). Press Enter for the
     default, Irodori-TTS v4.1 Small (GGUF Q8_0, about 1.3 GB), or type numbers
     such as 1,6. Files come from Hugging Face (mostly
     huggingface.co/audio-cpp/audio.cpp-gguf) into models\ and their SHA256 is
     checked. Run it again to resume an interrupted download or to add models.
3. Run start_server.bat
     Creates server_config.json on the first run, starts the server in that window
     and opens the WebUI (http://127.0.0.1:8090/) once the server is ready.
     Close the window or press Ctrl+C to stop the server.
4. Optional: with the server running, run test_tts.bat to write test.wav.

Windows may show a SmartScreen warning for downloaded files. If the scripts do
not run, open the zip file's Properties and tick "Unblock" before extracting.

Files
-----
  start_server.bat      start the server (options: -NoBrowser, -Port <n> for the first run)
  download_model.bat    download models (options: -List, -Model 1,6, -Yes, -AcceptLicense)
  test_tts.bat          test request: test_tts.bat ["text"] [voice] [-Model <id>]
  voices\               reference voices (.wav) and Speaker Inversion embeddings
                        (.speaker.safetensors); see voices\README.txt
  scripts\              the PowerShell scripts called by the .bat files
                        (scripts\models.ps1 lists the models)

Models
------
download_model.bat offers these. "id" is the name to use as "model" in API
requests and the name shown in the WebUI.

  Text to speech (Irodori-TTS; WebUI: Text to speech tab)
     1  Irodori-TTS v4.1 Small Q8_0 (default)   id irodori-tts
     2  Irodori-TTS v4.1 Anime Q8_0             id irodori-tts-anime (WebUI name: "Irodori-TTS")
     3  Irodori-TTS 500M v3 Q8_0                id irodori-tts-v3-500m
     4  Irodori-TTS 600M v3 VoiceDesign Q8_0    id irodori-tts-v3-vdesign (WebUI: Voice design tab)
  Speech recognition (WebUI: ASR / Transcription tab)
     5  Qwen3-ASR 0.6B Q8_0                     id qwen3-asr
     6  Qwen3-ASR 1.7B Q8_0                     id qwen3-asr-1.7b
     7  CrisperWhisper 2.0 Large Q8_0           id crisperwhisper
  Voice conversion (WebUI: Voice conversion tab)
     8  MeanVC2 F32                             id meanvc2
     9  Seed-VC Q8_0                            id seed-vc
    10  MioCodec 25Hz 44.1kHz v2 Q8_0           id miocodec

The WebUI names models after upstream's catalog. Irodori-TTS v4.1 Anime is kept
in models\Irodori-TTS-v4.1-Anime-GGUF so that it does not show under the name of
v4.1 Small; it appears as plain "Irodori-TTS".

Each model keeps the license of its original release; download_model.bat shows
it before downloading. Note especially:
  - Irodori-TTS: MIT with ethical restrictions (no voice cloning without consent,
    no deepfakes). The same applies to voice conversion.
  - CrisperWhisper 2.0: the model AND its transcripts are for NON-COMMERCIAL use
    only. download_model.bat asks you to type "agree" (or pass -AcceptLicense).
  - Seed-VC: GPL-3.0. Qwen3-ASR and MeanVC2: Apache-2.0. MioCodec: MIT.

Speech recognition takes WAV files at any sample rate. CrisperWhisper relies on
soxr.dll (in the binary packages from v0.9.2 on) to resample to 16 kHz; with an
older package it accepts 16 kHz audio only.

Voice conversion returns audio at the model's own sample rate: MioCodec
44.1 kHz, Seed-VC 22.05 kHz, MeanVC2 16 kHz.

The files are stored where upstream's model manager stores the same packages,
so the WebUI's model management (below) sees them as installed.

server_config.json
------------------
Created on the first run and otherwise kept as you edit it. The one change the
launcher makes later: models downloaded after the file was created are added to
"models" when start_server.bat runs (it prints what it added and keeps the
previous file as server_config.json.bak-<date-time>). With more than one model it
also adds
  "lazy_load": true, "max_loaded_models": 1,
so that a model is loaded on its first request and only one stays in memory;
switching models in the WebUI unloads the previous one. The first request to a
model therefore takes longer. Delete the file to create it again from scratch.

The server listens on 127.0.0.1 only (this PC). It has no authentication: do not
change "host" to "0.0.0.0" unless the network is trusted.

Memory settings. The config enables the options that bound the peak memory of
Irodori-TTS, under "session_option_defaults" (packages from v0.9.0 on; older
packages put them under "session_options" of the model):

  "irodori_tts.codec_decode_chunk_steps": "100"   decode audio in 4 s windows
  "irodori_tts.codec_encode_chunk_steps": "100"   encode reference audio in 4 s windows
  "irodori_tts.codec_weight_type": "f16"          codec weights in F16

With them, GPU memory stays at about 2 GB for short and long requests alike
(Irodori-TTS v4, RTX 5060 Ti; without them a 26 s output needed 6.2 GB). The
difference in the output is very small. If you have enough memory and want the
same behaviour as upstream audio.cpp, delete these three lines and restart the
server. They apply to every Irodori-TTS model and to no other model. Details
(English and Japanese): docs/irodori_codec_chunked_decode.md in the repository.

Reference audio longer than the model's limit (120 s for v4, 30 s for v3) is
trimmed as Python Irodori-TTS does; audio.cpp does this by default now.
Configs created by older packages may also contain
"irodori_tts.max_ref_seconds": "checkpoint". It is still accepted and does
the same, so it can stay or be deleted.

Using the API
-------------
  curl -o out.wav -H "Content-Type: application/json" ^
    -d "{\"model\":\"irodori-tts\",\"input\":\"...\",\"voice\":\"name\"}" ^
    http://127.0.0.1:8090/v1/audio/speech

  curl -F model=qwen3-asr -F file=@speech.wav http://127.0.0.1:8090/v1/audio/transcriptions

Request fields and Speaker Inversion usage: docs/irodori_speaker_inversion.md
in the repository.

Model management in the WebUI (optional, v0.9.0 packages and later)
-------------------------------------------------------------------
The packages are built with upstream's model manager. start_server.bat writes
  "ui_management": false,
into server_config.json, so the WebUI keeps showing the voices in voices\
(reference WAVs and Speaker Inversion embeddings) under "Configured voices",
and lists the models of server_config.json. To use upstream's model management
instead, change it to true and restart the server: the WebUI's Models tab can
then download, switch and delete models (stored in models\ next to the exe).
Models loaded from the WebUI also get the memory settings above, because they
are in "session_option_defaults". While it is on:
  - the WebUI does not list the voices in voices\ (only reference audio
    files and voices saved in the browser), so the embeddings cannot be
    picked in the WebUI (test_tts.bat and the API still accept their names);
  - Irodori-TTS v4.1 Anime and F16 install into the same
    models\Irodori-TTS-v4-Small-GGUF folder. That is fine: server_config.json
    points to each file itself. (download_model.bat keeps Anime in a folder of
    its own instead, so the model manager does not see it as installed.)
download_model.bat is the way to add models while keeping the voice list.
A server_config.json made by an older launcher stays as it is; the launcher
prints what to change. The WebUI has a Japanese interface (Interface language).

License
-------
These scripts are part of the fork and licensed under the Apache License 2.0
(LICENSE in the binary package). Models are downloaded separately and keep
their own licenses (shown by download_model.bat, summarised above).

Troubleshooting
---------------
  "a DLL is missing"         extract the cudart zip into the same folder (CUDA build)
  "No model found"           run download_model.bat
  "already running"          a server is already using the port; the browser is opened for it
  "already has a model with id"  an entry in server_config.json uses that id for another
                             file; rename one of them, or add the model yourself
  CUDA fails to start        update the NVIDIA driver (R570 or newer)
  Port 8090 in use           change "port" in server_config.json

------------------------------------------------------------------------------
日本語
------------------------------------------------------------------------------
audiocpp_server.exe を、設定ファイルを手で書かずに Irodori-TTS と WebUI 付きで
起動するためのスクリプトです（非公式ビルド用）。

使い方
  1. 本体の zip（cpu-avx2、または cuda12.8 と cudart）をフォルダに展開し、この
     ランチャーの zip も「同じフォルダ」に展開する。パスは英数字だけにする
     （例: C:\audiocpp）。
  2. download_model.bat を実行する。取得できるモデルの一覧（下の「モデル」）が出るので、
     Enter で既定の Irodori-TTS v4.1 Small（GGUF Q8_0、約 1.3 GB）、または 1,6 の
     ように番号を入力する。Hugging Face（主に huggingface.co/audio-cpp/audio.cpp-gguf）
     から models\ に取得し、SHA256 を確認する。途中で止まった場合や、モデルを追加
     したいときは、もう一度実行する。
  3. start_server.bat を実行する。初回に server_config.json を作り、その窓で
     サーバーを起動し、準備ができるとブラウザで WebUI（http://127.0.0.1:8090/）を
     開く。窓を閉じるか Ctrl+C で停止する。
  4. 任意: サーバーの起動中に test_tts.bat を実行すると test.wav を作る。

  ダウンロードしたファイルに SmartScreen の警告が出ることがあります。スクリプトが
  動かない場合は、zip のプロパティで「許可する」にチェックしてから展開してください。

モデル
  download_model.bat で取得できるモデルと id（API の "model" に指定する名前、WebUI の
  表示名）は上の英語の節の「Models」のとおりです。
    1〜4   音声合成（Irodori-TTS v4.1 Small Q8_0（既定）・Anime、500M v3、
           600M v3 VoiceDesign（WebUI の「声のデザイン」タブ））
    5〜7   音声認識（Qwen3-ASR 0.6B / 1.7B、CrisperWhisper 2.0）
    8〜10  声質変換（MeanVC2、Seed-VC、MioCodec）
  WebUI はモデルの表示名を上流のカタログから決めます。v4.1 Anime は v4.1 Small と同じ名前で
  表示されないよう models\Irodori-TTS-v4.1-Anime-GGUF に置くので、WebUI では単に
  「Irodori-TTS」と表示されます。
  各モデルは元の公開時のライセンスに従います（取得前に表示します）。特に:
    - Irodori-TTS: MIT（倫理上の制限あり。本人の同意なく声を複製しない、ディープ
      フェイクを作らない）。声質変換にも同じことが当てはまります
    - CrisperWhisper 2.0: モデルと、その出力（文字起こし）は「非商用」に限られます。
      取得時に agree と入力する必要があります（または -AcceptLicense）
    - Seed-VC は GPL-3.0、Qwen3-ASR と MeanVC2 は Apache-2.0、MioCodec は MIT
  音声認識には任意の標本化周波数の WAV を使えます。CrisperWhisper は 16 kHz への変換に
  soxr.dll（v0.9.2 以降の本体のパッケージに同梱）を使うので、それより前のパッケージでは
  16 kHz の音声だけを受け付けます。
  声質変換の出力の標本化周波数はモデルごとに決まっています（MioCodec 44.1 kHz、
  Seed-VC 22.05 kHz、MeanVC2 16 kHz）。
  保存場所は上流のモデル管理と同じなので、WebUI のモデル管理からも取得済みに見えます。

server_config.json
  初回に作り、以後は編集した内容を保ちます。ただし、作った後に取得したモデルは、
  start_server.bat が起動時に "models" へ追加します（追加したものを表示し、元のファイルは
  server_config.json.bak-<日時> に残します）。モデルが 2 つ以上になると
    "lazy_load": true, "max_loaded_models": 1,
  も加えます。モデルは最初のリクエストで読み込まれ、メモリに置くのは 1 つだけです
  （WebUI でモデルを切り替えると前のモデルは解放されます）。そのため、各モデルの最初の
  生成は時間がかかります。削除すると次回に作り直します。
  待ち受けは 127.0.0.1（この PC のみ）です。認証がないので、信頼できないネットワーク
  では "host" を "0.0.0.0" にしないでください。

メモリの設定
  Irodori-TTS の使用メモリのピークを抑える 3 つのオプションを有効にしています（上の
  英語の節の 3 行。v0.9.0 以降のパッケージでは "session_option_defaults"、それより前は
  モデルの "session_options" の中）。短文でも長文でも GPU のメモリは約 2 GB にとどまります
  （Irodori-TTS v4、RTX 5060 Ti。無効だと 26 秒の出力で 6.2 GB）。出力の違いはごくわずか
  です。すべての Irodori-TTS のモデルに効き、他のモデルには影響しません。
  メモリに余裕があり、上流の audio.cpp と同じ動作にしたい場合は、この 3 行を
  削除してサーバーを再起動してください。詳細（英語・日本語）は
  リポジトリの docs/irodori_codec_chunked_decode.md にあります。

参照音声・Speaker Inversion の埋め込みは voices\ に置き、ファイル名で指定します
（voices\README.txt）。WebUI の声の一覧（Configured voices）にも表示されます
（"ui_management" が false のとき。ランチャーの既定）。

WebUI のモデル管理（任意、v0.9.0 以降のパッケージ）:
  バイナリは上流のモデルマネージャ付きでビルドしています。start_server.bat は
  server_config.json に "ui_management": false, と書くので、WebUI の声の一覧
  （Configured voices）には voices\ の参照音声と Speaker Inversion の埋め込みが出て、
  モデルの一覧には server_config.json のモデルが出ます。
  上流のモデル管理を使いたい場合は true に変えてサーバーを再起動してください。WebUI の
  「モデル」タブからモデルのダウンロード・切り替え・削除ができます（保存先は exe と同じ
  フォルダの models\）。メモリの設定は "session_option_defaults" にあるので、WebUI から
  読み込んだモデルにも効きます。有効にしている間は次のようになります。
  - WebUI に voices\ の声の一覧が出なくなり（参照音声ファイルとブラウザ内に保存した
    音声だけ）、埋め込みは WebUI では選べません（test_tts.bat や API からは名前で使えます）
  - Irodori-TTS v4.1 の Anime と F16 は同じ models\Irodori-TTS-v4-Small-GGUF に入りますが、
    server_config.json はそれぞれのファイルを直接指しているので問題ありません
    （download_model.bat は Anime を専用のフォルダに置くので、モデル管理からは未取得に見えます）
  声の一覧を残したままモデルを増やすには download_model.bat を使ってください。
  以前のランチャーで作った server_config.json はそのまま使い、変更が必要な点は起動時に
  表示します。WebUI の日本語表示は Interface language から選べます。
