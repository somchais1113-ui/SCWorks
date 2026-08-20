#!/usr/bin/env bash
set -euxo pipefail

ROOT=scdrive-app
cp build-assets/v190/drive_dynamics_panel.dart "$ROOT/lib/features/head_unit/drive_dynamics_panel.dart"

python3 - <<'PY'
from pathlib import Path

root = Path('scdrive-app')

head = root / 'lib/features/head_unit/head_unit_screen.dart'
s = head.read_text()

anchor = "import 'drive_deck_panel.dart';\n"
if anchor not in s:
    raise SystemExit('head unit drive deck import anchor missing')
if "import 'drive_dynamics_panel.dart';" not in s:
    s = s.replace(anchor, anchor + "import 'drive_dynamics_panel.dart';\n", 1)

old = '''                                      child: _MediaPager(
                                        spotify: widget.spotify,
                                        compact: compact,
                                      ),'''
new = '''                                      child: _MediaPager(
                                        spotify: widget.spotify,
                                        telemetry: widget.telemetry,
                                        compact: compact,
                                      ),'''
if old not in s:
    raise SystemExit('MediaPager call anchor missing')
s = s.replace(old, new, 1)

old = '''  const _MediaPager({
    required this.spotify,
    required this.compact,
  });

  final SpotifyService spotify;
  final bool compact;'''
new = '''  const _MediaPager({
    required this.spotify,
    required this.telemetry,
    required this.compact,
  });

  final SpotifyService spotify;
  final DriveTelemetryService telemetry;
  final bool compact;'''
if old not in s:
    raise SystemExit('MediaPager constructor anchor missing')
s = s.replace(old, new, 1)

old = '''            RadioGardenPanel(
              compact: widget.compact,
            ),
          ],'''
new = '''            RadioGardenPanel(
              compact: widget.compact,
            ),
            DriveDynamicsPanel(
              telemetry: widget.telemetry,
              compact: widget.compact,
            ),
          ],'''
if old not in s:
    raise SystemExit('MediaPager children anchor missing')
s = s.replace(old, new, 1)

old = 'children: List<Widget>.generate(2, (index) {'
if old not in s:
    raise SystemExit('MediaPager indicator count anchor missing')
s = s.replace(old, 'children: List<Widget>.generate(3, (index) {', 1)

old = '''                        color: active
                            ? (index == 0
                                ? const Color(0xFF1ED760)
                                : const Color(0xFF65D996))
                            : const Color(0xFF5D6773),'''
new = '''                        color: active
                            ? (index == 0
                                ? const Color(0xFF1ED760)
                                : index == 1
                                    ? const Color(0xFF65D996)
                                    : const Color(0xFF39BFF0))
                            : const Color(0xFF5D6773),'''
if old not in s:
    raise SystemExit('MediaPager indicator color anchor missing')
s = s.replace(old, new, 1)
head.write_text(s)

deck = root / 'lib/features/head_unit/drive_deck_panel.dart'
s = deck.read_text()
s = s.replace("\nimport 'drive_dynamics_panel.dart';\n", '\n', 1)

old = '''            children: <Widget>[
              _mapPage(),
              _drivePage(),
              DriveDynamicsPanel(
                telemetry: widget.telemetry,
                compact: widget.compact,
              ),
            ],'''
new = '''            children: <Widget>[
              _mapPage(),
              _drivePage(),
            ],'''
if old not in s:
    raise SystemExit('DriveDeck dynamics child anchor missing')
s = s.replace(old, new, 1)

old = '''                  Row(
                    children: List<Widget>.generate(
                      3,'''
new = '''                  Row(
                    children: List<Widget>.generate(
                      2,'''
if old not in s:
    raise SystemExit('DriveDeck indicator count anchor missing')
s = s.replace(old, new, 1)

old = '''                    'DRIVE DATA',
                    style: TextStyle(
                      color: _page >= 1'''
new = '''                    'DRIVE DATA',
                    style: TextStyle(
                      color: _page == 1'''
if old not in s:
    raise SystemExit('DriveDeck header color anchor missing')
s = s.replace(old, new, 1)
deck.write_text(s)

pub = root / 'pubspec.yaml'
s = pub.read_text()
if 'version: 1.8.8+34' not in s:
    raise SystemExit('v1.8.8 baseline missing')
pub.write_text(s.replace('version: 1.8.8+34', 'version: 1.9.0+35', 1))
PY

dart format \
  "$ROOT/lib/features/head_unit/drive_dynamics_panel.dart" \
  "$ROOT/lib/features/head_unit/head_unit_screen.dart" \
  "$ROOT/lib/features/head_unit/drive_deck_panel.dart"

grep -n '^version: 1.9.0+35' "$ROOT/pubspec.yaml"
grep -q 'COMBINED G' "$ROOT/lib/features/head_unit/drive_dynamics_panel.dart"
grep -q 'PEAK G' "$ROOT/lib/features/head_unit/drive_dynamics_panel.dart"
grep -q 'Duration(milliseconds: 33)' "$ROOT/lib/features/head_unit/drive_dynamics_panel.dart"
grep -q 'response = 0.72' "$ROOT/lib/features/head_unit/drive_dynamics_panel.dart"
grep -q 'DriveDynamicsPanel' "$ROOT/lib/features/head_unit/head_unit_screen.dart"
grep -q 'List<Widget>.generate(3' "$ROOT/lib/features/head_unit/head_unit_screen.dart"
if grep -q 'DriveDynamicsPanel' "$ROOT/lib/features/head_unit/drive_deck_panel.dart"; then
  echo 'DriveDynamicsPanel still present in lower DriveDeck' >&2
  exit 1
fi

(cd "$ROOT" && sha256sum -c /tmp/v181-physics-authority.sha256)
