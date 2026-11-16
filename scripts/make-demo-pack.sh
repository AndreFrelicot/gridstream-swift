#!/bin/bash
# Builds the iPad demo pack into build/demo-pack/v1, ready to upload to the CDN.
#
#   scripts/make-demo-pack.sh            cut the missing clips, then build the pack
#   scripts/make-demo-pack.sh --serve    same, then serve build/demo-pack/v1 on :8765
#                                        (DEMO_PACK_PORT changes the port)
#
# 1. Cuts each clip of scripts/demo-pack/sources.json from the Blender open
#    movies (ffmpeg reads only the needed ranges over HTTP) into 720p H.264,
#    one keyframe per second for scrubbing. Cut clips are kept in
#    build/demo-pack/work, so a rebuild does not download them again.
# 2. scripts/demo-pack/build_pack.py names each clip after its fileId,
#    extracts thumbnails, writes seed.json from scripts/demo-pack/catalog.json,
#    CREDITS.md and manifest.json (size and SHA-256 of every file).
#
# Upload: copy the contents of build/demo-pack/v1 to the CDN folder that
# DemoPack.defaultBaseURL points at (manifest.json last).
set -euo pipefail

cd "$(dirname "$0")/.."
ROOT="$(pwd)"
WORK="$ROOT/build/demo-pack/work"
OUT="$ROOT/build/demo-pack/v1"
SOURCES="$ROOT/scripts/demo-pack/sources.json"

command -v ffmpeg >/dev/null || { echo "ffmpeg is required (brew install ffmpeg)" >&2; exit 1; }
mkdir -p "$WORK"

python3 -I -c '
import json, sys
data = json.load(open(sys.argv[1]))
for clip in data["clips"]:
    film = data["films"][clip["film"]]
    print(clip["id"], film["url"], clip["start"], clip["duration"])
' "$SOURCES" | while read -r id url start duration; do
    target="$WORK/$id.mp4"
    if [[ -s "$target" ]]; then
        continue
    fi
    echo "Cutting $id ($duration s at $start s)"
    ffmpeg -nostdin -hide_banner -loglevel error -y \
        -ss "$start" -i "$url" -t "$duration" \
        -map 0:v:0 -map 0:a:0 \
        -vf "scale=-2:720:flags=lanczos,format=yuv420p" \
        -c:v libx264 -preset slow -crf 23 -maxrate 2800k -bufsize 5600k \
        -g 24 -keyint_min 24 -sc_threshold 0 -profile:v high -tag:v avc1 \
        -c:a aac -b:a 128k -ac 2 \
        -movflags +faststart \
        "$target.partial.mp4"
    mv "$target.partial.mp4" "$target"
done

python3 -I "$ROOT/scripts/demo-pack/build_pack.py" "$SOURCES" "$ROOT/scripts/demo-pack/catalog.json" "$WORK" "$OUT"

if [[ "${1:-}" == "--serve" ]]; then
    PORT="${DEMO_PACK_PORT:-8765}"
    echo "Serving $OUT on http://localhost:$PORT/ (launch the app with -DemoPackBaseURL http://localhost:$PORT/)"
    cd "$OUT" && python3 -m http.server "$PORT"
fi
