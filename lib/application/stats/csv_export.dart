import '../../domain/activity/activity_mode.dart';
import '../progress/progression.dart';
import '../workday/workday_store.dart';

/// Columnas del CSV de jornadas.
const csvHeader = [
  'fecha',
  'inicio',
  'fin',
  'modo',
  'enfoque_min',
  'descanso_min',
  'bloques_enfoque',
  'ciclos',
  'completa',
  'xp',
];

String _two(int n) => n.toString().padLeft(2, '0');
String _date(DateTime t) => '${t.year}-${_two(t.month)}-${_two(t.day)}';
String _time(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String _mode(ActivityMode m) => switch (m) {
      ActivityMode.work => 'trabajo',
      ActivityMode.study => 'estudio',
      ActivityMode.gaming => 'juego',
      ActivityMode.free => 'libre',
    };

/// Escapa un campo si lleva separador, comillas o saltos de línea.
String _field(String v) =>
    v.contains(RegExp('[;"\\n\\r]')) ? '"${v.replaceAll('"', '""')}"' : v;

/// Jornadas en CSV, de la más antigua a la más reciente, en hora local.
///
/// Usa `;` como separador y empieza con BOM UTF-8: así Excel en español lo
/// abre con columnas y acentos bien, y Numbers también.
String workdaysCsv(List<WorkdayRecord> records) {
  final sorted = [...records]
    ..sort((a, b) => a.startedAt.compareTo(b.startedAt));
  final lines = [
    csvHeader.join(';'),
    for (final r in sorted)
      [
        _date(r.startedAt.toLocal()),
        _time(r.startedAt.toLocal()),
        _time(r.endedAt.toLocal()),
        _mode(r.mode),
        '${r.effectiveFocus.inMinutes}',
        '${r.effectiveBreak.inMinutes}',
        '${r.focusBlocksCompleted}',
        '${r.cyclesCompleted}',
        r.completed ? 'sí' : 'no',
        '${xpForRecord(r)}',
      ].map(_field).join(';'),
  ];
  return '﻿${lines.join('\r\n')}\r\n';
}

/// Nombre sugerido: "pixelmate-jornadas-2026-11-08.csv".
String csvFileName(DateTime now) =>
    'pixelmate-jornadas-${_date(now.toLocal())}.csv';
