#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test --disable-sandbox --cache-path .build/cache --scratch-path .build
swift test --package-path Packages/GestureKit --disable-sandbox --cache-path .build/cache --scratch-path .build/gesture-kit
