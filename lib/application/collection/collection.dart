import '../../domain/mascot/pet_accessory.dart';
import '../../domain/mascot/pet_kind.dart';
import '../game/star_catch.dart';
import '../progress/progression.dart';

/// Qué se puede hacer con una pieza desbloqueada del álbum.
enum CollectionAction { species, accessory, aura, basket, none }

/// Una pieza del álbum.
class CollectionItem {
  final String id;
  final String emoji;
  final String name;

  /// Qué hace o cómo se consiguió.
  final String detail;

  /// Cómo se desbloquea (si aún no se tiene).
  final String hint;
  final bool unlocked;

  /// Puesta ahora (mascota, accesorio, aura o cesta).
  final bool inUse;

  final CollectionAction action;

  /// Valor para la acción (la especie, el accesorio o la cesta).
  final Object? value;

  const CollectionItem({
    required this.id,
    required this.emoji,
    required this.name,
    required this.unlocked,
    this.detail = '',
    this.hint = '',
    this.inUse = false,
    this.action = CollectionAction.none,
    this.value,
  });

  bool get usable => unlocked && action != CollectionAction.none;
}

class CollectionSection {
  final String title;
  final List<CollectionItem> items;
  const CollectionSection(this.title, this.items);

  int get unlocked => items.where((i) => i.unlocked).length;
}

class Collection {
  final List<CollectionSection> sections;
  const Collection(this.sections);

  int get total => sections.fold(0, (n, s) => n + s.items.length);
  int get unlocked => sections.fold(0, (n, s) => n + s.unlocked);
  double get fraction => total == 0 ? 0 : unlocked / total;

  /// Lo próximo que se puede conseguir subiendo de nivel.
  CollectionItem? nextByLevel(int level) {
    CollectionItem? best;
    var bestLevel = 1 << 30;
    for (final s in sections) {
      for (final i in s.items) {
        final need = _levelNeeded[i.id];
        if (!i.unlocked && need != null && need > level && need < bestLevel) {
          best = i;
          bestLevel = need;
        }
      }
    }
    return best;
  }
}

/// Nivel que pide cada pieza que se gana subiendo de nivel.
final Map<String, int> _levelNeeded = {
  for (final k in PetKind.values) 'species.${k.name}': k.unlockLevel,
  for (final a in PetAccessory.values) 'accessory.${a.name}': a.unlockLevel,
  'aura': auraUnlockLevel,
};

/// Arma el álbum con el progreso actual.
Collection buildCollection({
  required PlayerProgress progress,
  required PetKind species,
  required PetAccessory? accessory,
  required bool auraOn,
  required GameStore game,
}) {
  final level = progress.level;
  String byLevel(int n) =>
      'Se desbloquea en el nivel $n (te ${n - level == 1 ? 'falta 1 nivel' : 'faltan ${n - level} niveles'}).';
  return Collection([
    CollectionSection('Mascotas', [
      for (final k in PetKind.values)
        CollectionItem(
          id: 'species.${k.name}',
          emoji: k.emoji,
          name: k.label,
          unlocked: k.unlockedAt(level),
          detail: 'Mascota del nivel ${k.unlockLevel}.',
          hint: byLevel(k.unlockLevel),
          inUse: k == species,
          action: CollectionAction.species,
          value: k,
        ),
    ]),
    CollectionSection('Accesorios', [
      for (final a in PetAccessory.values)
        CollectionItem(
          id: 'accessory.${a.name}',
          emoji: a.emoji,
          name: a.label,
          unlocked: a.unlockedAt(level),
          detail: 'Accesorio del nivel ${a.unlockLevel}.',
          hint: byLevel(a.unlockLevel),
          inUse: a == accessory,
          action: CollectionAction.accessory,
          value: a,
        ),
      CollectionItem(
        id: 'aura',
        emoji: '✨',
        name: 'Aura brillante',
        unlocked: level >= auraUnlockLevel,
        detail: 'Chispitas alrededor de tu mascota.',
        hint: byLevel(auraUnlockLevel),
        inUse: auraOn,
        action: CollectionAction.aura,
      ),
    ]),
    CollectionSection('Logros', [
      for (final a in achievements)
        CollectionItem(
          id: 'achievement.${a.id}',
          emoji: a.emoji,
          name: a.title,
          unlocked: progress.isUnlocked(a),
          detail: a.description,
          hint: a.description,
        ),
    ]),
    CollectionSection('Medallas del juego', [
      for (final m in gameMedals)
        CollectionItem(
          id: 'medal.${m.id}',
          emoji: m.emoji,
          name: m.title,
          unlocked: m.done(game.stats),
          detail:
              '${m.description} Te dio ${m.reward.emoji} ${m.reward.label}.',
          hint: '${m.description} (${m.progress(game.stats)}/${m.goal})',
        ),
    ]),
    CollectionSection('Cestas del juego', [
      for (final s in BasketSkin.values)
        CollectionItem(
          id: 'basket.${s.name}',
          emoji: s.emoji,
          name: s.label,
          unlocked: game.isUnlocked(s),
          detail: s.perk,
          hint: 'Se gana con la medalla '
              '«${gameMedals.where((m) => m.reward == s).map((m) => m.title).firstOrNull ?? '—'}». '
              'Truco: ${s.perk}.',
          inUse: game.skin == s,
          action: CollectionAction.basket,
          value: s,
        ),
    ]),
  ]);
}
