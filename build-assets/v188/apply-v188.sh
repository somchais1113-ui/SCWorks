#!/usr/bin/env bash
set -euxo pipefail

ROOT=scdrive-app
cp build-assets/v188/camera_awareness_service.dart "$ROOT/lib/features/camera/camera_awareness_service.dart"
cp build-assets/v188/radio_garden_panel.dart "$ROOT/lib/features/head_unit/radio_garden_panel.dart"

python3 - <<'PY'
from pathlib import Path

root = Path('scdrive-app')

deck = root / 'lib/features/head_unit/drive_deck_panel.dart'
s = deck.read_text()
old = '''    _cameraAwareness.updateVehicle(
      latitude: t.latitude,
      longitude: t.longitude,
      headingDeg: t.heading,
      speedKph: t.displaySpeedKph,
      gpsUsable: gpsUsable,
    );'''
new = '''    _cameraAwareness.updateVehicle(
      latitude: t.latitude,
      longitude: t.longitude,
      headingDeg: t.heading,
      speedKph: t.displaySpeedKph,
      gpsUsable: gpsUsable,
      gpsConfidence: t.gpsConfidence,
      gpsAgeMs: t.gpsAgeMs,
      gpsAccuracyM: t.accuracyM,
      speedAccuracyMps: t.speedAccuracyMps,
      bearingAccuracyDeg: t.bearingAccuracyDeg,
    );'''
if old not in s:
    raise SystemExit('camera telemetry feed anchor not found')
deck.write_text(s.replace(old, new, 1))

spotify = root / 'android/app/src/main/kotlin/com/scdeport/scdrive/spotify/SpotifyMediaSessionBridge.kt'
radio = root / 'android/app/src/main/kotlin/com/scdeport/scdrive/spotify/RadioGardenMediaSessionBridge.kt'
s = spotify.read_text()
s = s.replace('class SpotifyMediaSessionBridge', 'class RadioGardenMediaSessionBridge', 1)
s = s.replace('private const val SPOTIFY_PACKAGE = "com.spotify.music"',
              'private const val RADIO_GARDEN_PACKAGE = "com.jonathanpuckey.radiogarden"', 1)
s = s.replace('spotifyController', 'radioGardenController')
s = s.replace('selectSpotifyController', 'selectRadioGardenController')
s = s.replace('SPOTIFY_PACKAGE', 'RADIO_GARDEN_PACKAGE')
s = s.replace('"spotifySessionActive"', '"radioGardenSessionActive"')
radio.write_text(s)

main = root / 'android/app/src/main/kotlin/com/scdeport/scdrive/MainActivity.kt'
s = main.read_text()
import_anchor = 'import com.scdeport.scdrive.spotify.SpotifyMediaSessionBridge\n'
if import_anchor not in s:
    raise SystemExit('Spotify bridge import anchor missing')
s = s.replace(
    import_anchor,
    import_anchor + 'import com.scdeport.scdrive.spotify.RadioGardenMediaSessionBridge\n',
    1,
)
channel_anchor = '    private val spotifyControlChannel = "com.scdeport.scdrive/spotify_media_control"\n'
if channel_anchor not in s:
    raise SystemExit('Spotify channel anchor missing')
s = s.replace(
    channel_anchor,
    channel_anchor +
    '    private val radioGardenEventChannel = "com.scdeport.scdrive/radio_garden_media"\n'
    '    private val radioGardenControlChannel = "com.scdeport.scdrive/radio_garden_media_control"\n',
    1,
)
field_anchor = '    private var spotifyMediaBridge: SpotifyMediaSessionBridge? = null\n'
if field_anchor not in s:
    raise SystemExit('Spotify bridge field anchor missing')
s = s.replace(
    field_anchor,
    field_anchor +
    '    private var radioGardenMediaBridge: RadioGardenMediaSessionBridge? = null\n',
    1,
)
setup_anchor = '        val obd = ObdManager(this)\n'
if setup_anchor not in s:
    raise SystemExit('OBD setup anchor missing')
radio_setup = '''        val radioGardenBridge = RadioGardenMediaSessionBridge(this)
        radioGardenMediaBridge = radioGardenBridge
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, radioGardenEventChannel)
            .setStreamHandler(radioGardenBridge)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, radioGardenControlChannel)
            .setMethodCallHandler { call, result ->
                when (call.method.lowercase()) {
                    "start", "resume" -> result.success(radioGardenBridge.resume())
                    "refresh" -> result.success(radioGardenBridge.refresh())
                    "ispermissiongranted" -> result.success(radioGardenBridge.hasPermission())
                    "requestpermission" -> {
                        radioGardenBridge.openPermissionSettings()
                        result.success(true)
                    }
                    "toggleplaypause" -> result.success(radioGardenBridge.togglePlayPause())
                    "next" -> result.success(radioGardenBridge.next())
                    "previous" -> result.success(radioGardenBridge.previous())
                    else -> result.notImplemented()
                }
            }

'''
s = s.replace(setup_anchor, radio_setup + setup_anchor, 1)
resume_anchor = '        spotifyMediaBridge?.resume()\n'
if resume_anchor not in s:
    raise SystemExit('Spotify resume anchor missing')
s = s.replace(
    resume_anchor,
    resume_anchor + '        radioGardenMediaBridge?.resume()\n',
    1,
)
destroy_anchor = '        spotifyMediaBridge?.destroy()\n        spotifyMediaBridge = null\n'
if destroy_anchor not in s:
    raise SystemExit('Spotify destroy anchor missing')
s = s.replace(
    destroy_anchor,
    destroy_anchor +
    '        radioGardenMediaBridge?.destroy()\n        radioGardenMediaBridge = null\n',
    1,
)
main.write_text(s)

pub = root / 'pubspec.yaml'
s = pub.read_text()
if 'version: 1.8.7+33' not in s:
    raise SystemExit('v1.8.7 baseline missing')
pub.write_text(s.replace('version: 1.8.7+33', 'version: 1.8.8+34', 1))
PY

dart format \
  "$ROOT/lib/features/camera/camera_awareness_service.dart" \
  "$ROOT/lib/features/head_unit/drive_deck_panel.dart" \
  "$ROOT/lib/features/head_unit/radio_garden_panel.dart"

grep -n '^version: 1.8.8+34' "$ROOT/pubspec.yaml"
grep -q 'gpsConfidence: t.gpsConfidence' "$ROOT/lib/features/head_unit/drive_deck_panel.dart"
grep -q 'gpsAgeMs: t.gpsAgeMs' "$ROOT/lib/features/head_unit/drive_deck_panel.dart"
grep -q 'crossTrackMeters' "$ROOT/lib/features/camera/camera_awareness_service.dart"
grep -q '_acquisitionGpsQualityOk' "$ROOT/lib/features/camera/camera_awareness_service.dart"
grep -q 'radio_garden_media_control' "$ROOT/lib/features/head_unit/radio_garden_panel.dart"
grep -q 'radioGardenSessionActive' "$ROOT/lib/features/head_unit/radio_garden_panel.dart"
grep -q 'class RadioGardenMediaSessionBridge' "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/spotify/RadioGardenMediaSessionBridge.kt"
grep -q 'com.jonathanpuckey.radiogarden' "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/spotify/RadioGardenMediaSessionBridge.kt"
grep -q 'radioGardenMediaBridge' "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/MainActivity.kt"

(cd "$ROOT" && sha256sum -c /tmp/v181-physics-authority.sha256)
