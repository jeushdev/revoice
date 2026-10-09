#!/bin/sh
# Rebuilds ios-native/Models/ (not stored in git: ~1.3 GB). Needs internet ONCE, on your Mac.
# Usage:  sh ios-native/fetch-models.sh              # speech + speaker + LLM (Qwen 2.5 1.5B)
#         LLM=0.5b sh ios-native/fetch-models.sh     # smaller LLM if the phone runs out of memory
#         LLM=3b   sh ios-native/fetch-models.sh     # bigger LLM for 6 GB phones (iPhone 14 Pro Max)
#         LLM=none sh ios-native/fetch-models.sh     # skip the LLM
# The app uses the first .gguf (by name) in Models/llm, so delete the old one when switching.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
python3 -m venv "$TMP/venv"
"$TMP/venv/bin/pip" install -q moonshine-voice
# model-arch 4 = Small Streaming (change to 2 for Tiny Streaming; also update sttArch in ReviseModelStore.swift)
"$TMP/venv/bin/python" -I -m moonshine_voice.download --stt --language en --model-arch 4 --root "$TMP/dl"
"$TMP/venv/bin/python" -I -m moonshine_voice.download --diarization --root "$TMP/dl"
mkdir -p "$HERE/Models/stt-small-streaming" "$HERE/Models/diarization"
cp "$TMP"/dl/download.moonshine.ai/model/small-streaming-en/*/* "$HERE/Models/stt-small-streaming/"
cp "$TMP"/dl/download.moonshine.ai/model/diarization-community1/*.ort "$HERE/Models/diarization/"
rm -rf "$TMP"

case "${LLM:-1.5b}" in
  0.5b) FILE=qwen2.5-0.5b-instruct-q4_k_m.gguf; REPO=Qwen/Qwen2.5-0.5B-Instruct-GGUF ;;
  1.5b) FILE=qwen2.5-1.5b-instruct-q4_k_m.gguf; REPO=Qwen/Qwen2.5-1.5B-Instruct-GGUF ;;
  3b)   FILE=qwen2.5-3b-instruct-q4_k_m.gguf;   REPO=Qwen/Qwen2.5-3B-Instruct-GGUF ;;
  none) FILE="" ;;
  *) echo "LLM must be 0.5b, 1.5b, 3b or none"; exit 1 ;;
esac
if [ -n "$FILE" ]; then
  mkdir -p "$HERE/Models/llm"
  [ -f "$HERE/Models/llm/$FILE" ] || curl -L --fail -o "$HERE/Models/llm/$FILE" "https://huggingface.co/$REPO/resolve/main/$FILE"
fi
echo "Done. Models are in $HERE/Models"
