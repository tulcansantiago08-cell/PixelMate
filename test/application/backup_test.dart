import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/settings/backup.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('guarda tus datos y los restaura en otro Mac', () async {
    SharedPreferences.setMockInitialValues({
      'assistant.tasks': '[{"id":"1","text":"Estudiar"}]',
      'calendar.notes': '[]',
      'calendar.toMac': true,
      'alarm.snooze': 10,
      'goal.dailyMinutes': 120,
      'detection.excluded': ['Safari'],
      'mascot.name': 'James',
      'mascot.bottomRight.x': 900.0, // de este Mac: no
      'briefing.lastDay': '2026-11-18', // cambia solo: no
      'algo.ajeno': 'x', // no es de PixelMate: no
    });
    final prefs = await SharedPreferences.getInstance();
    final json = makeBackup(prefs, DateTime(2026, 11, 18, 23));
    final data = (jsonDecode(json) as Map)['data'] as Map;
    expect(data.keys.toSet(), {
      'assistant.tasks',
      'calendar.notes',
      'calendar.toMac',
      'alarm.snooze',
      'goal.dailyMinutes',
      'detection.excluded',
      'mascot.name',
    });

    SharedPreferences.setMockInitialValues({'mascot.name': 'Otro'});
    final other = await SharedPreferences.getInstance();
    expect(await restoreBackup(other, json), 7);
    expect(other.getString('mascot.name'), 'James');
    expect(other.getBool('calendar.toMac'), isTrue);
    expect(other.getInt('alarm.snooze'), 10);
    expect(other.getStringList('detection.excluded'), ['Safari']);
    expect(other.getString('assistant.tasks'), contains('Estudiar'));
  });

  test('rechaza lo que no es una copia de PixelMate', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    expect(() => restoreBackup(prefs, 'hola'), throwsFormatException);
    expect(() => restoreBackup(prefs, '{"app":"Otra","data":{}}'),
        throwsFormatException);
    // Y no deja escribir claves que no son de la copia.
    final count = await restoreBackup(
        prefs, '{"app":"PixelMate","data":{"algo.ajeno":{"string":"x"}}}');
    expect(count, 0);
    expect(prefs.getString('algo.ajeno'), isNull);
  });

  test('nombre del archivo', () {
    expect(backupFileName(DateTime(2026, 1, 5)),
        'pixelmate-copia-2026-01-05.json');
  });
}
