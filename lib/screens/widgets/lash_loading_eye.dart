import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight vector animation: repaints its own layer, without rebuilding
/// the camera or the page. Its cycle never controls camera readiness.
class LashLoadingEye extends StatefulWidget {
  const LashLoadingEye({super.key});
  @override
  State<LashLoadingEye> createState() => _LashLoadingEyeState();
}

class _LashLoadingEyeState extends State<LashLoadingEye>
    with SingleTickerProviderStateMixin {
  late final AnimationController _motion = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _motion.stop();
      _motion.value = 0;
    } else if (!_motion.isAnimating) {
      _motion.repeat();
    }
  }

  @override
  void dispose() {
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Preparando la cámara',
    image: true,
    child: RepaintBoundary(
      child: SizedBox(
        width: 248,
        height: 216,
        child: CustomPaint(painter: _LashEyePainter(_motion)),
      ),
    ),
  );
}

class _LashEyePainter extends CustomPainter {
  _LashEyePainter(this.motion) : super(repaint: motion);
  final Animation<double> motion;
  static const gold = Color(0xFFE2C990);
  @override
  void paint(Canvas canvas, Size size) {
    final t = motion.value;
    final pulse = .5 + .5 * math.sin(t * math.pi * 2);
    final blink = (1 - (t - .54).abs() / .065).clamp(0.0, 1.0);
    final open = 1 - .96 * Curves.easeInOut.transform(blink);
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * .40;
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .7;
    for (var i = 0; i < 3; i++) {
      ring.color = gold.withValues(alpha: .06 + .025 * pulse);
      canvas.drawCircle(center, radius + i * 9, ring);
    }
    final orbit = Rect.fromCircle(center: center, radius: radius + 9);
    canvas.drawArc(
      orbit,
      -math.pi * .8 + t * math.pi * 2,
      .58,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round
        ..color = gold.withValues(alpha: .55),
    );
    canvas.save();
    canvas.translate(center.dx, center.dy + 8);
    canvas.scale(size.width * .42);
    final eye = Path()
      ..moveTo(-.82, 0)
      ..quadraticBezierTo(0, -.84 * open, .82, 0)
      ..quadraticBezierTo(0, .53 * open, -.82, 0)
      ..close();
    final goldStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = .018
      ..strokeCap = StrokeCap.round
      ..color = gold;
    canvas.drawPath(
      eye,
      Paint()..color = const Color(0xFF183C34).withValues(alpha: .7),
    );
    canvas.save();
    canvas.clipPath(eye);
    final iris = Offset(.025 * math.sin(t * 2 * math.pi), -.02);
    canvas.drawCircle(
      iris,
      .255,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFF0B211C), Color(0xFF5D8D72), Color(0xFFB8BE85)],
        ).createShader(Rect.fromCircle(center: iris, radius: .255)),
    );
    canvas.drawCircle(
      iris,
      .245,
      goldStroke
        ..color = gold.withValues(alpha: .65)
        ..strokeWidth = .010,
    );
    for (var i = 0; i < 22; i++) {
      final angle = i * math.pi * 2 / 22;
      canvas.drawLine(
        iris + Offset(math.cos(angle), math.sin(angle)) * .13,
        iris + Offset(math.cos(angle + .07), math.sin(angle + .07)) * .23,
        Paint()
          ..color = gold.withValues(alpha: .22)
          ..strokeWidth = .006,
      );
    }
    canvas.drawCircle(iris, .115, Paint()..color = const Color(0xFF061A15));
    canvas.drawCircle(
      iris + const Offset(-.07, -.085),
      .039,
      Paint()..color = const Color(0xFFFFF5DB).withValues(alpha: .9),
    );
    canvas.drawCircle(
      iris + const Offset(.065, .06),
      .015,
      Paint()..color = gold.withValues(alpha: .6),
    );
    canvas.restore();
    goldStroke
      ..color = gold
      ..strokeWidth = .018;
    canvas.drawPath(eye, goldStroke);
    // A tapered fan follows the upper lid throughout the blink.
    for (var i = 0; i < 13; i++) {
      final u = .055 + .89 * i / 12;
      final root = Offset(-.82 + 1.64 * u, -1.68 * u * (1 - u) * open);
      final tangent = Offset(1.64, -1.68 * (1 - 2 * u) * open);
      final normal = Offset(tangent.dy, -tangent.dx) / tangent.distance;
      final length = .12 + .17 * math.sin(math.pi * u) + .04 * u;
      final tip = root + normal * length + Offset((u - .5) * .12, -.025);
      final path = Path()
        ..moveTo(root.dx, root.dy)
        ..cubicTo(
          root.dx + normal.dx * length * .25,
          root.dy + normal.dy * length * .55,
          tip.dx - .015,
          tip.dy + .04,
          tip.dx,
          tip.dy,
        );
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = .014
          ..strokeCap = StrokeCap.round
          ..color = gold,
      );
    }
    final crease = Path()
      ..moveTo(-.63, -.19 * open - .12)
      ..quadraticBezierTo(0, -.65 * open - .12, .62, -.19 * open - .12);
    canvas.drawPath(
      crease,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .009
        ..color = gold.withValues(alpha: .22),
    );
    canvas.restore();
    // Small light accents stay within the illustration's own bounds.
    for (final (pos, r) in [
      (Offset(size.width * .84, size.height * .24), 3.0),
      (Offset(size.width * .16, size.height * .73), 2.0),
    ]) {
      final paint = Paint()
        ..color = gold.withValues(alpha: .35 + .35 * pulse)
        ..strokeWidth = .8;
      canvas.drawLine(pos - Offset(r, 0), pos + Offset(r, 0), paint);
      canvas.drawLine(pos - Offset(0, r), pos + Offset(0, r), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _LashEyePainter oldDelegate) =>
      oldDelegate.motion != motion;
}
