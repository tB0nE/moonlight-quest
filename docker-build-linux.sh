#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IMAGE_NAME="nightfall-linux-builder"
SOURCE_DIR="$SCRIPT_DIR/addons/nightfall-stream"
OUTPUT_DIR="$SCRIPT_DIR/addons/nightfall-stream/bin/linux"

docker build -t "$IMAGE_NAME" -f "$SCRIPT_DIR/Dockerfile.linux-build" "$SCRIPT_DIR"

docker run --rm \
    -v "$SOURCE_DIR:/build/source:ro" \
    -v "$OUTPUT_DIR:/build/output" \
    "$IMAGE_NAME" \
    bash -c '
set -e
cp -r /build/source /build/work
cd /build/work
rm -rf build/linux-release

cmake --preset linux -DCMAKE_BUILD_TYPE=Release -B build/linux-release
cmake --build build/linux-release

cp build/linux-release/bin/linux/libnightfall-stream.linux.template_release.x86_64.so /build/output/
echo "Built: $(ls -lh /build/output/libnightfall-stream.linux.template_release.x86_64.so)"
'
