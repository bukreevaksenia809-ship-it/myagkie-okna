import 'package:shared_preferences/shared_preferences.dart';

import '../models/warehouse.dart';

/// Локальное хранилище склада. Все изменения сохраняются сразу.
class WarehouseStore {
  WarehouseStore._();

  static const String key = 'warehouse_v2';

  static Future<WarehouseData> load() async {
    final prefs = await SharedPreferences.getInstance();
    return WarehouseData.fromJsonString(prefs.getString(key) ?? '');
  }

  static Future<void> save(WarehouseData data) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, data.toJson());
  }

  static Future<WarehouseData> upsertProduct(WarehouseProduct product) async {
    final data = await load();
    final next = [...data.products];
    final index = next.indexWhere((item) => item.id == product.id);
    if (index >= 0) {
      next[index] = product;
    } else {
      next.add(product);
    }
    final updated = WarehouseData(products: next, moves: data.moves);
    await save(updated);
    return updated;
  }

  static Future<WarehouseData> deleteProduct(String id) async {
    final data = await load();
    final updated = WarehouseData(
      products: data.products.where((item) => item.id != id).toList(),
      moves: data.moves.where((move) => move.productId != id).toList(),
    );
    await save(updated);
    return updated;
  }

  static Future<WarehouseData> addMove(StockMove move) async {
    final data = await load();
    final updated = WarehouseData(
      products: data.products,
      moves: [...data.moves, move],
    );
    await save(updated);
    return updated;
  }
}
