#!/bin/bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="gridstream-macos"
CONFIG="Release"
DESTINATION="platform=macOS"

BUILD_ARGS=(
    -project "$PROJECT_DIR/gridstream-macos.xcodeproj"
    -scheme "$SCHEME"
    -configuration "$CONFIG"
    -destination "$DESTINATION"
)

if [[ "${GRIDSTREAM_ENABLE_CODE_SIGNING:-0}" != "1" ]]; then
    BUILD_ARGS+=(
        CODE_SIGNING_ALLOWED=NO
        CODE_SIGNING_REQUIRED=NO
    )
fi

echo "Building $SCHEME ($CONFIG)..."
if [[ "${GRIDSTREAM_ENABLE_CODE_SIGNING:-0}" != "1" ]]; then
    echo "Code signing disabled for local build. Set GRIDSTREAM_ENABLE_CODE_SIGNING=1 for signed output."
fi

BUILD_LOG=$(xcodebuild \
    "${BUILD_ARGS[@]}" \
    -showBuildSettings 2>/dev/null \
    | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $NF}')

xcodebuild \
    "${BUILD_ARGS[@]}" \
    build \
    | tail -5

APP_PATH="$BUILD_LOG/GridStream.app"

echo ""
echo "$APP_PATH"
