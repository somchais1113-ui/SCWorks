#!/usr/bin/env bash
set -euo pipefail

ROOT="${1:-scdrive-app}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

patch -d "$ROOT" -p1 < "$SCRIPT_DIR/v192-ui-loop.patch"

python3 - "$ROOT/pubspec.yaml" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
s = p.read_text()
old = 'version: 1.9.1+36'
new = 'version: 1.9.2+37'
if old not in s:
    raise SystemExit(f'missing expected version: {old}')
p.write_text(s.replace(old, new, 1))
PY

grep -n '^version: 1.9.2+37' "$ROOT/pubspec.yaml"
grep -q 'final topClearance = math.max' "$ROOT/lib/features/head_unit/head_unit_screen.dart"
grep -q "label: 'RPM SOURCE'" "$ROOT/lib/features/head_unit/head_unit_screen.dart"
grep -q 'final tachRadius = outerRadius \* 0.655' "$ROOT/lib/features/head_unit/head_unit_screen.dart"
grep -q 'redZoneStart = 0.82' "$ROOT/lib/features/head_unit/head_unit_screen.dart"
grep -q 'PageController(initialPage: _loopAnchor)' "$ROOT/lib/features/head_unit/drive_deck_panel.dart"
grep -q 'PageView.builder' "$ROOT/lib/features/head_unit/drive_deck_panel.dart"
