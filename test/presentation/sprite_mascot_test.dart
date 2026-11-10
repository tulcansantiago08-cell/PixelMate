import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/mascot/idle_behavior.dart';
import 'package:pixelmate/domain/mascot/mascot_state.dart';
import 'package:pixelmate/domain/mascot/pet_accessory.dart';
import 'package:pixelmate/domain/mascot/pet_species.dart';
import 'package:pixelmate/presentation/mascot/pet_sprites.dart';
import 'package:pixelmate/presentation/mascot/sprite_mascot.dart';

Map<String, dynamic> catJson() =>
    jsonDecode(File('assets/pets/cat/pet.json').readAsStringSync())
        as Map<String, dynamic>;

void main() {
  group('especie', () {
    test('el gato tiene todas las animaciones', () {
      final cat = PetSpecies.fromJson(catJson());
      expect(cat.animations.keys, containsAll(PetAnimation.values));
      expect(cat.frameWidth, 32);
      for (final a in PetAnimation.values) {
        final s = cat.spec(a);
        expect(s.frames, inInclusiveRange(2, 8), reason: a.name);
        expect(s.fps, inInclusiveRange(1, 12), reason: a.name);
      }
      // Las de una sola vez no se repiten.
      expect(cat.spec(PetAnimation.wakeUp).loop, isFalse);
      expect(cat.spec(PetAnimation.stretch).loop, isFalse);
      expect(cat.spec(PetAnimation.wave).loop, isFalse);
      expect(cat.spec(PetAnimation.idle).loop, isTrue);
    });

    test('el gato declara una capa por accesorio; las desconocidas se ignoran',
        () {
      final json = catJson();
      expect(PetSpecies.fromJson(json).accessoryAssets.keys,
          containsAll(PetAccessory.values));
      (json['accessories'] as Map)['capa_rara'] = 'x.png';
      json.remove('accessories');
      expect(PetSpecies.fromJson(json).accessoryAssets, isEmpty);
    });

    test('una especie incompleta se rechaza al cargar', () {
      final json = catJson();
      (json['animations'] as Map).remove('sleep');
      expect(() => PetSpecies.fromJson(json), throwsFormatException);
    });

    test('cada estado de la mascota tiene animación', () {
      for (final s in MascotState.values) {
        expect(() => animationFor(s), returnsNormally);
      }
      expect(animationFor(MascotState.working), PetAnimation.work);
      expect(animationFor(MascotState.gaming), PetAnimation.gaming);
      expect(animationFor(MascotState.sleeping), PetAnimation.sleep);
    });
  });

  group('comportamiento en reposo', () {
    final t0 = DateTime(2026, 11, 9, 10);

    test('se duerme tras 10 min sin actividad y despierta con un clic', () {
      final b = IdleBehavior(now: t0, fidgetChance: 0);
      expect(b.tick(t0.add(const Duration(minutes: 9)), idle: true),
          isA<StayStill>());
      expect(b.tick(t0.add(const Duration(minutes: 10)), idle: true),
          isA<FallAsleep>());
      expect(b.asleep, isTrue);
      expect(b.tick(t0.add(const Duration(minutes: 11)), idle: true),
          isA<StayStill>());
      expect(b.activity(t0.add(const Duration(minutes: 12))), isTrue);
      expect(b.asleep, isFalse);
      expect(b.activity(t0.add(const Duration(minutes: 13))), isFalse);
    });

    test('una sesión en marcha cuenta como actividad', () {
      final b = IdleBehavior(now: t0, fidgetChance: 0);
      b.tick(t0.add(const Duration(minutes: 30)), idle: false);
      expect(b.tick(t0.add(const Duration(minutes: 35)), idle: true),
          isA<StayStill>());
      expect(b.asleep, isFalse);
    });

    test('a veces se estira o saluda, nunca en sesión', () {
      final b = IdleBehavior(now: t0, fidgetChance: 1, random: Random(1));
      final d = b.tick(t0.add(const Duration(minutes: 1)), idle: true);
      expect(d, isA<PlayOnce>());
      expect((d as PlayOnce).animation,
          anyOf(PetAnimation.stretch, PetAnimation.wave));
      expect(b.tick(t0.add(const Duration(minutes: 2)), idle: false),
          isA<StayStill>());
    });
  });

  group('SpriteMascot', () {
    late LoadedPet pet;

    setUpAll(() async {
      TestWidgetsFlutterBinding.ensureInitialized();
    });

    Future<void> load(WidgetTester tester) async {
      await tester.runAsync(() async {
        pet = await loadPet('cat', bundle: rootBundle);
      });
    }

    testWidgets('carga el spritesheet real y avanza a su ritmo',
        (tester) async {
      await load(tester);
      expect(pet.sheet.width, greaterThanOrEqualTo(32 * 4));
      await tester.pumpWidget(
          Center(child: SpriteMascot(pet: pet, animation: PetAnimation.idle)));
      final state = tester.state<SpriteMascotState>(find.byType(SpriteMascot));
      expect(state.frame, 0);
      // idle va a 3 fps: 333 ms por fotograma (poco consumo).
      await tester.pump(const Duration(milliseconds: 340));
      expect(state.frame, 1);
      await tester.pump(const Duration(milliseconds: 334 * 3));
      expect(state.frame, 0, reason: 'vuelve al inicio (bucle)');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('carga las capas de accesorios del mismo tamaño que la hoja',
        (tester) async {
      await load(tester);
      expect(pet.accessories.keys, containsAll(PetAccessory.values));
      for (final layer in pet.accessories.values) {
        expect(layer.width, pet.sheet.width);
        expect(layer.height, pet.sheet.height);
      }
      await tester.pumpWidget(Center(
          child: SpriteMascot(
              pet: pet,
              animation: PetAnimation.idle,
              accessory: pet.accessories[PetAccessory.crown])));
      expect(find.byType(SpriteMascot), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('pausada (mascota oculta) no anima y sigue donde iba',
        (tester) async {
      await load(tester);
      Widget build(bool paused) => Center(
          child: SpriteMascot(
              pet: pet, animation: PetAnimation.work, paused: paused));
      await tester.pumpWidget(build(false));
      final state = tester.state<SpriteMascotState>(find.byType(SpriteMascot));
      await tester.pump(const Duration(milliseconds: 260)); // work: 4 fps
      expect(state.frame, 1);

      await tester.pumpWidget(build(true));
      expect(state.animating, isFalse);
      await tester.pump(const Duration(seconds: 5));
      expect(state.frame, 1, reason: 'oculta: sin temporizador');

      await tester.pumpWidget(build(false));
      expect(state.animating, isTrue);
      await tester.pump(const Duration(milliseconds: 260));
      expect(state.frame, 2, reason: 'sigue donde iba');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('una animación de una sola vez avisa al terminar',
        (tester) async {
      await load(tester);
      var done = 0;
      Widget build(PetAnimation? oneShot) => Center(
            child: SpriteMascot(
              pet: pet,
              animation: PetAnimation.idle,
              oneShot: oneShot,
              onOneShotDone: () => done++,
            ),
          );
      await tester.pumpWidget(build(PetAnimation.wakeUp));
      final state = tester.state<SpriteMascotState>(find.byType(SpriteMascot));
      expect(state.playing, PetAnimation.wakeUp);
      final spec = pet.species.spec(PetAnimation.wakeUp);
      await tester.pump(spec.totalDuration + const Duration(milliseconds: 50));
      expect(done, 1);
      await tester.pump(const Duration(seconds: 2));
      expect(done, 1, reason: 'no se repite');

      await tester.pumpWidget(build(null));
      expect(state.playing, PetAnimation.idle);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('cambiar de estado cambia la animación desde el inicio',
        (tester) async {
      await load(tester);
      await tester.pumpWidget(
          Center(child: SpriteMascot(pet: pet, animation: PetAnimation.work)));
      await tester.pump(const Duration(milliseconds: 400));
      final state = tester.state<SpriteMascotState>(find.byType(SpriteMascot));
      expect(state.frame, greaterThan(0));
      await tester.pumpWidget(
          Center(child: SpriteMascot(pet: pet, animation: PetAnimation.rest)));
      expect(state.playing, PetAnimation.rest);
      expect(state.frame, 0);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
