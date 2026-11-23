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
          tr('🆕 Versión ${release.version} disponible.', '🆕 Version ${release.version} available.'),
          TextButton(
            key: const ValueKey('update-download'),
            onPressed: () => onDownload(release.page),
            child: Text(tr('Descargar ↗', 'Download ↗')),
          ),
        ),
      UpdateStatus.checking => (tr('Buscando…', 'Checking…'), null),
      UpdateStatus.upToDate => (
          tr('✅ Tienes la última versión.', '✅ You have the latest version.'),
          TextButton(
              key: const ValueKey('update-check'),
              onPressed: onCheck,
              child: Text(tr('Buscar otra vez', 'Check again'))),
        ),
      UpdateStatus.failed => (
          tr('⚠️ No pude conectar con GitHub.', "⚠️ I couldn't connect to GitHub."),
          TextButton(
              key: const ValueKey('update-check'),
              onPressed: onCheck,
              child: Text(tr('Reintentar', 'Retry'))),
        ),
      _ => (
          '',
          TextButton(
              key: const ValueKey('update-check'),
              onPressed: onCheck,
              child: Text(tr('Buscar actualizaciones', 'Check for updates'))),
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
