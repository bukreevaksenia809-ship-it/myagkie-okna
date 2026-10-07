import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Ссылка на сохранённый заказ.
class StoredOrderRef {
  const StoredOrderRef({
    required this.id,
    required this.label,
    required this.savedAt,
  });

  final String id;
  final String label;
  final DateTime savedAt;
}

const _storageKey = 'myagkie_okna_orders';

/// В браузере заказы лежат в локальном хранилище (localStorage).
String ordersFolderDescriptionImpl([String? directoryPath]) =>
    'локальное хранилище браузера';

Future<Map<String, dynamic>> _readAll() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString(_storageKey);
  if (raw == null || raw.isEmpty) return <String, dynamic>{};
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map ? decoded.cast<String, dynamic>() : <String, dynamic>{};
  } catch (_) {
    return <String, dynamic>{};
  }
}

Future<void> _writeAll(Map<String, dynamic> data) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_storageKey, jsonEncode(data));
}

/// Сохраняет заказ в локальном хранилище браузера.
Future<StoredOrderRef> storeOrder(
  Map<String, dynamic> payload,
  String fileName, {
  String? directoryPath,
  DateTime? savedAt,
}) async {
  final moment = savedAt ?? DateTime.now();
  final all = await _readAll();
  all[fileName] = payload;
  await _writeAll(all);
  return StoredOrderRef(id: fileName, label: fileName, savedAt: moment);
}

/// Список сохранённых заказов вместе с их JSON.
Future<List<(StoredOrderRef, Map<String, dynamic>)>> readStoredOrders({
  String? directoryPath,
}) async {
  final all = await _readAll();
  final result = <(StoredOrderRef, Map<String, dynamic>)>[];
  for (final entry in all.entries) {
    final value = entry.value;
    if (value is! Map) continue;
    final json = value.cast<String, dynamic>();
    result.add((
      StoredOrderRef(
        id: entry.key,
        label: entry.key,
        savedAt: DateTime.tryParse('${json['savedAt']}') ?? DateTime.now(),
      ),
      json,
    ));
  }
  return result;
}

/// Читает один заказ.
Future<Map<String, dynamic>> readStoredOrder(StoredOrderRef ref) async {
  final all = await _readAll();
  final value = all[ref.id];
  return value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};
}

/// Удаляет заказ из локального хранилища.
Future<void> removeStoredOrder(StoredOrderRef ref) async {
  final all = await _readAll();
  all.remove(ref.id);
  await _writeAll(all);
}
