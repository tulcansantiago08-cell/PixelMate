import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelmate/application/stats/csv_export.dart';
import 'package:pixelmate/application/stats/file_saver.dart';
import 'package:pixelmate/application/workday/workday_providers.dart';
import 'package:pixelmate/application/workday/workday_store.dart';
import 'package:pixelmate/domain/activity/activity_mode.dart';
import 'package:pixelmate/infrastructure/persistence/sqlite_workday_store.dart';
import 'package:pixelmate/presentation/stats/export_csv_button.dart';

WorkdayRecord rec(String id, DateTime start, int focus,
        {ActivityMode mode = ActivityMode.work, bool completed = false}) =>
    WorkdayRecord(
      id: id,
      mode: mode,
      startedAt: start.toUtc(),
      endedAt: start.add(Duration(minutes: focus + 10)).toUtc(),
      planned: const Duration(hours: 8),
      effectiveFocus: Duration(minutes: focus),
      effectiveBreak: const Duration(minutes: 10),
      focusBlocksCompleted: 2,
      cyclesCompleted: 1,
      completed: completed,
    );

void main() {
  final records = [
    rec('b', DateTime(2026, 11, 7, 20, 17), 370, completed: true),
    rec('a', DateTime(2026, 11, 5, 9, 5), 45, mode: ActivityMode.study),
  ];

  test('cabecera, una fila por jornada en orden, hora local y XP', () {
    final csv = workdaysCsv(records);
    expect(csv.startsWith('﻿'), isTrue, reason: 'BOM para Excel');
    final lines = csv.substring(1).trimRight().split('\r\n');
    expect(lines.first,
        'fecha;inicio;fin;modo;enfoque_min;descanso_min;bloques_enfoque;ciclos;completa;xp');
    expect(lines, hasLength(3));
    expect(lines[1], '2026-11-05;09:05;10:00;estudio;45;10;2;1;no;60');
    expect(lines[2], '2026-11-07;20:17;02:37;trabajo;370;10;2;1;sí;410');
  });

  test('sin jornadas, solo la cabecera', () {
    expect(workdaysCsv([]).trimRight().split('\r\n'), hasLength(1));
  });

  test('nombre sugerido con la fecha', () {
    expect(csvFileName(DateTime(2026, 11, 8, 12)),
        'pixelmate-jornadas-2026-11-08.csv');
  });

  Future<void> pumpButton(WidgetTester tester, FileSaver saver) async {
    final store = SqliteWorkdayStore.inMemory();
    for (final r in records) {
      store.completeActive(r);
    }
    await tester.pumpWidget(ProviderScope(
      overrides: [
        workdayStoreProvider.overrideWithValue(store),
        fileSaverProvider.overrideWithValue(saver),
      ],
      child: const MaterialApp(home: Scaffold(body: ExportCsvButton())),
    ));
  }

  testWidgets('exportar guarda el CSV y lo confirma', (tester) async {
    final saver = MemoryFileSaver();
    await pumpButton(tester, saver);
    await tester.tap(find.byKey(const ValueKey('export-csv')));
    await tester.pumpAndSettle();
    expect(saver.files.keys.single, startsWith('pixelmate-jornadas-'));
    expect(saver.files.values.single, contains('estudio;45'));
    expect(find.textContaining('✅ 2 jornadas guardadas en pixelmate-jornadas-'),
        findsOneWidget);
  });

  testWidgets('si se cancela no dice nada', (tester) async {
    final saver = MemoryFileSaver(cancel: true);
    await pumpButton(tester, saver);
    await tester.tap(find.byKey(const ValueKey('export-csv')));
    await tester.pumpAndSettle();
    expect(saver.files, isEmpty);
    expect(find.byKey(const ValueKey('export-status')), findsNothing);
  });
}
