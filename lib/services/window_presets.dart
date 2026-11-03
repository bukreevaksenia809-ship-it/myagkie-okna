import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_json.dart';
import '../models/window_params.dart';

/// Сохранённый пользовательский пресет окна: имя + все параметры.
class WindowPreset {
  const WindowPreset({required this.name, required this.params});

  final String name;
  final WindowParams params;

  Map<String, dynamic> toJson() => {
    'name': name,
    'window': windowToJson(params),
  };

  static WindowPreset? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final name = (raw['name'] as Object?)?.toString().trim() ?? '';
    final window = raw['window'];
    if (name.isEmpty || window is! Map) return null;
    try {
      return WindowPreset(
        name: name,
        params: windowFromJson(window.cast<String, dynamic>()),
      );
    } catch (_) {
      return null;
    }
  }
}

/// Пресеты окон в локальных настройках. Не зависят от заказов и переживают
/// перезапуск; хранятся небольшим JSON-списком.
class WindowPresetStore {
  static const String _key = 'window_presets_v1';
  static const int _maxPresets = 40;

  Future<List<WindowPreset>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (WindowPreset.fromJson(item) case final preset?) preset,
      ];
    } catch (_) {
      return const [];
    }
  }

  Future<List<WindowPreset>> save(String name, WindowParams params) async {
    final clean = name.trim();
    if (clean.isEmpty) return load();
    final current = await load();
    final next = [
      WindowPreset(name: clean, params: params),
      for (final preset in current)
        if (preset.name.toLowerCase() != clean.toLowerCase()) preset,
    ].take(_maxPresets).toList(growable: false);
    await _write(next);
    return next;
  }

  Future<List<WindowPreset>> remove(String name) async {
    final current = await load();
    final next = [
      for (final preset in current)
        if (preset.name != name) preset,
    ];
    await _write(next);
    return next;
  }

  Future<void> _write(List<WindowPreset> presets) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode([for (final preset in presets) preset.toJson()]),
    );
  }
}
