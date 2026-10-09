#!/bin/sh
# Rebuilds ios-native/Models/ (not stored in git: ~150 MB). Needs internet ONCE, on your Mac.
# Usage: sh ios-native/fetch-models.sh
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
echo "Done. Models are in $HERE/Models"
