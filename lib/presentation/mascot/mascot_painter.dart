import 'package:flutter/material.dart';
import '../../domain/mascot/mascot_state.dart';

/// Dibuja la mascota pixel art estilo peluche suave.
class MascotPainter extends CustomPainter {
  final MascotState state;
  final double animValue; // 0.0 → 1.0 animación continua

  const MascotPainter({required this.state, required this.animValue});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2 + (animValue * 4 - 2); // bob suave

    _drawBody(canvas, cx, cy, size);
    _drawFace(canvas, cx, cy);
    _drawAccessory(canvas, cx, cy);
  }

  void _drawBody(Canvas canvas, double cx, double cy, Size size) {
    final color = _bodyColor;
    final paint = Paint()..color = color;
    final shadowPaint = Paint()..color = Colors.black26;

    // Sombra
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, size.height - 18), width: 70, height: 14),
      shadowPaint,
    );

    // Cuerpo
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx, cy + 30), width: 90, height: 80),
      paint,
    );

    // Cabeza
    canvas.drawCircle(Offset(cx, cy - 10), 48, paint);

    // Brillo peluche
    canvas.drawCircle(
      Offset(cx - 14, cy - 24),
      14,
      Paint()..color = Colors.white.withOpacity(0.25),
    );

    // Orejas
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 36, cy - 48), width: 20, height: 26),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 36, cy - 48), width: 20, height: 26),
      paint,
    );
    // Interior orejas
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 36, cy - 48), width: 12, height: 16),
      Paint()..color = _earColor,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 36, cy - 48), width: 12, height: 16),
      Paint()..color = _earColor,
    );

    // Brazos
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 54, cy + 20), width: 20, height: 32),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 54, cy + 20), width: 20, height: 32),
      paint,
    );

    // Pies
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 24, cy + 70), width: 32, height: 18),
      paint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 24, cy + 70), width: 32, height: 18),
      paint,
    );
  }

  void _drawFace(Canvas canvas, double cx, double cy) {
    final eyePaint = Paint()..color = const Color(0xFF1a1a2e);
    final whitePaint = Paint()..color = Colors.white;
    final cheekPaint = Paint()
      ..color = Colors.pink.withOpacity(0.5);

    // Mejillas
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx - 28, cy + 4), width: 20, height: 14),
      cheekPaint,
    );
    canvas.drawOval(
      Rect.fromCenter(center: Offset(cx + 28, cy + 4), width: 20, height: 14),
      cheekPaint,
    );

    switch (state) {
      case MascotState.sleeping:
      case MascotState.tired:
        _drawTiredEyes(canvas, cx, cy);
        _drawSleepingMouth(canvas, cx, cy);
        break;
      case MascotState.celebrating:
        _drawStarEyes(canvas, cx, cy);
        _drawHappyMouth(canvas, cx, cy);
        break;
      case MascotState.alert:
        _drawWideEyes(canvas, cx, cy, eyePaint, whitePaint);
        _drawAlertMouth(canvas, cx, cy);
        break;
      default:
        // Ojos normales brillantes
        canvas.drawCircle(Offset(cx - 16, cy - 6), 10, whitePaint);
        canvas.drawCircle(Offset(cx + 16, cy - 6), 10, whitePaint);
        canvas.drawCircle(Offset(cx - 14, cy - 6), 7, eyePaint);
        canvas.drawCircle(Offset(cx + 18, cy - 6), 7, eyePaint);
        canvas.drawCircle(Offset(cx - 16, cy - 9), 3, whitePaint);
        canvas.drawCircle(Offset(cx + 16, cy - 9), 3, whitePaint);
        _drawHappyMouth(canvas, cx, cy);
    }
  }

  void _drawTiredEyes(Canvas canvas, double cx, double cy) {
    final p = Paint()
      ..color = _bodyColor.withRed((_bodyColor.red * 0.7).toInt())
      ..style = PaintingStyle.fill;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx - 16, cy - 4), width: 20, height: 8),
        const Radius.circular(4),
      ),
      p,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 16, cy - 4), width: 20, height: 8),
        const Radius.circular(4),
      ),
      p,
    );
  }

  void _drawStarEyes(Canvas canvas, double cx, double cy) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    tp.text = const TextSpan(text: '★', style: TextStyle(fontSize: 18, color: Color(0xFFFFD700)));
    tp.layout();
    tp.paint(canvas, Offset(cx - 26, cy - 16));
    tp.paint(canvas, Offset(cx + 8, cy - 16));
  }

  void _drawWideEyes(Canvas canvas, double cx, double cy, Paint eye, Paint white) {
    canvas.drawCircle(Offset(cx - 16, cy - 6), 12, white);
    canvas.drawCircle(Offset(cx + 16, cy - 6), 12, white);
    canvas.drawCircle(Offset(cx - 16, cy - 6), 7, eye);
    canvas.drawCircle(Offset(cx + 16, cy - 6), 7, eye);
  }

  void _drawHappyMouth(Canvas canvas, double cx, double cy) {
    final path = Path()
      ..moveTo(cx - 16, cy + 14)
      ..quadraticBezierTo(cx, cy + 26, cx + 16, cy + 14);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF5a3010)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawSleepingMouth(Canvas canvas, double cx, double cy) {
    final path = Path()
      ..moveTo(cx - 12, cy + 16)
      ..quadraticBezierTo(cx, cy + 10, cx + 12, cy + 16);
    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF5a3010)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round,
    );
  }

  void _drawAlertMouth(Canvas canvas, double cx, double cy) {
    canvas.drawCircle(
      Offset(cx, cy + 18),
      8,
      Paint()..color = const Color(0xFFc05030),
    );
  }

  void _drawAccessory(Canvas canvas, double cx, double cy) {
    switch (state) {
      case MascotState.working:
      case MascotState.chatting:
        _drawHeadphones(canvas, cx, cy);
        break;
      case MascotState.celebrating:
        _drawPartyHat(canvas, cx, cy);
        break;
      case MascotState.sleeping:
        _drawZzz(canvas, cx, cy);
        break;
      default:
        break;
    }
  }

  void _drawHeadphones(Canvas canvas, double cx, double cy) {
    final p = Paint()
      ..color = const Color(0xFF1a1a1a)
      ..strokeWidth = 5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final path = Path()
      ..moveTo(cx - 46, cy - 30)
      ..quadraticBezierTo(cx, cy - 70, cx + 46, cy - 30);
    canvas.drawPath(path, p);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx - 46, cy - 24), width: 18, height: 22),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFF222222),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(cx + 46, cy - 24), width: 18, height: 22),
        const Radius.circular(9),
      ),
      Paint()..color = const Color(0xFF222222),
    );
  }

  void _drawPartyHat(Canvas canvas, double cx, double cy) {
    final path = Path()
      ..moveTo(cx, cy - 68)
      ..lineTo(cx - 24, cy - 42)
      ..lineTo(cx + 24, cy - 42)
      ..close();
    canvas.drawPath(path, Paint()..color = const Color(0xFFff6eb4));
    canvas.drawCircle(Offset(cx, cy - 68), 5, Paint()..color = const Color(0xFFFFD700));
  }

  void _drawZzz(Canvas canvas, double cx, double cy) {
    final tp = TextPainter(textDirection: TextDirection.ltr);
    for (final z in [
      (cx + 44, cy - 50, 10.0, 0.5),
      (cx + 52, cy - 62, 13.0, 0.65),
      (cx + 62, cy - 76, 16.0, 0.8),
    ]) {
      tp.text = TextSpan(
        text: 'z',
        style: TextStyle(
          fontSize: z.$3,
          color: Colors.blueGrey.withOpacity(z.$4),
        ),
      );
      tp.layout();
      tp.paint(canvas, Offset(z.$1, z.$2));
    }
  }

  Color get _bodyColor {
    switch (state) {
      case MascotState.working:
      case MascotState.studying:
        return const Color(0xFFe8c87a);
      case MascotState.sleeping:
      case MascotState.tired:
        return const Color(0xFF8aaac8);
      case MascotState.celebrating:
        return const Color(0xFFb87ae8);
      case MascotState.alert:
        return const Color(0xFFe8907a);
      case MascotState.gaming:
        return const Color(0xFF7ae8b8);
      default:
        return const Color(0xFFe8d0a0);
    }
  }

  Color get _earColor {
    switch (state) {
      case MascotState.sleeping:
      case MascotState.tired:
        return const Color(0xFF6a8aaa);
      case MascotState.celebrating:
        return const Color(0xFFed93b1);
      default:
        return const Color(0xFFf4c0d1);
    }
  }

  @override
  bool shouldRepaint(MascotPainter oldDelegate) =>
      oldDelegate.state != state || oldDelegate.animValue != animValue;
}
