import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/assistant/mac_actions.dart';
import 'package:pixelmate/application/desktop/app_info.dart';
import 'package:pixelmate/application/desktop/updates.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pixelmate/presentation/settings/settings_panel.dart';
import 'package:pixelmate/application/activity/activity_providers.dart';
import 'package:pixelmate/application/activity/detection_settings.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';

ReleaseInfo rel(String v) => ReleaseInfo(v, Uri.parse('$releasesPage/tag/v$v'));

void main() {
  test('comparar versiones', () {
    expect(compareVersions('1.1.0', '1.0.0'), greaterThan(0));
    expect(compareVersions('1.10.0', '1.9.2'), greaterThan(0));
    expect(compareVersions('v1.0.0', '1.0.0 (2)'), 0);
    expect(compareVersions('1.0.0+3', '1.0.0'), 0,
        reason: 'compilación no cuenta');
    expect(compareVersions('1.0', '1.0.1'), lessThan(0));
    expect(compareVersions('2.0.0', '10.0.0'), lessThan(0));
  });

  test('solo enlaces de este repositorio', () {
    expect(safeReleasePage('$releasesPage/tag/v1.1.0', '1.1.0').toString(),
        '$releasesPage/tag/v1.1.0');
    expect(safeReleasePage('https://malo.example/descarga', '1.1.0').toString(),
        '$releasesPage/tag/v1.1.0');
    expect(
        safeReleasePage(null, '2.0.0').toString(), '$releasesPage/tag/v2.0.0');
  });

  group('revisión', () {
    late FakeUpdateChecker checker;
    late UpdateSettings settings;
    late UpdateController c;

    Future<void> setUpWith(String installed, {bool enabled = true}) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      checker = FakeUpdateChecker();
      settings = UpdateSettings(prefs);
      await settings.setEnabled(enabled);
      c = UpdateController(checker, settings, () async => installed,
          schedule: false);
      addTearDown(c.dispose);
    }

    test('al día', () async {
      await setUpWith('1.0.0 (2)');
      checker.release = rel('1.0.0');
      await c.check();
      expect(c.state.status, UpdateStatus.upToDate);
      expect(c.state.announce, 0);
    });

    test('versión nueva: se avisa una sola vez', () async {
      await setUpWith('1.0.0 (2)');
      checker.release = rel('1.1.0');
      await c.check();
      expect(c.state.status, UpdateStatus.available);
      expect(c.state.release!.version, '1.1.0');
      expect(c.state.announce, 1);
      await c.check();
      expect(c.state.announce, 1, reason: 'no se repite el aviso');
      expect(settings.notified, '1.1.0');

      checker.release = rel('1.2.0');
      await c.check();
      expect(c.state.announce, 2, reason: 'otra versión sí se avisa');
      expect(updateMessage(c.state.release!), contains('la 1.2.0'));
    });

    test('desactivada solo revisa si se pide a mano; sin red, falla', () async {
      await setUpWith('1.0.0', enabled: false);
      checker.release = rel('1.1.0');
      await c.check();
      expect(checker.calls, 0);
      await c.check(manual: true);
      expect(c.state.status, UpdateStatus.available);

      checker.release = null;
      await c.check(manual: true);
      expect(c.state.status, UpdateStatus.failed);
    });
  });

  testWidgets('Acerca de: muestra la versión nueva y la descarga',
      (tester) async {
    tester.view.physicalSize = const Size(320, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({'onboarding.done': true});
    final prefs = await SharedPreferences.getInstance();
    final mac = FakeMacActions();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(SqliteWorkdayStore.inMemory()),
        detectionSettingsProvider.overrideWithValue(DetectionSettings(prefs)),
        appInfoProvider.overrideWithValue(FakeAppInfo('1.0.0 (2)')),
        updateCheckerProvider
            .overrideWithValue(FakeUpdateChecker(rel('1.1.0'))),
        macActionsProvider.overrideWithValue(mac),
      ],
      child: MaterialApp(
          home: Scaffold(
              body: SettingsPanel(onClose: () {}, onShowWelcome: () {}))),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('update-check')));
    await tester.pumpAndSettle();
    expect(find.text('🆕 Versión 1.1.0 disponible.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('update-download')));
    expect(mac.opened.single, '$releasesPage/tag/v1.1.0');
    expect(find.text('Buscar actualizaciones solo'), findsOneWidget);
  });
}
