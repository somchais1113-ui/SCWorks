import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../services/drive_telemetry_service.dart';

class DriveDynamicsPanel extends StatefulWidget {
  const DriveDynamicsPanel({
    required this.telemetry,
    required this.compact,
    super.key,
  });

  final DriveTelemetryService telemetry;
  final bool compact;

  @override
  State<DriveDynamicsPanel> createState() => _DriveDynamicsPanelState();
}

class _DriveDynamicsPanelState extends State<DriveDynamicsPanel> {
  static const Duration _renderPeriod = Duration(milliseconds: 33);
  static const Duration _speedSamplePeriod = Duration(milliseconds: 50);
  static const Duration _traceWindow = Duration(seconds: 20);

  final List<_SpeedSample> _speedSamples = <_SpeedSample>[];
  Timer? _renderTimer;
  DateTime? _lastSpeedSampleAt;

  double _longitudinalG = 0;
  double _lateralG = 0;
  double _combinedG = 0;
  double _peakG = 0;

  @override
  void initState() {
    super.initState();
    _refreshValues(forceSpeedSample: true);
    _renderTimer = Timer.periodic(_renderPeriod, (_) => _refreshValues());
  }

  @override
  void didUpdateWidget(covariant DriveDynamicsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.telemetry != widget.telemetry) {
      _speedSamples.clear();
      _lastSpeedSampleAt = null;
      _longitudinalG = 0;
      _lateralG = 0;
      _combinedG = 0;
      _peakG = 0;
      _refreshValues(forceSpeedSample: true);
    }
  }

  @override
  void dispose() {
    _renderTimer?.cancel();
    super.dispose();
  }

  void _refreshValues({bool forceSpeedSample = false}) {
    final now = DateTime.now();
    final t = widget.telemetry;

    final rawLong = t.longitudinalG.clamp(-2.0, 2.0).toDouble();
    final rawLat = t.lateralG.clamp(-2.0, 2.0).toDouble();
    const response = 0.72;

    _longitudinalG += (rawLong - _longitudinalG) * response;
    _lateralG += (rawLat - _lateralG) * response;

    if (_longitudinalG.abs() < 0.002) _longitudinalG = 0;
    if (_lateralG.abs() < 0.002) _lateralG = 0;

    _combinedG = math.sqrt(
      (_longitudinalG * _longitudinalG) + (_lateralG * _lateralG),
    );
    _peakG = math.max(_peakG, _combinedG);

    final lastSampleAt = _lastSpeedSampleAt;
    if (forceSpeedSample ||
        lastSampleAt == null ||
        now.difference(lastSampleAt) >= _speedSamplePeriod) {
      _lastSpeedSampleAt = now;
      _speedSamples.add(
        _SpeedSample(
          timestamp: now,
          speedKph: t.displaySpeedKph.clamp(0, 240).toDouble(),
        ),
      );
      final cutoff = now.subtract(_traceWindow);
      _speedSamples.removeWhere((sample) => sample.timestamp.isBefore(cutoff));
    }

    if (mounted) setState(() {});
  }

  String _signedG(double value) {
    final normalized = value.abs() < 0.002 ? 0.0 : value;
    return '${normalized >= 0 ? '+' : '-'}${normalized.abs().toStringAsFixed(2)} G';
  }

  String _unsignedG(double value) => '${value.abs().toStringAsFixed(2)} G';

  @override
  Widget build(BuildContext context) {
    final compact = widget.compact;
    final gap = compact ? 10.0 : 14.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        compact ? 14 : 18,
        compact ? 14 : 18,
        compact ? 14 : 18,
        compact ? 18 : 22,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            flex: 38,
            child: _MetricsPanel(
              compact: compact,
              longitudinalG: _signedG(_longitudinalG),
              lateralG: _signedG(_lateralG),
              combinedG: _unsignedG(_combinedG),
              peakG: _unsignedG(_peakG),
            ),
          ),
          SizedBox(width: gap),
          Container(width: 1, color: const Color(0xFF252B33)),
          SizedBox(width: gap),
          Expanded(
            flex: 62,
            child: _SpeedTracePanel(
              compact: compact,
              samples: _speedSamples,
              currentSpeedKph: widget.telemetry.displaySpeedKph,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricsPanel extends StatelessWidget {
  const _MetricsPanel({
    required this.compact,
    required this.longitudinalG,
    required this.lateralG,
    required this.combinedG,
    required this.peakG,
  });

  final bool compact;
  final String longitudinalG;
  final String lateralG;
  final String combinedG;
  final String peakG;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'DRIVE DYNAMICS',
              style: TextStyle(
                color: const Color(0xFF9CA6B2),
                fontFamily: 'NissanBrand',
                fontSize: compact ? 9.5 : 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.65,
              ),
            ),
            const Spacer(),
            Container(
              width: compact ? 5 : 6,
              height: compact ? 5 : 6,
              decoration: const BoxDecoration(
                color: Color(0xFF39BFF0),
                shape: BoxShape.circle,
              ),
            ),
            SizedBox(width: compact ? 4 : 5),
            Text(
              '30 FPS',
              style: TextStyle(
                color: const Color(0xFF39BFF0),
                fontFamily: 'NissanBrand',
                fontSize: compact ? 8 : 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.45,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 7 : 9),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: <Widget>[
              _MetricRow(
                compact: compact,
                label: 'LONGITUDINAL G',
                value: longitudinalG,
              ),
              _MetricRow(
                compact: compact,
                label: 'LATERAL G',
                value: lateralG,
              ),
              _MetricRow(
                compact: compact,
                label: 'COMBINED G',
                value: combinedG,
              ),
              _MetricRow(
                compact: compact,
                label: 'PEAK G',
                value: peakG,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricRow extends StatelessWidget {
  const _MetricRow({
    required this.compact,
    required this.label,
    required this.value,
  });

  final bool compact;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.fade,
            softWrap: false,
            style: TextStyle(
              color: const Color(0xFF89939F),
              fontFamily: 'NissanBrand',
              fontSize: compact ? 9.2 : 11.2,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.45,
            ),
          ),
        ),
        SizedBox(width: compact ? 8 : 10),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 45),
          switchInCurve: Curves.linear,
          switchOutCurve: Curves.linear,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: child,
          ),
          child: Text(
            value,
            key: ValueKey<String>(value),
            textAlign: TextAlign.right,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'NissanBrand',
              fontSize: compact ? 17 : 21,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.3,
              fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedTracePanel extends StatelessWidget {
  const _SpeedTracePanel({
    required this.compact,
    required this.samples,
    required this.currentSpeedKph,
  });

  final bool compact;
  final List<_SpeedSample> samples;
  final double currentSpeedKph;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'SPEED TRACE',
              style: TextStyle(
                color: const Color(0xFF9CA6B2),
                fontFamily: 'NissanBrand',
                fontSize: compact ? 9.5 : 11.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.65,
              ),
            ),
            const Spacer(),
            Text(
              '${currentSpeedKph.round()} km/h',
              style: TextStyle(
                color: Colors.white,
                fontFamily: 'NissanBrand',
                fontSize: compact ? 13 : 16,
                fontWeight: FontWeight.w500,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 7 : 9),
        Expanded(
          child: CustomPaint(
            painter: _SpeedTracePainter(samples: samples),
          ),
        ),
        SizedBox(height: compact ? 3 : 5),
        Align(
          alignment: Alignment.center,
          child: Text(
            'TIME · LAST 20 SEC',
            style: TextStyle(
              color: const Color(0xFF626C78),
              fontFamily: 'NissanBrand',
              fontSize: compact ? 8 : 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.45,
            ),
          ),
        ),
      ],
    );
  }
}

class _SpeedTracePainter extends CustomPainter {
  _SpeedTracePainter({required this.samples});

  final List<_SpeedSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 28.0;
    const right = 5.0;
    const top = 5.0;
    const bottom = 8.0;
    final plot = Rect.fromLTRB(left, top, size.width - right, size.height - bottom);
    if (plot.width <= 1 || plot.height <= 1) return;

    final axisPaint = Paint()
      ..color = const Color(0xFF48515C)
      ..strokeWidth = 1;
    final gridPaint = Paint()
      ..color = const Color(0xFF232A32)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF39BFF0)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);

    final maxObserved = samples.fold<double>(
      0,
      (value, sample) => math.max(value, sample.speedKph),
    );
    final stepped = math.max(40.0, (maxObserved / 20).ceil() * 20.0);
    final ceiling = stepped.clamp(40.0, 240.0).toDouble();

    const divisions = 4;
    for (var i = 1; i <= divisions; i++) {
      final fraction = i / divisions;
      final y = plot.bottom - plot.height * fraction;
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      final label = (ceiling * fraction).round().toString();
      final painter = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            color: Color(0xFF77818D),
            fontSize: 8,
            fontFamily: 'NissanBrand',
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
        canvas,
        Offset(plot.left - painter.width - 5, y - painter.height / 2),
      );
    }

    if (samples.length < 2) return;
    final now = samples.last.timestamp;
    final start = now.subtract(const Duration(seconds: 20));
    final path = Path();
    var started = false;
    for (final sample in samples) {
      final elapsedMs = sample.timestamp
          .difference(start)
          .inMilliseconds
          .clamp(0, 20000)
          .toInt();
      final x = plot.left + plot.width * (elapsedMs / 20000.0);
      final y = plot.bottom -
          plot.height * (sample.speedKph / ceiling).clamp(0.0, 1.0);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final last = samples.last;
    final lastY = plot.bottom -
        plot.height * (last.speedKph / ceiling).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(plot.right, lastY),
      3.2,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedTracePainter oldDelegate) => true;
}

class _SpeedSample {
  const _SpeedSample({required this.timestamp, required this.speedKph});

  final DateTime timestamp;
  final double speedKph;
}
