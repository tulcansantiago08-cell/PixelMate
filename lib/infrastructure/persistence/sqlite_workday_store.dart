import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:sqlite3/sqlite3.dart';

import '../../application/workday/workday_store.dart';
import '../../domain/activity/activity_mode.dart';
import '../../domain/session/workday_timer.dart';

/// Guarda la jornada activa y el historial en SQLite local.
class SqliteWorkdayStore implements WorkdayStore {
  final Database _db;

  static const _schemaVersion = 1;

  SqliteWorkdayStore(this._db) {
    _migrate();
  }

  factory SqliteWorkdayStore.open(String path) =>
      SqliteWorkdayStore(sqlite3.open(path));

  factory SqliteWorkdayStore.inMemory() =>
      SqliteWorkdayStore(sqlite3.openInMemory());

  void _migrate() {
    final version = _db.select('PRAGMA user_version').first.columnAt(0) as int;
    if (version >= _schemaVersion) return;
    _db.execute('BEGIN');
    try {
      if (version < 1) {
        _db.execute('''
          CREATE TABLE active_workday (
            slot        INTEGER PRIMARY KEY CHECK (slot = 1),
            mode        TEXT NOT NULL,
            timer_json  TEXT NOT NULL
          )''');
        _db.execute('''
          CREATE TABLE workday_history (
            id                   TEXT PRIMARY KEY,
            mode                 TEXT NOT NULL,
            started_at           TEXT NOT NULL,
            ended_at             TEXT NOT NULL,
            planned_s            INTEGER NOT NULL,
            effective_focus_s    INTEGER NOT NULL,
            effective_break_s    INTEGER NOT NULL,
            focus_blocks         INTEGER NOT NULL,
            cycles               INTEGER NOT NULL,
            completed            INTEGER NOT NULL
          )''');
        _db.execute(
            'CREATE INDEX idx_history_started ON workday_history(started_at)');
      }
      _db.execute('PRAGMA user_version = $_schemaVersion');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  ActiveWorkday? loadActive() {
    final rows = _db
        .select('SELECT mode, timer_json FROM active_workday WHERE slot = 1');
    if (rows.isEmpty) return null;
    final row = rows.first;
    try {
      return ActiveWorkday(
        ActivityMode.values.byName(row['mode'] as String),
        WorkdayTimer.fromJson(
            jsonDecode(row['timer_json'] as String) as Map<String, dynamic>),
      );
    } catch (e) {
      // Un registro dañado no debe impedir abrir la app.
      debugPrint('Jornada activa ilegible, se descarta: $e');
      _db.execute('DELETE FROM active_workday');
      return null;
    }
  }

  @override
  void saveActive(ActiveWorkday active) {
    _db.execute(
      'INSERT OR REPLACE INTO active_workday (slot, mode, timer_json) '
      'VALUES (1, ?, ?)',
      [active.mode.name, jsonEncode(active.timer.toJson())],
    );
  }

  @override
  void completeActive(WorkdayRecord r) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'INSERT OR REPLACE INTO workday_history (id, mode, started_at, '
        'ended_at, planned_s, effective_focus_s, effective_break_s, '
        'focus_blocks, cycles, completed) VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          r.id,
          r.mode.name,
          r.startedAt.toUtc().toIso8601String(),
          r.endedAt.toUtc().toIso8601String(),
          r.planned.inSeconds,
          r.effectiveFocus.inSeconds,
          r.effectiveBreak.inSeconds,
          r.focusBlocksCompleted,
          r.cyclesCompleted,
          r.completed ? 1 : 0,
        ],
      );
      _db.execute('DELETE FROM active_workday');
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  @override
  List<WorkdayRecord> history({DateTime? since}) {
    final rows = since == null
        ? _db.select('SELECT * FROM workday_history ORDER BY started_at')
        : _db.select(
            'SELECT * FROM workday_history WHERE started_at >= ? '
            'ORDER BY started_at',
            [since.toUtc().toIso8601String()]);
    return [
      for (final row in rows)
        WorkdayRecord(
          id: row['id'] as String,
          mode: ActivityMode.values.byName(row['mode'] as String),
          startedAt: DateTime.parse(row['started_at'] as String),
          endedAt: DateTime.parse(row['ended_at'] as String),
          planned: Duration(seconds: row['planned_s'] as int),
          effectiveFocus: Duration(seconds: row['effective_focus_s'] as int),
          effectiveBreak: Duration(seconds: row['effective_break_s'] as int),
          focusBlocksCompleted: row['focus_blocks'] as int,
          cyclesCompleted: row['cycles'] as int,
          completed: (row['completed'] as int) == 1,
        )
    ];
  }

  void close() => _db.close();
}
