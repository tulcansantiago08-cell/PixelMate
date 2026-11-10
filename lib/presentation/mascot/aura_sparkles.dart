import 'dart:async';

import 'package:flutter/widgets.dart';

/// Chispitas pixel art alrededor de la mascota (premio del nivel 20).
///
/// Solo 3 cuadros por segundo: se nota viva sin gastar CPU.
class AuraSparkles extends StatefulWidget {
  final double size;
  const AuraSparkles({super.key, this.size = 160});

  @override
  State<AuraSparkles> createState() => AuraSparklesState();
}

class AuraSparklesState extends State<AuraSparkles> {
  Timer? _timer;
  int frame = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 333), (_) {
      if (mounted) setState(() => frame++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _SparklePainter(frame),
        ),
      );
}

class _SparklePainter extends CustomPainter {
  final int frame;
  _SparklePainter(this.frame);

  /// Posiciones (en la cuadrícula de 32×32 del sprite) alrededor del cuerpo.
  static const _spots = [
    Offset(3, 6), Offset(28, 4), Offset(1, 17), Offset(30, 15),
    Offset(5, 27), Offset(27, 26), Offset(15, 1), Offset(23, 10),
  ];
  static const _gold = Color(0xFFFFD84A);
  static const _white = Color(0xFFFFF6D6);

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / 32;
    final paint = Paint()..isAntiAlias = false;
    for (var i = 0; i < _spots.length; i++) {
      // Cada chispa aparece, brilla y se apaga en su propio turno.
      final phase = (frame + i * 3) % 6;
      if (phase > 2) continue;
      final c = _spots[i];
      paint.color = phase == 1 ? _white : _gold;
      void dot(double dx, double dy) => canvas.drawRect(
          Rect.fromLTWH((c.dx + dx) * px, (c.dy + dy) * px, px, px), paint);
      dot(0, 0);
      if (phase == 1) {
        // Brillo máximo: estrella de 4 puntas.
        dot(-1, 0);
        dot(1, 0);
        dot(0, -1);
        dot(0, 1);
      }
    }
  }

  @override
  bool shouldRepaint(_SparklePainter old) => old.frame != frame;
}
