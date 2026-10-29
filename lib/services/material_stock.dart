import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/window_params.dart';

/// Позиция склада: рулон или остаток материала.
class StockItem {
  const StockItem({
    required this.id,
    required this.material,
    required this.widthMm,
    required this.lengthMm,
    required this.quantity,
    this.note = '',
  });

  final String id;
  final FilmMaterial material;
  final double widthMm;
  final double lengthMm;
  final int quantity;
  final String note;

  double get areaM2 => widthMm * lengthMm * quantity / 1000000;

  Map<String, dynamic> toJson() => {
    'id': id,
    'material': material.name,
    'widthMm': widthMm,
    'lengthMm': lengthMm,
    'quantity': quantity,
    'note': note,
  };

  factory StockItem.fromJson(Map<String, dynamic> json) => StockItem(
    id: '${json['id'] ?? ''}',
    material: FilmMaterial.values.firstWhere(
      (value) => value.name == json['material'],
      orElse: () => FilmMaterial.clearPvc,
    ),
    widthMm: (json['widthMm'] as num?)?.toDouble() ?? 0,
    lengthMm: (json['lengthMm'] as num?)?.toDouble() ?? 0,
    quantity: (json['quantity'] as num?)?.toInt() ?? 0,
    note: '${json['note'] ?? ''}',
  );
}

/// Локальный склад материалов. Данные лежат в shared_preferences.
class MaterialStock {
  MaterialStock._();

  static const String key = 'material_stock_v1';

  static Future<List<StockItem>> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const [];
      return [
        for (final item in decoded)
          if (item is Map) StockItem.fromJson(item.cast<String, dynamic>()),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> save(List<StockItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      key,
      jsonEncode([for (final item in items) item.toJson()]),
    );
  }

  static Future<List<StockItem>> add(StockItem item) async {
    final items = [...await load(), item];
    await save(items);
    return items;
  }

  static Future<List<StockItem>> remove(String id) async {
    final items = (await load()).where((item) => item.id != id).toList();
    await save(items);
    return items;
  }
}
