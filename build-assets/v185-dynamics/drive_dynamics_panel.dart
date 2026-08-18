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
  final List<_DynamicsSample> _samples = <_DynamicsSample>[];
  DateTime? _lastSampleAt;

  @override
  void initState() {
    super.initState();
    widget.telemetry.addListener(_onTelemetry);
    _appendSample(force: true);
  }

  @override
  void didUpdateWidget(covariant DriveDynamicsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.telemetry != widget.telemetry) {
      oldWidget.telemetry.removeListener(_onTelemetry);
      widget.telemetry.addListener(_onTelemetry);
      _samples.clear();
      _lastSampleAt = null;
      _appendSample(force: true);
    }
  }

  @override
  void dispose() {
    widget.telemetry.removeListener(_onTelemetry);
    super.dispose();
  }

  void _onTelemetry() => _appendSample();

  void _appendSample({bool force = false}) {
    final now = DateTime.now();
    final previous = _lastSampleAt;
    if (!force && previous != null && now.difference(previous).inMilliseconds < 90) {
      return;
    }
    _lastSampleAt = now;
    final t = widget.telemetry;
    _samples.add(
      _DynamicsSample(
        timestamp: now,
        speedKph: t.displaySpeedKph.clamp(0, 240).toDouble(),
        longitudinalG: t.filteredLongitudinalG.clamp(-2.0, 2.0).toDouble(),
        lateralG: t.lateralG.clamp(-2.0, 2.0).toDouble(),
      ),
    );
    final cutoff = now.subtract(const Duration(seconds: 30));
    _samples.removeWhere((sample) => sample.timestamp.isBefore(cutoff));
    if (mounted) setState(() {});
  }

  String _signedG(double value) {
    final normalized = value.abs() < 0.005 ? 0.0 : value;
    final sign = normalized >= 0 ? '+' : '-';
    return '$sign${normalized.abs().toStringAsFixed(2)} G';
  }

  @override
  Widget build(BuildContext context) {
    final t = widget.telemetry;
    final longitudinal = t.filteredLongitudinalG;
    final lateral = t.lateralG;
    final positivePeak = t.tripPeakPositiveG.abs();
    final negativePeak = t.tripPeakNegativeG <= 0
        ? t.tripPeakNegativeG
        : -t.tripPeakNegativeG.abs();

    return Padding(
      padding: EdgeInsets.fromLTRB(
        widget.compact ? 14 : 18,
        widget.compact ? 49 : 58,
        widget.compact ? 14 : 18,
        widget.compact ? 13 : 17,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final gap = widget.compact ? 10.0 : 14.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Expanded(
                flex: 25,
                child: _MetricColumn(
                  compact: widget.compact,
                  longitudinal: _signedG(longitudinal),
                  lateral: _signedG(lateral),
                  positivePeak: '+${positivePeak.toStringAsFixed(2)}',
                  negativePeak: negativePeak.toStringAsFixed(2),
                ),
              ),
              SizedBox(width: gap),
              const _DynamicsDivider(),
              SizedBox(width: gap),
              Expanded(
                flex: 40,
                child: _SpeedTracePanel(
                  compact: widget.compact,
                  samples: _samples,
                ),
              ),
              SizedBox(width: gap),
              const _DynamicsDivider(),
              SizedBox(width: gap),
              Expanded(
                flex: 35,
                child: _GgDiagramPanel(
                  compact: widget.compact,
                  samples: _samples,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MetricColumn extends StatelessWidget {
  const _MetricColumn({
    required this.compact,
    required this.longitudinal,
    required this.lateral,
    required this.positivePeak,
    required this.negativePeak,
  });

  final bool compact;
  final String longitudinal;
  final String lateral;
  final String positivePeak;
  final String negativePeak;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: <Widget>[
        _DynamicsMetric(
          label: 'LONGITUDINAL G',
          value: longitudinal,
          compact: compact,
        ),
        _DynamicsMetric(
          label: 'LATERAL G',
          value: lateral,
          compact: compact,
        ),
        _DynamicsMetric(
          label: 'PEAK G',
          value: '$positivePeak / $negativePeak',
          compact: compact,
        ),
      ],
    );
  }
}

class _DynamicsMetric extends StatelessWidget {
  const _DynamicsMetric({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.fade,
          softWrap: false,
          style: TextStyle(
            color: const Color(0xFF9CA6B2),
            fontFamily: 'NissanBrand',
            fontSize: compact ? 9.5 : 11.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.65,
          ),
        ),
        SizedBox(height: compact ? 4 : 6),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              color: Colors.white,
              fontFamily: 'NissanBrand',
              fontSize: compact ? 19 : 24,
              fontWeight: FontWeight.w400,
              letterSpacing: -0.25,
            ),
          ),
        ),
      ],
    );
  }
}

class _DynamicsDivider extends StatelessWidget {
  const _DynamicsDivider();

  @override
  Widget build(BuildContext context) {
    return Container(width: 1, color: const Color(0xFF252B33));
  }
}

class _SpeedTracePanel extends StatelessWidget {
  const _SpeedTracePanel({
    required this.compact,
    required this.samples,
  });

  final bool compact;
  final List<_DynamicsSample> samples;

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
              'km/h',
              style: TextStyle(
                color: const Color(0xFF6F7A87),
                fontFamily: 'NissanBrand',
                fontSize: compact ? 9 : 11,
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
            'TIME · LAST 30 SEC',
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

class _GgDiagramPanel extends StatelessWidget {
  const _GgDiagramPanel({
    required this.compact,
    required this.samples,
  });

  final bool compact;
  final List<_DynamicsSample> samples;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(
              'G-G DIAGRAM',
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
              'LIVE',
              style: TextStyle(
                color: const Color(0xFF39BFF0),
                fontFamily: 'NissanBrand',
                fontSize: compact ? 8.5 : 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.7,
              ),
            ),
          ],
        ),
        SizedBox(height: compact ? 5 : 7),
        Expanded(
          child: CustomPaint(
            painter: _GgDiagramPainter(samples: samples),
          ),
        ),
      ],
    );
  }
}

class _SpeedTracePainter extends CustomPainter {
  _SpeedTracePainter({required this.samples});

  final List<_DynamicsSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 26.0;
    const right = 4.0;
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
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    canvas.drawLine(plot.bottomLeft, plot.topLeft, axisPaint);
    canvas.drawLine(plot.bottomLeft, plot.bottomRight, axisPaint);

    final maxObserved = samples.fold<double>(0, (value, sample) => math.max(value, sample.speedKph));
    final ceiling = (math.max(120.0, (maxObserved / 20).ceil() * 20.0)).clamp(120.0, 240.0);
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
      painter.paint(canvas, Offset(plot.left - painter.width - 5, y - painter.height / 2));
    }

    if (samples.length < 2) return;
    final now = samples.last.timestamp;
    final start = now.subtract(const Duration(seconds: 30));
    final path = Path();
    var started = false;
    for (final sample in samples) {
      final elapsedMs = sample.timestamp.difference(start).inMilliseconds.clamp(0, 30000);
      final x = plot.left + plot.width * (elapsedMs / 30000.0);
      final y = plot.bottom - plot.height * (sample.speedKph / ceiling).clamp(0.0, 1.0);
      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);

    final last = samples.last;
    final lastY = plot.bottom - plot.height * (last.speedKph / ceiling).clamp(0.0, 1.0);
    canvas.drawCircle(
      Offset(plot.right, lastY),
      2.8,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant _SpeedTracePainter oldDelegate) => true;
}

class _GgDiagramPainter extends CustomPainter {
  _GgDiagramPainter({required this.samples});

  final List<_DynamicsSample> samples;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromLTWH(19, 13, math.max(1, size.width - 38), math.max(1, size.height - 26));
    final center = rect.center;
    final axisPaint = Paint()
      ..color = const Color(0xFF59636F)
      ..strokeWidth = 1;
    final guidePaint = Paint()
      ..color = const Color(0xFF252C34)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawLine(Offset(rect.left, center.dy), Offset(rect.right, center.dy), axisPaint);
    canvas.drawLine(Offset(center.dx, rect.top), Offset(center.dx, rect.bottom), axisPaint);
    canvas.drawOval(Rect.fromCenter(center: center, width: rect.width * 0.74, height: rect.height * 0.74), guidePaint);

    _paintLabel(canvas, 'LEFT', Offset(rect.left - 3, center.dy - 5), TextAlign.right);
    _paintLabel(canvas, 'RIGHT', Offset(rect.right + 3, center.dy - 5), TextAlign.left);
    _paintLabel(canvas, '+G ACCEL', Offset(center.dx, rect.top - 12), TextAlign.center);
    _paintLabel(canvas, '-G BRAKE', Offset(center.dx, rect.bottom + 3), TextAlign.center);

    if (samples.isEmpty) return;
    final recentCutoff = samples.last.timestamp.subtract(const Duration(seconds: 15));
    final recent = samples.where((sample) => !sample.timestamp.isBefore(recentCutoff)).toList(growable: false);
    var maxAbs = 0.6;
    for (final sample in recent) {
      maxAbs = math.max(maxAbs, sample.longitudinalG.abs());
      maxAbs = math.max(maxAbs, sample.lateralG.abs());
    }
    maxAbs = (maxAbs * 1.18).clamp(0.6, 1.5);

    for (var i = 0; i < recent.length; i++) {
      final sample = recent[i];
      final x = center.dx + (sample.lateralG / maxAbs).clamp(-1.0, 1.0) * rect.width / 2;
      final y = center.dy - (sample.longitudinalG / maxAbs).clamp(-1.0, 1.0) * rect.height / 2;
      final ageFraction = recent.length <= 1 ? 1.0 : i / (recent.length - 1);
      final alpha = (50 + ageFraction * 155).round().clamp(40, 220);
      canvas.drawCircle(
        Offset(x, y),
        i == recent.length - 1 ? 3.4 : 1.7,
        Paint()..color = i == recent.length - 1 ? Colors.white : Color.fromARGB(alpha, 57, 191, 240),
      );
    }
  }

  void _paintLabel(Canvas canvas, String text, Offset anchor, TextAlign align) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Color(0xFF77818D),
          fontSize: 7.5,
          fontFamily: 'NissanBrand',
          fontWeight: FontWeight.w600,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout();
    var dx = anchor.dx;
    if (align == TextAlign.center) dx -= painter.width / 2;
    if (align == TextAlign.right) dx -= painter.width;
    painter.paint(canvas, Offset(dx, anchor.dy));
  }

  @override
  bool shouldRepaint(covariant _GgDiagramPainter oldDelegate) => true;
}

class _DynamicsSample {
  const _DynamicsSample({
    required this.timestamp,
    required this.speedKph,
    required this.longitudinalG,
    required this.lateralG,
  });

  final DateTime timestamp;
  final double speedKph;
  final double longitudinalG;
  final double lateralG;
}
