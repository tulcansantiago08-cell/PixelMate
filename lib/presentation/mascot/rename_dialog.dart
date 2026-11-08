import 'package:flutter/material.dart';

import '../../application/mascot/mascot_settings.dart';

/// Pide un nombre para la mascota. Devuelve el texto escrito o `null` si se
/// cancela.
Future<String?> showRenameDialog(BuildContext context, String current) =>
    showDialog<String>(
      context: context,
      // La ventana es transparente: un fondo oscuro pintaría un rectángulo
      // gris sobre el escritorio.
      barrierColor: Colors.transparent,
      builder: (_) => _RenameDialog(current),
    );

/// El diálogo es dueño de su campo de texto, así se libera cuando termina
/// la animación de cierre (y no antes).
class _RenameDialog extends StatefulWidget {
  final String current;
  const _RenameDialog(this.current);

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
      backgroundColor: const Color(0xFF1E1B2E),
      title: const Text('¿Cómo me llamo? 🐾',
          style: TextStyle(color: Colors.white, fontSize: 15)),
      content: TextField(
        key: const ValueKey('pet-name-field'),
        controller: _controller,
        autofocus: true,
        maxLength: MascotSettings.maxNameLength,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          hintText: 'Michi, Luna, Nube…',
          hintStyle: TextStyle(color: Colors.white38),
          counterStyle: TextStyle(color: Colors.white38),
        ),
        onSubmitted: (_) => _save(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          key: const ValueKey('pet-name-save'),
          onPressed: _save,
          child: const Text('Guardar'),
        ),
      ],
    );
  }
}
