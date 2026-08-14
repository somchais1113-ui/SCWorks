import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../services/drive_telemetry_service.dart';

class SpeedDebugOverlay extends StatefulWidget {
  const SpeedDebugOverlay({required this.telemetry, super.key});

  final DriveTelemetryService telemetry;

  @override
  State<SpeedDebugOverlay> createState() => _SpeedDebugOverlayState();
}

class _SpeedDebugOverlayState extends State<SpeedDebugOverlay>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Timer? _fpsTimer;
  int _frames = 0;
  int _fps = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) => _frames++)..start();
    _fpsTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _fps = _frames;
        _frames = 0;
      });
    });
    unawaited(widget.telemetry.refreshSpeedLogPath());
  }

  @override
  void dispose() {
    _fpsTimer?.cancel();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.telemetry;
    final speedAccuracy = t.speedAccuracyMps < 0
        ? '--'
        : '±${t.speedAccuracyMps.toStringAsFixed(2)} m/s';
    final gpsAge = t.gpsAgeMs < 0 ? '--' : '${t.gpsAgeMs.toStringAsFixed(0)} ms';
    return RepaintBoundary(
      child: Container(
        width: 300,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xE6070A0E),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFF335267)),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Color(0x66000000), blurRadius: 12),
          ],
        ),
        child: DefaultTextStyle(
          style: const TextStyle(
            color: Color(0xFFD6DEE7),
            fontSize: 9,
            height: 1.25,
            fontWeight: FontWeight.w500,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const Text(
                'VEHICLE SPEED ENGINE • DEV',
                style: TextStyle(
                  color: Color(0xFF39BFF0),
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(height: 7),
              _row('RAW GPS SPEED', '${t.rawGpsSpeedKph.toStringAsFixed(1)} km/h'),
              _row('PREDICTED SPEED', '${t.predictedSpeedKph.toStringAsFixed(1)} km/h'),
              _row('ESTIMATED SPEED', '${t.estimatedSpeedKph.toStringAsFixed(1)} km/h'),
              _row('DISPLAY SPEED', '${t.displaySpeedKph.toStringAsFixed(1)} km/h'),
              const Divider(height: 10, color: Color(0xFF26313B)),
              _row('GPS RATE', '${t.gpsRateHz.toStringAsFixed(2)} Hz'),
              _row('GPS AGE', gpsAge),
              _row('GPS ACCURACY', '±${t.accuracyM.toStringAsFixed(1)} m'),
              _row('SPEED ACCURACY', speedAccuracy),
              _row('GPS CONFIDENCE', t.gpsConfidence.toStringAsFixed(2)),
              _row('FORWARD ACCEL', '${t.forwardAccelerationMps2 >= 0 ? '+' : ''}${t.forwardAccelerationMps2.toStringAsFixed(2)} m/s²'),
              _row('FILTER ACCEL', '${t.accelerationMps2 >= 0 ? '+' : ''}${t.accelerationMps2.toStringAsFixed(2)} m/s²'),
              _row('RAW ACCEL', '${t.rawAccelMps2.toStringAsFixed(2)} m/s²'),
              _row('FILTER GAIN', t.filterGain.toStringAsFixed(2)),
              const Divider(height: 10, color: Color(0xFF26313B)),
              _row('IMU RATE', '${t.imuRateHz.toStringAsFixed(1)} Hz'),
              _row('ENGINE RATE', '${t.engineRateHz.toStringAsFixed(1)} Hz'),
              _row('UI FPS', '$_fps'),
              _row('NATIVE PROCESSING', '${t.nativeProcessingMs.toStringAsFixed(2)} ms'),
              _row('BRIDGE LATENCY', '${t.bridgeLatencyMs.toStringAsFixed(2)} ms'),
              _row('IMU', t.imuAvailable ? (t.imuCalibrated ? 'CALIBRATED' : 'CALIBRATING') : 'GNSS ONLY'),
              _row('STATE', t.vehicleState),
              _row('STALE', t.isStale ? 'YES' : 'NO'),
              if (t.speedLogPath != null) ...<Widget>[
                const SizedBox(height: 5),
                Text(
                  'CSV: ${t.speedLogPath}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF8795A5), fontSize: 8),
                ),
              ],
              const SizedBox(height: 5),
              const Text(
                'Long-press gauge to close',
                style: TextStyle(color: Color(0xFF72808F), fontSize: 8),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        children: <Widget>[
          Expanded(child: Text(label, style: const TextStyle(color: Color(0xFF7F8D9B)))),
          const SizedBox(width: 8),
          Text(value, textAlign: TextAlign.right),
        ],
      ),
    );
  }
}
