from pathlib import Path
import re

ROOT = Path("scdrive-app")

repo_path = ROOT / "lib/features/camera/camera_repository.dart"
service_path = ROOT / "lib/features/camera/camera_awareness_service.dart"
panel_path = ROOT / "lib/features/head_unit/drive_deck_panel.dart"

# 1) Repository cache semantics and interface lifecycle.
r = repo_path.read_text()
refresh_pattern = re.compile(
    r"if\s*\(\s*_records\.isEmpty\s*\|\|\s*centerLat\s*==\s*null\s*\|\|\s*centerLon\s*==\s*null\s*\|\|\s*synced\s*==\s*null\s*\)\s*\{",
    re.MULTILINE,
)
replacement = "if (centerLat == null || centerLon == null || synced == null) {"
if refresh_pattern.search(r):
    r = refresh_pattern.sub(replacement, r, count=1)
elif "_records.isEmpty" in r:
    raise SystemExit("camera repository refresh gate shape changed unexpectedly")
elif not all(x in r for x in ("centerLat == null", "centerLon == null", "synced == null")):
    raise SystemExit("camera repository refresh gate missing")

if "void dispose();" not in r:
    marker = "  Future<void> refreshAround(double latitude, double longitude);\n"
    if marker not in r:
        raise SystemExit("CameraRepository refreshAround interface marker missing")
    r = r.replace(marker, marker + "  void dispose();\n", 1)

if "  void dispose() {\n    _client.close();\n  }" in r and "  @override\n  void dispose()" not in r:
    r = r.replace(
        "  void dispose() {\n    _client.close();\n  }",
        "  @override\n  void dispose() {\n    _client.close();\n  }",
        1,
    )
repo_path.write_text(r)

# 2) Depend on CameraRepository interface and reduce unnecessary network retries.
s = service_path.read_text()
if "final OsmCameraRepository repository;" in s:
    s = s.replace(
        "final OsmCameraRepository repository;",
        "final CameraRepository repository;",
        1,
    )
elif "final CameraRepository repository;" not in s:
    raise SystemExit("CameraAwarenessService repository type marker missing")

if "const Duration(seconds: 30)" in s:
    s = s.replace(
        "const Duration(seconds: 30)",
        "const Duration(minutes: 2)",
        1,
    )
elif "const Duration(minutes: 2)" not in s:
    raise SystemExit("camera network retry interval marker missing")
service_path.write_text(s)

# 3) Match the approved map UI: alert top-right, compass beneath it, zoom fixed lower-right.
p = panel_path.read_text()
alert_marker = (
    "        Positioned(\n"
    "          right: widget.compact ? 12 : 16,\n"
    "          top: widget.compact ? 48 : 58,\n"
    "          child: _CameraAlertOverlay("
)
alert_pos = p.find(alert_marker)
camera_gate = p.find("cameraAlert.shouldRender")
if alert_pos < 0 or camera_gate < 0:
    raise SystemExit("camera alert/control markers missing")

group_start = p.rfind("        AnimatedPositioned(", 0, camera_gate)
if group_start < 0 or group_start > alert_pos:
    raise SystemExit("map compass/zoom group start missing")

group = p[group_start:alert_pos]
if "_MapCompass" in group and "_MapZoomControls" in group:
    controls_lines = [
        "        Positioned(",
        "          right: widget.compact ? 12 : 16,",
        "          bottom: widget.compact ? 56 : 68,",
        "          child: _MapZoomControls(",
        "            compact: widget.compact,",
        "            onZoomIn: () => unawaited(_changeZoom(0.8)),",
        "            onZoomOut: () => unawaited(_changeZoom(-0.8)),",
        "          ),",
        "        ),",
        "        AnimatedPositioned(",
        "          duration: const Duration(milliseconds: 300),",
        "          curve: Curves.easeOutCubic,",
        "          right: widget.compact ? 12 : 16,",
        "          top: cameraAlert.shouldRender",
        "              ? (widget.compact ? 176 : 202)",
        "              : (widget.compact ? 62 : 74),",
        "          child: _MapCompass(",
        "            label: t.compassLabel,",
        "            compact: widget.compact,",
        "          ),",
        "        ),",
    ]
    controls = "\n".join(controls_lines) + "\n"
    p = p[:group_start] + controls + p[alert_pos:]
else:
    # Idempotency: accept an already-separated control layout.
    before_alert = p[max(0, alert_pos - 1800):alert_pos]
    if not (
        "_MapCompass" in before_alert
        and "_MapZoomControls" in before_alert
        and "bottom:" in before_alert
        and "AnimatedPositioned" in before_alert
    ):
        raise SystemExit("map controls are neither grouped nor already separated")
panel_path.write_text(p)

print("SC Drive v1.8.3 Camera final hardening applied")
