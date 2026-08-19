import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'camera_models.dart';
import 'camera_repository.dart';

class CameraAwarenessService extends ChangeNotifier {
  CameraAwarenessService(this.repository);

  final OsmCameraRepository repository;

  CameraAlertSnapshot _snapshot = const CameraAlertSnapshot.hidden();
  CameraAlertSnapshot get snapshot => _snapshot;

  Timer? _countdownTimer;
  DateTime? _lastCountdownTick;
  DateTime? _lastEvaluationAt;
  DateTime? _candidateSince;
  DateTime? _irrelevantSince;
  DateTime? _poorGpsSince;
  String? _candidateId;
  CameraRecord? _activeCamera;
  double? _minimumDistanceMeters;
  double? _displayDistanceMeters;

  double _vehicleLatitude = 0;
  double _vehicleLongitude = 0;
  double _vehicleHeadingDeg = 0;
  double _vehicleSpeedKph = 0;
  bool _gpsUsable = false;
  double _gpsConfidence = 0;
  double _gpsAgeMs = -1;
  double _gpsAccuracyM = 999;
  double _speedAccuracyMps = -1;
  double _bearingAccuracyDeg = -1;

  double? _previousTrackLatitude;
  double? _previousTrackLongitude;
  double? _trackHeadingDeg;
  double _trackHeadingConfidence = 0;

  bool _initialized = false;
  bool _refreshRequested = false;
  DateTime? _lastRefreshAttemptAt;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    await repository.initialize();
    _countdownTimer = Timer.periodic(
      const Duration(milliseconds: 250),
      (_) => _countdownTick(),
    );
    _publish();
  }

  void updateVehicle({
    required double latitude,
    required double longitude,
    required double headingDeg,
    required double speedKph,
    required bool gpsUsable,
    required double gpsConfidence,
    required double gpsAgeMs,
    required double gpsAccuracyM,
    required double speedAccuracyMps,
    required double bearingAccuracyDeg,
  }) {
    _updateTrackHeading(latitude, longitude);
    _vehicleLatitude = latitude;
    _vehicleLongitude = longitude;
    _vehicleHeadingDeg = (headingDeg % 360 + 360) % 360;
    _vehicleSpeedKph = speedKph.clamp(0.0, 260.0).toDouble();
    _gpsUsable = gpsUsable;
    _gpsConfidence = gpsConfidence.clamp(0.0, 1.0).toDouble();
    _gpsAgeMs = gpsAgeMs;
    _gpsAccuracyM = gpsAccuracyM;
    _speedAccuracyMps = speedAccuracyMps;
    _bearingAccuracyDeg = bearingAccuracyDeg;

    final now = DateTime.now();
    if (_lastEvaluationAt != null &&
        now.difference(_lastEvaluationAt!) < const Duration(milliseconds: 160)) {
      return;
    }
    _lastEvaluationAt = now;
    _evaluate(now);
    _maybeRefreshRepository();
  }

  void _updateTrackHeading(double latitude, double longitude) {
    final previousLat = _previousTrackLatitude;
    final previousLon = _previousTrackLongitude;
    if (previousLat != null && previousLon != null) {
      final distance = _distanceMeters(previousLat, previousLon, latitude, longitude);
      if (distance >= 5.0 && distance <= 120.0) {
        final measured = _initialBearing(previousLat, previousLon, latitude, longitude);
        final old = _trackHeadingDeg;
        if (old == null) {
          _trackHeadingDeg = measured;
          _trackHeadingConfidence = 0.45;
        } else {
          final delta = _signedAngleDifference(measured, old);
          _trackHeadingDeg = (old + delta * 0.32 + 360) % 360;
          _trackHeadingConfidence = math.min(1.0, _trackHeadingConfidence + 0.08);
        }
      }
    }
    _previousTrackLatitude = latitude;
    _previousTrackLongitude = longitude;
  }

  void _maybeRefreshRepository() {
    if (!_gpsUsable || _refreshRequested || repository.syncInProgress) return;
    final now = DateTime.now();
    if (_lastRefreshAttemptAt != null &&
        now.difference(_lastRefreshAttemptAt!) < const Duration(minutes: 2)) {
      return;
    }
    _lastRefreshAttemptAt = now;
    _refreshRequested = true;
    unawaited(() async {
      try {
        await repository.refreshAround(_vehicleLatitude, _vehicleLongitude);
        if (_gpsUsable) _evaluate(DateTime.now());
      } finally {
        _refreshRequested = false;
        _publish();
      }
    }());
  }

  bool get _hardGpsQualityOk {
    if (!_gpsUsable) return false;
    if (_gpsAgeMs >= 0 && _gpsAgeMs > 5200) return false;
    if (_gpsAccuracyM > 0 && _gpsAccuracyM > 80) return false;
    if (_gpsConfidence < 0.08) return false;
    return true;
  }

  bool get _acquisitionGpsQualityOk {
    if (!_hardGpsQualityOk) return false;
    if (_gpsAgeMs >= 0 && _gpsAgeMs > 2800) return false;
    if (_gpsAccuracyM > 0 && _gpsAccuracyM > 48) return false;
    if (_gpsConfidence < 0.20) return false;
    if (_vehicleSpeedKph >= 25 &&
        _speedAccuracyMps >= 0 &&
        _speedAccuracyMps > 5.0) {
      return false;
    }
    return true;
  }

  void _evaluate(DateTime now) {
    if (!_hardGpsQualityOk) {
      _poorGpsSince ??= now;
      if (_activeCamera != null &&
          now.difference(_poorGpsSince!) < const Duration(milliseconds: 2400)) {
        _publishActiveWithoutGeometry();
        return;
      }
      _markIrrelevant(now);
      return;
    }
    _poorGpsSince = null;

    final active = _activeCamera;
    if (active != null) {
      final distance = _distanceMeters(
        _vehicleLatitude,
        _vehicleLongitude,
        active.latitude,
        active.longitude,
      );
      final aheadDelta = _angleDifference(
        _effectiveRoadHeading,
        _initialBearing(
          _vehicleLatitude,
          _vehicleLongitude,
          active.latitude,
          active.longitude,
        ),
      );
      _updateActive(now, active, distance, aheadDelta);
      if (_activeCamera != null) return;
    }

    if (!_acquisitionGpsQualityOk) {
      _candidateId = null;
      _candidateSince = null;
      _publish();
      return;
    }

    final candidate = _selectCandidate();
    if (candidate == null) {
      _candidateId = null;
      _candidateSince = null;
      _markIrrelevant(now);
      return;
    }

    final camera = candidate.camera;
    if (_candidateId != camera.id) {
      _candidateId = camera.id;
      _candidateSince = now;
      _publish();
      return;
    }

    final since = _candidateSince ?? now;
    final stableFor = _gpsConfidence >= 0.55 ? 320 : 520;
    if (now.difference(since) < Duration(milliseconds: stableFor)) return;
    _activate(camera, candidate.distanceMeters);
  }

  double get _effectiveRoadHeading {
    final track = _trackHeadingDeg;
    if (track == null || _trackHeadingConfidence < 0.35 || _vehicleSpeedKph < 7) {
      return _vehicleHeadingDeg;
    }
    final delta = _signedAngleDifference(track, _vehicleHeadingDeg);
    final trackWeight = (_trackHeadingConfidence * 0.45).clamp(0.15, 0.45);
    return (_vehicleHeadingDeg + delta * trackWeight + 360) % 360;
  }

  _Candidate? _selectCandidate() {
    final qualityScale = (0.58 + _gpsConfidence * 0.42).clamp(0.58, 1.0);
    final radius = _alertRadiusMeters(_vehicleSpeedKph) * qualityScale;
    final roadHeading = _effectiveRoadHeading;
    _Candidate? best;

    for (final camera in repository.records) {
      final distance = _distanceMeters(
        _vehicleLatitude,
        _vehicleLongitude,
        camera.latitude,
        camera.longitude,
      );
      if (distance > radius || distance < 2) continue;

      final bearing = _initialBearing(
        _vehicleLatitude,
        _vehicleLongitude,
        camera.latitude,
        camera.longitude,
      );
      final aheadDelta = _angleDifference(roadHeading, bearing);
      final qualityTightening = _gpsConfidence < 0.35 ? 10.0 : 0.0;
      final aheadGate = (_vehicleSpeedKph < 8 ? 88.0 : 62.0) - qualityTightening;
      if (aheadDelta > aheadGate) continue;

      final angleRad = aheadDelta * math.pi / 180.0;
      final forwardMeters = distance * math.cos(angleRad);
      final crossTrackMeters = (distance * math.sin(angleRad)).abs();
      if (forwardMeters <= 0) continue;
      var corridorMeters = 58.0 + math.min(135.0, forwardMeters * 0.115);
      if (_vehicleSpeedKph < 25) corridorMeters += 24.0;
      if (_gpsAccuracyM > 0) corridorMeters += math.min(28.0, _gpsAccuracyM * 0.35);
      if (camera.headingDeg != null) corridorMeters *= 0.86;
      if (crossTrackMeters > corridorMeters) continue;

      final cameraHeading = camera.headingDeg;
      if (cameraHeading != null) {
        var directionGate = 48.0;
        if (_bearingAccuracyDeg >= 0) {
          directionGate += math.min(12.0, _bearingAccuracyDeg * 0.18);
        }
        if (_angleDifference(roadHeading, cameraHeading) > directionGate) continue;
      }

      final qualityPenalty = (1.0 - _gpsConfidence) * 120.0;
      final crossTrackPenalty = crossTrackMeters * 1.35;
      final score = distance +
          aheadDelta * 2.3 +
          crossTrackPenalty +
          qualityPenalty -
          camera.confidence * 90.0;
      if (best == null || score < best.score) {
        best = _Candidate(
          camera: camera,
          distanceMeters: distance,
          score: score,
        );
      }
    }
    return best;
  }

  void _activate(CameraRecord camera, double distanceMeters) {
    _activeCamera = camera;
    _minimumDistanceMeters = distanceMeters;
    _displayDistanceMeters = distanceMeters;
    _irrelevantSince = null;
    _snapshot = CameraAlertSnapshot(
      phase: CameraAlertPhase.entering,
      camera: camera,
      vehicleSpeedKph: _vehicleSpeedKph,
      rawDistanceMeters: distanceMeters,
      displayDistanceMeters: distanceMeters,
      cachedCameraCount: repository.records.length,
      usingOfflineCache: repository.usingOfflineCache,
      syncInProgress: repository.syncInProgress,
    );
    notifyListeners();
    Timer(const Duration(milliseconds: 24), () {
      if (_activeCamera?.id != camera.id ||
          _snapshot.phase != CameraAlertPhase.entering) {
        return;
      }
      final distance = _snapshot.rawDistanceMeters;
      _snapshot = CameraAlertSnapshot(
        phase: distance <= 150 ? CameraAlertPhase.near : CameraAlertPhase.visible,
        camera: camera,
        vehicleSpeedKph: _vehicleSpeedKph,
        rawDistanceMeters: distance,
        displayDistanceMeters: _displayDistanceMeters ?? distance,
        cachedCameraCount: repository.records.length,
        usingOfflineCache: repository.usingOfflineCache,
        syncInProgress: repository.syncInProgress,
      );
      notifyListeners();
    });
  }

  void _updateActive(
    DateTime now,
    CameraRecord camera,
    double rawDistance,
    double aheadDelta,
  ) {
    final minimum = _minimumDistanceMeters;
    if (minimum == null || rawDistance < minimum) {
      _minimumDistanceMeters = rawDistance;
    }

    final minDistance = _minimumDistanceMeters ?? rawDistance;
    final definitelyBehind = aheadDelta > 105.0;
    final movedPastMinimum = rawDistance > minDistance + 20.0;
    final closePass = minDistance <= 70.0 && movedPastMinimum && definitelyBehind;
    final directPass = minDistance <= 28.0 && rawDistance > minDistance + 12.0;

    if (closePass || directPass) {
      _beginExit(CameraAlertPhase.passed);
      return;
    }

    final allowed = _alertRadiusMeters(_vehicleSpeedKph) + 180.0;
    if (rawDistance > allowed || aheadDelta > 125.0) {
      _markIrrelevant(now);
      return;
    }
    _irrelevantSince = null;

    final currentDisplay = _displayDistanceMeters;
    if (currentDisplay == null) {
      _displayDistanceMeters = rawDistance;
    } else if (rawDistance <= currentDisplay) {
      _displayDistanceMeters = currentDisplay * 0.28 + rawDistance * 0.72;
    } else if (rawDistance > currentDisplay + 32.0) {
      _displayDistanceMeters = currentDisplay * 0.45 + rawDistance * 0.55;
    }

    final phase = rawDistance <= 150
        ? CameraAlertPhase.near
        : _snapshot.phase == CameraAlertPhase.entering
            ? CameraAlertPhase.entering
            : CameraAlertPhase.visible;
    _snapshot = CameraAlertSnapshot(
      phase: phase,
      camera: camera,
      vehicleSpeedKph: _vehicleSpeedKph,
      rawDistanceMeters: rawDistance,
      displayDistanceMeters: _displayDistanceMeters ?? rawDistance,
      cachedCameraCount: repository.records.length,
      usingOfflineCache: repository.usingOfflineCache,
      syncInProgress: repository.syncInProgress,
    );
    notifyListeners();
  }

  void _publishActiveWithoutGeometry() {
    final camera = _activeCamera;
    if (camera == null) return;
    _snapshot = CameraAlertSnapshot(
      phase: _snapshot.phase,
      camera: camera,
      vehicleSpeedKph: _vehicleSpeedKph,
      rawDistanceMeters: _snapshot.rawDistanceMeters,
      displayDistanceMeters: _displayDistanceMeters ?? _snapshot.displayDistanceMeters,
      cachedCameraCount: repository.records.length,
      usingOfflineCache: repository.usingOfflineCache,
      syncInProgress: repository.syncInProgress,
    );
    notifyListeners();
  }

  void _markIrrelevant(DateTime now) {
    if (_activeCamera == null) {
      _publish();
      return;
    }
    _irrelevantSince ??= now;
    if (now.difference(_irrelevantSince!) >= const Duration(milliseconds: 1200)) {
      _beginExit(CameraAlertPhase.exiting);
    }
  }

  void _beginExit(CameraAlertPhase reason) {
    if (_activeCamera == null || _snapshot.phase == CameraAlertPhase.exiting) return;
    final camera = _activeCamera;
    _snapshot = CameraAlertSnapshot(
      phase: reason,
      camera: camera,
      vehicleSpeedKph: _vehicleSpeedKph,
      rawDistanceMeters: _snapshot.rawDistanceMeters,
      displayDistanceMeters: _snapshot.displayDistanceMeters,
      cachedCameraCount: repository.records.length,
      usingOfflineCache: repository.usingOfflineCache,
      syncInProgress: repository.syncInProgress,
    );
    notifyListeners();
    Timer(const Duration(milliseconds: 320), () {
      if (_activeCamera?.id != camera?.id) return;
      _snapshot = CameraAlertSnapshot(
        phase: CameraAlertPhase.exiting,
        camera: camera,
        vehicleSpeedKph: _vehicleSpeedKph,
        rawDistanceMeters: _snapshot.rawDistanceMeters,
        displayDistanceMeters: _snapshot.displayDistanceMeters,
        cachedCameraCount: repository.records.length,
        usingOfflineCache: repository.usingOfflineCache,
        syncInProgress: repository.syncInProgress,
      );
      notifyListeners();
      Timer(const Duration(milliseconds: 360), _finishExit);
    });
  }

  void _finishExit() {
    _activeCamera = null;
    _candidateId = null;
    _candidateSince = null;
    _irrelevantSince = null;
    _poorGpsSince = null;
    _minimumDistanceMeters = null;
    _displayDistanceMeters = null;
    _publish();
  }

  void _countdownTick() {
    final camera = _activeCamera;
    if (camera == null || !_snapshot.isEnteringOrVisible) {
      _lastCountdownTick = DateTime.now();
      return;
    }
    final now = DateTime.now();
    final previous = _lastCountdownTick ?? now;
    _lastCountdownTick = now;
    final dt = (now.difference(previous).inMilliseconds / 1000.0)
        .clamp(0.0, 0.6)
        .toDouble();
    if (dt <= 0) return;
    final speedMps = _vehicleSpeedKph / 3.6;
    final current = _displayDistanceMeters ?? _snapshot.rawDistanceMeters;
    if (current.isFinite && speedMps > 0.5) {
      _displayDistanceMeters = math.max(0.0, current - speedMps * dt);
      _snapshot = CameraAlertSnapshot(
        phase: _snapshot.phase,
        camera: camera,
        vehicleSpeedKph: _vehicleSpeedKph,
        rawDistanceMeters: _snapshot.rawDistanceMeters,
        displayDistanceMeters: _displayDistanceMeters!,
        cachedCameraCount: repository.records.length,
        usingOfflineCache: repository.usingOfflineCache,
        syncInProgress: repository.syncInProgress,
      );
      notifyListeners();
    }
  }

  void _publish() {
    if (_activeCamera == null) {
      _snapshot = CameraAlertSnapshot.hidden(
        cachedCameraCount: repository.records.length,
        usingOfflineCache: repository.usingOfflineCache,
        syncInProgress: repository.syncInProgress,
      );
    }
    notifyListeners();
  }

  double _alertRadiusMeters(double speedKph) {
    if (speedKph >= 100) return 1250;
    if (speedKph >= 70) return 1000;
    if (speedKph >= 35) return 820;
    return 650;
  }

  double _angleDifference(double a, double b) =>
      ((a - b + 540) % 360 - 180).abs();

  double _signedAngleDifference(double target, double source) =>
      ((target - source + 540) % 360) - 180;

  double _initialBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earth = 6371000.0;
    final p1 = lat1 * math.pi / 180;
    final p2 = lat2 * math.pi / 180;
    final dp = (lat2 - lat1) * math.pi / 180;
    final dl = (lon2 - lon1) * math.pi / 180;
    final a = math.sin(dp / 2) * math.sin(dp / 2) +
        math.cos(p1) * math.cos(p2) * math.sin(dl / 2) * math.sin(dl / 2);
    return earth * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    repository.dispose();
    super.dispose();
  }
}

class _Candidate {
  const _Candidate({
    required this.camera,
    required this.distanceMeters,
    required this.score,
  });

  final CameraRecord camera;
  final double distanceMeters;
  final double score;
}
