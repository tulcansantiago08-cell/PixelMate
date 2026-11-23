import '../../core/i18n/language.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/collection/collection.dart';
import '../../application/game/star_catch.dart';
import '../../application/mascot/accessory_providers.dart';
import '../../application/mascot/mascot_settings.dart';
import '../../domain/mascot/pet_accessory.dart';
import '../../domain/mascot/pet_kind.dart';
import '../../application/progress/progress_providers.dart';
import '../stats/stats_style.dart';

/// Álbum con todo lo que se puede desbloquear.
final collectionProvider = Provider<Collection>((ref) => buildCollection(
      progress: ref.watch(progressProvider),
      species: ref.watch(activeSpeciesProvider),
      accessory: ref.watch(equippedAccessoryProvider),
      auraOn: ref.watch(auraActiveProvider),
      game: ref.watch(gameStoreProvider),
    ));

/// Panel «Álbum»: lo conseguido, lo que falta y cómo conseguirlo. Tocar una
/// pieza la muestra; las que se pueden usar (mascota, accesorio, aura,
/// cesta) se ponen desde ahí.
class CollectionPanel extends ConsumerStatefulWidget {
  final VoidCallback onClose;
  const CollectionPanel({super.key, required this.onClose});

  @override
  ConsumerState<CollectionPanel> createState() => _CollectionPanelState();
}

class _CollectionPanelState extends ConsumerState<CollectionPanel> {
  String? _selected;

  Future<void> _use(CollectionItem item) async {
    final mascot = ref.read(mascotSettingsProvider);
    switch (item.action) {
      case CollectionAction.species:
        await mascot.setSpecies(item.value! as PetKind);
      case CollectionAction.accessory:
        await mascot
            .setAccessory(item.inUse ? null : item.value! as PetAccessory);
      case CollectionAction.aura:
        await mascot.setAura(!item.inUse);
      case CollectionAction.basket:
        await ref.read(gameStoreProvider).selectSkin(item.value! as BasketSkin);
      case CollectionAction.none:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = ref.watch(collectionProvider);
    final level = ref.watch(progressProvider.select((p) => p.level));
    final next = collection.nextByLevel(level);
    CollectionItem? selected;
    for (final s in collection.sections) {
      for (final i in s.items) {
        if (i.id == _selected) selected = i;
      }
    }

    return Container(
      decoration: StatsStyle.panel(),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [
            Expanded(
              child: Row(children: [
                const Icon(Icons.collections_bookmark_outlined,
                    size: 18, color: StatsStyle.accentLight),
                const SizedBox(width: 6),
                Flexible(
                    child: Text(tr('Álbum', 'Album'),
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: StatsStyle.textPrimary,
                            fontSize: 15,
                            fontWeight: FontWeight.w600))),
              ]),
            ),
            Text(
                '${collection.unlocked}/${collection.total} · ${(collection.fraction * 100).round()} %',
                key: const ValueKey('album-count'),
                style: const TextStyle(
                    color: StatsStyle.textSecondary, fontSize: 12)),
            IconButton(
              tooltip: tr('Cerrar', 'Close'),
              onPressed: widget.onClose,
              icon: const Icon(Icons.close,
                  size: 18, color: StatsStyle.textSecondary),
            ),
          ]),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: collection.fraction,
                minHeight: 6,
                backgroundColor: StatsStyle.grid,
                color: const Color(0xFFFFD54F),
              ),
            ),
          ),
          if (next != null)
            Padding(
              padding: const EdgeInsets.only(top: 4, right: 8),
              child: Text(tr('Próximo por nivel: ${next.emoji} ${next.name}', 'Next by level: ${next.emoji} ${next.name}'),
                  key: const ValueKey('album-next'),
                  style: const TextStyle(
                      color: StatsStyle.textMuted, fontSize: 11)),
            ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _Detail(item: selected, onUse: _use),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(right: 8),
              children: [
                for (final section in collection.sections) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 4),
                    child: Text(
                        '${section.title} · ${section.unlocked}/${section.items.length}',
                        style: const TextStyle(
                            color: StatsStyle.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                  ),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final item in section.items)
                      _Tile(
                        item: item,
                        selected: item.id == _selected,
                        onTap: () => setState(() =>
                            _selected = _selected == item.id ? null : item.id),
                      ),
                  ]),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  final CollectionItem item;
  final bool selected;
  final VoidCallback onTap;
  const _Tile(
      {required this.item, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Lo bloqueado se ve en gris: así se sabe qué se está buscando.
    Widget emoji = Text(item.emoji, style: const TextStyle(fontSize: 20));
    if (!item.unlocked) {
      emoji = Opacity(
        opacity: 0.35,
        child: ColorFiltered(
          colorFilter: const ColorFilter.matrix([
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0.33, 0.33, 0.33, 0, 0, //
            0, 0, 0, 1, 0,
          ]),
          child: emoji,
        ),
      );
    }
    return Tooltip(
      message: item.name,
      child: InkWell(
        key: ValueKey('album-${item.id}'),
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 38,
          height: 38,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? StatsStyle.accent : StatsStyle.surfaceRaised,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: item.inUse && item.unlocked
                  ? const Color(0xFFFFD54F)
                  : StatsStyle.grid,
              width: item.inUse && item.unlocked ? 2 : 1,
            ),
          ),
          child: emoji,
        ),
      ),
    );
  }
}

/// Lo que dice la pieza elegida y, si se puede, el botón para usarla.
class _Detail extends StatelessWidget {
  final CollectionItem? item;
  final ValueChanged<CollectionItem> onUse;
  const _Detail({required this.item, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final item = this.item;
    return Container(
      key: const ValueKey('album-detail'),
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: StatsStyle.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
      ),
      child: item == null
          ? Text(tr('Toca una pieza para ver qué es y cómo conseguirla.', 'Tap a piece to see what it is and how to get it.'),
              style: const TextStyle(color: StatsStyle.textMuted, fontSize: 11))
          : Row(children: [
              Text(item.unlocked ? item.emoji : '🔒',
                  style: const TextStyle(fontSize: 22)),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.name,
                        style: const TextStyle(
                            color: StatsStyle.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w600)),
                    Text(item.unlocked ? item.detail : item.hint,
                        key: const ValueKey('album-detail-text'),
                        style: const TextStyle(
                            color: StatsStyle.textSecondary, fontSize: 11)),
                  ],
                ),
              ),
              if (item.usable)
                TextButton(
                  key: const ValueKey('album-use'),
                  onPressed: () => onUse(item),
                  child: Text(_useLabel(item)),
                ),
            ]),
    );
  }

  static String _useLabel(CollectionItem item) {
    final toggles = item.action == CollectionAction.accessory ||
        item.action == CollectionAction.aura;
    if (item.inUse) return toggles ? tr('Quitar', 'Remove') : tr('En uso', 'In use');
    return toggles ? tr('Poner', 'Put on') : tr('Usar', 'Use');
  }
}
