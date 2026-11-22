part of '../command_parser.dart';

// Mensajes por WhatsApp: «mándale a Mamá por WhatsApp que llego tarde».

/// «mándale a Mamá por WhatsApp que llego tarde», «ve a WhatsApp y
/// escríbele a Ana: ya voy», «envía un WhatsApp a Juan diciendo que sí».
/// [ParsedCommand.app] es el contacto y [ParsedCommand.text] el mensaje.
ParsedCommand? _whatsappCommand(String original, String m) {
  // Con «WhatsApp» en la frase, o «envía un mensaje a…» / «escríbele a…»
  // (sin decir por dónde: se entiende WhatsApp).
  final saysWhatsapp = RegExp(r'\b(whatsapp|wasap|whats|wsp)\b').hasMatch(m);
  // Sin «WhatsApp»: «envía un mensaje a X» o «escríbele a X», nunca «a las
  // 5» (eso es un recordatorio), «para …» (un texto que escribir) ni
  // «mándame» (es para ti).
  final saysMessage = RegExp(
          r'^(?:manda|envia|escribe)(?:le|les)?\s+(?:un\s+)?(?:mensaje|msj|mensajito)\s+(?:a|al)\s+(?!las?\s+\d|la una\b)'
          r'|^(?:mandale|enviale|escribele|mandales)\s+(?:un\s+(?:mensaje|msj)\s+)?(?:a|al)\s+(?!las?\s+\d|la una\b)')
      .hasMatch(m);
  if (!saysWhatsapp && !saysMessage) return null;
  // «Mándame un WhatsApp…» o «escríbeme…»: no es para otra persona.
  if (RegExp(r'^(?:mandame|enviame|escribeme)\b').hasMatch(m)) return null;
  // Se recorta igual el texto original y el plegado (misma longitud).
  var o = original.trim();
  var f = m.trim();
  void cut(RegExp re) {
    final x = re.firstMatch(f);
    if (x == null) return;
    o = (o.substring(0, x.start) + o.substring(x.end)).trim();
    f = (f.substring(0, x.start) + f.substring(x.end)).trim();
  }

  cut(RegExp(r'^(?:ve a|abre|entra a|en)\s+(?:el\s+)?whatsapp\s*(?:y|,)?\s*'));
  final verb = RegExp(
          r'^(?:manda|envia|escribe|mandar|enviar|escribir)(?:le|les|me)?\b\s*')
      .firstMatch(f);
  if (verb == null) return null;
  cut(RegExp(
      r'^(?:manda|envia|escribe|mandar|enviar|escribir)(?:le|les|me)?\b\s*'));
  cut(RegExp(
      r'^(?:un|una)\s+(?:mensaje|mensajito|msj|whatsapp|wasap|nota|texto)\s*'));
  cut(RegExp(
      r'\s*\b(?:por|en|al|via)\s+(?:el\s+)?(?:whatsapp|wasap|whats|wsp)\b'));

  // «… a Mamá que llego tarde» / «… a Ana: ya voy».
  String contact;
  String message;
  // Primero «:», «que», «diciendo»…; la coma solo si no hay nada de eso
  // («a Ana, Pedro y Luis que ya llegué» son varios destinatarios).
  final split =
      RegExp(r'\s*(?::|\s(?:que diga|que le digas?|que|diciendo(?:le)?|diciendole|con el texto)\s)')
              .firstMatch(f) ??
          RegExp(r'\s*,\s*').firstMatch(f);
  if (split != null) {
    contact = o.substring(0, split.start);
    message = o.substring(split.end);
  } else {
    contact = o;
    message = '';
  }
  contact = contact
      .replaceFirst(
          RegExp(r'^(?:a la|a mi|al|a|para)\s+', caseSensitive: false), '')
      .replaceAll(RegExp(r'[.,;:!¡?¿]+$'), '')
      .trim();
  message = message
      .replaceAll(RegExp(r'^[\s:,]+'), '')
      .replaceFirst(RegExp(r'^que\s+', caseSensitive: false), '')
      .trim();
  if (message.isNotEmpty) {
    message = message[0].toUpperCase() + message.substring(1);
  }
  return ParsedCommand(AssistantIntent.whatsapp, text: message, app: contact);
}
