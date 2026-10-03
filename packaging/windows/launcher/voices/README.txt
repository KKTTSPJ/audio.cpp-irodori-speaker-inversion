Voice library (voice_dir in server_config.json)
================================================

Put reference voices here and select them by file name (without extension):

  name.wav                  reference audio (a few seconds to about 30 s of one speaker)
  name.speaker.safetensors  Irodori-TTS Speaker Inversion embedding (this fork)

API request:  {"model": "irodori-tts", "input": "...", "voice": "name"}
Test:         test_tts.bat "text" name

If both name.speaker.safetensors and name.wav exist, the embedding is used.
The WebUI lists both under "Configured voices" when "ui_management" is false
(v0.8.2-r4 and later; r3 lists only the .wav files). With WebUI model management
on (the default from v0.9.0) the WebUI shows only upstream's demo voices; the
names here still work through the API and test_tts.bat.
Note: if no file matches the name (for example a typo), the server does not
report an error and generates without a reference. test_tts.bat checks the name.

------------------------------------------------------------------------
参照音声を置くフォルダです。拡張子を除いたファイル名で指定します。
  name.wav                  参照音声（1 人の話者、数秒〜30 秒程度）
  name.speaker.safetensors  Irodori-TTS の Speaker Inversion 埋め込み（このフォーク）
同じ名前の両方がある場合は埋め込みが使われます。"ui_management" が false のときは
WebUI の声の一覧（Configured voices）に両方が表示されます（v0.8.2-r4 以降。r3 では
.wav だけ）。WebUI のモデル管理が有効なとき（v0.9.0 以降の既定）は上流のデモ音声だけが
表示されますが、ここの名前は API と test_tts.bat でそのまま使えます。
注意: 名前に合うファイルが無い場合（打ち間違いなど）、サーバーはエラーにせず参照なしで
生成します。test_tts.bat は名前を事前に確認します。
