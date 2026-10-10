#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${1:?App bundle required}"
IDENTITY="${2:?Signing identity required}"
SOURCE="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$SOURCE"
mkdir -p "$APP/Contents/Frameworks"
ditto "$SOURCE" "$APP/Contents/Frameworks/Sparkle.framework"
python3 - "$APP/Contents/Frameworks/Sparkle.framework" "$IDENTITY" <<'PY'
from pathlib import Path
import subprocess, sys
framework = Path(sys.argv[1])
identity = sys.argv[2]
magics = {b'\xcf\xfa\xed\xfe', b'\xce\xfa\xed\xfe', b'\xfe\xed\xfa\xcf', b'\xfe\xed\xfa\xce', b'\xca\xfe\xba\xbe', b'\xbe\xba\xfe\xca', b'\xca\xfe\xba\xbf'}
def sign(path):
    subprocess.run(['codesign', '--force', '--options', 'runtime', '--timestamp',
                    '--preserve-metadata=identifier,entitlements', '--sign', identity, str(path)], check=True)
for path in sorted(framework.rglob('*')):
    if path.is_file() and not path.is_symlink():
        with path.open('rb') as stream:
            if stream.read(4) in magics:
                sign(path)
bundles = [p for p in framework.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in ('.app', '.xpc')]
for path in sorted(bundles, key=lambda p: len(p.parts), reverse=True):
    sign(path)
sign(framework)
subprocess.run(['codesign', '--verify', '--deep', '--strict', str(framework)], check=True)
PY
