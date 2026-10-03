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

Memory settings. The config enables every option that bounds peak memory:

  "irodori_tts.codec_decode_chunk_steps": "100"   decode audio in 4 s windows
  "irodori_tts.codec_encode_chunk_steps": "100"   encode reference audio in 4 s windows
  "irodori_tts.codec_weight_type": "f16"          codec weights in F16
  "irodori_tts.max_ref_seconds": "checkpoint"     trim reference audio as Python Irodori-TTS does

With them, GPU memory stays at about 2 GB for short and long requests alike
(Irodori-TTS v4, RTX 5060 Ti; without them a 26 s output needed 6.2 GB). The
difference in the output is very small. If you have enough memory and want the
same behaviour as upstream audio.cpp, delete these four lines from
"session_options" and restart the server. Details (English and Japanese):
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
The binary packages are built with upstream's model manager. If you add
  "ui_management": true,
to server_config.json, the WebUI can also download, switch and delete models
(stored in models\ next to the exe). start_server.bat leaves it off and only
prints a note, because while it is on:
  - the WebUI lists upstream's model catalog, and a model it loads runs WITHOUT
    the memory options above. It also reloads the "irodori-tts" model of
    server_config.json that way, so API requests run without the options too
    until the server is restarted;
  - the WebUI's voice list shows upstream's demo voices instead of voices\
    (the API still accepts the names in voices\);
  - upstream's package list installs Irodori-TTS v4.1 Anime into the same
    models\Irodori-TTS-v4-Small-GGUF folder, but start_server.bat needs exactly
    one .gguf there. Move the other one to a folder of its own.
The WebUI has a Japanese interface (Interface language) either way.

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
  4 行）。短文でも長文でも GPU のメモリは約 2 GB にとどまります（Irodori-TTS v4、
  RTX 5060 Ti。無効だと 26 秒の出力で 6.2 GB）。出力の違いはごくわずかです。
  メモリに余裕があり、上流の audio.cpp と同じ動作にしたい場合は、"session_options"
  からこの 4 行を削除してサーバーを再起動してください。詳細（英語・日本語）は
  リポジトリの docs/irodori_codec_chunked_decode.md にあります。

参照音声・Speaker Inversion の埋め込みは voices\ に置き、ファイル名で指定します
（voices\README.txt）。WebUI の声の一覧（Configured voices）にも表示されます（v0.8.2-r4 以降）。

WebUI のモデル管理（任意、v0.9.0 以降のパッケージ）:
  バイナリは上流のモデルマネージャ付きでビルドしています。server_config.json に
  "ui_management": true, を足すと、WebUI からモデルのダウンロード・切り替え・削除も
  できます（保存先は exe と同じフォルダの models\）。start_server.bat は有効にせず
  案内だけを出します。有効にすると次のようになるためです。
  - WebUI のモデル一覧が上流のカタログになり、そこから読み込んだモデルは上記の
    メモリの設定なしで動きます。server_config.json の "irodori-tts" もこの形で
    読み込み直されるので、サーバーを再起動するまでは API からの要求も設定なしになります
  - WebUI の声の一覧は voices\ ではなく上流のデモ音声になります（API からは voices\ の
    名前をそのまま使えます）
  - 上流のパッケージ一覧は Irodori-TTS v4.1 Anime を同じ
    models\Irodori-TTS-v4-Small-GGUF に入れますが、start_server.bat はこのフォルダに
    .gguf が 1 個だけであることを前提にしています。もう一方は別のフォルダへ移してください
  WebUI の日本語表示は、どちらの場合も Interface language から選べます。
