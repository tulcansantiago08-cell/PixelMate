import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Lo que la app necesita de la ventana de la mascota, sin depender del plugin.
abstract class MascotWindowPort {
  /// `true` mientras la mascota está en pantalla.
  ValueListenable<bool> get visible;

  /// Agranda la ventana (para el chat) o la vuelve compacta, sin mover la
  /// esquina inferior derecha donde está la mascota.
  Future<void> setExpanded(bool expanded);

  Future<void> show();
  Future<void> hide();

  Future<void> toggle() => visible.value ? hide() : show();

  /// Posición y tamaño actuales de la ventana.
  Future<Rect> bounds();

  /// Área visible (sin Dock ni barra de menú) de la pantalla donde está.
  Future<Rect> visibleAreaOf(Rect bounds);

  /// Mueve la ventana sin guardar la posición (para pasos de animación).
  Future<void> moveTo(Offset origin);

  /// Guarda la posición actual para la próxima vez.
  Future<void> rememberPosition();
}

/// Implementación vacía para pruebas y para cuando no hay ventana nativa.
class NoopMascotWindow extends MascotWindowPort {
  @override
  final ValueNotifier<bool> visible = ValueNotifier(true);

  Rect currentBounds;
  final Rect screenArea;
  final List<Offset> moves = [];
  int remembered = 0;

  NoopMascotWindow({
    this.currentBounds = const Rect.fromLTWH(1148, 485, 280, 340),
    this.screenArea = const Rect.fromLTWH(0, 30, 1440, 807),
  });

  @override
  Future<Rect> bounds() async => currentBounds;

  @override
  Future<Rect> visibleAreaOf(Rect bounds) async => screenArea;

  @override
  Future<void> moveTo(Offset origin) async {
    moves.add(origin);
    currentBounds = origin & currentBounds.size;
  }

  @override
  Future<void> rememberPosition() async => remembered++;

  /// Cambios de tamaño pedidos (para pruebas).
  final List<bool> expandedCalls = [];

  @override
  Future<void> setExpanded(bool expanded) async => expandedCalls.add(expanded);

  @override
  Future<void> show() async => visible.value = true;

  @override
  Future<void> hide() async => visible.value = false;
}

/// Se sobrescribe en `main()` con la ventana real.
final mascotWindowProvider =
    Provider<MascotWindowPort>((_) => NoopMascotWindow());
