import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../domain/mascot/pet_species.dart';
import 'pet_sprites.dart';

/// Dibuja la mascota a partir de su spritesheet.
///
/// - [animation] es la animación continua del estado actual.
/// - [oneShot], si no es `null`, se reproduce una vez por encima y luego se
///   llama a [onOneShotDone] (estirarse, despertar, saludar…).
///
/// Solo se redibuja a los fps de la animación (2–8 fps), no a 60 fps, para
/// consumir lo mínimo.
class SpriteMascot extends StatefulWidget {
  final LoadedPet pet;
  final PetAnimation animation;
  final PetAnimation? oneShot;
  final VoidCallback? onOneShotDone;
  final double size;
  final bool flipped;

  const SpriteMascot({
    super.key,
    required this.pet,
    required this.animation,
    this.oneShot,
    this.onOneShotDone,
    this.size = 160,
    this.flipped = false,
  });

  @override
  State<SpriteMascot> createState() => SpriteMascotState();
}

class SpriteMascotState extends State<SpriteMascot> {
  Timer? _timer;
  int _frame = 0;
  late PetAnimation _playing;

  /// Animación y fotograma visibles (para pruebas).
  PetAnimation get playing => _playing;
  int get frame => _frame;

  PetAnimation get _target => widget.oneShot ?? widget.animation;

  @override
  void initState() {
    super.initState();
    _start(_target);
  }

  @override
  void didUpdateWidget(SpriteMascot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_target != _playing || widget.pet != oldWidget.pet) _start(_target);
  }

  void _start(PetAnimation a) {
    _timer?.cancel();
    _playing = a;
    _frame = 0;
    final spec = widget.pet.species.spec(a);
    _timer = Timer.periodic(spec.frameDuration, (_) => _advance(spec));
  }

  void _advance(AnimationSpec spec) {
    if (!mounted) return;
    final isOneShot = widget.oneShot != null && _playing == widget.oneShot;
    final last = _frame >= spec.frames - 1;
    if (!last) {
      setState(() => _frame++);
    } else if (spec.loop && !isOneShot) {
      setState(() => _frame = 0);
    } else {
      // Fin de una animación de una sola vez: se queda en el último
      // fotograma y avisa (el padre decide qué viene después).
      _timer?.cancel();
      if (isOneShot) widget.onOneShotDone?.call();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(widget.size),
      painter: _SpritePainter(
        sheet: widget.pet.sheet,
        species: widget.pet.species,
        spec: widget.pet.species.spec(_playing),
        frame: _frame,
        flipped: widget.flipped,
      ),
    );
  }
}

class _SpritePainter extends CustomPainter {
  final ui.Image sheet;
  final PetSpecies species;
  final AnimationSpec spec;
  final int frame;
  final bool flipped;

  _SpritePainter({
    required this.sheet,
    required this.species,
    required this.spec,
    required this.frame,
    required this.flipped,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = species.frameWidth.toDouble();
    final h = species.frameHeight.toDouble();
    final src = Rect.fromLTWH(frame * w, spec.row * h, w, h);
    final dst = Offset.zero & size;
    if (flipped) {
      canvas.save();
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(
      sheet,
      src,
      dst,
      Paint()
        ..filterQuality = FilterQuality.none // píxeles nítidos
        ..isAntiAlias = false,
    );
    if (flipped) canvas.restore();
  }

  @override
  bool shouldRepaint(_SpritePainter old) =>
      old.frame != frame ||
      old.spec != spec ||
      old.sheet != sheet ||
      old.flipped != flipped;
}
