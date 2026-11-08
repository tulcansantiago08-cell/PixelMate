/// Especies de mascota. El gato está desde el principio; las demás se
/// desbloquean al subir de nivel. Cada una tiene su carpeta en
/// `assets/pets/<id>/` (spritesheet, `pet.json` y accesorios).
enum PetKind {
  cat('Gato', '🐱', 1),
  dog('Perro', '🐶', 5),
  fox('Zorro', '🦊', 10);

  final String label;
  final String emoji;
  final int unlockLevel;

  const PetKind(this.label, this.emoji, this.unlockLevel);

  /// Carpeta de assets.
  String get id => name;

  /// "un gato", "un perro", "un zorro".
  String get withArticle => 'un ${label.toLowerCase()}';

  bool unlockedAt(int level) => level >= unlockLevel;

  static PetKind? byId(String? id) =>
      values.where((k) => k.id == id).firstOrNull;

  /// Las que se estrenan al pasar de [from] a [to].
  static List<PetKind> unlockedBetween(int from, int to) => [
        for (final k in values)
          if (k.unlockLevel > from && k.unlockLevel <= to) k
      ];
}
