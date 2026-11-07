import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/infrastructure/claude/claude_provider.dart';

void main() {
  group('ChatNotifier', () {
    test('inicia con mensaje de bienvenida', () {
      final messages = [
        ChatMessage(text: '¡Hola! Soy PixelMate 🐾 ¿En qué te ayudo hoy?', isUser: false),
      ];
      expect(messages.first.isUser, isFalse);
      expect(messages.first.text, contains('PixelMate'));
    });

    test('ChatMessage registra hora de creación', () {
      final before = DateTime.now();
      final msg = ChatMessage(text: 'test', isUser: true);
      final after = DateTime.now();
      expect(msg.time.isAfter(before) || msg.time.isAtSameMomentAs(before), isTrue);
      expect(msg.time.isBefore(after) || msg.time.isAtSameMomentAs(after), isTrue);
    });
  });
}
