import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../application/assistant/mac_actions.dart';
import 'portable_files.dart';

/// Lo que el asistente puede hacer en Windows y Linux: abrir webs y apps,
/// guardar código y copiar texto. Lo propio del Mac (música, volumen,
/// Calendario, Contactos, Recordatorios, Atajos) responde que no está
/// disponible, y el asistente lo dice.
class PortableActions implements MacActions {
  @override
  Future<bool> openUrl(Uri url, {String? browser}) async {
    try {
      return await launchUrl(url, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> openApp(String name) async {
    try {
      final result = Platform.isWindows
          ? await Process.run('cmd', ['/c', 'start', '', name], runInShell: true)
          : await Process.run('gtk-launch', [name.toLowerCase()]);
      return result.exitCode == 0 ? name : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SavedCode?> saveCode(String fileName, String content,
      {String? editor}) async {
    final path = await saveWithDialog(fileName, content);
    if (path == null) return null;
    await launchUrl(Uri.file(path));
    return SavedCode(path, '');
  }

  @override
  Future<bool> copyText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  }

  /// País del sistema ("CO", "EC"…), de la configuración regional.
  @override
  Future<String> regionCode() async {
    final parts = Platform.localeName.split(RegExp(r'[_\-.]'));
    return parts.length > 1 ? parts[1].toUpperCase() : '';
  }

  @override
  Future<String?> closeApp(String name) async => null;

  @override
  Future<String?> hideApp(String name) async => null;

  @override
  Future<List<String>> runningApps() async => const [];

  @override
  Future<MediaResult> media(String action, {String? player}) async =>
      (player: null, track: null, error: 'none');

  @override
  Future<VolumeLevel?> volume(String action, [int value = 0]) async => null;

  @override
  Future<List<CalendarEvent>> events(int dayOffset) async =>
      throw const CalendarDenied();

  @override
  Future<String?> createEvent(String title, DateTime start,
          {int minutes = 60, bool allDay = false, int? alert, String? repeat}) async =>
      throw const CalendarDenied();

  @override
  Future<bool> deleteEvent(String id) async => false;

  @override
  Future<String?> addAppleReminder(String title, {DateTime? due}) async => null;

  @override
  Future<bool> setAppleReminderDone(String id, bool done) async => false;

  @override
  Future<bool> removeAppleReminder(String id) async => false;

  @override
  Future<Map<String, bool>> appleRemindersDone(List<String> ids) async => const {};

  @override
  Future<List<Contact>> findContacts(String name) async =>
      throw const ContactsDenied();

  @override
  Future<bool> audioPlaying() async => false;

  @override
  Future<String> runShortcut(String name) async => 'missing';
}
