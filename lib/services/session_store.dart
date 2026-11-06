import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_json.dart';
import '../models/order_project.dart';

/// Автосохранение рабочей сессии: заказ, размеры, настройки.
///
/// Если приложение закрыли случайно, при следующем запуске открывается тот же
/// заказ. Хранится только текущий проект, а не история — история заказов
/// лежит в сохранённых файлах.
class SessionStore {
  SessionStore._();

  static const String key = 'working_session_v1';

  static Future<void> save(OrderProject project) => saveJson(orderToJson(project));

  /// Сохраняет JSON строкой, чтобы не зависеть от кодека платформы.
  static Future<void> saveJson(Map<String, dynamic> json) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, _encode(json));
    } catch (_) {}
  }

  static Future<OrderProject?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = _decode(raw);
      if (decoded is! Map) return null;
      return orderFromJson(decoded.cast<String, dynamic>());
    } catch (_) {
      return null;
    }
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  static String _encode(Map<String, dynamic> json) {
    try {
      return const JsonEncoder().convert(json);
    } catch (_) {
      return '';
    }
  }

  static Object? _decode(String raw) {
    try {
      return const JsonDecoder().convert(raw);
    } catch (_) {
      return null;
    }
  }
}
