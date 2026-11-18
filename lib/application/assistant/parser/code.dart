part of '../command_parser.dart';

// Pedir código: «hazme un programa en Python que…».

/// Lenguajes que se pueden pedir y su extensión de archivo.
const codeLanguages = {
  'python': 'py',
  'javascript': 'js',
  'typescript': 'ts',
  'swift': 'swift',
  'dart': 'dart',
  'java': 'java',
  'bash': 'sh',
  'html': 'html',
  'css': 'css',
  'ruby': 'rb',
  'go': 'go',
  'php': 'php',
  'sql': 'sql',
  'kotlin': 'kt',
  'c++': 'cpp',
  'c#': 'cs',
  'rust': 'rs',
};

const _languageAliases = {
  'js': 'javascript',
  'ts': 'typescript',
  'py': 'python',
  'shell': 'bash',
  'cpp': 'c++',
};

/// Editores que se pueden pedir ("en VS Code").
const editorNames = {
  'visual studio code': 'Visual Studio Code',
  'vs code': 'Visual Studio Code',
  'vscode': 'Visual Studio Code',
  'vs': 'Visual Studio Code',
  'code': 'Visual Studio Code',
  'xcode': 'Xcode',
  'sublime text': 'Sublime Text',
  'sublime': 'Sublime Text',
  'cursor': 'Cursor',
  'zed': 'Zed',
  'pycharm': 'PyCharm',
  'intellij': 'IntelliJ IDEA',
  'android studio': 'Android Studio',
  'textedit': 'TextEdit',
  'editor de texto': 'TextEdit',
};

final _codeRequest = RegExp(
    r'\b(?:haz(?:me)?|crea(?:me)?|escribe(?:me)?|genera(?:me)?|programa(?:me)?|hacer|crear|escribir|generar|necesito)\s+(?:un|una|el|la)?\s*(script|programa|codigo|archivo|funcion)\b');

final _editorPhrase = RegExp(
    r'\b(?:(?:en|con|desde)\s+(?:el\s+)?)?(visual studio code|vs code|vscode|android studio|sublime text|editor de texto|xcode|sublime|cursor|pycharm|intellij|textedit|zed|vs)\b');

/// "abre VS Code y haz un script de Python para sumar" → crear código.
ParsedCommand? _codeCommand(String original) {
  final folded = fold(original);
  final request = _codeRequest.firstMatch(folded);
  if (request == null) return null;

  // Editor (en cualquier parte de la frase).
  String? editor;
  final e = _editorPhrase.firstMatch(folded);
  if (e != null) editor = editorNames[e.group(1)!];

  // Lo que va después de "un script…": lenguaje y descripción.
  var rest = original.substring(request.end);
  var restFolded = fold(rest);
  String? language;
  final lang = RegExp(
          r'\b(?:de|en)\s+(python|javascript|typescript|swift|dart|java|bash|shell|html|css|ruby|go|php|sql|kotlin|rust|js|ts|py|cpp|c\+\+|c#)\b')
      .firstMatch(restFolded);
  if (lang != null) {
    final name = lang.group(1)!;
    language = _languageAliases[name] ?? name;
    rest = rest.substring(0, lang.start) + rest.substring(lang.end);
    restFolded = fold(rest);
  }
  final ed = _editorPhrase.firstMatch(restFolded);
  if (ed != null) {
    rest = rest.substring(0, ed.start) + rest.substring(ed.end);
  }
  var description = rest
      .replaceFirst(
          RegExp(r'^\s*(?:(?:para|que|con|de|el cual|y que)\s+)',
              caseSensitive: false),
          '')
      .trim();
  description = description.replaceAll(RegExp(r'[\s,.;:!¡?¿]+$'), '');
  if (description.isEmpty) return null;
  return ParsedCommand(AssistantIntent.createCode,
      text: description, language: language ?? 'python', editor: editor);
}
