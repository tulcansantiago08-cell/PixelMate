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
}

/// Implementación vacía para pruebas y para cuando no hay ventana nativa.
class NoopMascotWindow extends MascotWindowPort {
  @override
  final ValueNotifier<bool> visible = ValueNotifier(true);

  @override
  Future<void> setExpanded(bool expanded) async {}

  @override
  Future<void> show() async => visible.value = true;

  @override
  Future<void> hide() async => visible.value = false;
}

/// Se sobrescribe en `main()` con la ventana real.
final mascotWindowProvider =
    Provider<MascotWindowPort>((_) => NoopMascotWindow());
