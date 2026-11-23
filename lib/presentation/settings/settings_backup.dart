part of 'settings_panel.dart';

// Copia de seguridad.

/// Guardar tus datos en un archivo y restaurarlos (por ejemplo, en otro Mac).
class _BackupButtons extends ConsumerStatefulWidget {
  const _BackupButtons();

  @override
  ConsumerState<_BackupButtons> createState() => _BackupButtonsState();
}

class _BackupButtonsState extends ConsumerState<_BackupButtons> {
  String? _message;

  Future<void> _export() async {
    final prefs = ref.read(backupPrefsProvider);
    if (prefs == null) return;
    final now = DateTime.now();
    try {
      final path = await ref
          .read(backupFilesProvider)
          .save(backupFileName(now), makeBackup(prefs, now));
      if (path != null) setState(() => _message = tr('✅ Copia guardada.', '✅ Backup saved.'));
    } catch (_) {
      setState(() => _message = tr('⚠️ No pude guardar la copia.', "⚠️ I couldn't save the backup."));
    }
  }

  Future<void> _import() async {
    final prefs = ref.read(backupPrefsProvider);
    if (prefs == null) return;
    final files = ref.read(backupFilesProvider);
    final String? json;
    try {
      json = await files.open();
    } catch (_) {
      setState(() => _message = tr('⚠️ No pude abrir el archivo.', "⚠️ I couldn't open the file."));
      return;
    }
    if (json == null || !mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('¿Restaurar la copia?', 'Restore the backup?')),
        content: Text(tr('Tus tareas, calendario, alarmas y ajustes se cambian por los de la copia, y PixelMate se vuelve a abrir.', "Your tasks, calendar, alarms and settings are replaced with the backup's, and PixelMate reopens.")),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('Cancelar', 'Cancel'))),
          FilledButton(
              key: const ValueKey('backup-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('Restaurar', 'Restore'))),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final count = await restoreBackup(prefs, json);
      setState(() => _message = tr('✅ Restaurados $count datos. Reiniciando…', '✅ Restored $count items. Restarting…'));
      await files.relaunch();
    } on FormatException catch (e) {
      setState(() => _message = '⚠️ ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
              tr('Guarda tus tareas, calendario, alarmas y ajustes en un archivo para no perderlos (por ejemplo, al cambiar de Mac).', "Save your tasks, calendar, alarms and settings to a file so you don't lose them (for example, when changing Macs)."),
              style: const TextStyle(color: StatsStyle.textMuted, fontSize: 10)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('backup-export'),
                onPressed: _export,
                child: Text(tr('Guardar…', 'Save…'), style: const TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('backup-import'),
                onPressed: _import,
                child: Text(tr('Restaurar…', 'Restore…'), style: const TextStyle(fontSize: 12)),
              ),
            ),
          ]),
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: PlainText(_message!,
                  key: const ValueKey('backup-message'),
                  style: const TextStyle(
                      color: StatsStyle.textSecondary, fontSize: 11)),
            ),
        ],
      );
}
