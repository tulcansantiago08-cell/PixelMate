part of '../command_parser.dart';

// Respuestas a una pregunta: «sí» / «no».

/// «sí» → `true`, «no» → `false`; `null` si no es una respuesta así.
bool? yesNo(String message) {
  final m = fold(message)
      .replaceAll(RegExp(r'[¿?¡!.,;:]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  if (RegExp(r'^(?:no|nop|nel|cancela(?:lo)?|mejor no|dejalo|no gracias|'
          r'olvidalo|no lo hagas|para|detente)$')
      .hasMatch(m)) {
    return false;
  }
  if (RegExp(r'^(?:si|sip|dale|confirmo|hazlo|claro|ok|okey|okay|va|vale|'
          r'adelante|de una|por favor|si por favor|si claro|si hazlo|si dale|'
          r'si (?:cierra|quita|borra)(?:la|lo|las|los)?|correcto|afirmativo)$')
      .hasMatch(m)) {
    return true;
  }
  return null;
}
