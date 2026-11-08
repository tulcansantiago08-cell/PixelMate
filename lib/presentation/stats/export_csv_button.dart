import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/progress/progress_providers.dart';
import '../../application/stats/csv_export.dart';
import '../../application/stats/file_saver.dart';
import 'stats_style.dart';

/// "⬇️ Exportar CSV": guarda todas las jornadas donde elija el usuario.
class ExportCsvButton extends ConsumerStatefulWidget {
  const ExportCsvButton({super.key});

  @override
  ConsumerState<ExportCsvButton> createState() => _ExportCsvButtonState();
}

class _ExportCsvButtonState extends ConsumerState<ExportCsvButton> {
  String? _status;
  bool _busy = false;

  Future<void> _export() async {
    final history = ref.read(allHistoryProvider);
    setState(() {
      _busy = true;
      _status = null;
    });
    String status;
    try {
      final path = await ref
          .read(fileSaverProvider)
          .saveText(csvFileName(DateTime.now()), workdaysCsv(history));
      status = path == null
          ? ''
          : '✅ ${history.length} '
              '${history.length == 1 ? 'jornada guardada' : 'jornadas guardadas'}'
              ' en ${path.split('/').last}';
    } catch (_) {
      status = '⚠️ No se pudo guardar el archivo.';
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _status = status.isEmpty ? null : status;
      });
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          OutlinedButton(
            key: const ValueKey('export-csv'),
            onPressed: _busy ? null : _export,
            child: const Text('⬇️ Exportar CSV'),
          ),
          if (_status != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_status!,
                  key: const ValueKey('export-status'),
                  style: const TextStyle(
                      color: StatsStyle.textSecondary, fontSize: 11)),
            ),
        ],
      );
}
