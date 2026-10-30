import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:sqflite_common/sqlite_api.dart';

import '../models/order_json.dart';
import '../models/order_project.dart';
import '../models/order_record.dart';
import '../services/estimate.dart';
import 'app_database.dart';

/// Результат изменения заказа.
class OrderActionResult {
  const OrderActionResult({
    required this.ok,
    required this.message,
    this.order,
  });

  final bool ok;
  final String message;
  final OrderRecord? order;

  static OrderActionResult failure(String message) =>
      OrderActionResult(ok: false, message: message);

  static OrderActionResult success(String message, [OrderRecord? order]) =>
      OrderActionResult(ok: true, message: message, order: order);
}

/// Репозиторий заказов: карточки, статусы, история, чек-листы, вложения.
class OrderRepository {
  OrderRepository({AppDatabase? database})
    : _database = database ?? AppDatabase.instance;

  final AppDatabase _database;

  static final OrderRepository instance = OrderRepository();

  Future<List<OrderRecord>> list({
    bool includeArchived = true,
    int limit = 2000,
  }) async {
    final db = await _database.database;
    final rows = await db.query(
      'orders',
      where: includeArchived ? null : 'archived = 0',
      orderBy: "CASE WHEN deadline IS NULL THEN 1 ELSE 0 END, deadline ASC, "
          'created_at DESC',
      limit: limit,
    );
    return [for (final row in rows) OrderRecord.fromDb(row)];
  }

  Future<OrderRecord?> get(String id) async {
    final db = await _database.database;
    final rows = await db.query(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : OrderRecord.fromDb(rows.first);
  }

  Future<OrderRecord?> findByLegacyRef(String ref) async {
    if (ref.isEmpty) return null;
    final db = await _database.database;
    final rows = await db.query(
      'orders',
      where: 'legacy_ref = ?',
      whereArgs: [ref],
      limit: 1,
    );
    return rows.isEmpty ? null : OrderRecord.fromDb(rows.first);
  }

  Future<OrderDetails> details(String id) async {
    final order = await get(id);
    if (order == null) {
      throw StateError('Заказ не найден');
    }
    final db = await _database.database;
    final events = await db.query(
      'order_events',
      where: 'order_id = ?',
      whereArgs: [id],
      orderBy: 'at DESC, id DESC',
      limit: 300,
    );
    final comments = await db.query(
      'order_comments',
      where: 'order_id = ?',
      whereArgs: [id],
      orderBy: 'at DESC, id DESC',
    );
    final checklist = await db.query(
      'order_checklist',
      where: 'order_id = ?',
      whereArgs: [id],
      orderBy: 'sort ASC, id ASC',
    );
    final attachments = await db.query(
      'order_attachments',
      where: 'order_id = ?',
      whereArgs: [id],
      orderBy: 'added_at DESC, id DESC',
    );
    return OrderDetails(
      order: order,
      events: [for (final row in events) OrderEvent.fromDb(row)],
      comments: [for (final row in comments) OrderComment.fromDb(row)],
      checklist: [
        for (final row in checklist) OrderChecklistItem.fromDb(row),
      ],
      attachments: [
        for (final row in attachments) OrderAttachment.fromDb(row),
      ],
    );
  }

  Future<OrderRecord> create({
    String title = '',
    String customer = '',
    String phone = '',
    String address = '',
    OrderStatus status = OrderStatus.newOrder,
    OrderPriority priority = OrderPriority.normal,
    String assignee = '',
    List<String> labels = const [],
    DateTime? deadline,
    String comment = '',
    OrderProject project = const OrderProject(),
    double? amount,
    String legacyRef = '',
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final now = DateTime.now();
      final number = await _nextNumber(txn, now);
      final id = _newOrderId();
      final order = OrderRecord(
        id: id,
        number: number,
        title: title.trim(),
        customer: customer.trim(),
        phone: phone.trim(),
        address: address.trim(),
        status: status,
        priority: priority,
        assignee: assignee.trim(),
        labels: _cleanLabels(labels),
        deadline: deadline == null ? null : _dateOnly(deadline),
        amount: amount ?? _amountFor(project),
        comment: comment.trim(),
        projectJson: jsonEncode(orderToJson(project)),
        legacyRef: legacyRef,
        createdAt: now,
        updatedAt: now,
        statusChangedAt: now,
      );
      await txn.insert('orders', order.toDb());
      await _event(
        txn,
        id,
        'Заказ создан',
        now,
        field: 'created',
        after: number,
      );
      return order;
    });
  }

  /// Создаёт заказ из проекта, если такого ещё нет; иначе обновляет.
  Future<OrderRecord> upsertProject({
    required OrderProject project,
    required String name,
    String legacyRef = '',
    String customer = '',
    String phone = '',
    String address = '',
    String assignee = '',
    DateTime? deadline,
    OrderPriority? priority,
    List<String>? labels,
    String comment = '',
    double? amount,
  }) async {
    final existing = await findByLegacyRef(legacyRef);
    if (existing != null) {
      final updated = await updateProject(
        existing.id,
        project,
        amount: amount ?? _amountFor(project),
        metadata: existing.copyWith(
          title: name,
          customer: customer.isEmpty ? existing.customer : customer,
          phone: phone.isEmpty ? existing.phone : phone,
          address: address.isEmpty ? existing.address : address,
          assignee: assignee.isEmpty ? existing.assignee : assignee,
          deadline: deadline ?? existing.deadline,
          priority: priority ?? existing.priority,
          labels: labels ?? existing.labels,
          comment: comment.isEmpty ? existing.comment : comment,
        ),
      );
      return updated;
    }
    final created = await create(
      title: name,
      customer: customer,
      phone: phone,
      address: address,
      project: project,
      legacyRef: legacyRef,
      priority: priority ?? OrderPriority.normal,
      assignee: assignee,
      deadline: deadline,
      labels: labels ?? const [],
      comment: comment,
      amount: amount,
    );
    return created;
  }

  Future<OrderRecord> updateProject(
    String id,
    OrderProject project, {
    double? amount,
    OrderRecord? metadata,
  }) async {
    final db = await _database.database;
    return db.transaction((txn) async {
      final current = await _getInTxn(txn, id);
      if (current == null) throw StateError('Заказ не найден');
      final now = DateTime.now();
      final next = (metadata ?? current).copyWith(
        projectJson: jsonEncode(orderToJson(project)),
        amount: amount ?? _amountFor(project),
        updatedAt: now,
      );
      await txn.update(
        'orders',
        next.toDb(),
        where: 'id = ?',
        whereArgs: [id],
      );
      await _diffEvents(txn, current, next, now);
      return next;
    });
  }

  Future<OrderActionResult> updateMetadata(
    OrderRecord next, {
    String author = '',
  }) async {
    if (next.title.trim().isEmpty && next.customer.trim().isEmpty) {
      return OrderActionResult.failure('Укажите название или клиента');
    }
    final db = await _database.database;
    try {
      return await db.transaction((txn) async {
        final current = await _getInTxn(txn, next.id);
        if (current == null) {
          return OrderActionResult.failure('Заказ не найден');
        }
        final now = DateTime.now();
        final value = next.copyWith(
          title: next.title.trim(),
          customer: next.customer.trim(),
          phone: next.phone.trim(),
          address: next.address.trim(),
          assignee: next.assignee.trim(),
          labels: _cleanLabels(next.labels),
          updatedAt: now,
          statusChangedAt: current.status == next.status
              ? current.statusChangedAt
              : now,
        );
        await txn.update(
          'orders',
          value.toDb(),
          where: 'id = ?',
          whereArgs: [next.id],
        );
        await _diffEvents(txn, current, value, now, author: author);
        return OrderActionResult.success('Заказ сохранён', value);
      });
    } on DatabaseException catch (error) {
      return OrderActionResult.failure('Не удалось сохранить: $error');
    }
  }

  Future<OrderActionResult> setStatus(
    String id,
    OrderStatus status, {
    String author = '',
  }) async {
    final current = await get(id);
    if (current == null) return OrderActionResult.failure('Заказ не найден');
    return updateMetadata(current.copyWith(status: status), author: author);
  }

  Future<OrderActionResult> archive(String id, bool archived) async {
    final current = await get(id);
    if (current == null) return OrderActionResult.failure('Заказ не найден');
    return updateMetadata(current.copyWith(archived: archived));
  }

  Future<OrderActionResult> bulkUpdate(
    List<String> ids, {
    OrderStatus? status,
    OrderPriority? priority,
    String? assignee,
    bool? archived,
    DateTime? deadline,
  }) async {
    if (ids.isEmpty) return OrderActionResult.failure('Ничего не выбрано');
    final db = await _database.database;
    await db.transaction((txn) async {
      final now = DateTime.now();
      for (final id in ids) {
        final current = await _getInTxn(txn, id);
        if (current == null) continue;
        final next = current.copyWith(
          status: status ?? current.status,
          priority: priority ?? current.priority,
          assignee: assignee ?? current.assignee,
          archived: archived ?? current.archived,
          deadline: deadline ?? current.deadline,
          statusChangedAt: status != null && status != current.status
              ? now
              : current.statusChangedAt,
          updatedAt: now,
        );
        await txn.update(
          'orders',
          next.toDb(),
          where: 'id = ?',
          whereArgs: [id],
        );
        await _diffEvents(txn, current, next, now);
      }
    });
    return OrderActionResult.success('Обновлено заказов: ${ids.length}');
  }

  Future<List<String>> assignees() async {
    final db = await _database.database;
    final rows = await db.rawQuery(
      "SELECT DISTINCT assignee FROM orders WHERE assignee <> '' "
      'ORDER BY assignee COLLATE NOCASE',
    );
    return [for (final row in rows) '${row['assignee']}'];
  }

  Future<List<String>> labels() async {
    final db = await _database.database;
    final rows = await db.query('orders', columns: ['labels']);
    final result = <String>{};
    for (final row in rows) {
      result.addAll(OrderRecord.labelsFromJson(row['labels']));
    }
    final list = result.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return list;
  }

  Future<int> count() async {
    final db = await _database.database;
    final rows = await db.rawQuery('SELECT COUNT(*) AS c FROM orders');
    return (rows.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Счётчики для всех карточек одним запросом — доска не делает N+1.
  Future<Map<String, OrderCardStats>> stats() async {
    final db = await _database.database;
    final rows = await db.rawQuery('''
      SELECT o.id,
        (SELECT COUNT(*) FROM order_checklist c WHERE c.order_id = o.id) AS checklist_total,
        (SELECT COUNT(*) FROM order_checklist c WHERE c.order_id = o.id AND c.done = 1) AS checklist_done,
        (SELECT COUNT(*) FROM order_comments c WHERE c.order_id = o.id) AS comments,
        (SELECT COUNT(*) FROM order_attachments a WHERE a.order_id = o.id) AS attachments,
        (SELECT COUNT(*) FROM order_materials m WHERE m.order_id = o.id AND m.reserved_qty > 0) AS reserved_materials,
        (SELECT COUNT(*) FROM order_materials m WHERE m.order_id = o.id AND m.issued_qty > 0) AS issued_materials
      FROM orders o
    ''');
    return {
      for (final row in rows)
        '${row['id']}': OrderCardStats(
          checklistDone: (row['checklist_done'] as num?)?.toInt() ?? 0,
          checklistTotal: (row['checklist_total'] as num?)?.toInt() ?? 0,
          comments: (row['comments'] as num?)?.toInt() ?? 0,
          attachments: (row['attachments'] as num?)?.toInt() ?? 0,
          reservedMaterials: (row['reserved_materials'] as num?)?.toInt() ?? 0,
          issuedMaterials: (row['issued_materials'] as num?)?.toInt() ?? 0,
        ),
    };
  }

  Future<OrderActionResult> deleteOrder(String id) async {
    final db = await _database.database;
    await db.delete('orders', where: 'id = ?', whereArgs: [id]);
    return OrderActionResult.success('Заказ удалён');
  }

  Future<OrderRecord?> duplicateOrder(String id) async {
    final source = await get(id);
    if (source == null) return null;
    final project = projectOf(source);
    return create(
      title: '${source.displayTitle} · копия',
      customer: source.customer,
      phone: source.phone,
      address: source.address,
      priority: source.priority,
      assignee: source.assignee,
      labels: source.labels,
      deadline: source.deadline,
      comment: source.comment,
      project: project,
      amount: source.amount,
    );
  }

  // ------------------------------------------------------- комментарии

  Future<void> addComment(String orderId, String text, {String author = ''}) async {
    if (text.trim().isEmpty) return;
    final db = await _database.database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.insert('order_comments', {
        'order_id': orderId,
        'text': text.trim(),
        'author': author,
        'at': now.toIso8601String(),
      });
      await txn.update(
        'orders',
        {'updated_at': now.toIso8601String()},
        where: 'id = ?',
        whereArgs: [orderId],
      );
    });
  }

  Future<void> deleteComment(int id, String orderId) async {
    final db = await _database.database;
    await db.delete('order_comments', where: 'id = ?', whereArgs: [id]);
  }

  // --------------------------------------------------------- чек-лист

  Future<void> addChecklistItem(
    String orderId,
    String text, {
    int? sort,
  }) async {
    if (text.trim().isEmpty) return;
    final db = await _database.database;
    final nextSort = sort ??
        ((await db.rawQuery(
                  'SELECT COALESCE(MAX(sort), 0) + 1 AS s '
                  'FROM order_checklist WHERE order_id = ?',
                  [orderId],
                ))
                .first['s'] as num?)
            ?.toInt() ??
        1;
    await db.insert('order_checklist', {
      'order_id': orderId,
      'text': text.trim(),
      'done': 0,
      'sort': nextSort,
    });
  }

  Future<void> toggleChecklistItem(OrderChecklistItem item) async {
    final db = await _database.database;
    await db.update(
      'order_checklist',
      {'done': item.done ? 0 : 1},
      where: 'id = ?',
      whereArgs: [item.id],
    );
  }

  Future<void> deleteChecklistItem(int id) async {
    final db = await _database.database;
    await db.delete('order_checklist', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addDefaultChecklist(String orderId) async {
    final existing = (await details(orderId)).checklist;
    if (existing.isNotEmpty) return;
    for (final text in const [
      'Замер подтверждён',
      'Материалы проверены',
      'Полотно раскроено',
      'Люверсы и фурнитура установлены',
      'Контроль качества пройден',
      'Упаковано и передано на монтаж',
    ]) {
      await addChecklistItem(orderId, text);
    }
  }

  // --------------------------------------------------------- вложения

  Future<void> addAttachment(
    String orderId, {
    required String name,
    String path = '',
    String url = '',
    String mime = '',
  }) async {
    if (name.trim().isEmpty) return;
    final db = await _database.database;
    await db.insert('order_attachments', {
      'order_id': orderId,
      'name': name.trim(),
      'path': path,
      'url': url,
      'mime': mime,
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> addAttachmentBytes(
    String orderId, {
    required String name,
    required Uint8List bytes,
    String mime = '',
  }) async {
    if (name.trim().isEmpty) return;
    final db = await _database.database;
    await db.insert('order_attachments', {
      'order_id': orderId,
      'name': name.trim(),
      'path': '',
      'url': '',
      'mime': mime,
      'data': Uint8List.fromList(bytes),
      'added_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> deleteAttachment(int id) async {
    final db = await _database.database;
    await db.delete('order_attachments', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> addEvent(
    String orderId,
    String text, {
    String author = '',
  }) async {
    final db = await _database.database;
    await _event(
      db,
      orderId,
      text,
      DateTime.now(),
      author: author,
    );
  }

  /// Загружает проект заказа.
  OrderProject projectOf(OrderRecord order) {
    try {
      final decoded = jsonDecode(order.projectJson);
      if (decoded is Map) {
        return orderFromJson(decoded.cast<String, dynamic>());
      }
    } catch (_) {
      // Битая запись не должна ронять приложение: откроем пустой проект.
    }
    return const OrderProject();
  }

  /// Сумма заказа по текущему прайсу.
  double amountOf(OrderProject project) => _amountFor(project);

  // ------------------------------------------------------------ helpers

  Future<OrderRecord?> _getInTxn(Transaction txn, String id) async {
    final rows = await txn.query(
      'orders',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : OrderRecord.fromDb(rows.first);
  }

  Future<String> _nextNumber(Transaction txn, DateTime at) async {
    final rows = await txn.rawQuery('SELECT COUNT(*) AS c FROM orders');
    var index = ((rows.first['c'] as num?)?.toInt() ?? 0) + 1;
    while (true) {
      final number = 'МО-${index.toString().padLeft(4, '0')}';
      final exists = await txn.query(
        'orders',
        columns: ['id'],
        where: 'number = ?',
        whereArgs: [number],
        limit: 1,
      );
      if (exists.isEmpty) return number;
      index++;
    }
  }

  double _amountFor(OrderProject project) {
    try {
      return Estimate.of(project, const PriceList.defaults()).total;
    } catch (_) {
      return 0;
    }
  }

  Future<void> _diffEvents(
    Transaction txn,
    OrderRecord before,
    OrderRecord after,
    DateTime at, {
    String author = '',
  }) async {
    Future<void> add(String field, String from, String to) async {
      await txn.insert('order_events', {
        'order_id': after.id,
        'text': '$field: $from → $to',
        'field': field,
        'before_value': from,
        'after_value': to,
        'author': author,
        'at': at.toIso8601String(),
      });
    }

    if (before.title != after.title) {
      await add('Название', before.title, after.title);
    }
    if (before.customer != after.customer) {
      await add('Клиент', before.customer, after.customer);
    }
    if (before.phone != after.phone) {
      await add('Телефон', before.phone, after.phone);
    }
    if (before.address != after.address) {
      await add('Адрес', before.address, after.address);
    }
    if (before.status != after.status) {
      await add('Статус', before.status.label, after.status.label);
    }
    if (before.priority != after.priority) {
      await add('Приоритет', before.priority.label, after.priority.label);
    }
    if (before.assignee != after.assignee) {
      await add('Ответственный', before.assignee, after.assignee);
    }
    if (before.deadline != after.deadline) {
      await add(
        'Срок',
        _date(before.deadline),
        _date(after.deadline),
      );
    }
    if (before.labels.join(',') != after.labels.join(',')) {
      await add('Метки', before.labels.join(', '), after.labels.join(', '));
    }
    if (before.comment != after.comment) {
      await add('Комментарий', 'изменён', '');
    }
    if (before.archived != after.archived) {
      await add(
        'Архив',
        before.archived ? 'да' : 'нет',
        after.archived ? 'да' : 'нет',
      );
    }
    if (before.projectJson != after.projectJson) {
      await add('Состав заказа', 'изменён', '');
    }
  }

  Future<void> _event(
    DatabaseExecutor db,
    String orderId,
    String text,
    DateTime at, {
    String field = '',
    String before = '',
    String after = '',
    String author = '',
  }) async {
    await db.insert('order_events', {
      'order_id': orderId,
      'text': text,
      'field': field,
      'before_value': before,
      'after_value': after,
      'author': author,
      'at': at.toIso8601String(),
    });
  }

  List<String> _cleanLabels(Iterable<String> labels) {
    final seen = <String>{};
    final result = <String>[];
    for (final label in labels) {
      final value = label.trim();
      if (value.isEmpty) continue;
      if (seen.add(value.toLowerCase())) result.add(value);
    }
    return result;
  }
}

DateTime _dateOnly(DateTime value) => DateTime(value.year, value.month, value.day);

String _newOrderId() =>
    'ord-${DateTime.now().microsecondsSinceEpoch}-'
    '${math.Random().nextInt(0x7fffffff).toRadixString(16)}';

String _date(DateTime? value) {
  if (value == null) return '—';
  return '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';
}
