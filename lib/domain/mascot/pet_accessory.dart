/// Accesorios que la mascota se puede poner. Se desbloquean al subir de
/// nivel y se lleva uno a la vez.
///
/// El arte de cada uno es una capa del mismo tamaño que el spritesheet
/// (declarada en `pet.json` de cada especie), alineada fotograma a
/// fotograma para que siga los movimientos de la mascota.
enum PetAccessory {
  scarf('Bufanda', '🧣', 2),
  bow('Moño', '🎀', 4),
  sunglasses('Gafas de sol', '🕶️', 6),
  headphones('Audífonos', '🎧', 9),
  crown('Corona', '👑', 12),
  wizardHat('Gorro de mago', '🧙', 15),
  cape('Capa de héroe', '🦸', 18);

  final String label;
  final String emoji;
  final int unlockLevel;

  const PetAccessory(this.label, this.emoji, this.unlockLevel);

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
