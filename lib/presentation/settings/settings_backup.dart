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
      if (path != null) setState(() => _message = '✅ Copia guardada.');
    } catch (_) {
      setState(() => _message = '⚠️ No pude guardar la copia.');
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
      setState(() => _message = '⚠️ No pude abrir el archivo.');
      return;
    }
    if (json == null || !mounted) return;
    final sure = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('¿Restaurar la copia?'),
        content: const Text('Tus tareas, calendario, alarmas y ajustes se '
            'cambian por los de la copia, y PixelMate se vuelve a abrir.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              key: const ValueKey('backup-confirm'),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restaurar')),
        ],
      ),
    );
    if (sure != true) return;
    try {
      final count = await restoreBackup(prefs, json);
      setState(() => _message = '✅ Restaurados $count datos. Reiniciando…');
      await files.relaunch();
    } on FormatException catch (e) {
      setState(() => _message = '⚠️ ${e.message}');
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
              'Guarda tus tareas, calendario, alarmas y ajustes en un archivo '
              'para no perderlos (por ejemplo, al cambiar de Mac).',
              style: TextStyle(color: StatsStyle.textMuted, fontSize: 10)),
          const SizedBox(height: 6),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('backup-export'),
                onPressed: _export,
                child: const Text('Guardar…', style: TextStyle(fontSize: 12)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                key: const ValueKey('backup-import'),
                onPressed: _import,
                child: const Text('Restaurar…', style: TextStyle(fontSize: 12)),
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
