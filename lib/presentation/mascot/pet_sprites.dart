import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/mascot/pet_accessory.dart';
import '../../domain/mascot/pet_species.dart';

/// Especie cargada con su spritesheet ya decodificado.
class LoadedPet {
  final PetSpecies species;
  final ui.Image sheet;

  /// Capas de accesorios ya decodificadas (mismo tamaño que [sheet]).
  final Map<PetAccessory, ui.Image> accessories;

  const LoadedPet(this.species, this.sheet, [this.accessories = const {}]);
}

Future<ui.Image> _decode(AssetBundle b, String asset) async {
  final bytes = await b.load(asset);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  return (await codec.getNextFrame()).image;
}

/// Carga `assets/pets/<id>/pet.json` y su spritesheet.
Future<LoadedPet> loadPet(String id, {AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  final json = jsonDecode(await b.loadString('assets/pets/$id/pet.json'))
      as Map<String, dynamic>;
  final species = PetSpecies.fromJson(json);
  final sheet = await _decode(b, species.sheetAsset);

  // Comprueba que todas las animaciones caben en la imagen.
  for (final a in PetAnimation.values) {
    final s = species.spec(a);
    if ((s.row + 1) * species.frameHeight > sheet.height ||
        s.frames * species.frameWidth > sheet.width) {
      throw FormatException(
          'La animación "${a.name}" no cabe en el spritesheet');
    }
  }

  // Un accesorio que falta o no cuadra se omite: la mascota sigue igual.
  final accessories = <PetAccessory, ui.Image>{};
  for (final MapEntry(key: accessory, value: asset)
      in species.accessoryAssets.entries) {
    try {
      final layer = await _decode(b, asset);
      if (layer.width == sheet.width && layer.height == sheet.height) {
        accessories[accessory] = layer;
      }
    } catch (_) {}
  }
  return LoadedPet(species, sheet, accessories);
}

/// Especie elegida (por ahora solo existe el gato).
final petSpeciesIdProvider = StateProvider<String>((_) => 'cat');

final loadedPetProvider = FutureProvider<LoadedPet>(
  (ref) => loadPet(ref.watch(petSpeciesIdProvider)),
);
