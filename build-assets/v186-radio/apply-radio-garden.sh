#!/usr/bin/env bash
set -euxo pipefail

cp build-assets/v186-radio/radio_garden_panel.dart scdrive-app/lib/features/head_unit/radio_garden_panel.dart

python3 - <<'PY'
from pathlib import Path

pub=Path('scdrive-app/pubspec.yaml')
s=pub.read_text()
if 'url_launcher:' not in s:
    if '\ndev_dependencies:' not in s:
        raise SystemExit('dev_dependencies anchor not found')
    s=s.replace('\ndev_dependencies:', '\n  url_launcher: ^6.3.2\n\ndev_dependencies:', 1)
if 'version: 1.8.5+31' not in s:
    raise SystemExit('v1.8.5 version baseline not found')
s=s.replace('version: 1.8.5+31','version: 1.8.6+32',1)
pub.write_text(s)

screen=Path('scdrive-app/lib/features/head_unit/head_unit_screen.dart')
s=screen.read_text()
old="import 'car_radio_panel.dart';"
if old not in s:
    raise SystemExit('legacy radio import not found')
s=s.replace(old,"import 'radio_garden_panel.dart';",1)

old_call="""                                      child: _MediaPager(
                                        spotify: widget.spotify,
                                        radio: widget.radio,
                                        compact: compact,
                                      ),"""
new_call="""                                      child: _MediaPager(
                                        spotify: widget.spotify,
                                        compact: compact,
                                      ),"""
if old_call not in s:
    raise SystemExit('MediaPager call anchor not found')
s=s.replace(old_call,new_call,1)

old_ctor="""  const _MediaPager({
    required this.spotify,
    required this.radio,
    required this.compact,
  });"""
new_ctor="""  const _MediaPager({
    required this.spotify,
    required this.compact,
  });"""
if old_ctor not in s:
    raise SystemExit('MediaPager constructor anchor not found')
s=s.replace(old_ctor,new_ctor,1)

old_fields="""  final SpotifyService spotify;
  final CarRadioService radio;
  final bool compact;"""
new_fields="""  final SpotifyService spotify;
  final bool compact;"""
if old_fields not in s:
    raise SystemExit('MediaPager fields anchor not found')
s=s.replace(old_fields,new_fields,1)

old_panel="""            CarRadioPanel(
              radio: widget.radio,
              compact: widget.compact,
            ),"""
new_panel="""            RadioGardenPanel(
              compact: widget.compact,
            ),"""
if old_panel not in s:
    raise SystemExit('CarRadioPanel anchor not found')
s=s.replace(old_panel,new_panel,1)

s=s.replace("? const Color(0xFF1ED760)\n                                : const Color(0xFFE72846)",
            "? const Color(0xFF1ED760)\n                                : const Color(0xFF65D996)",1)
screen.write_text(s)
PY

dart format \
  scdrive-app/lib/features/head_unit/radio_garden_panel.dart \
  scdrive-app/lib/features/head_unit/head_unit_screen.dart

grep -n '^version: 1.8.6+32' scdrive-app/pubspec.yaml
grep -q 'url_launcher:' scdrive-app/pubspec.yaml
grep -q 'RADIO GARDEN' scdrive-app/lib/features/head_unit/radio_garden_panel.dart
grep -q 'RadioGardenPanel' scdrive-app/lib/features/head_unit/head_unit_screen.dart
! grep -q 'CarRadioPanel(' scdrive-app/lib/features/head_unit/head_unit_screen.dart
