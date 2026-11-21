import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/apple_reminders.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/assistant/personal_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late PersonalStore store;
  late FakeMacActions mac;
  late AppleRemindersSync sync;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    store = PersonalStore(prefs);
    mac = FakeMacActions();
    sync = AppleRemindersSync(store, mac, prefs);
  });
  tearDown(() => sync.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('apagado no toca Recordatorios', () async {
    await store.addTask('Estudiar');
    await settle();
    expect(mac.appleReminders, isEmpty);
  });

  test('al activarlo sube lo pendiente y lo nuevo', () async {
    await store.addTask('Estudiar');
    final hecha = await store.addTask('Ya hecha');
    await store.setDone(hecha.id, true);
    await store.addReminder('Llamar a Ana', DateTime(2030, 1, 1, 9));
    await sync.setEnabled(true);
    expect(mac.appleReminders.values.map((r) => r.$1).toSet(),
        {'Estudiar', 'Llamar a Ana'});
    await store.addTask('Comprar pan');
    await settle();
    await sync.push();
    expect(mac.appleReminders.values.map((r) => r.$1), contains('Comprar pan'));
  });

  test('tachar o borrar aquí se refleja allí', () async {
    await sync.setEnabled(true);
    final t = await store.addTask('Estudiar');
    await sync.push();
    final id = mac.appleReminders.keys.single;
    await store.setDone(t.id, true);
    await sync.push();
    expect(mac.appleReminders[id]!.$2, isTrue);
    await store.removeTask(t.id);
    await sync.push();
    expect(mac.appleReminders, isEmpty);
  });

  test('un recordatorio que ya avisó queda hecho allí', () async {
    await sync.setEnabled(true);
    await store.addReminder('Llamar a Ana', DateTime(2026, 1, 1, 9));
    await sync.push();
    await store.takeDue(DateTime(2026, 1, 1, 10));
    await sync.push();
    expect(mac.appleReminders.values.single, ('Llamar a Ana', true));
  });

  test('tachado en el iPhone se tacha aquí', () async {
    await sync.setEnabled(true);
    final t = await store.addTask('Estudiar');
    await sync.push();
    final id = mac.appleReminders.keys.single;
    mac.appleReminders[id] = ('Estudiar', true); // en el iPhone
    expect(await sync.pull(), 1);
    expect(store.allTasks.single.done, isTrue);
    expect(t.done, isFalse);
  });

  test('sin permiso se apaga y lo explica', () async {
    mac.calendarAllowed = false;
    await store.addTask('Estudiar');
    await sync.setEnabled(true);
    expect(sync.enabled, isFalse);
    expect(sync.problem, contains('Recordatorios'));
  });
}
