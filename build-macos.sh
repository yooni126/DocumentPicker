#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_SDK="${1:-}"
if [[ "$(uname -s)" != "Darwin" ]]; then
    echo "The native iOS build requires macOS and full Xcode, not Windows." >&2
    exit 1
fi
if [[ -z "$TASK_SDK" || ! -f "$TASK_SDK/include/FlashRuntimeExtensions.h" ||
      ! -x "$TASK_SDK/bin/acompc" || ! -x "$TASK_SDK/bin/adt" ]]; then
    echo "Usage: bash build-macos.sh /absolute/path/to/macOS-AIR-SDK-51.4.1" >&2
    exit 1
fi
TASK_SDK="$(cd "$TASK_SDK" && pwd)"
TASK_IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
TASK_MIN_IOS="${FDP_MIN_IOS:-12.0}"
mkdir -p "$TASK_ROOT/build" "$TASK_ROOT/dist"
TASK_WORK="$(mktemp -d "$TASK_ROOT/build/session.XXXXXXXX")"
mkdir -p "$TASK_WORK/iPhone-ARM" "$TASK_WORK/default"

"$TASK_SDK/bin/acompc" "-source-path=$TASK_ROOT/as3" \
    -include-classes=com.fdp.documentpicker.DocumentPickerExtension \
    "-output=$TASK_WORK/FDPDocumentPicker.swc" -target-player=51.0 -swf-version=51 -strict=true
unzip -q "$TASK_WORK/FDPDocumentPicker.swc" library.swf -d "$TASK_WORK/iPhone-ARM"
cp "$TASK_WORK/iPhone-ARM/library.swf" "$TASK_WORK/default/library.swf"

xcrun --sdk iphoneos clang -arch arm64 -isysroot "$TASK_IOS_SDK" \
    "-miphoneos-version-min=$TASK_MIN_IOS" -fobjc-arc -fblocks -O2 -Wall -Wextra \
    -Wno-unused-parameter -Werror=implicit-function-declaration \
    -I "$TASK_SDK/include" -c "$TASK_ROOT/ios/FDPDocumentPicker.m" \
    -o "$TASK_WORK/FDPDocumentPicker.o"
xcrun libtool -static -o "$TASK_WORK/iPhone-ARM/libFDPDocumentPicker.a" "$TASK_WORK/FDPDocumentPicker.o"
xcrun lipo "$TASK_WORK/iPhone-ARM/libFDPDocumentPicker.a" -verify_arch arm64

"$TASK_SDK/bin/adt" -package -target ane "$TASK_ROOT/dist/FDPDocumentPicker.ane" \
    "$TASK_ROOT/extension.xml" -swc "$TASK_WORK/FDPDocumentPicker.swc" \
    -platform iPhone-ARM -platformoptions "$TASK_ROOT/platform-ios.xml" \
    -C "$TASK_WORK/iPhone-ARM" library.swf libFDPDocumentPicker.a \
    -platform default -C "$TASK_WORK/default" library.swf
unzip -tq "$TASK_ROOT/dist/FDPDocumentPicker.ane"
echo "Built: $TASK_ROOT/dist/FDPDocumentPicker.ane"
echo "Native device build still needs an actual iPhone/iPad import test before release."
