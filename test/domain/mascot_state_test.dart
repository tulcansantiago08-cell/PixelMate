import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/domain/mascot/mascot_state.dart';

void main() {
  group('MascotState', () {
    test('displayName no está vacío para ningún estado', () {
      for (final state in MascotState.values) {
        expect(state.displayName, isNotEmpty);
      }
    });

    test('isActive es true solo para working, studying y gaming', () {
      expect(MascotState.working.isActive, isTrue);
      expect(MascotState.studying.isActive, isTrue);
      expect(MascotState.gaming.isActive, isTrue);
      expect(MascotState.idle.isActive, isFalse);
      expect(MascotState.sleeping.isActive, isFalse);
      expect(MascotState.celebrating.isActive, isFalse);
    });
  });
}
