import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

/// Pista de baile de discoteca alrededor de la mascota mientras suena
/// música: bola de espejos, rayos de colores, baldosas que se encienden al
/// ritmo y una coreografía que cambia cada compás.
///
/// Va a 15 cuadros por segundo con un temporizador (como el pixel art de
/// la mascota): se ve animado y gasta poco. Sin [dancing] no anima nada.
class MusicDance extends StatefulWidget {
  final bool dancing;

  /// Dibuja la mascota. [armsUp] pide la animación con brazos arriba (los
  /// compases de pose y salto); si no, la de feliz.
  final Widget Function(BuildContext context, bool armsUp) builder;

  final double size;

  const MusicDance(
      {super.key,
      required this.dancing,
      required this.builder,
      this.size = 160});

  /// Cuadros por segundo de la pista.
  static const fps = 15;

  /// Duración de un compás (4 tiempos a 120 pulsaciones por minuto).
  static const bar = Duration(seconds: 2);

  @override
  State<MusicDance> createState() => _MusicDanceState();
}

/// Paso de baile de cada compás.
enum DanceMove { sideSteps, discoPoint, spin, jump }

/// Posición de la mascota en el instante [t] (segundos desde que empezó).
({
  DanceMove move,
  double dx,
  double dy,
  double angle,
  double scaleX,
  double scaleY
}) danceFrame(double t) {
  final barLength = MusicDance.bar.inMilliseconds / 1000;
  final bar = (t / barLength).floor();
  final inBar = (t % barLength) / barLength; // 0–1 dentro del compás
  final beat = inBar * 4; // 0–4
  final inBeat = beat % 1;
  final hop = -sin(inBeat * pi) * 5;
  final move = DanceMove.values[bar % DanceMove.values.length];
  switch (move) {
    case DanceMove.sideSteps:
      // Paso a un lado y al otro en cada tiempo.
      final side = beat.floor().isEven ? 1.0 : -1.0;
      return (
        move: move,
        dx: side * sin(inBeat * pi) * 14,
        dy: hop,
        angle: side * 0.06,
        scaleX: 1,
        scaleY: 1,
      );
    case DanceMove.discoPoint:
      // La pose de discoteca: inclinarse a un lado y al otro cada dos tiempos.
      final side = (beat / 2).floor().isEven ? 1.0 : -1.0;
      return (
        move: move,
        dx: side * 6,
        dy: hop * 0.6,
        angle: side * 0.18,
        scaleX: side,
        scaleY: 1,
      );
    case DanceMove.spin:
      // Una vuelta entera en el compás (se ve de frente, de lado y al revés).
      return (
        move: move,
        dx: 0,
        dy: hop,
        angle: 0,
        scaleX: cos(inBar * 2 * pi),
        scaleY: 1,
      );
    case DanceMove.jump:
      // Saltos grandes, aplastándose un poco al caer.
      final air = sin(inBeat * pi);
      return (
        move: move,
        dx: 0,
        dy: -air * 16,
        angle: 0,
        scaleX: 1 + (1 - air) * 0.08,
        scaleY: 1 - (1 - air) * 0.1,
      );
  }
}

class _MusicDanceState extends State<MusicDance> {
  Timer? _timer;
  int _frame = 0;

  double get _t => _frame / MusicDance.fps;

  @override
  void initState() {
    super.initState();
    if (widget.dancing) _start();
  }

  @override
  void didUpdateWidget(MusicDance old) {
    super.didUpdateWidget(old);
    if (widget.dancing && _timer == null) {
      _start();
    } else if (!widget.dancing && _timer != null) {
      _timer!.cancel();
      _timer = null;
      _frame = 0;
    }
  }

  void _start() {
    _timer = Timer.periodic(
        const Duration(milliseconds: 1000 ~/ MusicDance.fps), (_) {
      if (mounted) setState(() => _frame++);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.dancing) return widget.builder(context, false);
    final f = danceFrame(_t);
    final armsUp = f.move == DanceMove.discoPoint || f.move == DanceMove.jump;
    // Mitad del giro: el sprite se ve "de canto"; que no desaparezca.
    final scaleX = f.scaleX.abs() < 0.15 ? 0.15 * f.scaleX.sign : f.scaleX;
    return SizedBox.square(
      dimension: widget.size,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('disco-floor'),
              size: Size.square(widget.size),
              painter: DiscoPainter(_t, front: false),
            ),
          ),
          Transform.translate(
            offset: Offset(f.dx, f.dy),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..rotateZ(f.angle)
                ..scaleByDouble(scaleX == 0 ? 0.15 : scaleX, f.scaleY, 1, 1),
              child: widget.builder(context, armsUp),
            ),
          ),
          IgnorePointer(
            child: CustomPaint(
              key: const ValueKey('music-notes'),
              size: Size.square(widget.size),
              painter: DiscoPainter(_t, front: true),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dibuja la discoteca. Detrás de la mascota ([front] falso): rayos de luz
/// y la pista de baldosas. Delante: la bola de espejos, destellos y notas.
class DiscoPainter extends CustomPainter {
  final double t;
  final bool front;
  DiscoPainter(this.t, {required this.front});

  static const _lights = [
    Color(0xFFFF4FD8), // magenta
    Color(0xFF4FE3FF), // cian
    Color(0xFFFFE14F), // amarillo
    Color(0xFF7CFF4F), // verde
  ];

  int get _beat => (t * 2).floor(); // 2 tiempos por segundo

  @override
  void paint(Canvas canvas, Size size) =>
      front ? _paintFront(canvas, size) : _paintBack(canvas, size);

  Offset _ballCenter(Size s) => Offset(s.width / 2, s.height * 0.08);

  void _paintBack(Canvas canvas, Size size) {
    final ball = _ballCenter(size);
    // Rayos que barren desde la bola.
    for (var i = 0; i < 3; i++) {
      final color = _lights[(i + _beat) % _lights.length];
      final angle = pi / 2 + sin(t * 1.3 + i * 2.1) * 0.75;
      final length = size.height * 1.05;
      const spread = 0.13;
      final a =
          ball + Offset(cos(angle - spread), sin(angle - spread)) * length;
      final b =
          ball + Offset(cos(angle + spread), sin(angle + spread)) * length;
      final path = Path()
        ..moveTo(ball.dx, ball.dy)
        ..lineTo(a.dx, a.dy)
        ..lineTo(b.dx, b.dy)
        ..close();
      canvas.drawPath(
        path,
        Paint()
          ..shader = RadialGradient(
            colors: [
              color.withValues(alpha: 0.38),
              color.withValues(alpha: 0.0),
            ],
          ).createShader(Rect.fromCircle(center: ball, radius: length)),
      );
    }

    // Pista de baile: baldosas que cambian de color en cada tiempo.
    const cols = 6;
    final tile = size.width * 0.8 / cols;
    final left = size.width * 0.1;
    final top = size.height - tile * 0.9;
    final paint = Paint()..isAntiAlias = false;
    for (var c = 0; c < cols; c++) {
      final lit = (c + _beat) % 3 == 0;
      final color = _lights[(c + _beat ~/ 2) % _lights.length];
      paint.color = color.withValues(alpha: lit ? 0.75 : 0.22);
      canvas.drawRect(
          Rect.fromLTWH(left + c * tile + 1, top, tile - 2, tile * 0.55),
          paint);
    }
  }

  void _paintFront(Canvas canvas, Size size) {
    final ball = _ballCenter(size);
    final r = size.width * 0.075;
    // Cordón.
    canvas.drawLine(
        Offset(ball.dx, 0),
        ball - Offset(0, r),
        Paint()
          ..color = const Color(0xFFB0B0B0)
          ..strokeWidth = 1.5);
    // Bola de espejos: cuadritos que brillan por turnos (parece que gira).
    canvas.drawCircle(ball, r, Paint()..color = const Color(0xFF8E8E9A));
    canvas.save();
    canvas.clipPath(Path()..addOval(Rect.fromCircle(center: ball, radius: r)));
    const n = 5;
    final cell = r * 2 / n;
    final shift = (t * 6).floor();
    final tilePaint = Paint()..isAntiAlias = false;
    for (var y = 0; y < n; y++) {
      for (var x = 0; x < n; x++) {
        final bright = (x + y * 2 + shift) % 4 == 0;
        tilePaint.color =
            bright ? const Color(0xFFFFFFFF) : const Color(0xFFC9CAD6);
        canvas.drawRect(
            Rect.fromLTWH(ball.dx - r + x * cell + 0.5,
                ball.dy - r + y * cell + 0.5, cell - 1, cell - 1),
            tilePaint);
      }
    }
    canvas.restore();

    // Destellos que salen de la bola.
    final sparkle = Paint()..color = Colors.white;
    for (var i = 0; i < 4; i++) {
      final phase = (t * 1.5 + i / 4) % 1.0;
      if (phase > 0.5) continue;
      final angle = i * pi / 2 + t;
      final p = ball + Offset(cos(angle), sin(angle)) * (r + 4 + phase * 18);
      final s = 2.5 * (1 - phase * 2);
      canvas.drawRect(
          Rect.fromCenter(center: p, width: s * 2, height: 1), sparkle);
      canvas.drawRect(
          Rect.fromCenter(center: p, width: 1, height: s * 2), sparkle);
    }

    // Notas que suben a los lados.
    const notes = ['♪', '♫', '♬'];
    const xs = [0.08, 0.84, 0.2];
    for (var i = 0; i < notes.length; i++) {
      final p = (t * 0.5 + i / notes.length) % 1.0;
      final opacity = p < 0.2 ? p / 0.2 : (1 - p) / 0.8;
      final painter = TextPainter(
        text: TextSpan(
          text: notes[i],
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: _lights[(i + _beat) % _lights.length]
                .withValues(alpha: opacity.clamp(0.0, 1.0)),
            shadows: const [Shadow(blurRadius: 2, color: Color(0x88000000))],
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(
          canvas,
          Offset(size.width * xs[i] + sin(p * 2 * pi) * 5,
              size.height * (0.7 - 0.45 * p)));
    }
  }

  @override
  bool shouldRepaint(DiscoPainter old) => old.t != t || old.front != front;
}
