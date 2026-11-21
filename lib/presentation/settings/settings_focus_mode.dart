part of 'settings_panel.dart';

// Modo Concentración de macOS durante el enfoque.

class _FocusModeOptions extends ConsumerWidget {
  const _FocusModeOptions();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final focus = ref.watch(focusModeSettingsProvider);
    const small = TextStyle(color: StatsStyle.textMuted, fontSize: 10);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Switch(
          keyName: 'focusmode',
          label: 'Activar Concentración en el enfoque',
          help: 'Silencia las notificaciones mientras te enfocas y las '
              'devuelve en los descansos.',
          value: focus.enabled,
          onChanged: focus.setEnabled,
        ),
        const SizedBox(height: 4),
        const Text(
            'Necesita dos atajos en la app Atajos: «${FocusModeSettings.onShortcut}» '
            'con la acción «Activar Concentración» y '
            '«${FocusModeSettings.offShortcut}» con «Desactivar Concentración».',
            style: small),
        const SizedBox(height: 6),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            key: const ValueKey('focusmode-open'),
            onPressed: () => ref.read(macActionsProvider).openApp('Atajos'),
            icon: const Icon(Icons.open_in_new_rounded, size: 14),
            label: const Text('Abrir Atajos', style: TextStyle(fontSize: 11)),
          ),
          OutlinedButton.icon(
            key: const ValueKey('focusmode-test'),
            onPressed: () async {
              final mode = ref.read(focusModeProvider);
              if (await mode.set(true)) {
                await Future<void>.delayed(const Duration(seconds: 3));
                await mode.set(false);
              }
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 14),
            label: const Text('Probar', style: TextStyle(fontSize: 11)),
          ),
        ]),
        if (focus.problem != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(focus.problem!,
                key: const ValueKey('focusmode-problem'),
                style: const TextStyle(color: Colors.amber, fontSize: 10)),
          ),
      ],
    );
  }
}
