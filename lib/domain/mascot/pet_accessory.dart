import '../../core/i18n/language.dart';

/// Accesorios que la mascota se puede poner. Se desbloquean al subir de
/// nivel y se lleva uno a la vez.
///
/// El arte de cada uno es una capa del mismo tamaño que el spritesheet
/// (declarada en `pet.json` de cada especie), alineada fotograma a
/// fotograma para que siga los movimientos de la mascota.
enum PetAccessory {
  scarf('Bufanda', 'Scarf', '🧣', 2),
  bow('Moño', 'Bow', '🎀', 4),
  sunglasses('Gafas de sol', 'Sunglasses', '🕶️', 6),
  headphones('Audífonos', 'Headphones', '🎧', 9),
  crown('Corona', 'Crown', '👑', 12),
  wizardHat('Gorro de mago', 'Wizard hat', '🧙', 15),
  cape('Capa de héroe', 'Hero cape', '🦸', 18);

  final String _es;
  final String _en;
  final String emoji;
  final int unlockLevel;

  const PetAccessory(this._es, this._en, this.emoji, this.unlockLevel);

  /// Nombre en el idioma de la app.
  String get label => tr(_es, _en);

  bool unlockedAt(int level) => level >= unlockLevel;

  /// Los que se estrenan al pasar de [from] a [to].
  static List<PetAccessory> unlockedBetween(int from, int to) => [
        for (final a in values)
          if (a.unlockLevel > from && a.unlockLevel <= to) a
      ];

  static PetAccessory? byName(String? name) =>
      values.where((a) => a.name == name).firstOrNull;
}

/// Nivel desde el que se puede activar el aura brillante.
const auraUnlockLevel = 20;
