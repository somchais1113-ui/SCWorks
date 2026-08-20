#!/usr/bin/env bash
set -euxo pipefail

ROOT=scdrive-app
mkdir -p "$ROOT/lib/services"
mkdir -p "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/media"
cp build-assets/v189/media_favorites_service.dart "$ROOT/lib/services/media_favorites_service.dart"
cp build-assets/v189/CompanionMediaBridge.kt "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/media/CompanionMediaBridge.kt"
patch -d "$ROOT" -p1 --forward --batch < build-assets/v189/media-ui.patch

python3 - <<'PY'
from pathlib import Path

root = Path('scdrive-app')
main = root / 'android/app/src/main/kotlin/com/scdeport/scdrive/MainActivity.kt'
s = main.read_text()

import_anchor = 'import com.scdeport.scdrive.spotify.RadioGardenMediaSessionBridge\n'
if import_anchor not in s:
    raise SystemExit('Radio Garden bridge import anchor missing')
s = s.replace(
    import_anchor,
    import_anchor + 'import com.scdeport.scdrive.media.CompanionMediaBridge\n',
    1,
)

channel_anchor = '    private val radioGardenControlChannel = "com.scdeport.scdrive/radio_garden_media_control"\n'
if channel_anchor not in s:
    raise SystemExit('Radio Garden channel anchor missing')
s = s.replace(
    channel_anchor,
    channel_anchor +
    '    private val companionMediaShareChannel = "com.scdeport.scdrive/companion_media_share"\n'
    '    private val companionMediaControlChannel = "com.scdeport.scdrive/companion_media_control"\n',
    1,
)

field_anchor = '    private var radioGardenMediaBridge: RadioGardenMediaSessionBridge? = null\n'
if field_anchor not in s:
    raise SystemExit('Radio Garden field anchor missing')
s = s.replace(
    field_anchor,
    field_anchor + '    private var companionMediaBridge: CompanionMediaBridge? = null\n',
    1,
)

setup_anchor = '        val obd = ObdManager(this)\n'
if setup_anchor not in s:
    raise SystemExit('OBD setup anchor missing')
media_setup = '''        val companionBridge = CompanionMediaBridge(this)
        companionMediaBridge = companionBridge
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, companionMediaShareChannel)
            .setStreamHandler(companionBridge)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, companionMediaControlChannel)
            .setMethodCallHandler(companionBridge)
        companionBridge.handleIntent(intent)

'''
s = s.replace(setup_anchor, media_setup + setup_anchor, 1)

resume_anchor = '    override fun onResume() {\n'
if resume_anchor not in s:
    raise SystemExit('onResume anchor missing')
on_new_intent = '''    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        companionMediaBridge?.handleIntent(intent)
    }

'''
s = s.replace(resume_anchor, on_new_intent + resume_anchor, 1)

destroy_anchor = '        radioGardenMediaBridge?.destroy()\n        radioGardenMediaBridge = null\n'
if destroy_anchor not in s:
    raise SystemExit('Radio Garden destroy anchor missing')
s = s.replace(
    destroy_anchor,
    destroy_anchor +
    '        companionMediaBridge?.destroy()\n        companionMediaBridge = null\n',
    1,
)
main.write_text(s)

manifest = root / 'android/app/src/main/AndroidManifest.xml'
s = manifest.read_text()
query_anchor = '        <package android:name="com.spotify.music" />\n'
if query_anchor not in s:
    raise SystemExit('Spotify package query anchor missing')
s = s.replace(
    query_anchor,
    query_anchor + '        <package android:name="com.jonathanpuckey.radiogarden" />\n',
    1,
)
home_filter = '''            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.HOME"/>
                <category android:name="android.intent.category.DEFAULT"/>
            </intent-filter>
'''
if home_filter not in s:
    raise SystemExit('HOME intent filter anchor missing')
share_filter = '''            <intent-filter>
                <action android:name="android.intent.action.SEND" />
                <category android:name="android.intent.category.DEFAULT" />
                <data android:mimeType="text/plain" />
            </intent-filter>
'''
s = s.replace(home_filter, home_filter + share_filter, 1)
manifest.write_text(s)

pub = root / 'pubspec.yaml'
s = pub.read_text()
if 'version: 1.8.8+34' not in s:
    raise SystemExit('v1.8.8 baseline missing')
pub.write_text(s.replace('version: 1.8.8+34', 'version: 1.8.9+35', 1))
PY

dart format \
  "$ROOT/lib/services/media_favorites_service.dart" \
  "$ROOT/lib/services/spotify_service.dart" \
  "$ROOT/lib/features/head_unit/radio_garden_panel.dart" \
  "$ROOT/lib/features/head_unit/head_unit_screen.dart"

# Static gates for the media flow. These deliberately reject browser fallback.
grep -n '^version: 1.8.9+35' "$ROOT/pubspec.yaml"
grep -q 'class CompanionMediaBridge' "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/media/CompanionMediaBridge.kt"
grep -q 'setPackage(RADIO_GARDEN_PACKAGE)' "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/media/CompanionMediaBridge.kt"
grep -q 'setPackage(SPOTIFY_PACKAGE)' "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/media/CompanionMediaBridge.kt"
grep -q 'android.intent.action.SEND' "$ROOT/android/app/src/main/AndroidManifest.xml"
grep -q 'companion_media_share' "$ROOT/android/app/src/main/kotlin/com/scdeport/scdrive/MainActivity.kt"
grep -q 'SC DRIVE RADIO FAVORITES' "$ROOT/lib/features/head_unit/radio_garden_panel.dart"
grep -q 'SPOTIFY LIBRARY' "$ROOT/lib/features/head_unit/head_unit_screen.dart"
grep -q 'playPlaylist' "$ROOT/lib/services/spotify_service.dart"
grep -q 'playTrack' "$ROOT/lib/services/spotify_service.dart"
grep -q 'MediaFavoritesService.instance.openSpotify' "$ROOT/lib/services/spotify_service.dart"
if grep -q "launchUrl(target, mode: LaunchMode.externalApplication)" "$ROOT/lib/services/spotify_service.dart"; then
  echo 'Spotify browser-style launch fallback still present.' >&2
  exit 1
fi
if grep -q "launchUrl(" "$ROOT/lib/features/head_unit/radio_garden_panel.dart"; then
  echo 'Radio Garden browser-style launch fallback still present.' >&2
  exit 1
fi

(cd "$ROOT" && sha256sum -c /tmp/v181-physics-authority.sha256)
