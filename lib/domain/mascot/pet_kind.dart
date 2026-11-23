import '../../core/i18n/language.dart';

/// Especies de mascota. El gato está desde el principio; las demás se
/// desbloquean al subir de nivel. Cada una tiene su carpeta en
/// `assets/pets/<id>/` (spritesheet, `pet.json` y accesorios).
enum PetKind {
  cat('Gato', 'Cat', '🐱', 1),
  dog('Perro', 'Dog', '🐶', 5),
  fox('Zorro', 'Fox', '🦊', 10);

  final String _es;
  final String _en;
  final String emoji;
  final int unlockLevel;

  const PetKind(this._es, this._en, this.emoji, this.unlockLevel);

  /// Nombre en el idioma de la app.
  String get label => tr(_es, _en);

  /// Carpeta de assets.
  String get id => name;

  /// "un gato", "un perro", "un zorro" (en inglés: "a cat"…).
  String get withArticle => tr('un ${_es.toLowerCase()}', 'a ${_en.toLowerCase()}');

  bool unlockedAt(int level) => level >= unlockLevel;

  static PetKind? byId(String? id) =>
      values.where((k) => k.id == id).firstOrNull;

  /// Las que se estrenan al pasar de [from] a [to].
  static List<PetKind> unlockedBetween(int from, int to) => [
        for (final k in values)
          if (k.unlockLevel > from && k.unlockLevel <= to) k
      ];
}
