from pathlib import Path

p = Path('lib/features/head_unit/head_unit_screen.dart')
text = p.read_text()
replacements = [
    ("fontFamily: 'sans-serif-light',\n                      fontSize: compact ? 44 : 55,\n                      height: 0.9,\n                      fontWeight: FontWeight.w300,\n                      letterSpacing: -1.35,", "fontFamily: 'NissanOpti',\n                      fontSize: compact ? 40 : 48,\n                      height: 0.92,\n                      fontWeight: FontWeight.w400,\n                      letterSpacing: -0.8,"),
    ("width: widget.compact ? 285 : 365,\n                        height: widget.compact ? 96 : 128,", "width: widget.compact ? 300 : 385,\n                        height: widget.compact ? 98 : 130,"),
    ("fontSize: widget.compact ? 112 : 150,\n                              height: 0.82,\n                              fontWeight: FontWeight.w300,\n                              letterSpacing: -3.2,", "fontFamily: 'NissanOpti',\n                              fontSize: widget.compact ? 104 : 138,\n                              height: 0.84,\n                              fontWeight: FontWeight.w400,\n                              letterSpacing: -2.4,"),
    ("fontSize: widget.compact ? 20 : 26,\n                          fontWeight: FontWeight.w400,", "fontFamily: 'NissanOpti',\n                          fontSize: widget.compact ? 18 : 24,\n                          fontWeight: FontWeight.w400,"),
    ("size: compact ? 58 : 70,", "size: compact ? 48 : 58,"),
    ("size: compact ? 76 : 92,", "size: compact ? 62 : 74,"),
    ("size: size * 0.48,", "size: primary ? size * 0.40 : size * 0.38,"),
    ("fontSize: compact ? 19 : 24,", "fontSize: compact ? 18 : 22,"),
]
for old, new in replacements:
    text = text.replace(old, new)
text = text.replace("style: TextStyle(\n                      color: Colors.white,\n                      fontSize: 22,\n                      fontWeight: FontWeight.w800,\n                      letterSpacing: 0.5,\n                    ),", "style: TextStyle(\n                      color: Colors.white,\n                      fontFamily: 'NissanOpti',\n                      fontSize: 22,\n                      fontWeight: FontWeight.w800,\n                      letterSpacing: 0.5,\n                    ),")
text = text.replace("style: TextStyle(\n                      color: Color(0xFF8A8F98),\n                      fontSize: 17,\n                      fontWeight: FontWeight.w500,\n                      letterSpacing: 0.2,\n                    ),", "style: TextStyle(\n                      color: Color(0xFF8A8F98),\n                      fontFamily: 'NissanOpti',\n                      fontSize: 17,\n                      fontWeight: FontWeight.w500,\n                      letterSpacing: 0.2,\n                    ),")
text = text.replace("style: const TextStyle(\n                color: Colors.white,\n                fontSize: 16,\n                fontWeight: FontWeight.w800,\n              ),", "style: const TextStyle(\n                color: Colors.white,\n                fontFamily: 'NissanOpti',\n                fontSize: 16,\n                fontWeight: FontWeight.w800,\n              ),")
text = text.replace("style: TextStyle(\n            color: const Color(0xFFCED1D6),\n            fontSize: math.max(12, radius * 0.071),\n            fontWeight: FontWeight.w500,\n          ),", "style: TextStyle(\n            color: const Color(0xFFCED1D6),\n            fontFamily: 'NissanOpti',\n            fontSize: math.max(12, radius * 0.071),\n            fontWeight: FontWeight.w500,\n          ),")
text = text.replace('OBD HARDWARE PROBE', 'OBD HARDWARE PROBE V2')
text = text.replace('PHASE 1 HARDWARE GATE: ATI is reported firmware only; OBD speed is logged and measured here but is NOT fused into the speedometer until 010D/010C rate, latency and stability are verified on the physical vehicle.', 'HARDWARE PROBE V2: Run with ENGINE RUNNING • transmission in P • parking brake engaged. OBD speed remains isolated from the speedometer until PID 010D is physically VERIFIED.')
p.write_text(text)

p = Path('lib/features/head_unit/drive_deck_panel.dart')
text = p.read_text()
old = '''  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..color = const Color(0x8839BFF0)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size.width * 0.43, halo);

    final body = Path()
      ..moveTo(size.width * 0.50, size.height * 0.06)
      ..lineTo(size.width * 0.84, size.height * 0.86)
      ..lineTo(size.width * 0.50, size.height * 0.70)
      ..lineTo(size.width * 0.16, size.height * 0.86)
      ..close();
    canvas.drawPath(
      body,
      Paint()
        ..color = coasting ? const Color(0xFFFFC56B) : const Color(0xFFF7FAFC)
        ..style = PaintingStyle.fill,
    );
    canvas.drawPath(
      body,
      Paint()
        ..color = const Color(0xFF0A1119)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(1.2, size.width * 0.06)
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawCircle(
      center,
      size.width * 0.10,
      Paint()..color = const Color(0xFF39BFF0),
    );
  }'''
new = '''  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final halo = Paint()
      ..color = const Color(0x44FF3B30)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, size.width * 0.43, halo);

    final body = Path()
      ..moveTo(size.width * 0.50, size.height * 0.05)
      ..lineTo(size.width * 0.86, size.height * 0.88)
      ..lineTo(size.width * 0.50, size.height * 0.72)
      ..lineTo(size.width * 0.14, size.height * 0.88)
      ..close();
    canvas.drawShadow(body, const Color(0xAA260707), 4.0, false);
    canvas.drawPath(body, Paint()..color = coasting ? const Color(0xFFD94C1A) : const Color(0xFFE53935)..style = PaintingStyle.fill);
    canvas.drawPath(body, Paint()..color = const Color(0xFF5E0F10)..style = PaintingStyle.stroke..strokeWidth = math.max(1.2, size.width * 0.055)..strokeJoin = StrokeJoin.round);
    canvas.drawCircle(center, size.width * 0.09, Paint()..color = const Color(0xFFFFE9E8));
  }'''
text = text.replace(old, new)
text = text.replace("style: const TextStyle(\n            color: Colors.white,\n            fontSize: 13,\n            fontWeight: FontWeight.w700,\n            letterSpacing: 0.2,\n          ),", "style: const TextStyle(\n            color: Colors.white,\n            fontFamily: 'NissanOpti',\n            fontSize: 13,\n            fontWeight: FontWeight.w700,\n            letterSpacing: 0.2,\n          ),")
p.write_text(text)

p = Path('pubspec.yaml')
text = p.read_text().replace('version: 1.7.0+20', 'version: 1.7.2+22')
p.write_text(text)
