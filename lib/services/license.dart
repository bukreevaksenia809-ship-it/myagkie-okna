import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'device_scan_io.dart'
    if (dart.library.js_interop) 'device_scan_web.dart' as device;
import 'test_env_io.dart'
    if (dart.library.js_interop) 'test_env_web.dart' as test_env;

/// Состояние лицензии.
class LicenseState {
  const LicenseState(this.active, this.message, {this.key = ''});

  final bool active;
  final String message;
  final String key;
}

/// Ключи активации: одноразовые и многоразовые.
///
/// Ключ хранится в Firestore (licenses/{key}), активации — в подколлекции
/// activations/{installId}. Проверка идёт по точному id документа, поэтому
/// перебрать ключи нельзя; список доступен только админке.
class LicenseService {
  static const String projectId = 'okna-7dbf8';
  static const String apiKey = 'AIzaSyAwOQn1TDzcApHt1PKmhxoQfFAtraYSaA4';
  static const String secret = 'okna-b0ZHSRJIz3XqCnQtsbL0FXBxHu4j';
  static const String _base =
      'https://firestore.googleapis.com/v1/projects/$projectId/databases/(default)/documents';

  static String? _installId;
  static String _key = '';

  static String? get savedKey => _key.isEmpty ? null : _key;

  static Future<void> loadSaved() async {
    final prefs = await SharedPreferences.getInstance();
    _key = prefs.getString('license_key') ?? '';
    _installId ??= prefs.getString('license_install_id');
    if (_installId == null) {
      final now = DateTime.now();
      _installId = 'okna-${now.millisecondsSinceEpoch}-${now.microsecond}';
      await prefs.setString('license_install_id', _installId!);
    }
  }

  static Future<LicenseState> check() async {
    if (test_env.isTestEnvironment) {
      return const LicenseState(true, 'тестовый режим');
    }
    await loadSaved();
    if (_key.isEmpty) {
      return const LicenseState(false, 'Введите ключ активации');
    }
    try {
      final license = await _license(_key);
      if (license == null) {
        return const LicenseState(false, 'Ключ не найден');
      }
      final problem = _checkFields(license);
      if (problem != null) return LicenseState(false, problem, key: _key);
      final activated = await _activation(_key);
      if (activated == null) {
        final count = _int(license['activationsCount']);
        final max = _int(license['maxActivations']);
        if (count >= max) {
          return LicenseState(false, 'Лимит активаций исчерпан', key: _key);
        }
        final result = await _activateNow(_key);
        if (!result.active) return result;
      } else {
        await _touchActivation(_key);
      }
      await _stampChecked();
      return LicenseState(true, 'Ключ активен: $_key', key: _key);
    } catch (_) {
      final prefs = await SharedPreferences.getInstance();
      final checked =
          DateTime.tryParse(prefs.getString('license_checked_at') ?? '');
      if (checked != null && DateTime.now().difference(checked).inDays <= 7) {
        return LicenseState(true, 'Офлайн-режим (ключ $_key)', key: _key);
      }
      return const LicenseState(false, 'Нет связи с сервером активации');
    }
  }

  /// Быстрая проверка для слежения за отключением ключа: только чтение,
  /// без записи lastSeen. Сетевые ошибки не блокируют работу.
  static Future<LicenseState> quickCheck() async {
    if (test_env.isTestEnvironment) {
      return const LicenseState(true, 'тестовый режим');
    }
    try {
      await loadSaved();
      if (_key.isEmpty) return const LicenseState(false, 'Введите ключ активации');
      final license = await _license(_key);
      if (license == null) return LicenseState(false, 'Ключ не найден', key: _key);
      final problem = _checkFields(license);
      if (problem != null) return LicenseState(false, problem, key: _key);
      final activated = await _activation(_key);
      if (activated == null) {
        return LicenseState(false, 'Ключ не активирован на этом ПК', key: _key);
      }
      return LicenseState(true, 'Ключ активен: $_key', key: _key);
    } catch (_) {
      return LicenseState(true, 'Офлайн: ключ $_key', key: _key);
    }
  }

  static Future<LicenseState> activate(String raw) async {
    final compact = raw.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');
    final key = compact.length == 16
        ? '${compact.substring(0, 4)}-${compact.substring(4, 8)}-'
              '${compact.substring(8, 12)}-${compact.substring(12, 16)}'
        : compact;
    if (key.isEmpty) {
      return const LicenseState(false, 'Введите ключ');
    }
    if (test_env.isTestEnvironment) {
      _key = key;
      return LicenseState(true, 'Ключ активен: $key', key: key);
    }
    await loadSaved();
    try {
      final license = await _license(key);
      if (license == null) return const LicenseState(false, 'Ключ не найден');
      final problem = _checkFields(license);
      if (problem != null) return LicenseState(false, problem);
      final existing = await _activation(key);
      if (existing != null) {
        await _touchActivation(key);
        _key = key;
        await _saveKey();
        return LicenseState(true, 'Ключ активирован: $key', key: key);
      }
      final count = _int(license['activationsCount']);
      final max = _int(license['maxActivations']);
      if (count >= max) {
        return const LicenseState(false, 'Лимит активаций исчерпан');
      }
      final result = await _activateNow(key);
      if (!result.active) return result;
      _key = key;
      await _saveKey();
      return LicenseState(true, 'Ключ активирован: $key', key: key);
    } catch (_) {
      return const LicenseState(false, 'Нет связи с сервером активации');
    }
  }

  static Future<LicenseState> _activateNow(String key) async {
    var ok = false;
    for (var attempt = 0; attempt < 3 && !ok; attempt++) {
      final fresh = await _license(key);
      if (fresh == null) return const LicenseState(false, 'Ключ не найден');
      final problem = _checkFields(fresh);
      if (problem != null) return LicenseState(false, problem);
      final count = _int(fresh['activationsCount']);
      final max = _int(fresh['maxActivations']);
      if (count >= max) {
        return const LicenseState(false, 'Лимит активаций исчерпан');
      }
      final updateTime = fresh['__updateTime'] as String?;
      final updateTimePart = updateTime == null
          ? ''
          : '&currentDocument.updateTime=${Uri.encodeComponent(updateTime)}';
      final uri = Uri.parse(
        '$_base/licenses/$key?key=$apiKey'
        '&updateMask.fieldPaths=activationsCount$updateTimePart',
      );
      final response = await http.patch(
        uri,
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fields': {
            'activationsCount': {'integerValue': '${count + 1}'},
          },
        }),
      );
      if (response.statusCode == 200) {
        ok = true;
      } else if (response.statusCode != 409) {
        break;
      }
    }
    if (!ok) {
      return const LicenseState(
        false,
        'Не удалось занять активацию, попробуйте ещё раз',
      );
    }
    final info = await device.basicDeviceInfo();
    final now = DateTime.now().toUtc().toIso8601String();
    await http.patch(
      Uri.parse('$_base/licenses/$key/activations/$_installId?key=$apiKey'),
      headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({
        'fields': {
          'licenseKey': {'stringValue': key},
          'installId': {'stringValue': _installId},
          'activatedAt': {'timestampValue': now},
          'lastSeen': {'timestampValue': now},
          'device': {
            'mapValue': {
              'fields': {
                for (final entry in info.entries)
                  entry.key: {'stringValue': '${entry.value}'},
              },
            },
          },
          'adminKey': {'stringValue': secret},
        },
      }),
    );
    return LicenseState(true, 'Ключ активирован: $key', key: key);
  }

  static Future<Map<String, dynamic>?> _license(String key) async {
    final response = await http.get(
      Uri.parse('$_base/licenses/$key?key=$apiKey'),
    );
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw StateError('license ${response.statusCode}');
    }
    final json = jsonDecode(response.body);
    final fields = json['fields'];
    if (fields is! Map) return null;
    return {
      for (final entry in fields.entries)
        entry.key as String: _value(entry.value),
      '__updateTime': json['updateTime'],
    };
  }

  static Future<Map<String, dynamic>?> _activation(String key) async {
    final response = await http.get(
      Uri.parse('$_base/licenses/$key/activations/$_installId?key=$apiKey'),
    );
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body);
    final fields = json['fields'];
    if (fields is! Map) return null;
    return {
      for (final entry in fields.entries)
        entry.key as String: _value(entry.value),
    };
  }

  static Future<void> _touchActivation(String key) async {
    try {
      await http.patch(
        Uri.parse(
          '$_base/licenses/$key/activations/$_installId?key=$apiKey'
          '&updateMask.fieldPaths=lastSeen',
        ),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({
          'fields': {
            'lastSeen': {
              'timestampValue': DateTime.now().toUtc().toIso8601String(),
            },
          },
        }),
      );
    } catch (_) {}
  }

  static String? _checkFields(Map<String, dynamic> license) {
    if (license['enabled'] == false) return 'Ключ отключён';
    final expires = license['expiresAt'];
    if (expires is String && expires.isNotEmpty) {
      final date = DateTime.tryParse(expires);
      if (date != null && date.isBefore(DateTime.now())) {
        return 'Срок действия ключа истёк';
      }
    }
    return null;
  }

  static int _int(Object? value) =>
      value is int ? value : int.tryParse('$value') ?? 0;

  static Object? _value(Object? raw) {
    if (raw is! Map) return null;
    if (raw.containsKey('stringValue')) return raw['stringValue'];
    if (raw.containsKey('integerValue')) {
      return int.tryParse('${raw['integerValue']}');
    }
    if (raw.containsKey('doubleValue')) return raw['doubleValue'];
    if (raw.containsKey('booleanValue')) return raw['booleanValue'];
    if (raw.containsKey('timestampValue')) return raw['timestampValue'];
    return null;
  }

  static Future<void> _saveKey() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('license_key', _key);
    await _stampChecked();
  }

  static Future<void> _stampChecked() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'license_checked_at',
      DateTime.now().toUtc().toIso8601String(),
    );
  }

  static Future<void> clear() async {
    _key = '';
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('license_key');
  }
}
