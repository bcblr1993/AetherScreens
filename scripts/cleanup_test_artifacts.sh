#!/bin/bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$DIR"

echo "==> Cleaning up test build artifacts and temporary files..."

# 1. Clean intermediate test directories in build/, preserving build/release
if [ -d "$DIR/build" ]; then
    find "$DIR/build" -mindepth 1 -maxdepth 1 ! -name "release" -exec rm -rf {} + 2>/dev/null || true
    # Also clean any staging directories inside build/release
    rm -rf "$DIR/build/release/staging."* 2>/dev/null || true
fi

# 2. Clean temporary files created by test fixtures in /tmp
rm -rf /tmp/aetherscreens* 2>/dev/null || true

# 3. Clean SwiftPM intermediate object files and debug outputs
swift package clean 2>/dev/null || true

# 4. Clean local Python pycache
find "$DIR/scripts" -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
find "$DIR" -name "*.pyc" -delete 2>/dev/null || true

echo "==> Cleanup complete. Current disk usage:"
du -sh "$DIR/build" "$DIR/.build" 2>/dev/null || true
