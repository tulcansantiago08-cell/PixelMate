import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/calendar_notes.dart';
import 'package:pixelmate/application/assistant/command_parser.dart';
import 'package:pixelmate/application/progress/progression.dart';
import 'package:pixelmate/core/i18n/language.dart';
import 'package:pixelmate/domain/mascot/pet_kind.dart';
import 'package:pixelmate/presentation/stats/stats_style.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// En inglés la app escribe sus textos en inglés y entiende órdenes comunes en
/// inglés; en español todo sigue igual.
void main() {
  final now = DateTime(2026, 11, 17, 10); // martes
  tearDown(() => LanguageSettings.current = AppLanguage.es);

  group('órdenes en inglés', () {
    setUp(() => LanguageSettings.current = AppLanguage.en);

    for (final (text, intent) in [
      ('Remind me in 20 minutes to call mom', AssistantIntent.remind),
      ('Set an alarm at 8 am virtual meeting', AssistantIntent.alarm),
      ('Turn off the alarm', AssistantIntent.alarmStop),
      ('Open Notes', AssistantIntent.open),
      ('Close Safari', AssistantIntent.closeApp),
      ('Turn up the volume', AssistantIntent.volume),
      ('Mute', AssistantIntent.volume),
      ('What do I have today?', AssistantIntent.showAgenda),
      ("What's pending?", AssistantIntent.showPending),
      ('Note down buy milk', AssistantIntent.addTask),
      ('Next song', AssistantIntent.media),
      ('Play Despacito on YouTube', AssistantIntent.open),
      ('Call me Santi', AssistantIntent.setUserName),
      ('Stop dancing', AssistantIntent.danceStop),
    ]) {
      test(text, () => expect(parseCommand(text, now)?.intent, intent));
    }

    test('«in 20 minutes» es dentro de 20 minutos', () {
      expect(parseCommand('Remind me in 20 minutes to call mom', now)?.when,
          now.add(const Duration(minutes: 20)));
    });
  });

  test('en español no se traduce nada', () {
    LanguageSettings.current = AppLanguage.es;
    expect(parseCommand('Open Notes', now)?.intent, isNot(AssistantIntent.open));
    expect(parseCommand('Abre Notas', now)?.intent, AssistantIntent.open);
  });

  test('textos de la app en inglés', () {
    LanguageSettings.current = AppLanguage.en;
    expect(tr('Ajustes', 'Settings'), 'Settings');
    expect(monthNames[10], 'November');
    expect(longDate(DateTime(2026, 11, 17)), 'Tuesday, Nov 17');
    expect(PetKind.cat.label, 'Cat');
    expect(PetKind.fox.withArticle, 'a fox');
    expect(achievements.first.title, 'First steps');
    expect(titleForLevel(1), 'Rookie kitten');
    LanguageSettings.current = AppLanguage.es;
    expect(achievements.first.title, 'Primeros pasos');
    expect(longDate(DateTime(2026, 11, 17)), 'Martes 17 nov');
  });

  test('el idioma se guarda y el español es el predeterminado', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final settings = LanguageSettings(prefs);
    expect(settings.language, AppLanguage.es);
    await settings.setLanguage(AppLanguage.en);
    expect(LanguageSettings(prefs).language, AppLanguage.en);
  });
}
