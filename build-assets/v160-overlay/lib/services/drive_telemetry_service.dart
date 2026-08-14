import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

import '../domain/teana_j32_powertrain.dart';

enum GpsState {
  checking,
  off,
  permissionDenied,
  permissionDeniedForever,
  searching,
  locked,
  signalLost,
}

class DriveTelemetryService extends ChangeNotifier {
  static const Duration _healthCheckEvery = Duration(seconds: 2);
  static const MethodChannel _platform =
      MethodChannel('com.scdeport.scdrive/headunit');
  static const EventChannel _speedEvents =
      EventChannel('com.scdeport.scdrive/speed');

  StreamSubscription<dynamic>? _speedSubscription;
  Timer? _healthTimer;
  bool _initialized = false;
  bool _starting = false;
  bool _engineStarted = false;
  bool _permissionGranted = false;
  bool _locationEnabled = false;
  String? _errorMessage;
  GpsState _gpsState = GpsState.checking;

  final Stopwatch _localMonotonic = Stopwatch()..start();
  double _nativeClockOffsetNanos = 0;
  bool _clockSynchronized = false;

  double _speedKph = 0;
  double _rawGpsSpeedKph = 0;
  double _predictedSpeedKph = 0;
  double _estimatedSpeedKph = 0;
  double _displaySpeedKph = 0;
  double _accelerationMps2 = 0;
  double _forwardAccelerationMps2 = 0;
  double _rawAccelMps2 = 0;
  double _gpsRateHz = 0;
  double _gpsAgeMs = -1;
  double _speedAccuracyMps = -1;
  double _gpsConfidence = 0;
  double _imuRateHz = 0;
  double _engineRateHz = 0;
  double _filterGain = 0;
  double _nativeProcessingMs = 0;
  double _bridgeLatencyMs = 0;
  bool _imuAvailable = false;
  bool _imuCalibrated = false;
  bool _isStale = true;
  String _vehicleState = 'SEARCHING';
  String? _speedLogPath;

  double _heading = 0;
  double _accuracyM = 0;
  double _latitude = 0;
  double _longitude = 0;
  bool _hasLocationFix = false;
  double _estimatedRpm = TeanaJ32Powertrain.idleRpm;
  double _estimatedCvtRatio = TeanaJ32Powertrain.cvtLowestRatio;
  double _driverLoad = 0;
  DateTime? _lastSampleAt;

  bool get permissionGranted => _permissionGranted;
  bool get locationEnabled => _locationEnabled;
  String? get errorMessage => _errorMessage;
  GpsState get gpsState => _gpsState;
  double get speedKph => _speedKph;
  double get rawGpsSpeedKph => _rawGpsSpeedKph;
  double get predictedSpeedKph => _predictedSpeedKph;
  double get estimatedSpeedKph => _estimatedSpeedKph;
  double get displaySpeedKph => _displaySpeedKph;
  double get accelerationMps2 => _accelerationMps2;
  double get forwardAccelerationMps2 => _forwardAccelerationMps2;
  double get rawAccelMps2 => _rawAccelMps2;
  double get gpsRateHz => _gpsRateHz;
  double get gpsAgeMs => _gpsAgeMs;
  double get speedAccuracyMps => _speedAccuracyMps;
  double get gpsConfidence => _gpsConfidence;
  double get imuRateHz => _imuRateHz;
  double get engineRateHz => _engineRateHz;
  double get filterGain => _filterGain;
  double get nativeProcessingMs => _nativeProcessingMs;
  double get bridgeLatencyMs => _bridgeLatencyMs;
  bool get imuAvailable => _imuAvailable;
  bool get imuCalibrated => _imuCalibrated;
  bool get isStale => _isStale;
  String get vehicleState => _vehicleState;
  String? get speedLogPath => _speedLogPath;
  double get heading => _heading;
  double get accuracyM => _accuracyM;
  double get latitude => _latitude;
  double get longitude => _longitude;
  bool get hasLocationFix => _hasLocationFix;
  bool get hasFreshLocationFix => _gpsState == GpsState.locked;
  double get estimatedRpm => _estimatedRpm;
  double get estimatedCvtRatio => _estimatedCvtRatio;
  DateTime? get lastSampleAt => _lastSampleAt;
  bool get gpsReady => hasFreshLocationFix;

  String get gpsStatusLabel => switch (_gpsState) {
        GpsState.checking => 'GPS CHECKING',
        GpsState.off => 'GPS OFF • TAP TO ENABLE',
        GpsState.permissionDenied => 'GPS PERMISSION • TAP',
        GpsState.permissionDeniedForever => 'GPS BLOCKED • OPEN SETTINGS',
        GpsState.searching => 'GPS SEARCHING…',
        GpsState.locked =>
          'GPS ${_accuracyM.toStringAsFixed(0)} m • ${_gpsRateHz.toStringAsFixed(1)} Hz',
        GpsState.signalLost => 'GPS SIGNAL LOST',
      };

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;
    _speedSubscription = _speedEvents.receiveBroadcastStream().listen(
      _handleNativeState,
      onError: (Object error) {
        _errorMessage = 'VehicleSpeedEngine: $error';
        _gpsState = GpsState.signalLost;
        notifyListeners();
      },
    );
    await _syncMonotonicClock();
    _healthTimer = Timer.periodic(
      _healthCheckEvery,
      (_) => unawaited(_checkGpsHealth()),
    );
    await start();
  }

  Future<void> start() async {
    if (_starting) return;
    _starting = true;
    try {
      _errorMessage = null;
      _gpsState = GpsState.checking;
      notifyListeners();

      _locationEnabled = await Geolocator.isLocationServiceEnabled();
      if (!_locationEnabled) {
        _permissionGranted = false;
        _gpsState = GpsState.off;
        _errorMessage = 'Android Location/GPS is turned off';
        await _stopNativeEngine();
        _invalidateLiveTelemetry(resetLastFix: true);
        notifyListeners();
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.deniedForever) {
        _permissionGranted = false;
        _gpsState = GpsState.permissionDeniedForever;
        _errorMessage = 'Location permission is blocked in Android settings';
        await _stopNativeEngine();
        _invalidateLiveTelemetry(resetLastFix: true);
        notifyListeners();
        return;
      }

      _permissionGranted = permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
      if (!_permissionGranted) {
        _gpsState = GpsState.permissionDenied;
        _errorMessage = 'Location permission is required for the speedometer';
        await _stopNativeEngine();
        _invalidateLiveTelemetry(resetLastFix: true);
        notifyListeners();
        return;
      }

      _gpsState = GpsState.searching;
      await _syncMonotonicClock();
      await _platform.invokeMethod<bool>('startSpeedEngine');
      _engineStarted = true;
      notifyListeners();
    } on PlatformException catch (error) {
      _errorMessage = 'Unable to start VehicleSpeedEngine: ${error.message}';
      _gpsState = GpsState.signalLost;
      notifyListeners();
    } finally {
      _starting = false;
    }
  }

  Future<void> resume() => start();

  Future<void> resolveGpsIssue() async {
    switch (_gpsState) {
      case GpsState.off:
        await Geolocator.openLocationSettings();
        break;
      case GpsState.permissionDeniedForever:
        await Geolocator.openAppSettings();
        break;
      case GpsState.permissionDenied:
      case GpsState.signalLost:
      case GpsState.searching:
      case GpsState.checking:
        await start();
        break;
      case GpsState.locked:
        break;
    }
  }

  Future<void> setSpeedDebugEnabled(bool enabled) async {
    await _platform.invokeMethod<bool>(
      'setSpeedDebugEnabled',
      <String, Object>{'enabled': enabled},
    );
    if (enabled) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      _speedLogPath = await _platform.invokeMethod<String>('getSpeedLogPath');
    }
  }

  Future<void> refreshSpeedLogPath() async {
    _speedLogPath = await _platform.invokeMethod<String>('getSpeedLogPath');
    notifyListeners();
  }

  Future<void> _syncMonotonicClock() async {
    try {
      final before = _localMonotonic.elapsedMicroseconds * 1000;
      final native = await _platform.invokeMethod<int>('getElapsedRealtimeNanos');
      final after = _localMonotonic.elapsedMicroseconds * 1000;
      if (native == null) return;
      final midpoint = (before + after) / 2.0;
      _nativeClockOffsetNanos = native - midpoint;
      _clockSynchronized = true;
    } on PlatformException {
      _clockSynchronized = false;
    }
  }

  Future<void> _checkGpsHealth() async {
    if (!_initialized || _starting) return;
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      if (_gpsState != GpsState.off || _locationEnabled) {
        _locationEnabled = false;
        _gpsState = GpsState.off;
        _errorMessage = 'Android Location/GPS is turned off';
        await _stopNativeEngine();
        _invalidateLiveTelemetry(resetLastFix: true);
        notifyListeners();
      }
      return;
    }
    if (!_locationEnabled) {
      _locationEnabled = true;
      await start();
    } else if (_permissionGranted && !_engineStarted) {
      await start();
    }
  }

  void _handleNativeState(dynamic event) {
    if (event is! Map) return;
    final map = Map<Object?, Object?>.from(event);
    double number(String key, [double fallback = 0]) {
      final value = map[key];
      return value is num ? value.toDouble() : fallback;
    }

    _rawGpsSpeedKph = number('rawGpsSpeedKmh');
    _predictedSpeedKph = number('predictedSpeedKmh');
    _estimatedSpeedKph = number('estimatedSpeedKmh');
    _displaySpeedKph = number('displaySpeedKmh');
    _speedKph = _estimatedSpeedKph;
    _accelerationMps2 = number('accelerationMps2');
    _forwardAccelerationMps2 = number('forwardAccelerationMps2');
    _rawAccelMps2 = number('rawAccelMps2');
    _gpsRateHz = number('gpsRateHz');
    _gpsAgeMs = number('gpsAgeMs', -1);
    _accuracyM = number('gpsAccuracyM', 999);
    _speedAccuracyMps = number('gpsSpeedAccuracyMps', -1);
    _gpsConfidence = number('gpsConfidence');
    _imuRateHz = number('imuRateHz');
    _engineRateHz = number('engineRateHz');
    _filterGain = number('filterGain');
    _nativeProcessingMs = number('nativeProcessingMs');
    _imuAvailable = map['imuAvailable'] == true;
    _imuCalibrated = map['imuCalibrated'] == true;
    _isStale = map['isStale'] == true;
    _vehicleState = map['state']?.toString() ?? 'UNKNOWN';
    _latitude = number('latitude');
    _longitude = number('longitude');
    _heading = number('headingDeg');
    _speedLogPath = map['logPath']?.toString() ?? _speedLogPath;
    _hasLocationFix = map['hasGpsFix'] == true;

    final emittedNanos = map['emittedElapsedRealtimeNanos'];
    if (_clockSynchronized && emittedNanos is num) {
      final localNowAsNative =
          _localMonotonic.elapsedMicroseconds * 1000 + _nativeClockOffsetNanos;
      _bridgeLatencyMs = math.max(
        0,
        (localNowAsNative - emittedNanos.toDouble()) / 1000000.0,
      );
    }

    if (!_hasLocationFix) {
      _gpsState = GpsState.searching;
    } else if (_gpsAgeMs < 0 || _gpsAgeMs > 6000) {
      _gpsState = GpsState.signalLost;
    } else {
      _gpsState = GpsState.locked;
      _lastSampleAt = DateTime.now().subtract(
        Duration(milliseconds: _gpsAgeMs.round().clamp(0, 60000).toInt()),
      );
    }
    _errorMessage = null;
    _updatePowertrain();
    notifyListeners();
  }

  void _updatePowertrain() {
    final dt = (_engineRateHz > 1 ? 1 / _engineRateHz : 0.04)
        .clamp(0.02, 0.20)
        .toDouble();
    final requestedLoad =
        (math.max(0.0, _accelerationMps2) / 2.4).clamp(0.0, 1.0);
    final loadTau = requestedLoad > _driverLoad
        ? 0.34
        : (_accelerationMps2 < -0.35 ? 0.72 : 1.55);
    final loadAlpha = 1 - math.exp(-dt / loadTau);
    _driverLoad += (requestedLoad - _driverLoad) * loadAlpha;
    _driverLoad = _driverLoad.clamp(0.0, 1.0).toDouble();

    final effectiveLoadAccel = _accelerationMps2 < -0.25
        ? _accelerationMps2
        : math.max(_accelerationMps2, _driverLoad * 1.75);
    final targetCvt = TeanaJ32Powertrain.estimatedCvtRatio(
      speedKph: _estimatedSpeedKph,
      accelerationMps2: effectiveLoadAccel,
    );
    final targetRpm = TeanaJ32Powertrain.estimatedEngineRpm(
      speedKph: _estimatedSpeedKph,
      accelerationMps2: effectiveLoadAccel,
    );
    final ratioTau = targetCvt >= _estimatedCvtRatio ? 0.52 : 0.82;
    final rpmTau = targetRpm >= _estimatedRpm ? 0.42 : 0.88;
    _estimatedCvtRatio +=
        (targetCvt - _estimatedCvtRatio) * (1 - math.exp(-dt / ratioTau));
    _estimatedRpm +=
        (targetRpm - _estimatedRpm) * (1 - math.exp(-dt / rpmTau));
    _estimatedRpm = _estimatedRpm
        .clamp(TeanaJ32Powertrain.idleRpm, TeanaJ32Powertrain.displayMaxRpm)
        .toDouble();
  }

  Future<void> _stopNativeEngine() async {
    if (!_engineStarted) return;
    try {
      await _platform.invokeMethod<bool>('stopSpeedEngine');
    } on PlatformException {
      // The Activity may already be shutting down.
    }
    _engineStarted = false;
  }

  void _invalidateLiveTelemetry({bool resetLastFix = false}) {
    _speedKph = 0;
    _rawGpsSpeedKph = 0;
    _predictedSpeedKph = 0;
    _estimatedSpeedKph = 0;
    _displaySpeedKph = 0;
    _accelerationMps2 = 0;
    _forwardAccelerationMps2 = 0;
    _driverLoad = 0;
    _estimatedRpm = TeanaJ32Powertrain.idleRpm;
    _estimatedCvtRatio = TeanaJ32Powertrain.cvtLowestRatio;
    if (resetLastFix) {
      _hasLocationFix = false;
      _latitude = 0;
      _longitude = 0;
      _accuracyM = 0;
      _heading = 0;
      _lastSampleAt = null;
    }
  }

  String get compassLabel {
    final normalized = (_heading % 360 + 360) % 360;
    const labels = <String>['N', 'NE', 'E', 'SE', 'S', 'SW', 'W', 'NW'];
    return labels[((normalized + 22.5) ~/ 45) % 8];
  }

  @override
  void dispose() {
    _healthTimer?.cancel();
    final subscription = _speedSubscription;
    if (subscription != null) unawaited(subscription.cancel());
    unawaited(_stopNativeEngine());
    super.dispose();
  }
}
