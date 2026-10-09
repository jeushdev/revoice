#!/bin/sh
# Which Dart entry point Xcode's Runner builds:  tool/set_ios_target.sh debug | main
cd "$(dirname "$0")/.." || exit 1
case "$1" in
  debug) echo 'FLUTTER_TARGET=lib/main_ai_debug.dart' > ios/Flutter/Target.xcconfig ;;
  main)  echo 'FLUTTER_TARGET=lib/main.dart' > ios/Flutter/Target.xcconfig ;;
  *) echo "usage: $0 debug|main"; exit 2 ;;
esac
echo "Runner now builds: $(cat ios/Flutter/Target.xcconfig)"
