import 'mascot_state.dart';
import 'pet_accessory.dart';

/// Animaciones que toda especie debe incluir en su spritesheet.
enum PetAnimation {
  idle,
  walk,
  sleep,
  wakeUp,
  stretch,
  work,
  study,
  gaming,
  happy,
  celebrate,
  tired,
  rest,
  alert,
  sad,
  wave,
}

/// Una fila del spritesheet.
class AnimationSpec {
  final int row;
  final int frames;
  final double fps;
  final bool loop;

  const AnimationSpec({
    required this.row,
    required this.frames,
    required this.fps,
    required this.loop,
  });

  Duration get frameDuration => Duration(microseconds: (1000000 / fps).round());

  Duration get totalDuration => frameDuration * frames;

  factory AnimationSpec.fromJson(Map<String, dynamic> json) => AnimationSpec(
        row: json['row'] as int,
        frames: json['frames'] as int,
        fps: (json['fps'] as num).toDouble(),
        loop: json['loop'] as bool,
      );
}

/// Especie de mascota: un spritesheet y la descripción de sus animaciones.
///
/// Para añadir una especie nueva basta con una carpeta en `assets/pets/`
/// con su `sheet.png` y su `pet.json` (mismo formato que el gato).
class PetSpecies {
  final String id;
  final String name;
  final String sheetAsset;
  final int frameWidth;
  final int frameHeight;
  final Map<PetAnimation, AnimationSpec> animations;

  /// Capas de accesorios disponibles para esta especie (puede no haber).
  final Map<PetAccessory, String> accessoryAssets;

  const PetSpecies({
    required this.id,
    required this.name,
    required this.sheetAsset,
    required this.frameWidth,
    required this.frameHeight,
    required this.animations,
    this.accessoryAssets = const {},
  });

  /// Lee `pet.json`. Lanza [FormatException] si falta alguna animación, para
  /// detectar un spritesheet incompleto al cargarlo y no a mitad de uso.
  factory PetSpecies.fromJson(Map<String, dynamic> json) {
    final raw = json['animations'] as Map<String, dynamic>;
    final animations = <PetAnimation, AnimationSpec>{};
    for (final a in PetAnimation.values) {
      final spec = raw[a.name];
      if (spec == null) {
        throw FormatException(
            'Falta la animación "${a.name}" en ${json['id']}');
      }
      animations[a] = AnimationSpec.fromJson(spec as Map<String, dynamic>);
    }
    return PetSpecies(
      id: json['id'] as String,
      name: json['name'] as String,
      sheetAsset: json['sheet'] as String,
      frameWidth: json['frameWidth'] as int,
      frameHeight: json['frameHeight'] as int,
      animations: animations,
      accessoryAssets: {
        for (final MapEntry(:key, :value)
            in ((json['accessories'] as Map<String, dynamic>?) ?? {}).entries)
          if (PetAccessory.byName(key) case final a?) a: value as String
      },
    );
  }

  AnimationSpec spec(PetAnimation a) => animations[a]!;
}

/// Animación continua que expresa cada estado de la mascota.
PetAnimation animationFor(MascotState state) => switch (state) {
      MascotState.idle => PetAnimation.idle,
      MascotState.greeting => PetAnimation.wave,
      MascotState.working => PetAnimation.work,
      MascotState.studying => PetAnimation.study,
      MascotState.gaming => PetAnimation.gaming,
      MascotState.resting => PetAnimation.rest,
      MascotState.sleeping => PetAnimation.sleep,
      MascotState.celebrating => PetAnimation.celebrate,
      MascotState.alert => PetAnimation.alert,
      MascotState.tired => PetAnimation.tired,
      MascotState.chatting => PetAnimation.happy,
    };
