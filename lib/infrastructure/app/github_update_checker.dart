import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../application/desktop/updates.dart';

/// Consulta el último release público en GitHub.
class GitHubUpdateChecker implements UpdateChecker {
  final http.Client _client;
  GitHubUpdateChecker([http.Client? client])
      : _client = client ?? http.Client();

  @override
  Future<ReleaseInfo?> latest() async {
    try {
      final res = await _client.get(
        Uri.https('api.github.com',
            '/repos/tulcansantiago08-cell/PixelMate/releases/latest'),
        headers: {
          'Accept': 'application/vnd.github+json',
          'User-Agent': 'PixelMate',
        },
      ).timeout(const Duration(seconds: 10));
      if (res.statusCode != 200) return null;
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['draft'] == true || data['prerelease'] == true) return null;
      final tag =
          (data['tag_name'] as String? ?? '').replaceFirst(RegExp('^v'), '');
      if (tag.isEmpty) return null;
      return ReleaseInfo(
          tag, safeReleasePage(data['html_url'] as String?, tag));
    } catch (e) {
      debugPrint('Buscar actualizaciones: $e');
      return null;
    }
  }
}
