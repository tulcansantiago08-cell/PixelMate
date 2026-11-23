import '../../core/i18n/language.dart';
import 'package:flutter/material.dart';

import '../../application/mascot/mascot_settings.dart';
import '../stats/stats_style.dart';

/// Pide un nombre para la mascota. Devuelve el texto escrito o `null` si se
/// cancela.
Future<String?> showRenameDialog(BuildContext context, String current,
        {String? title, String? hint, String fieldKey = 'pet-name'}) =>
    showDialog<String>(
      context: context,
      // La ventana es transparente: un fondo oscuro pintaría un rectángulo
      // gris sobre el escritorio.
      barrierColor: Colors.transparent,
      builder: (_) => _RenameDialog(
          current,
          title ?? tr('¿Cómo me llamo?', "What's my name?"),
          hint ?? tr('Michi, Luna, Nube…', 'Kitty, Luna, Cloud…'),
          fieldKey),
    );

/// El diálogo es dueño de su campo de texto, así se libera cuando termina
/// la animación de cierre (y no antes).
class _RenameDialog extends StatefulWidget {
  final String current;
  final String title;
  final String hint;
  final String fieldKey;
  const _RenameDialog(this.current, this.title, this.hint, this.fieldKey);

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _controller = TextEditingController(text: widget.current);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: StatsStyle.surface,
      title: Text(widget.title,
          style: const TextStyle(color: Colors.white, fontSize: 15)),
      content: TextField(
        key: ValueKey('${widget.fieldKey}-field'),
        controller: _controller,
        autofocus: true,
        maxLength: MascotSettings.maxNameLength,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          hintText: widget.hint,
          hintStyle: const TextStyle(color: Colors.white38),
          counterStyle: const TextStyle(color: Colors.white38),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(tr('Cancelar', 'Cancel')),
        ),
        FilledButton(
          key: ValueKey('${widget.fieldKey}-save'),
          onPressed: _save,
          child: Text(tr('Guardar', 'Save')),
        ),
      ],
    );
  }
}
