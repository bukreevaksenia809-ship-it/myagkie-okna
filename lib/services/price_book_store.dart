import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/price_list.dart';

/// Сохранение клиентского и дилерского прайсов между запусками.
///
/// Прайсы правятся в «Настройках», и настройка «Расход тента в смете» должна
/// переживать перезапуск. Один общий JSON-ключ на оба прайса проще, чем два
/// независимых: загрузка всегда возвращает согласованную пару.
class PriceBookStore {
  PriceBookStore._();

  static const String key = 'price_book_v1';

  static Future<void> save({
    required PriceList client,
    required PriceList dealer,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        key,
        jsonEncode({
          'client': client.toJson(),
          'dealer': dealer.toJson(),
        }),
      );
    } catch (_) {
      // Настройки — не критичные данные: при ошибке остаются значения в
      // памяти, приложение продолжает работать.
    }
  }

  /// Пара прайсов из хранилища; `null`, если их ещё не сохраняли.
  static Future<(PriceList, PriceList)?> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final client = decoded['client'];
      final dealer = decoded['dealer'];
      return (
        client is Map
            ? PriceList.fromJson(client.cast<String, dynamic>())
            : const PriceList.defaults(),
        dealer is Map
            ? PriceList.fromJson(dealer.cast<String, dynamic>())
            : const PriceList.defaults(),
      );
    } catch (_) {
      return null;
    }
  }

  /// Стирает сохранённые прайсы (пригодится для сброса настроек).
  static Future<void> clear() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
    } catch (_) {}
  }
}
