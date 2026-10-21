#!/bin/bash
# Fails when a release artifact contains the builder's personal data:
# home directory paths, the local account name, or patterns listed in
# scripts/privacy.local.patterns (one extended regex per line, not committed).
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET="${1:?Usage: check_release_privacy.sh <app bundle, dmg mount or directory>}"

patterns=("$HOME" "/Users/$(id -un)/")
LOCAL_PATTERNS="$DIR/scripts/privacy.local.patterns"
if [ -f "$LOCAL_PATTERNS" ]; then
    while IFS= read -r line; do
        [ -n "$line" ] && [ "${line:0:1}" != "#" ] && patterns+=("$line")
    done < "$LOCAL_PATTERNS"
fi

found=0
while IFS= read -r -d '' file; do
    for pattern in "${patterns[@]}"; do
        if strings -a "$file" 2>/dev/null | grep -qE -- "$pattern"; then
            echo "Personal data pattern '$pattern' found in ${file#"$TARGET"/}" >&2
            found=1
        fi
    done
done < <(find "$TARGET" -type f -print0)

if [ "$found" -ne 0 ]; then
    echo "Release privacy check failed." >&2
    exit 1
fi
echo "Release privacy check passed: $TARGET"
