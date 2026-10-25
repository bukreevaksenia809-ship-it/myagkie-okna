import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_json.dart';
import '../models/order_project.dart';
import 'license.dart';
import 'device_scan_io.dart'
    if (dart.library.js_interop) 'device_scan_web.dart' as device;
import 'test_env_io.dart'
    if (dart.library.js_interop) 'test_env_web.dart' as test_env;

/// Телеметрия и обновления через Firestore REST.
///
/// Внутренний контур: приложение отправляет «пульс» (версия, устройство,
/// список файлов рядом с папкой приложения, параметры окон и события), а
/// админ-панель читает это по общему ключу. Ключ лежит в коде — это
/// внутренняя сеть производства, не публичный продукт.
class Telemetry {
  static const String projectId = 'okna-7dbf8';
  static const String apiKey = 'AIzaSyAwOQn1TDzcApHt1PKmhxoQfFAtraYSaA4';
  static const String secret = 'okna-b0ZHSRJIz3XqCnQtsbL0FXBxHu4j';
  static const String _base =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  static String? _installId;
  static String? _firstSeen;
  static Map<String, Object?> _device = const {};
  static Timer? _timer;
  static Timer? _debounce;

  static bool get _enabled => !test_env.isTestEnvironment;

  /// Постоянный id установки (для команд и лицензий).
  static String? get installId => _installId;

  static Future<void> init({
    required OrderProject project,
    required String version,
  }) async {
    if (!_enabled) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _installId ??= prefs.getString('telemetry_install_id');
      if (_installId == null) {
        _installId =
            'okna-${DateTime.now().millisecondsSinceEpoch}-${DateTime.now().microsecond}';
        await prefs.setString('telemetry_install_id', _installId!);
      }
      _firstSeen ??= prefs.getString('telemetry_first_seen');
      if (_firstSeen == null) {
        _firstSeen = DateTime.now().toUtc().toIso8601String();
        await prefs.setString('telemetry_first_seen', _firstSeen!);
      }
      _device = await device.collectDeviceInfo();
      await _heartbeat(project, version);
      await event('start', {'version': version});
      _timer ??= Timer.periodic(const Duration(minutes: 10), (_) {
        _heartbeat(project, version);
      });
    } catch (_) {
      // Телеметрия не должна мешать работе приложения.
    }
  }

  static void projectChanged(OrderProject project, String version) {
    if (!_enabled) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(seconds: 4), () {
      _heartbeat(project, version);
      event('project_changed', {
        'windows': project.windowCount,
        'mode': project.sheetMode.name,
      });
    });
  }

  static Future<void> event(String type, [Map<String, Object?> data = const {}]) async {
    if (!_enabled || _installId == null) return;
    try {
      final body = jsonEncode({
        'fields': {
          'key': _s(secret),
          'installId': _s(_installId!),
          'type': _s(type),
          'at': _ts(DateTime.now().toUtc()),
          'data': _map(data),
        },
      });
      await http.post(
        Uri.parse('$_base/installations/$_installId/events?key=$apiKey'),
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (_) {}
  }

  static Future<void> _heartbeat(OrderProject project, String version) async {
    if (_installId == null) return;
    try {
      final selected = windowToJson(project.selected);
      final body = jsonEncode({
        'fields': {
          'key': _s(secret),
          'installId': _s(_installId!),
          'version': _s(version),
          'firstSeen': _ts(DateTime.parse(_firstSeen!)),
          'lastSeen': _ts(DateTime.now().toUtc()),
          'windowCount': _i(project.windowCount),
          'licenseKey': _s(LicenseService.savedKey ?? ''),
          'sheetMode': _s(project.sheetMode.name),
          'selectedParams': _s(jsonEncode(selected)),
          'order': _s(jsonEncode(orderToJson(project))),
          'device': _map(_device),
        },
      });
      await http.patch(
        Uri.parse('$_base/installations/$_installId?key=$apiKey'),
        headers: const {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (_) {}
  }

  static Future<AppUpdate?> checkUpdate() async {
    if (!_enabled) return null;
    try {
      final response = await http.get(
        Uri.parse('$_base/config/app?key=$apiKey'),
      );
      if (response.statusCode != 200) return null;
      final json = jsonDecode(response.body);
      final fields = json['fields'];
      if (fields is! Map) return null;
      final enabled = fields['enabled']?['booleanValue'] == true;
      if (!enabled) return null;
      final version = fields['latestVersion']?['stringValue'] ?? '';
      final url = fields['url']?['stringValue'] ?? '';
      if (version.isEmpty || url.isEmpty) return null;
      final rollout = fields['rollout']?['arrayValue']?['values'];
      final ids = rollout is List
          ? [for (final item in rollout) item['stringValue'] ?? '']
          : const <String>[];
      final all = fields['rolloutAll']?['booleanValue'] ?? true;
      if (!all && _installId != null && !ids.contains(_installId)) return null;
      return AppUpdate(
        version: version,
        url: url,
        sha256: fields['sha256']?['stringValue'] ?? '',
        notes: fields['notes']?['stringValue'] ?? '',
        autoUpdate: fields['autoUpdate']?['booleanValue'] == true,
      );
    } catch (_) {
      return null;
    }
  }

  /// Скачать и применить обновление (desktop). Возвращает false, если
  /// платформа не поддерживает замену файлов.
  static Future<bool> applyUpdate(AppUpdate update) async {
    try {
      final path = await device.downloadUpdate(update.url, update.sha256);
      await event('update_apply', {'version': update.version});
      await device.applyUpdateZip(path);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _s(String value) => {'stringValue': value};
  static Map<String, dynamic> _i(int value) => {'integerValue': '$value'};
  static Map<String, dynamic> _ts(DateTime value) =>
      {'timestampValue': value.toUtc().toIso8601String()};
  static Map<String, dynamic> _map(Map<String, Object?> value) => {
    'mapValue': {
      'fields': {
        for (final entry in value.entries)
          entry.key: _value(entry.value),
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

class AppUpdate {
  const AppUpdate({
    required this.version,
    required this.url,
    this.sha256 = '',
    this.notes = '',
    this.autoUpdate = false,
  });

  final String version;
  final String url;
  final String sha256;
  final String notes;

  /// Ставить без вопроса при запуске.
  final bool autoUpdate;
}
