import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/mascot/pet_accessory.dart';
import '../progress/progress_providers.dart';
import 'mascot_settings.dart';

/// Accesorio que la mascota lleva puesto ahora: el elegido, si ya está
/// desbloqueado con el nivel actual.
final equippedAccessoryProvider = Provider<PetAccessory?>((ref) {
  final settings = ref.watch(mascotSettingsProvider);
  void changed() => ref.invalidateSelf();
  settings.addListener(changed);
  ref.onDispose(() => settings.removeListener(changed));

  final level = ref.watch(progressProvider.select((p) => p.level));
  final chosen = settings.accessory;
  return chosen != null && chosen.unlockedAt(level) ? chosen : null;
});
