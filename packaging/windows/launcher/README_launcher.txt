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
     Downloads Irodori-TTS v4 Small (GGUF Q8_0, about 1.3 GB) from
     huggingface.co/audio-cpp/audio.cpp-gguf into models\Irodori-TTS-v4-Small-GGUF
     and checks its SHA256. It can be run again to resume an interrupted download.
     (The file keeps its v4 name but currently holds Irodori-TTS v4.1 Small; the
     WebUI shows the model as "Irodori-TTS v4.1 Small".)
3. Run start_server.bat
     Creates server_config.json on the first run, starts the server in that window
     and opens the WebUI (http://127.0.0.1:8090/) once the model is loaded.
     Close the window or press Ctrl+C to stop the server.
4. Optional: with the server running, run test_tts.bat to write test.wav.

Windows may show a SmartScreen warning for downloaded files. If the scripts do
not run, open the zip file's Properties and tick "Unblock" before extracting.

Files
-----
  start_server.bat      start the server (options: -NoBrowser, -Port <n> for the first run)
  download_model.bat    download the model
  test_tts.bat          test request: test_tts.bat ["text"] [voice]
  voices\               reference voices (.wav) and Speaker Inversion embeddings
                        (.speaker.safetensors); see voices\README.txt
  scripts\              the PowerShell scripts called by the .bat files

server_config.json
------------------
Created once and never overwritten; edit it freely, or delete it to create it
again. The server listens on 127.0.0.1 only (this PC). It has no authentication:
do not change "host" to "0.0.0.0" unless the network is trusted.

Memory settings. The config enables every option that bounds peak memory,
under "session_option_defaults" (packages from v0.9.0 on; older packages put
them under "session_options" of the model):

  "irodori_tts.codec_decode_chunk_steps": "100"   decode audio in 4 s windows
  "irodori_tts.codec_encode_chunk_steps": "100"   encode reference audio in 4 s windows
  "irodori_tts.codec_weight_type": "f16"          codec weights in F16
  "irodori_tts.max_ref_seconds": "checkpoint"     trim reference audio as Python Irodori-TTS does

With them, GPU memory stays at about 2 GB for short and long requests alike
(Irodori-TTS v4, RTX 5060 Ti; without them a 26 s output needed 6.2 GB). The
difference in the output is very small. If you have enough memory and want the
same behaviour as upstream audio.cpp, delete these four lines and restart the
server. Details (English and Japanese):
docs/irodori_codec_chunked_decode.md in the repository.

Using the API
-------------
  curl -o out.wav -H "Content-Type: application/json" ^
    -d "{\"model\":\"irodori-tts\",\"input\":\"...\",\"voice\":\"name\"}" ^
    http://127.0.0.1:8090/v1/audio/speech

Request fields and Speaker Inversion usage: docs/irodori_speaker_inversion.md
in the repository.

Model management in the WebUI (optional, v0.9.0 packages and later)
-------------------------------------------------------------------
The packages are built with upstream's model manager. start_server.bat writes
  "ui_management": false,
into server_config.json, so the WebUI keeps showing the voices in voices\
(reference WAVs and Speaker Inversion embeddings) under "Configured voices".
To use upstream's model management instead, change it to true and restart the
server: the WebUI's Models tab can then download, switch and delete models
(stored in models\ next to the exe). Models loaded from the WebUI also get the
memory settings above, because they are in "session_option_defaults".
While it is on:
  - the WebUI's voice list offers only upstream's demo voices, so the
    embeddings in voices\ cannot be picked in the WebUI (test_tts.bat and the
    API still accept their names);
  - Irodori-TTS v4.1 Anime installs into the same models\Irodori-TTS-v4-Small-GGUF
    folder. That is fine: server_config.json points to the Small file itself.
A server_config.json made by an older launcher stays as it is; the launcher
prints what to change. The WebUI has a Japanese interface (Interface language).

License
-------
These scripts are part of the fork and licensed under the Apache License 2.0
(LICENSE in the binary package). The model is downloaded separately and keeps
its own license (MIT with ethical restrictions, shown by download_model.bat).

Troubleshooting
---------------
  "a DLL is missing"         extract the cudart zip into the same folder (CUDA build)
  "No model found"           run download_model.bat
  "already running"          a server is already using the port; the browser is opened for it
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
  2. download_model.bat を実行する。Irodori-TTS v4 Small（GGUF Q8_0、約 1.3 GB）を
     models\Irodori-TTS-v4-Small-GGUF に取得し、SHA256 を確認する。途中で止まった
     場合は、もう一度実行すると続きから再開する。（ファイル名は v4 のままですが、中身は
     現在 Irodori-TTS v4.1 Small です。WebUI には "Irodori-TTS v4.1 Small" と表示されます）
  3. start_server.bat を実行する。初回に server_config.json を作り、その窓で
     サーバーを起動し、モデルの読み込みが終わるとブラウザで WebUI
     （http://127.0.0.1:8090/）を開く。窓を閉じるか Ctrl+C で停止する。
  4. 任意: サーバーの起動中に test_tts.bat を実行すると test.wav を作る。

  ダウンロードしたファイルに SmartScreen の警告が出ることがあります。スクリプトが
  動かない場合は、zip のプロパティで「許可する」にチェックしてから展開してください。

server_config.json
  初回に作るだけで、以後は上書きしません。自由に編集でき、削除すると次回に作り直します。
  待ち受けは 127.0.0.1（この PC のみ）です。認証がないので、信頼できないネットワーク
  では "host" を "0.0.0.0" にしないでください。

メモリの設定
  使用メモリのピークを抑える 4 つのオプションをすべて有効にしています（上の英語の節の
  4 行。v0.9.0 以降のパッケージでは "session_option_defaults"、それより前は
  モデルの "session_options" の中）。短文でも長文でも GPU のメモリは約 2 GB にとどまります（Irodori-TTS v4、
  RTX 5060 Ti。無効だと 26 秒の出力で 6.2 GB）。出力の違いはごくわずかです。
  メモリに余裕があり、上流の audio.cpp と同じ動作にしたい場合は、この 4 行を
  削除してサーバーを再起動してください。詳細（英語・日本語）は
  リポジトリの docs/irodori_codec_chunked_decode.md にあります。

参照音声・Speaker Inversion の埋め込みは voices\ に置き、ファイル名で指定します
（voices\README.txt）。WebUI の声の一覧（Configured voices）にも表示されます
（"ui_management" が false のとき。ランチャーの既定）。

WebUI のモデル管理（任意、v0.9.0 以降のパッケージ）:
  バイナリは上流のモデルマネージャ付きでビルドしています。start_server.bat は
  server_config.json に "ui_management": false, と書くので、WebUI の声の一覧
  （Configured voices）には voices\ の参照音声と Speaker Inversion の埋め込みが出ます。
  上流のモデル管理を使いたい場合は true に変えてサーバーを再起動してください。WebUI の
  「モデル」タブからモデルのダウンロード・切り替え・削除ができます（保存先は exe と同じ
  フォルダの models\）。メモリの設定は "session_option_defaults" にあるので、WebUI から
  読み込んだモデルにも効きます。有効にしている間は次のようになります。
  - WebUI の声の一覧は上流のデモ音声だけになり、voices\ の埋め込みは WebUI では選べません
    （test_tts.bat や API からは名前で使えます）
  - Irodori-TTS v4.1 Anime は同じ models\Irodori-TTS-v4-Small-GGUF に入りますが、
    server_config.json は Small のファイルを直接指しているので問題ありません
  以前のランチャーで作った server_config.json はそのまま使い、変更が必要な点は起動時に
  表示します。WebUI の日本語表示は Interface language から選べます。
