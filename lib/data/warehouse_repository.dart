import 'dart:math' as math;

import 'package:sqflite_common/sqlite_api.dart';

import '../models/order_project.dart';
import '../models/warehouse.dart';
import 'app_database.dart';

/// Результат операции склада.
class StockActionResult {
  const StockActionResult({
    required this.ok,
    required this.message,
    this.shortages = const [],
    this.moveIds = const [],
  });

  final bool ok;
  final String message;
  final List<String> shortages;
  final List<String> moveIds;

  static StockActionResult failure(String message, [List<String> shortages = const []]) =>
      StockActionResult(ok: false, message: message, shortages: shortages);

  static StockActionResult success(String message, [List<String> moveIds = const []]) =>
      StockActionResult(ok: true, message: message, moveIds: moveIds);
}

/// Точка истории цен.
class PricePoint {
  const PricePoint({
    required this.id,
    required this.productId,
    required this.kind,
    required this.price,
    required this.at,
    this.source = '',
  });

  final int id;
  final String productId;
  final String kind;
  final double price;
  final DateTime at;
  final String source;

  bool get isPurchase => kind == 'purchase';
}

/// Репозиторий склада. Все изменения остатков — только через транзакции.
class WarehouseRepository {
  WarehouseRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  static final WarehouseRepository instance = WarehouseRepository();

  Future<List<WarehouseProduct>> products({
    bool includeArchived = false,
    String query = '',
  }) async {
    final db = await _database.database;
    final where = <String>[];
    final args = <Object?>[];
    if (!includeArchived) where.add('archived = 0');
    final needle = query.trim();
    if (needle.isNotEmpty) {
      where.add(
        '(name LIKE ? OR category LIKE ? OR material LIKE ? OR color LIKE ? '
        'OR supplier LIKE ? OR location LIKE ? OR barcode LIKE ?)',
      );
      final like = '%$needle%';
      args.addAll([like, like, like, like, like, like, like]);
    }
    final rows = await db.query(
      'warehouse_products',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'archived ASC, name COLLATE NOCASE ASC',
    );
    return [for (final row in rows) WarehouseProduct.fromDb(row)];
  }

  Future<WarehouseProduct?> product(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'warehouse_products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : WarehouseProduct.fromDb(rows.first);
  }

  Future<StockActionResult> saveProduct(WarehouseProduct product) async {
    if (product.name.trim().isEmpty) {
      return StockActionResult.failure('Укажите название товара');
    }
    final db = await _database.database;
    try {
      return await db.transaction((txn) async {
        final existingRows = await txn.query(
          'warehouse_products',
          where: 'id = ?',
          whereArgs: [product.id],
          limit: 1,
        );
        final now = DateTime.now();
        final value = product.copyWith(
          name: product.name.trim(),
          createdAt: existingRows.isEmpty
              ? (product.createdAt ?? now)
              : product.createdAt,
          updatedAt: now,
        );
        if (existingRows.isEmpty) {
          await txn.insert('warehouse_products', value.toDb());
        } else {
          final previous = WarehouseProduct.fromDb(existingRows.first);
          await txn.update(
            'warehouse_products',
            value.toDb(),
            where: 'id = ?',
            whereArgs: [product.id],
          );
          if (previous.purchasePrice != value.purchasePrice) {
            await _addPriceHistory(
              txn,
              value.id,
              'purchase',
              value.purchasePrice,
              now,
              'карточка',
            );
          }
          if (previous.salePrice != value.salePrice) {
            await _addPriceHistory(
              txn,
              value.id,
              'sale',
              value.salePrice,
              now,
              'карточка',
            );
          }
        }
        return StockActionResult.success('Товар сохранён');
      });
    } on DatabaseException catch (error) {
      final text = '$error';
      if (text.contains('UNIQUE') || text.contains('unique')) {
        return StockActionResult.failure(
          'Штрихкод уже используется другим товаром',
        );
      }
      return StockActionResult.failure('Не удалось сохранить товар: $error');
    }
  }

  Future<StockActionResult> deleteProduct(String id) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final moves = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM stock_moves WHERE product_id = ?',
        [id],
      );
      if (((moves.first['c'] as num?)?.toInt() ?? 0) > 0) {
        return StockActionResult.failure(
          'У товара есть движения. Переведите его в архив — история сохранится.',
        );
      }
      final links = await txn.rawQuery(
        'SELECT COUNT(*) AS c FROM order_materials WHERE product_id = ?',
        [id],
      );
      if (((links.first['c'] as num?)?.toInt() ?? 0) > 0) {
        return StockActionResult.failure(
          'Товар привязан к заказам. Сначала отвяжите его или отправьте в архив.',
        );
      }
      await txn.delete('stock_batches', where: 'product_id = ?', whereArgs: [id]);
      await txn.delete('price_history', where: 'product_id = ?', whereArgs: [id]);
      await txn.delete(
        'warehouse_products',
        where: 'id = ?',
        whereArgs: [id],
      );
      return StockActionResult.success('Товар удалён');
    });
  }

  Future<StockActionResult> archiveProduct(String id, bool archived) async {
    final db = await _database.database;
    await db.update(
      'warehouse_products',
      {'archived': archived ? 1 : 0, 'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
    return StockActionResult.success(
      archived ? 'Товар в архиве' : 'Товар возвращён из архива',
    );
  }

  Future<WarehouseSnapshot> snapshot({
    bool includeArchived = false,
    String query = '',
  }) async {
    final db = await _database.database;
    final products = await this.products(
      includeArchived: includeArchived,
      query: query,
    );
    final balances = await _balances(db);
    final reserves = await _reserves(db);
    final averages = await _averageCosts(db);
    final batches = await _allBatches(db);
    final moves = await this.moves(limit: 200);
    final byProduct = <String, List<StockBatch>>{};
    for (final batch in batches) {
      byProduct.putIfAbsent(batch.productId, () => []).add(batch);
    }
    final stocks = [
      for (final product in products)
        WarehouseStock(
          product: product,
          balance: balances[product.id] ?? 0,
          reserved: reserves[product.id] ?? 0,
          averageCost: averages[product.id] ?? product.purchasePrice,
          batches: byProduct[product.id] ?? const [],
        ),
    ];
    return WarehouseSnapshot(
      stocks: stocks,
      moves: moves,
      generatedAt: DateTime.now(),
    );
  }

  Future<WarehouseStock?> stockFor(String productId) async {
    final db = await _database.database;
    final product = await this.product(productId);
    if (product == null) return null;
    final batches = await this.batches(productId);
    final balance = await _balance(db, productId);
    final reserved = await _reserved(db, productId);
    return WarehouseStock(
      product: product,
      balance: balance,
      reserved: reserved,
      averageCost: _averageFromBatches(batches) ?? product.purchasePrice,
      batches: batches,
    );
  }

  Future<List<StockBatch>> batches(String productId) async {
    final db = await _database.database;
    final rows = await db.query(
      'stock_batches',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'received_at ASC, id ASC',
    );
    return [for (final row in rows) StockBatch.fromDb(row)];
  }

  Future<List<StockMove>> moves({
    String productId = '',
    String orderId = '',
    DateTime? from,
    DateTime? to,
    int limit = 1000,
  }) async {
    final db = await _database.database;
    final where = <String>[];
    final args = <Object?>[];
    if (productId.isNotEmpty) {
      where.add('product_id = ?');
      args.add(productId);
    }
    if (orderId.isNotEmpty) {
      where.add('order_id = ?');
      args.add(orderId);
    }
    if (from != null) {
      where.add('at >= ?');
      args.add(from.toIso8601String());
    }
    if (to != null) {
      where.add('at < ?');
      args.add(to.add(const Duration(days: 1)).toIso8601String());
    }
    final rows = await db.query(
      'stock_moves',
      where: where.isEmpty ? null : where.join(' AND '),
      whereArgs: args,
      orderBy: 'at DESC, created_at DESC',
      limit: limit,
    );
    return [for (final row in rows) StockMove.fromDb(row)];
  }

  Future<List<PricePoint>> priceHistory(String productId) async {
    final db = await _database.database;
    final rows = await db.query(
      'price_history',
      where: 'product_id = ?',
      whereArgs: [productId],
      orderBy: 'at DESC, id DESC',
      limit: 100,
    );
    return [
      for (final row in rows)
        PricePoint(
          id: (row['id'] as num?)?.toInt() ?? 0,
          productId: '${row['product_id']}',
          kind: '${row['kind']}',
          price: (row['price'] as num?)?.toDouble() ?? 0,
          at: DateTime.tryParse('${row['at']}') ?? DateTime.now(),
          source: '${row['source'] ?? ''}',
        ),
    ];
  }

  // --------------------------------------------------------------- операции

  Future<StockActionResult> perform(StockOperation operation) async {
    if (operation.quantity <= 0 || !operation.quantity.isFinite) {
      return StockActionResult.failure('Количество должно быть больше нуля');
    }
    final product = await this.product(operation.productId);
    if (product == null) {
      return StockActionResult.failure('Товар не найден');
    }
    final db = await _database.database;
    try {
      return await db.transaction((txn) async {
        final at = operation.at ?? DateTime.now();
        final type = operation.type;
        if (type == StockMoveType.inventory) {
          return _inventory(
            txn,
            product,
            operation.quantity,
            operation.unitCost ?? product.purchasePrice,
            at,
            operation.note,
          );
        }
        if (type == StockMoveType.transferOut ||
            type == StockMoveType.transferIn) {
          return _transfer(txn, product, operation, at);
        }
        if (type.isExpense) {
          return _expense(txn, product, operation, at);
        }
        return _income(txn, product, operation, at);
      });
    } on DatabaseException catch (error) {
      return StockActionResult.failure('Операция не проведена: $error');
    } on StateError catch (error) {
      return StockActionResult.failure('Операция не проведена: ${error.message}');
    }
  }

  Future<StockActionResult> _income(
    Transaction txn,
    WarehouseProduct product,
    StockOperation operation,
    DateTime at,
  ) async {
    final type = operation.type;
    final quantity = operation.quantity;
    final unitCost = operation.unitCost ??
        operation.unitPrice ??
        product.purchasePrice;
    final moveId = _newId('mv');
    final batchId = _newId('bt');
    await txn.insert('stock_batches', {
      'id': batchId,
      'product_id': product.id,
      'received_at': at.toIso8601String(),
      'unit_cost': unitCost,
      'quantity': quantity,
      'remaining': quantity,
      'supplier': product.supplier,
      'order_id': operation.orderId,
      'note': operation.note,
    });
    await txn.insert('stock_moves', {
      'id': moveId,
      'product_id': product.id,
      'type': type.name,
      'quantity': quantity,
      'direction': 1,
      'unit_cost': unitCost,
      'unit_price': operation.unitPrice ?? unitCost,
      'at': at.toIso8601String(),
      'order_id': operation.orderId,
      'batch_id': batchId,
      'location_from': operation.locationFrom,
      'location_to': operation.locationTo,
      'note': operation.note,
      'created_at': at.toIso8601String(),
    });
    await txn.insert('stock_move_allocations', {
      'move_id': moveId,
      'batch_id': batchId,
      'quantity': quantity,
      'unit_cost': unitCost,
    });
    if (type == StockMoveType.purchase || type == StockMoveType.sale) {
      await _addPriceHistory(
        txn,
        product.id,
        type == StockMoveType.purchase ? 'purchase' : 'sale',
        operation.unitPrice ?? unitCost,
        at,
        _moveLabel(type),
      );
    }
    return StockActionResult.success(
      '${_moveLabel(type)}: ${_fmt(quantity)} ${product.unit.label}',
      [moveId],
    );
  }

  Future<StockActionResult> _expense(
    Transaction txn,
    WarehouseProduct product,
    StockOperation operation,
    DateTime at,
  ) async {
    final type = operation.type;
    final quantity = operation.quantity;
    final balance = await _balance(txn, product.id);
    final reserved = await _reserved(txn, product.id, excludeOrderId: operation.orderId);
    final available = math.max(0.0, balance - reserved);
    if (quantity > available + 0.000001) {
      return StockActionResult.failure(
        'Недостаточно свободного остатка: доступно '
        '${_fmt(available)} ${product.unit.label}, нужно '
        '${_fmt(quantity)} ${product.unit.label}',
      );
    }
    final moveId = _newId('mv');
    // Сначала строка журнала: на неё ссылаются распределения по партиям.
    await txn.insert('stock_moves', {
      'id': moveId,
      'product_id': product.id,
      'type': type.name,
      'quantity': quantity,
      'direction': -1,
      'unit_cost': 0.0,
      'unit_price': operation.unitPrice ?? 0,
      'at': at.toIso8601String(),
      'order_id': operation.orderId,
      'batch_id': '',
      'location_from': operation.locationFrom,
      'location_to': operation.locationTo,
      'note': operation.note,
      'created_at': at.toIso8601String(),
    });
    final allocations = await _consumeFifo(
      txn,
      product,
      quantity,
      at,
      moveId: moveId,
    );
    final cost = quantity <= 0
        ? 0.0
        : allocations.fold<double>(
                0,
                (sum, item) => sum + item.quantity * item.unitCost,
              ) /
              quantity;
    await txn.update(
      'stock_moves',
      {'unit_cost': cost},
      where: 'id = ?',
      whereArgs: [moveId],
    );
    if (type == StockMoveType.sale) {
      await _addPriceHistory(
        txn,
        product.id,
        'sale',
        operation.unitPrice ?? product.salePrice,
        at,
        _moveLabel(type),
      );
    }
    if (type == StockMoveType.issue && operation.orderId.isNotEmpty) {
      await _consumeOrderReserve(
        txn,
        operation.orderId,
        product.id,
        quantity,
        at,
      );
    }
    return StockActionResult.success(
      '${_moveLabel(type)}: ${_fmt(quantity)} ${product.unit.label}',
      [moveId],
    );
  }

  Future<StockActionResult> _transfer(
    Transaction txn,
    WarehouseProduct product,
    StockOperation operation,
    DateTime at,
  ) async {
    final quantity = operation.quantity;
    final balance = await _balance(txn, product.id);
    if (quantity > balance + 0.000001) {
      return StockActionResult.failure(
        'Для перемещения не хватает остатка: есть ${_fmt(balance)} '
        '${product.unit.label}',
      );
    }
    if (operation.locationTo.trim().isEmpty) {
      return StockActionResult.failure('Укажите место, куда перемещаем');
    }
    final outId = _newId('mv');
    final inId = _newId('mv');
    await txn.insert('stock_moves', {
      'id': outId,
      'product_id': product.id,
      'type': StockMoveType.transferOut.name,
      'quantity': quantity,
      'direction': -1,
      'unit_cost': 0.0,
      'unit_price': 0,
      'at': at.toIso8601String(),
      'order_id': operation.orderId,
      'batch_id': '',
      'location_from': operation.locationFrom,
      'location_to': operation.locationTo,
      'note': operation.note,
      'created_at': at.toIso8601String(),
    });
    final allocations = await _consumeFifo(
      txn,
      product,
      quantity,
      at,
      moveId: outId,
    );
    final cost = quantity <= 0
        ? 0.0
        : allocations.fold<double>(
                0,
                (sum, item) => sum + item.quantity * item.unitCost,
              ) /
              quantity;
    await txn.update(
      'stock_moves',
      {'unit_cost': cost},
      where: 'id = ?',
      whereArgs: [outId],
    );
    final batchId = _newId('bt');
    await txn.insert('stock_batches', {
      'id': batchId,
      'product_id': product.id,
      'received_at': at.toIso8601String(),
      'unit_cost': cost,
      'quantity': quantity,
      'remaining': quantity,
      'supplier': product.supplier,
      'order_id': operation.orderId,
      'note': 'Перемещение: ${operation.locationTo}',
    });
    await txn.insert('stock_moves', {
      'id': inId,
      'product_id': product.id,
      'type': StockMoveType.transferIn.name,
      'quantity': quantity,
      'direction': 1,
      'unit_cost': cost,
      'unit_price': 0,
      'at': at.toIso8601String(),
      'order_id': operation.orderId,
      'batch_id': batchId,
      'location_from': operation.locationFrom,
      'location_to': operation.locationTo,
      'note': operation.note,
      'created_at': at.toIso8601String(),
    });
    return StockActionResult.success(
      'Перемещено ${_fmt(quantity)} ${product.unit.label} → '
      '${operation.locationTo}',
      [outId, inId],
    );
  }

  Future<StockActionResult> _inventory(
    Transaction txn,
    WarehouseProduct product,
    double actual,
    double unitCost,
    DateTime at,
    String note,
  ) async {
    final balance = await _balance(txn, product.id);
    final delta = actual - balance;
    if (delta.abs() < 0.000001) {
      return StockActionResult.success('Остаток совпадает — изменений нет');
    }
    final moveId = _newId('mv');
    final noteText = note.isEmpty
        ? 'Инвентаризация: учёт ${_fmt(balance)}, факт ${_fmt(actual)}'
        : '$note · учёт ${_fmt(balance)}, факт ${_fmt(actual)}';
    if (delta > 0) {
      final batchId = _newId('bt');
      await txn.insert('stock_batches', {
        'id': batchId,
        'product_id': product.id,
        'received_at': at.toIso8601String(),
        'unit_cost': unitCost,
        'quantity': delta,
        'remaining': delta,
        'supplier': product.supplier,
        'order_id': '',
        'note': 'Инвентаризация',
      });
      await txn.insert('stock_moves', {
        'id': moveId,
        'product_id': product.id,
        'type': StockMoveType.inventory.name,
        'quantity': delta,
        'direction': 1,
        'unit_cost': unitCost,
        'unit_price': 0,
        'at': at.toIso8601String(),
        'order_id': '',
        'batch_id': batchId,
        'location_from': product.location,
        'location_to': product.location,
        'note': noteText,
        'created_at': at.toIso8601String(),
      });
      await txn.insert('stock_move_allocations', {
        'move_id': moveId,
        'batch_id': batchId,
        'quantity': delta,
        'unit_cost': unitCost,
      });
    } else {
      await txn.insert('stock_moves', {
        'id': moveId,
        'product_id': product.id,
        'type': StockMoveType.inventory.name,
        'quantity': -delta,
        'direction': -1,
        'unit_cost': 0.0,
        'unit_price': 0,
        'at': at.toIso8601String(),
        'order_id': '',
        'batch_id': '',
        'location_from': product.location,
        'location_to': product.location,
        'note': noteText,
        'created_at': at.toIso8601String(),
      });
      final allocations = await _consumeFifo(
        txn,
        product,
        -delta,
        at,
        moveId: moveId,
      );
      final cost = allocations.fold<double>(
            0,
            (sum, item) => sum + item.quantity * item.unitCost,
          ) /
          -delta;
      await txn.update(
        'stock_moves',
        {'unit_cost': cost},
        where: 'id = ?',
        whereArgs: [moveId],
      );
    }
    return StockActionResult.success(
      'Инвентаризация: ${_fmt(balance)} → ${_fmt(actual)} '
      '${product.unit.label}',
      [moveId],
    );
  }

  /// Списывает [quantity] по FIFO. Возвращает распределение по партиям или
  /// null, если партий не хватает.
  Future<List<_Allocation>> _consumeFifo(
    Transaction txn,
    WarehouseProduct product,
    double quantity,
    DateTime at, {
    required String moveId,
  }) async {
    final rows = await txn.query(
      'stock_batches',
      where: 'product_id = ? AND remaining > 0',
      whereArgs: [product.id],
      orderBy: 'received_at ASC, id ASC',
    );
    var left = quantity;
    final allocations = <_Allocation>[];
    for (final row in rows) {
      if (left <= 0.000001) break;
      final batch = StockBatch.fromDb(row);
      final take = math.min(left, batch.remaining);
      if (take <= 0) continue;
      await txn.update(
        'stock_batches',
        {'remaining': batch.remaining - take},
        where: 'id = ?',
        whereArgs: [batch.id],
      );
      allocations.add(_Allocation(batch.id, take, batch.unitCost));
      await txn.insert('stock_move_allocations', {
        'move_id': moveId,
        'batch_id': batch.id,
        'quantity': take,
        'unit_cost': batch.unitCost,
      });
      left -= take;
    }
    if (left > 0.000001) {
      // Старые остатки без партий: создаём вводную партию и сразу её
      // расходуем. Это не даёт журналу и партиям разойтись.
      final balance = await _balance(txn, product.id);
      if (balance + 0.000001 < quantity) {
        // Исключение откатывает всю транзакцию: частичное списание не
        // должно остаться в журнале.
        throw StateError('Партии не покрывают количество');
      }
      final batchId = _newId('bt');
      await txn.insert('stock_batches', {
        'id': batchId,
        'product_id': product.id,
        'received_at': at.toIso8601String(),
        'unit_cost': product.purchasePrice,
        'quantity': left,
        'remaining': 0,
        'supplier': product.supplier,
        'order_id': '',
        'note': 'Вводный остаток',
      });
      allocations.add(_Allocation(batchId, left, product.purchasePrice));
      await txn.insert('stock_move_allocations', {
        'move_id': moveId,
        'batch_id': batchId,
        'quantity': left,
        'unit_cost': product.purchasePrice,
      });
    }
    return allocations;
  }

  /// Инвентаризация нескольких позиций одной транзакцией.
  ///
  /// [actual] — фактический остаток по каждому товару. Нулевые и
  /// отсутствующие позиции не трогаются. Если хотя бы одна строка не
  /// проходит, не меняется ничего.
  Future<StockActionResult> inventoryAll(
    Map<String, double> actual, {
    String note = '',
  }) async {
    if (actual.isEmpty) {
      return StockActionResult.failure('Нет позиций для инвентаризации');
    }
    final db = await _database.database;
    try {
      return await db.transaction((txn) async {
        var changed = 0;
        for (final entry in actual.entries) {
          final product = await _productInTxn(txn, entry.key);
          if (product == null) continue;
          final result = await _inventory(
            txn,
            product,
            entry.value,
            product.purchasePrice,
            DateTime.now(),
            note,
          );
          if (!result.ok) {
            throw StateError(result.message);
          }
          if (result.moveIds.isNotEmpty) changed++;
        }
        return StockActionResult.success(
          changed == 0
              ? 'Расхождений нет'
              : 'Инвентаризация проведена: $changed поз.',
        );
      });
    } on DatabaseException catch (error) {
      return StockActionResult.failure('Не удалось провести: $error');
    } on StateError catch (error) {
      return StockActionResult.failure(error.message);
    }
  }

  // ------------------------------------------------------ связь с заказами

  Future<List<OrderMaterial>> orderMaterials(String orderId) async {
    final db = await _database.database;
    final rows = await db.query(
      'order_materials',
      where: 'order_id = ?',
      whereArgs: [orderId],
      orderBy: 'name COLLATE NOCASE ASC',
    );
    return [for (final row in rows) OrderMaterial.fromDb(row)];
  }

  /// Проверка остатков под потребности заказа.
  Future<List<OrderMaterialNeed>> checkNeeds(
    List<OrderMaterialNeed> needs,
  ) async {
    final db = await _database.database;
    final result = <OrderMaterialNeed>[];
    for (final need in needs) {
      final balance = await _balance(db, need.productId);
      final reserved = await _reserved(db, need.productId);
      result.add(
        OrderMaterialNeed(
          productId: need.productId,
          name: need.name,
          unit: need.unit,
          quantity: need.quantity,
          available: math.max(0.0, balance - reserved),
          reserved: reserved,
          source: need.source,
          note: need.note,
          linked: need.linked,
        ),
      );
    }
    return result;
  }

  /// Резервирует материалы под заказ. Либо резервирует всё, либо ничего.
  Future<StockActionResult> reserveOrder(
    String orderId,
    List<OrderMaterialNeed> needs, {
    String author = '',
  }) async {
    if (needs.isEmpty) {
      return StockActionResult.failure('Нет потребности в материалах');
    }
    final db = await _database.database;
    try {
      return await db.transaction((txn) async {
        final shortages = <String>[];
        final existing = <String, OrderMaterial>{};
        final existingRows = await txn.query(
          'order_materials',
          where: 'order_id = ?',
          whereArgs: [orderId],
        );
        for (final row in existingRows) {
          final link = OrderMaterial.fromDb(row);
          existing[link.productId] = link;
        }
        for (final need in needs) {
          if (!need.linked) continue;
          final previous = existing[need.productId];
          final already = previous == null
              ? 0.0
              : math.max(0.0, previous.reservedQty + previous.issuedQty);
          final delta = math.max(0.0, need.quantity - already);
          if (delta <= 0.000001) continue;
          final balance = await _balance(txn, need.productId);
          final reserved = await _reserved(
            txn,
            need.productId,
            excludeOrderId: orderId,
          );
          final available = math.max(0.0, balance - reserved);
          if (delta > available + 0.000001) {
            shortages.add(
              '${need.name}: нужно ${_fmt(delta)} ${need.unit.label}, '
              'доступно ${_fmt(available)}',
            );
          }
        }
        if (shortages.isNotEmpty) {
          return StockActionResult.failure(
            'Резерв не создан: не хватает материалов',
            shortages,
          );
        }
        final at = DateTime.now();
        for (final need in needs) {
          if (!need.linked) continue;
          final previous = existing[need.productId];
          final already = previous == null
              ? 0.0
              : math.max(0.0, previous.reservedQty + previous.issuedQty);
          final delta = math.max(0.0, need.quantity - already);
          if (previous == null) {
            await txn.insert('order_materials', {
              'order_id': orderId,
              'product_id': need.productId,
              'name': need.name,
              'unit': need.unit.name,
              'required_qty': need.quantity,
              'reserved_qty': need.quantity,
              'issued_qty': 0,
              'state': OrderMaterialState.reserved.name,
              'source': need.source,
              'note': need.note,
              'updated_at': at.toIso8601String(),
            });
          } else {
            await txn.update(
              'order_materials',
              {
                'name': need.name,
                'unit': need.unit.name,
                'required_qty': need.quantity,
                'reserved_qty': previous.reservedQty + delta,
                'state': previous.issuedQty > 0
                    ? OrderMaterialState.issued.name
                    : OrderMaterialState.reserved.name,
                'source': need.source,
                'note': need.note,
                'updated_at': at.toIso8601String(),
              },
              where: 'id = ?',
              whereArgs: [previous.id],
            );
          }
        }
        await txn.update(
          'orders',
          {
            'updated_at': at.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [orderId],
        );
        await _event(
          txn,
          orderId,
          'Материалы зарезервированы (${needs.where((n) => n.linked).length} поз.)',
          at,
          author: author,
        );
        return StockActionResult.success('Материалы зарезервированы');
      });
    } on DatabaseException catch (error) {
      return StockActionResult.failure('Не удалось зарезервировать: $error');
    }
  }

  /// Снимает резерв заказа. Уже списанные материалы не трогает.
  Future<StockActionResult> releaseOrder(
    String orderId, {
    String author = '',
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final at = DateTime.now();
      final rows = await txn.query(
        'order_materials',
        where: 'order_id = ?',
        whereArgs: [orderId],
      );
      var count = 0;
      for (final row in rows) {
        final link = OrderMaterial.fromDb(row);
        if (link.reservedQty <= 0) continue;
        count++;
        await txn.update(
          'order_materials',
          {
            'reserved_qty': 0,
            'state': link.issuedQty > 0
                ? OrderMaterialState.issued.name
                : OrderMaterialState.released.name,
            'updated_at': at.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [link.id],
        );
      }
      if (count > 0) {
        await _event(txn, orderId, 'Резерв снят ($count поз.)', at, author: author);
      }
      return StockActionResult.success(
        count == 0 ? 'Активного резерва нет' : 'Резерв снят: $count поз.',
      );
    });
  }

  /// Списывает зарезервированные материалы в заказ.
  Future<StockActionResult> issueOrder(
    String orderId, {
    String author = '',
  }) async {
    final db = await _database.database;
    try {
      return await db.transaction((txn) async {
        final rows = await txn.query(
          'order_materials',
          where: 'order_id = ? AND reserved_qty > 0.000001',
          whereArgs: [orderId],
        );
        if (rows.isEmpty) {
          return StockActionResult.failure(
            'Нет зарезервированных материалов. Сначала зарезервируйте.',
          );
        }
        final at = DateTime.now();
        var count = 0;
        for (final row in rows) {
          final link = OrderMaterial.fromDb(row);
          final product = await _productInTxn(txn, link.productId);
          if (product == null) continue;
          final quantity = link.reservedQty;
          final moveId = _newId('mv');
          await txn.insert('stock_moves', {
            'id': moveId,
            'product_id': product.id,
            'type': StockMoveType.issue.name,
            'quantity': quantity,
            'direction': -1,
            'unit_cost': 0.0,
            'unit_price': product.salePrice,
            'at': at.toIso8601String(),
            'order_id': orderId,
            'batch_id': '',
            'location_from': product.location,
            'location_to': '',
            'note': 'Списание в заказ',
            'created_at': at.toIso8601String(),
          });
          final allocations = await _consumeFifo(
            txn,
            product,
            quantity,
            at,
            moveId: moveId,
          );
          final cost = allocations.fold<double>(
                0,
                (sum, item) => sum + item.quantity * item.unitCost,
              ) /
              quantity;
          await txn.update(
            'stock_moves',
            {'unit_cost': cost},
            where: 'id = ?',
            whereArgs: [moveId],
          );
          await txn.update(
            'order_materials',
            {
              'reserved_qty': 0,
              'issued_qty': link.issuedQty + quantity,
              'state': OrderMaterialState.issued.name,
              'updated_at': at.toIso8601String(),
            },
            where: 'id = ?',
            whereArgs: [link.id],
          );
          count++;
        }
        await _event(txn, orderId, 'Материалы списаны ($count поз.)', at, author: author);
        return StockActionResult.success('Списано в заказ: $count поз.');
      });
    } on DatabaseException catch (error) {
      return StockActionResult.failure('Не удалось списать: $error');
    } on StateError catch (error) {
      return StockActionResult.failure(error.message);
    }
  }

  /// Возвращает списанные по заказу материалы обратно на склад.
  Future<StockActionResult> returnOrder(
    String orderId, {
    String author = '',
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final at = DateTime.now();
      await releaseOrderTx(txn, orderId, at);
      final rows = await txn.query(
        'order_materials',
        where: 'order_id = ? AND issued_qty > 0.000001',
        whereArgs: [orderId],
      );
      var count = 0;
      var quantityTotal = 0.0;
      for (final row in rows) {
        final link = OrderMaterial.fromDb(row);
        final product = await _productInTxn(txn, link.productId);
        if (product == null) continue;
        final quantity = link.issuedQty;
        if (quantity <= 0) continue;
        final moveId = _newId('mv');
        final batchId = _newId('bt');
        final cost = await _lastIssueCost(txn, orderId, product.id) ??
            product.purchasePrice;
        await txn.insert('stock_batches', {
          'id': batchId,
          'product_id': product.id,
          'received_at': at.toIso8601String(),
          'unit_cost': cost,
          'quantity': quantity,
          'remaining': quantity,
          'supplier': 'Возврат по заказу',
          'order_id': orderId,
          'note': 'Возврат из заказа',
        });
        await txn.insert('stock_moves', {
          'id': moveId,
          'product_id': product.id,
          'type': StockMoveType.returnIn.name,
          'quantity': quantity,
          'direction': 1,
          'unit_cost': cost,
          'unit_price': 0,
          'at': at.toIso8601String(),
          'order_id': orderId,
          'batch_id': batchId,
          'location_from': '',
          'location_to': product.location,
          'note': 'Возврат из заказа',
          'created_at': at.toIso8601String(),
        });
        await txn.insert('stock_move_allocations', {
          'move_id': moveId,
          'batch_id': batchId,
          'quantity': quantity,
          'unit_cost': cost,
        });
        await txn.update(
          'order_materials',
          {
            'issued_qty': 0,
            'state': OrderMaterialState.returned.name,
            'updated_at': at.toIso8601String(),
          },
          where: 'id = ?',
          whereArgs: [link.id],
        );
        count++;
        quantityTotal += quantity;
      }
      await _event(
        txn,
        orderId,
        'Материалы возвращены на склад ($count поз., ${_fmt(quantityTotal)})',
        at,
        author: author,
      );
      return StockActionResult.success(
        count == 0 ? 'Возвращать нечего' : 'Возвращено на склад: $count поз.',
      );
    });
  }

  Future<void> releaseOrderTx(
    Transaction txn,
    String orderId,
    DateTime at,
  ) async {
    await txn.update(
      'order_materials',
      {'reserved_qty': 0, 'state': OrderMaterialState.released.name},
      where: 'order_id = ? AND reserved_qty > 0',
      whereArgs: [orderId],
    );
  }

  Future<void> _consumeOrderReserve(
    Transaction txn,
    String orderId,
    String productId,
    double quantity,
    DateTime at,
  ) async {
    final rows = await txn.query(
      'order_materials',
      where: 'order_id = ? AND product_id = ?',
      whereArgs: [orderId, productId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final link = OrderMaterial.fromDb(rows.first);
    final taken = math.min(link.reservedQty, quantity);
    await txn.update(
      'order_materials',
      {
        'reserved_qty': math.max(0.0, link.reservedQty - taken),
        'issued_qty': link.issuedQty + quantity,
        'state': OrderMaterialState.issued.name,
        'updated_at': at.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [link.id],
    );
  }

  // ------------------------------------------------------------ отчёты

  Future<WarehouseReport> report(
    WarehouseReportKind kind, {
    DateTime? from,
    DateTime? to,
  }) async {
    final snapshot = await this.snapshot(includeArchived: true);
    final moves = await this.moves(
      from: from,
      to: to,
      limit: 100000,
    );
    final names = <String, WarehouseProduct>{
      for (final stock in snapshot.stocks) stock.product.id: stock.product,
    };
    switch (kind) {
      case WarehouseReportKind.stock:
        final rows = [
          for (final stock in snapshot.stocks)
            if (!stock.product.archived)
              [
                stock.product.name,
                stock.product.unit.label,
                _fmt(stock.balance),
                _fmt(stock.reserved),
                _fmt(stock.available),
                _fmt(stock.product.minQuantity),
                _money(stock.averageCost),
                _money(stock.balanceValue),
              ],
        ];
        return WarehouseReport(
          kind: kind,
          title: 'Остатки склада',
          columns: const [
            'Наименование',
            'Ед.',
            'Остаток',
            'Резерв',
            'Доступно',
            'Мин.',
            'Себест.',
            'Стоимость',
          ],
          rows: rows,
          totals: {
            'Позиций': '${rows.length}',
            'Стоимость': _money(snapshot.totalValue),
            'Резерв': _money(snapshot.reservedValue),
          },
          note: 'Остаток считается по журналу движений, резерв — по заказам.',
        );
      case WarehouseReportKind.movement:
        final rows = [
          for (final move in moves)
            [
              _dateTime(move.at),
              names[move.productId]?.name ?? move.productId,
              move.type.label,
              '${move.direction > 0 ? '+' : '−'}${_fmt(move.quantity)}',
              _money(move.unitPrice),
              _money(move.costAmount),
              move.orderId,
              move.note,
            ],
        ];
        return WarehouseReport(
          kind: kind,
          title: 'Движение склада',
          columns: const [
            'Дата',
            'Товар',
            'Операция',
            'Кол-во',
            'Цена',
            'Сумма',
            'Заказ',
            'Примечание',
          ],
          rows: rows,
          totals: {'Записей': '${rows.length}'},
          note: from == null && to == null
              ? 'Все движения журнала.'
              : 'Период: ${_date(from)} — ${_date(to)}',
        );
      case WarehouseReportKind.orderConsumption:
        final grouped = <String, _ReportGroup>{};
        for (final move in moves) {
          if (move.type != StockMoveType.issue) continue;
          if (move.orderId.isEmpty) continue;
          final key = '${move.orderId}|${move.productId}';
          final group = grouped.putIfAbsent(
            key,
            () => _ReportGroup(
              orderId: move.orderId,
              productId: move.productId,
            ),
          );
          group.quantity += move.quantity;
          group.cost += move.costAmount;
          group.revenue += move.unitPrice * move.quantity;
        }
        final rows = [
          for (final group in grouped.values)
            [
              group.orderId,
              names[group.productId]?.name ?? group.productId,
              _fmt(group.quantity),
              _money(group.cost),
              _money(group.revenue),
            ],
        ];
        return WarehouseReport(
          kind: kind,
          title: 'Расход по заказам',
          columns: const [
            'Заказ',
            'Товар',
            'Списано',
            'Себестоимость',
            'По продаже',
          ],
          rows: rows,
          totals: {
            'Позиций': '${rows.length}',
            'Себестоимость': _money(
              grouped.values.fold(0.0, (sum, group) => sum + group.cost),
            ),
          },
          note: 'Списания в заказы за период.',
        );
      case WarehouseReportKind.purchases:
        final rows = <List<String>>[];
        var total = 0.0;
        for (final move in moves) {
          if (move.type != StockMoveType.purchase &&
              move.type != StockMoveType.receipt) {
            continue;
          }
          final amount = move.unitPrice * move.quantity;
          total += amount;
          rows.add([
            _dateTime(move.at),
            names[move.productId]?.name ?? move.productId,
            move.type.label,
            _fmt(move.quantity),
            _money(move.unitPrice),
            _money(amount),
            move.note,
          ]);
        }
        return WarehouseReport(
          kind: kind,
          title: 'Закупки',
          columns: const [
            'Дата',
            'Товар',
            'Операция',
            'Кол-во',
            'Цена',
            'Сумма',
            'Примечание',
          ],
          rows: rows,
          totals: {'Сумма закупок': _money(total)},
        );
      case WarehouseReportKind.sales:
        final rows = <List<String>>[];
        var revenue = 0.0;
        var cost = 0.0;
        for (final move in moves) {
          if (move.type != StockMoveType.sale) continue;
          final amount = move.unitPrice * move.quantity;
          revenue += amount;
          cost += move.costAmount;
          rows.add([
            _dateTime(move.at),
            names[move.productId]?.name ?? move.productId,
            _fmt(move.quantity),
            _money(move.unitPrice),
            _money(amount),
            _money(move.costAmount),
          ]);
        }
        return WarehouseReport(
          kind: kind,
          title: 'Продажи',
          columns: const [
            'Дата',
            'Товар',
            'Кол-во',
            'Цена',
            'Выручка',
            'Себестоимость',
          ],
          rows: rows,
          totals: {
            'Выручка': _money(revenue),
            'Себестоимость': _money(cost),
            'Прибыль': _money(revenue - cost),
          },
        );
      case WarehouseReportKind.profit:
        final grouped = <String, _ReportGroup>{};
        for (final move in moves) {
          if (move.type != StockMoveType.sale) continue;
          final group = grouped.putIfAbsent(
            move.productId,
            () => _ReportGroup(orderId: '', productId: move.productId),
          );
          group.quantity += move.quantity;
          group.cost += move.costAmount;
          group.revenue += move.unitPrice * move.quantity;
        }
        final rows = [
          for (final group in grouped.values)
            [
              names[group.productId]?.name ?? group.productId,
              _fmt(group.quantity),
              _money(group.revenue),
              _money(group.cost),
              _money(group.revenue - group.cost),
              group.revenue <= 0
                  ? '—'
                  : '${((group.revenue - group.cost) / group.revenue * 100).toStringAsFixed(1)} %',
            ],
        ];
        final revenue = grouped.values.fold(0.0, (sum, g) => sum + g.revenue);
        final cost = grouped.values.fold(0.0, (sum, g) => sum + g.cost);
        return WarehouseReport(
          kind: kind,
          title: 'Прибыль по товарам',
          columns: const [
            'Товар',
            'Продано',
            'Выручка',
            'Себестоимость',
            'Прибыль',
            'Маржа',
          ],
          rows: rows,
          totals: {
            'Выручка': _money(revenue),
            'Себестоимость': _money(cost),
            'Прибыль': _money(revenue - cost),
          },
        );
      case WarehouseReportKind.lowStock:
        final rows = [
          for (final stock in snapshot.stocks)
            if (!stock.product.archived && stock.isLow)
              [
                stock.product.name,
                _fmt(stock.balance),
                _fmt(stock.product.minQuantity),
                _fmt(stock.available),
                stock.product.supplier,
                stock.product.location,
              ],
        ];
        return WarehouseReport(
          kind: kind,
          title: 'Низкие остатки',
          columns: const [
            'Товар',
            'Остаток',
            'Минимум',
            'Доступно',
            'Поставщик',
            'Место',
          ],
          rows: rows,
          totals: {'Позиций': '${rows.length}'},
          note: 'Позиции, где остаток не выше минимального.',
        );
      case WarehouseReportKind.inventory:
        final rows = <List<String>>[];
        for (final stock in snapshot.stocks) {
          if (stock.product.archived) continue;
          final last = moves
              .where(
                (move) =>
                    move.productId == stock.product.id &&
                    move.type == StockMoveType.inventory,
              )
              .firstOrNull;
          rows.add([
            stock.product.name,
            _fmt(stock.balance),
            _fmt(stock.product.minQuantity),
            last == null ? '—' : _dateTime(last.at),
            stock.isLow ? 'Требует внимания' : 'В норме',
            stock.product.location,
          ]);
        }
        return WarehouseReport(
          kind: kind,
          title: 'Инвентаризация',
          columns: const [
            'Товар',
            'Учётный остаток',
            'Минимум',
            'Последняя сверка',
            'Статус',
            'Место',
          ],
          rows: rows,
          totals: {
            'Позиций': '${rows.length}',
            'Стоимость': _money(snapshot.totalValue),
          },
        );
    }
  }

  // ------------------------------------------------------------ helpers

  Future<Map<String, double>> _balances(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT product_id, SUM(direction * quantity) AS balance '
      'FROM stock_moves GROUP BY product_id',
    );
    return {
      for (final row in rows)
        '${row['product_id']}': (row['balance'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<Map<String, double>> _reserves(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT product_id, SUM(reserved_qty) AS reserved '
      'FROM order_materials GROUP BY product_id',
    );
    return {
      for (final row in rows)
        '${row['product_id']}': (row['reserved'] as num?)?.toDouble() ?? 0,
    };
  }

  Future<Map<String, double>> _averageCosts(DatabaseExecutor db) async {
    final rows = await db.rawQuery(
      'SELECT product_id, '
      'SUM(remaining * unit_cost) AS value, SUM(remaining) AS qty '
      'FROM stock_batches WHERE remaining > 0 GROUP BY product_id',
    );
    return {
      for (final row in rows)
        if (((row['qty'] as num?)?.toDouble() ?? 0) > 0)
          '${row['product_id']}':
              ((row['value'] as num?)?.toDouble() ?? 0) /
              ((row['qty'] as num?)?.toDouble() ?? 1),
    };
  }

  Future<List<StockBatch>> _allBatches(DatabaseExecutor db) async {
    final rows = await db.query(
      'stock_batches',
      orderBy: 'received_at ASC, id ASC',
    );
    return [for (final row in rows) StockBatch.fromDb(row)];
  }

  Future<double> _balance(DatabaseExecutor db, String productId) async {
    final rows = await db.rawQuery(
      'SELECT SUM(direction * quantity) AS balance FROM stock_moves '
      'WHERE product_id = ?',
      [productId],
    );
    return (rows.first['balance'] as num?)?.toDouble() ?? 0;
  }

  Future<double> _reserved(
    DatabaseExecutor db,
    String productId, {
    String excludeOrderId = '',
  }) async {
    final rows = excludeOrderId.isEmpty
        ? await db.rawQuery(
            'SELECT SUM(reserved_qty) AS reserved FROM order_materials '
            'WHERE product_id = ?',
            [productId],
          )
        : await db.rawQuery(
            'SELECT SUM(reserved_qty) AS reserved FROM order_materials '
            'WHERE product_id = ? AND order_id <> ?',
            [productId, excludeOrderId],
          );
    return (rows.first['reserved'] as num?)?.toDouble() ?? 0;
  }

  Future<WarehouseProduct?> _productInTxn(
    Transaction txn,
    String id,
  ) async {
    final rows = await txn.query(
      'warehouse_products',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : WarehouseProduct.fromDb(rows.first);
  }

  Future<double?> _lastIssueCost(
    Transaction txn,
    String orderId,
    String productId,
  ) async {
    final rows = await txn.query(
      'stock_moves',
      columns: ['unit_cost'],
      where: 'order_id = ? AND product_id = ? AND type = ?',
      whereArgs: [orderId, productId, StockMoveType.issue.name],
      orderBy: 'at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : (rows.first['unit_cost'] as num?)?.toDouble();
  }

  Future<void> _addPriceHistory(
    Transaction txn,
    String productId,
    String kind,
    double price,
    DateTime at,
    String source,
  ) async {
    await txn.insert('price_history', {
      'product_id': productId,
      'kind': kind,
      'price': price,
      'at': at.toIso8601String(),
      'source': source,
    });
  }

  Future<void> _event(
    Transaction txn,
    String orderId,
    String text,
    DateTime at, {
    String author = '',
  }) async {
    await txn.insert('order_events', {
      'order_id': orderId,
      'text': text,
      'field': '',
      'before_value': '',
      'after_value': '',
      'author': author,
      'at': at.toIso8601String(),
    });
  }

  double? _averageFromBatches(List<StockBatch> batches) {
    final active = batches.where((batch) => batch.remaining > 0);
    final quantity = active.fold<double>(0, (sum, batch) => sum + batch.remaining);
    if (quantity <= 0) return null;
    final value = active.fold<double>(
      0,
      (sum, batch) => sum + batch.remaining * batch.unitCost,
    );
    return value / quantity;
  }
}

class _Allocation {
  const _Allocation(this.batchId, this.quantity, this.unitCost);

  final String batchId;
  final double quantity;
  final double unitCost;
}

class _ReportGroup {
  _ReportGroup({required this.orderId, required this.productId});

  final String orderId;
  final String productId;
  double quantity = 0;
  double cost = 0;
  double revenue = 0;
}

String _newId(String prefix) =>
    '$prefix-${DateTime.now().microsecondsSinceEpoch}-'
    '${math.Random().nextInt(0x7fffffff).toRadixString(16)}';

String _moveLabel(StockMoveType type) => type.label;

String _fmt(double value) {
  if (!value.isFinite) return '—';
  final fixed = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  return fixed.replaceAll('.', ',');
}

String _money(double value) {
  final fixed = value.toStringAsFixed(2).replaceAll('.', ',');
  return '$fixed ₽';
}

String _date(DateTime? value) {
  if (value == null) return '—';
  return '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';
}

String _dateTime(DateTime value) =>
    '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:'
    '${value.minute.toString().padLeft(2, '0')}';

/// Имя заказа для отчётов и резерва: номер + клиент.
String orderDisplayName(OrderProject project, {String fallback = 'Заказ'}) {
  final number = project.windows.first.drawingNumber.trim();
  final customer = project.windows.first.customer.trim();
  if (number.isNotEmpty && customer.isNotEmpty) return '$number · $customer';
  if (number.isNotEmpty) return number;
  if (customer.isNotEmpty) return customer;
  return fallback;
}
