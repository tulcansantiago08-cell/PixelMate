import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/mascot/pet_species.dart';

/// Especie cargada con su spritesheet ya decodificado.
class LoadedPet {
  final PetSpecies species;
  final ui.Image sheet;
  const LoadedPet(this.species, this.sheet);
}

/// Carga `assets/pets/<id>/pet.json` y su spritesheet.
Future<LoadedPet> loadPet(String id, {AssetBundle? bundle}) async {
  final b = bundle ?? rootBundle;
  final json = jsonDecode(await b.loadString('assets/pets/$id/pet.json'))
      as Map<String, dynamic>;
  final species = PetSpecies.fromJson(json);
  final bytes = await b.load(species.sheetAsset);
  final codec = await ui.instantiateImageCodec(bytes.buffer.asUint8List());
  final frame = await codec.getNextFrame();
  final sheet = frame.image;

  // Comprueba que todas las animaciones caben en la imagen.
  for (final a in PetAnimation.values) {
    final s = species.spec(a);
    if ((s.row + 1) * species.frameHeight > sheet.height ||
        s.frames * species.frameWidth > sheet.width) {
      throw FormatException(
          'La animación "${a.name}" no cabe en el spritesheet');
    }
  }
  return LoadedPet(species, sheet);
}

/// Especie elegida (por ahora solo existe el gato).
final petSpeciesIdProvider = StateProvider<String>((_) => 'cat');

final loadedPetProvider = FutureProvider<LoadedPet>(
  (ref) => loadPet(ref.watch(petSpeciesIdProvider)),
);
