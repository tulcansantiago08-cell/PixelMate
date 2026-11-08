import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/desktop/mascot_panel.dart';
import 'package:pixelmate/application/desktop/mascot_window_port.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/desktop/system_notifier.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/desktop/desktop_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Prueba el camino real de la barra de menú: el menú que se envía al
/// plugin nativo y el clic que llega de macOS con el id del elemento.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tray_manager');
  const codec = StandardMethodCodec();
  late List<Map<String, dynamic>> menus;

  setUp(() {
    menus = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'setContextMenu') {
        menus.add(Map<String, dynamic>.from(
            (call.arguments as Map)['menu'] as Map));
      }
      return true;
    });
  });

  /// Busca el id que el plugin recibió para la etiqueta dada.
  int idOf(String label) {
    int? find(List items) {
      for (final raw in items) {
        final item = Map<String, dynamic>.from(raw as Map);
        if (item['label'] == label) return item['id'] as int;
        final sub = item['submenu'];
        if (sub != null) {
          final r = find((sub as Map)['items'] as List);
          if (r != null) return r;
        }
      }
      return null;
    }

    final id = find(menus.last['items'] as List);
    expect(id, isNotNull, reason: 'No hay "$label" en el menú');
    return id!;
  }

  /// Simula el clic que macOS envía a Flutter.
  Future<void> click(String label) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(
          MethodCall('onTrayMenuItemClick', {'id': idOf(label)})),
      (_) {},
    );
    await pumpEventQueue();
  }

  Future<(ProviderContainer, NoopMascotWindow)> startShell() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final window = NoopMascotWindow();
    final container = ProviderContainer(overrides: [
      workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
      mascotWindowProvider.overrideWithValue(window),
    ]);
    addTearDown(container.dispose);
    final shell = DesktopShell(
      container: container,
      window: window,
      notifier: SystemNotifier(),
      detection: DetectionSettings(prefs),
      quitApp: () async {},
    );
    await shell.start();
    addTearDown(shell.dispose);
    await pumpEventQueue();
    return (container, window);
  }

  test('"Estadísticas" en la barra de menú abre el panel', () async {
    final (container, _) = await startShell();
    await click('Estadísticas');
    expect(container.read(mascotPanelProvider), MascotPanel.stats);
  });

  test('con una jornada en marcha también abre el panel', () async {
    final (container, _) = await startShell();
    await click('8 horas');
    expect(container.read(workdayControllerProvider).isActive, isTrue);
    await click('Estadísticas');
    expect(container.read(mascotPanelProvider), MascotPanel.stats);
    container.read(workdayControllerProvider.notifier).finish();
  });

  test('con la mascota oculta, la muestra y abre el panel', () async {
    final (container, window) = await startShell();
    await click('Ocultar mascota');
    expect(window.visible.value, isFalse);
    await click('Estadísticas');
    expect(window.visible.value, isTrue);
    expect(container.read(mascotPanelProvider), MascotPanel.stats);
  });
}
