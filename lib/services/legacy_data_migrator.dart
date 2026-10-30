import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../data/app_database.dart';
import '../data/order_repository.dart';
import '../models/order_json.dart';
import '../models/warehouse.dart';
import '../services/order_storage.dart';
import '../services/order_store.dart';

/// Переносит данные старых версий (shared_preferences и JSON-файлы заказов)
/// в SQLite. Запускается один раз; повторный запуск ничего не дублирует.
class LegacyDataMigrator {
  LegacyDataMigrator({
    AppDatabase? database,
    OrderRepository? orders,
  }) : _database = database ?? AppDatabase.instance,
       _orders = orders ?? OrderRepository.instance;

  final AppDatabase _database;
  final OrderRepository _orders;

  static const String _warehouseKey = 'warehouse_v2';
  static const String _doneKey = 'legacy_import_v1';

  Future<void> run({bool orders = true}) async {
    final db = await _database.database;
    final done = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [_doneKey],
      limit: 1,
    );
    if (done.isNotEmpty) return;

    await _importWarehouse();
    if (orders) await _importOrders();

    await db.insert(
      'app_meta',
      {'key': _doneKey, 'value': DateTime.now().toIso8601String()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _importWarehouse() async {
    final db = await _database.database;
    final count = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM warehouse_products',
    );
    if (((count.first['c'] as num?)?.toInt() ?? 0) > 0) return;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_warehouseKey);
    if (raw == null || raw.trim().isEmpty) return;
    Map<String, dynamic> decoded;
    try {
      final value = jsonDecode(raw);
      if (value is! Map) return;
      decoded = value.cast<String, dynamic>();
    } catch (_) {
      return;
    }

    final products = <WarehouseProduct>[];
    for (final item in (decoded['products'] as List? ?? const [])) {
      if (item is Map) {
        final product = WarehouseProduct.fromLegacyJson(
          item.cast<String, dynamic>(),
        );
        if (product.id.isNotEmpty) products.add(product);
      }
    }
    final legacyMoves = <StockMove>[];
    for (final item in (decoded['moves'] as List? ?? const [])) {
      if (item is! Map) continue;
      final map = item.cast<String, dynamic>();
      final type = StockMoveType.fromName('${map['type']}');
      legacyMoves.add(
        StockMove(
          id: '${map['id']}',
          productId: '${map['productId']}',
          type: type,
          quantity: (map['quantity'] as num?)?.toDouble() ?? 0,
          direction: type == StockMoveType.inventory
              ? ((map['quantity'] as num?)?.toDouble() ?? 0) >= 0
                    ? 1
                    : -1
              : type.direction,
          at: DateTime.tryParse('${map['at']}') ?? DateTime.now(),
          unitCost: (map['price'] as num?)?.toDouble() ?? 0,
          unitPrice: (map['price'] as num?)?.toDouble() ?? 0,
          orderId: '${map['orderId'] ?? ''}',
          note: '${map['note'] ?? ''}',
        ),
      );
    }

    await db.transaction((txn) async {
      for (final product in products) {
        await txn.insert(
          'warehouse_products',
          product.toDb(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
        await txn.insert('price_history', {
          'product_id': product.id,
          'kind': 'purchase',
          'price': product.purchasePrice,
          'at': (product.createdAt ?? DateTime.now()).toIso8601String(),
          'source': 'перенос',
        });
        await txn.insert('price_history', {
          'product_id': product.id,
          'kind': 'sale',
          'price': product.salePrice,
          'at': (product.createdAt ?? DateTime.now()).toIso8601String(),
          'source': 'перенос',
        });
      }
      for (final move in legacyMoves) {
        final exists = await txn.query(
          'warehouse_products',
          columns: ['id'],
          where: 'id = ?',
          whereArgs: [move.productId],
          limit: 1,
        );
        if (exists.isEmpty) continue;
        await txn.insert(
          'stock_moves',
          move.toDb(),
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }
      // Вводные партии: остаток старых движений должен совпасть с суммой
      // остатков партий, иначе FIFO начнёт «терять» товар.
      for (final product in products) {
        final rows = await txn.rawQuery(
          'SELECT SUM(direction * quantity) AS balance FROM stock_moves '
          'WHERE product_id = ?',
          [product.id],
        );
        final balance = (rows.first['balance'] as num?)?.toDouble() ?? 0;
        if (balance <= 0.000001) continue;
        await txn.insert('stock_batches', {
          'id': 'legacy-${product.id}',
          'product_id': product.id,
          'received_at': DateTime.now().toIso8601String(),
          'unit_cost': product.purchasePrice,
          'quantity': balance,
          'remaining': balance,
          'supplier': product.supplier,
          'order_id': '',
          'note': 'Вводный остаток при переходе на SQLite',
        });
      }
    });
  }

  Future<void> _importOrders() async {
    final existing = await _orders.count();
    if (existing > 0) return;
    final List<SavedOrder> saved;
    try {
      saved = await listSavedOrders();
    } catch (_) {
      return;
    }
    for (final order in saved) {
      try {
        final json = await readStoredOrder(order.ref);
        final project = orderFromJson(json);
        final customer = project.windows.isEmpty
            ? order.customer
            : project.windows.first.customer;
        final deadline = project.deadline ?? order.deadline;
        await _orders.create(
          title: order.title,
          customer: customer,
          project: project,
          legacyRef: order.ref.label,
          status: project.status,
          deadline: deadline,
          amount: orderSummaryAmount(json),
        );
      } catch (_) {
        // Один битый файл не должен останавливать перенос остальных.
      }
    }
    if (saved.isNotEmpty) {
      final db = await _database.database;
      await db.insert(
        'app_meta',
        {
          'key': 'legacy_orders_imported',
          'value': '${saved.length}',
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  double orderSummaryAmount(Map<String, dynamic> json) {
    final summary = json['summary'];
    if (summary is Map) {
      final value = summary['total'];
      if (value is num) return value.toDouble();
    }
    try {
      final project = orderFromJson(json);
      return _orders.amountOf(project);
    } catch (_) {
      return 0;
    }
  }
}

/// Полная резервная копия базы в JSON (для кнопки «Резервная копия»).
Future<String> exportDatabaseBackup() async {
  final db = await AppDatabase.instance.database;
  final products = await db.query('warehouse_products');
  final batches = await db.query('stock_batches');
  final moves = await db.query('stock_moves');
  final allocations = await db.query('stock_move_allocations');
  final prices = await db.query('price_history');
  final orders = await db.query('orders');
  final events = await db.query('order_events');
  final comments = await db.query('order_comments');
  final checklist = await db.query('order_checklist');
  final attachments = await db.query('order_attachments');
  final materials = await db.query('order_materials');
  return jsonEncode({
    'format': 'soft_window_drawer_backup',
    'version': 1,
    'exportedAt': DateTime.now().toIso8601String(),
    'warehouse_products': products,
    'stock_batches': batches,
    'stock_moves': moves,
    'stock_move_allocations': allocations,
    'price_history': prices,
    'orders': orders,
    'order_events': events,
    'order_comments': comments,
    'order_checklist': checklist,
    'order_attachments': attachments,
    'order_materials': materials,
  });
}
