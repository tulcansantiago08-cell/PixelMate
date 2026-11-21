part of 'settings_panel.dart';

// Buscar versiones nuevas.

/// Estado de las actualizaciones y su botón.
class _UpdateRow extends StatelessWidget {
  final UpdateState state;
  final VoidCallback onCheck;
  final ValueChanged<Uri> onDownload;

  const _UpdateRow(
      {required this.state, required this.onCheck, required this.onDownload});

  @override
  Widget build(BuildContext context) {
    final release = state.release;
    final (text, button) = switch (state.status) {
      UpdateStatus.available when release != null => (
          '🆕 Versión ${release.version} disponible.',
          TextButton(
            key: const ValueKey('update-download'),
            onPressed: () => onDownload(release.page),
            child: const Text('Descargar ↗'),
          ),
        ),
      UpdateStatus.checking => ('Buscando…', null),
      UpdateStatus.upToDate => (
          '✅ Tienes la última versión.',
          TextButton(
              key: const ValueKey('update-check'),
              onPressed: onCheck,
              child: const Text('Buscar otra vez')),
        ),
      UpdateStatus.failed => (
          '⚠️ No pude conectar con GitHub.',
          TextButton(
              key: const ValueKey('update-check'),
              onPressed: onCheck,
              child: const Text('Reintentar')),
        ),
      _ => (
          '',
          TextButton(
              key: const ValueKey('update-check'),
              onPressed: onCheck,
              child: const Text('Buscar actualizaciones')),
        ),
    };
    // Texto y botón uno debajo del otro si no caben en una línea.
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 4,
      children: [
        if (text.isNotEmpty)
          PlainText(text,
              key: const ValueKey('update-status'),
              style: const TextStyle(
                  color: StatsStyle.textSecondary, fontSize: 11)),
        if (button != null) button,
      ],
    );
  }
}
