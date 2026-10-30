import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'order_project.dart';

/// Приоритет заказа на доске.
enum OrderPriority {
  low('Низкий', Color(0xFF6F746F)),
  normal('Обычный', Color(0xFF52708C)),
  high('Высокий', Color(0xFFB86B3D)),
  urgent('Срочный', Color(0xFFB03A3A));

  const OrderPriority(this.label, this.color);

  final String label;
  final Color color;

  static OrderPriority fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => OrderPriority.normal,
  );
}

/// Состояние срока заказа.
enum DeadlineState { none, future, soon, today, overdue }

/// Полная запись заказа в локальной базе.
///
/// JSON проекта ([projectJson]) — это ровно тот же формат, что сохраняется в
/// файл заказа: заказ можно открыть в конструкторе и сохранить обратно без
/// потери параметров окон, раскроя и сметы.
class OrderRecord {
  const OrderRecord({
    required this.id,
    required this.number,
    required this.title,
    required this.customer,
    required this.status,
    required this.priority,
    required this.projectJson,
    this.phone = '',
    this.address = '',
    this.assignee = '',
    this.labels = const [],
    this.deadline,
    this.archived = false,
    this.amount = 0,
    this.comment = '',
    this.legacyRef = '',
    this.createdAt,
    this.updatedAt,
    this.statusChangedAt,
  });

  final String id;
  final String number;
  final String title;
  final String customer;
  final String phone;
  final String address;
  final OrderStatus status;
  final OrderPriority priority;
  final String assignee;
  final List<String> labels;
  final DateTime? deadline;
  final bool archived;
  final double amount;
  final String comment;
  final String projectJson;
  final String legacyRef;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? statusChangedAt;

  String get displayTitle => title.trim().isEmpty ? 'Заказ $number' : title.trim();

  String get initials {
    final source = assignee.trim().isNotEmpty
        ? assignee.trim()
        : customer.trim().isNotEmpty
        ? customer.trim()
        : displayTitle;
    final parts = source.split(RegExp(r'\s+')).where((part) => part.isNotEmpty);
    return parts.take(2).map((part) => part.characters.first.toUpperCase()).join();
  }

  bool get isOverdue {
    final value = deadline;
    if (value == null || archived) return false;
    return DateUtils.dateOnly(value).isBefore(DateUtils.dateOnly(DateTime.now()));
  }

  int get daysToDeadline {
    final value = deadline;
    if (value == null) return 0;
    return DateUtils.dateOnly(value)
        .difference(DateUtils.dateOnly(DateTime.now()))
        .inDays;
  }

  DeadlineState get deadlineState {
    final value = deadline;
    if (value == null) return DeadlineState.none;
    final days = daysToDeadline;
    if (days < 0) return DeadlineState.overdue;
    if (days == 0) return DeadlineState.today;
    if (days <= 2) return DeadlineState.soon;
    return DeadlineState.future;
  }

  String get deadlineLabel {
    final value = deadline;
    if (value == null) return 'Без срока';
    final text = _date(value);
    return switch (deadlineState) {
      DeadlineState.overdue => 'Просрочен · $text',
      DeadlineState.today => 'Сегодня · $text',
      DeadlineState.soon => 'Через $daysToDeadline дн. · $text',
      DeadlineState.future => 'Срок $text',
      DeadlineState.none => 'Без срока',
    };
  }

  OrderRecord copyWith({
    String? number,
    String? title,
    String? customer,
    String? phone,
    String? address,
    OrderStatus? status,
    OrderPriority? priority,
    String? assignee,
    List<String>? labels,
    DateTime? deadline,
    bool clearDeadline = false,
    bool? archived,
    double? amount,
    String? comment,
    String? projectJson,
    String? legacyRef,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? statusChangedAt,
  }) => OrderRecord(
    id: id,
    number: number ?? this.number,
    title: title ?? this.title,
    customer: customer ?? this.customer,
    phone: phone ?? this.phone,
    address: address ?? this.address,
    status: status ?? this.status,
    priority: priority ?? this.priority,
    assignee: assignee ?? this.assignee,
    labels: labels ?? this.labels,
    deadline: clearDeadline ? null : (deadline ?? this.deadline),
    archived: archived ?? this.archived,
    amount: amount ?? this.amount,
    comment: comment ?? this.comment,
    projectJson: projectJson ?? this.projectJson,
    legacyRef: legacyRef ?? this.legacyRef,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    statusChangedAt: statusChangedAt ?? this.statusChangedAt,
  );

  Map<String, Object?> toDb() => {
    'id': id,
    'number': number,
    'title': title,
    'customer': customer,
    'phone': phone,
    'address': address,
    'status': status.name,
    'priority': priority.name,
    'assignee': assignee,
    'labels': jsonEncode(labels),
    'deadline': deadline?.toIso8601String(),
    'archived': archived ? 1 : 0,
    'amount': amount,
    'comment': comment,
    'project_json': projectJson,
    'legacy_ref': legacyRef,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
    'status_changed_at': statusChangedAt?.toIso8601String(),
  };

  factory OrderRecord.fromDb(Map<String, Object?> row) => OrderRecord(
    id: '${row['id']}',
    number: '${row['number'] ?? ''}',
    title: '${row['title'] ?? ''}',
    customer: '${row['customer'] ?? ''}',
    phone: '${row['phone'] ?? ''}',
    address: '${row['address'] ?? ''}',
    status: OrderStatus.fromName(row['status'] as String?),
    priority: OrderPriority.fromName(row['priority'] as String?),
    assignee: '${row['assignee'] ?? ''}',
    labels: labelsFromJson(row['labels']),
    deadline: DateTime.tryParse('${row['deadline'] ?? ''}'),
    archived: (row['archived'] is num)
        ? (row['archived'] as num).toInt() == 1
        : row['archived'] == true,
    amount: _double(row['amount']),
    comment: '${row['comment'] ?? ''}',
    projectJson: '${row['project_json'] ?? '{}'}',
    legacyRef: '${row['legacy_ref'] ?? ''}',
    createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
    updatedAt: DateTime.tryParse('${row['updated_at'] ?? ''}'),
    statusChangedAt: DateTime.tryParse('${row['status_changed_at'] ?? ''}'),
  );

  static List<String> labelsFromJson(Object? raw) {
    if (raw is! String || raw.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return [for (final item in decoded) if (item is String) item];
      }
    } catch (_) {
      // Битая метка не должна ломать карточку.
    }
    return const [];
  }

  static double _double(Object? value) =>
      value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
}

/// Событие истории заказа.
class OrderEvent {
  const OrderEvent({
    required this.id,
    required this.orderId,
    required this.text,
    required this.at,
    this.field = '',
    this.before = '',
    this.after = '',
    this.author = '',
  });

  final int id;
  final String orderId;
  final String text;
  final DateTime at;
  final String field;
  final String before;
  final String after;
  final String author;

  factory OrderEvent.fromDb(Map<String, Object?> row) => OrderEvent(
    id: (row['id'] as num?)?.toInt() ?? 0,
    orderId: '${row['order_id']}',
    text: '${row['text'] ?? ''}',
    at: DateTime.tryParse('${row['at'] ?? ''}') ?? DateTime.now(),
    field: '${row['field'] ?? ''}',
    before: '${row['before_value'] ?? ''}',
    after: '${row['after_value'] ?? ''}',
    author: '${row['author'] ?? ''}',
  );
}

/// Комментарий к заказу.
class OrderComment {
  const OrderComment({
    required this.id,
    required this.orderId,
    required this.text,
    required this.at,
    this.author = '',
  });

  final int id;
  final String orderId;
  final String text;
  final DateTime at;
  final String author;

  factory OrderComment.fromDb(Map<String, Object?> row) => OrderComment(
    id: (row['id'] as num?)?.toInt() ?? 0,
    orderId: '${row['order_id']}',
    text: '${row['text'] ?? ''}',
    at: DateTime.tryParse('${row['at'] ?? ''}') ?? DateTime.now(),
    author: '${row['author'] ?? ''}',
  );
}

/// Пункт чек-листа заказа.
class OrderChecklistItem {
  const OrderChecklistItem({
    required this.id,
    required this.orderId,
    required this.text,
    required this.done,
    this.sort = 0,
  });

  final int id;
  final String orderId;
  final String text;
  final bool done;
  final int sort;

  factory OrderChecklistItem.fromDb(Map<String, Object?> row) =>
      OrderChecklistItem(
        id: (row['id'] as num?)?.toInt() ?? 0,
        orderId: '${row['order_id']}',
        text: '${row['text'] ?? ''}',
        done: (row['done'] as num?)?.toInt() == 1,
        sort: (row['sort'] as num?)?.toInt() ?? 0,
      );
}

/// Вложение заказа: фото, документ или ссылка.
class OrderAttachment {
  const OrderAttachment({
    required this.id,
    required this.orderId,
    required this.name,
    required this.addedAt,
    this.path = '',
    this.url = '',
    this.mime = '',
    this.data,
  });

  final int id;
  final String orderId;
  final String name;
  final String path;
  final String url;
  final String mime;
  final Uint8List? data;
  final DateTime addedAt;

  bool get isImage => mime.startsWith('image/');

  factory OrderAttachment.fromDb(Map<String, Object?> row) => OrderAttachment(
    id: (row['id'] as num?)?.toInt() ?? 0,
    orderId: '${row['order_id']}',
    name: '${row['name'] ?? ''}',
    path: '${row['path'] ?? ''}',
    url: '${row['url'] ?? ''}',
    mime: '${row['mime'] ?? ''}',
    data: row['data'] is Uint8List
        ? row['data'] as Uint8List
        : row['data'] is List<int>
        ? Uint8List.fromList(row['data'] as List<int>)
        : null,
    addedAt: DateTime.tryParse('${row['added_at'] ?? ''}') ?? DateTime.now(),
  );
}

/// Все связанные данные карточки заказа.
class OrderDetails {
  const OrderDetails({
    required this.order,
    this.events = const [],
    this.comments = const [],
    this.checklist = const [],
    this.attachments = const [],
  });

  final OrderRecord order;
  final List<OrderEvent> events;
  final List<OrderComment> comments;
  final List<OrderChecklistItem> checklist;
  final List<OrderAttachment> attachments;

  int get doneCount => checklist.where((item) => item.done).length;

  double get checklistProgress =>
      checklist.isEmpty ? 0 : doneCount / checklist.length;
}

/// Счётчики для карточки на доске.
class OrderCardStats {
  const OrderCardStats({
    this.checklistDone = 0,
    this.checklistTotal = 0,
    this.comments = 0,
    this.attachments = 0,
    this.reservedMaterials = 0,
    this.issuedMaterials = 0,
  });

  final int checklistDone;
  final int checklistTotal;
  final int comments;
  final int attachments;
  final int reservedMaterials;
  final int issuedMaterials;

  double get checklistProgress =>
      checklistTotal == 0 ? 0 : checklistDone / checklistTotal;

  bool get hasMaterials => reservedMaterials > 0 || issuedMaterials > 0;
}

/// Фильтры доски заказов.
class OrderFilter {
  const OrderFilter({
    this.query = '',
    this.statuses = const {},
    this.priorities = const {},
    this.assignee = '',
    this.label = '',
    this.onlyOverdue = false,
    this.onlySoon = false,
    this.includeArchived = false,
    this.sort = OrderSort.deadline,
  });

  final String query;
  final Set<OrderStatus> statuses;
  final Set<OrderPriority> priorities;
  final String assignee;
  final String label;
  final bool onlyOverdue;
  final bool onlySoon;
  final bool includeArchived;
  final OrderSort sort;

  bool get isActive =>
      query.trim().isNotEmpty ||
      statuses.isNotEmpty ||
      priorities.isNotEmpty ||
      assignee.isNotEmpty ||
      label.isNotEmpty ||
      onlyOverdue ||
      onlySoon ||
      includeArchived;

  OrderFilter copyWith({
    String? query,
    Set<OrderStatus>? statuses,
    Set<OrderPriority>? priorities,
    String? assignee,
    String? label,
    bool? onlyOverdue,
    bool? onlySoon,
    bool? includeArchived,
    OrderSort? sort,
  }) => OrderFilter(
    query: query ?? this.query,
    statuses: statuses ?? this.statuses,
    priorities: priorities ?? this.priorities,
    assignee: assignee ?? this.assignee,
    label: label ?? this.label,
    onlyOverdue: onlyOverdue ?? this.onlyOverdue,
    onlySoon: onlySoon ?? this.onlySoon,
    includeArchived: includeArchived ?? this.includeArchived,
    sort: sort ?? this.sort,
  );

  /// Применяет фильтр к списку.
  List<OrderRecord> apply(Iterable<OrderRecord> source) {
    final needle = query.trim().toLowerCase();
    final result = <OrderRecord>[];
    for (final order in source) {
      if (!includeArchived && order.archived) continue;
      if (includeArchived && !order.archived && !onlyOverdue && !onlySoon) {
        // Архивный режим показывает только архив, если явно не выбран статус.
        if (statuses.isEmpty && priorities.isEmpty && needle.isEmpty) continue;
      }
      if (statuses.isNotEmpty && !statuses.contains(order.status)) continue;
      if (priorities.isNotEmpty && !priorities.contains(order.priority)) {
        continue;
      }
      if (assignee.isNotEmpty && order.assignee != assignee) continue;
      if (label.isNotEmpty && !order.labels.contains(label)) continue;
      if (onlyOverdue && !order.isOverdue) continue;
      if (onlySoon && order.deadlineState != DeadlineState.soon) continue;
      if (needle.isNotEmpty) {
        final haystack = [
          order.title,
          order.customer,
          order.phone,
          order.address,
          order.number,
          order.assignee,
          ...order.labels,
        ].join(' ').toLowerCase();
        if (!haystack.contains(needle)) continue;
      }
      result.add(order);
    }
    result.sort((a, b) => switch (sort) {
      OrderSort.deadline => _compareDeadline(a, b),
      OrderSort.priority => b.priority.index.compareTo(a.priority.index),
      OrderSort.created => (b.createdAt ?? DateTime(0)).compareTo(
        a.createdAt ?? DateTime(0),
      ),
      OrderSort.amount => b.amount.compareTo(a.amount),
      OrderSort.title => a.displayTitle.toLowerCase().compareTo(
        b.displayTitle.toLowerCase(),
      ),
    });
    return result;
  }

  int _compareDeadline(OrderRecord a, OrderRecord b) {
    final left = a.deadline;
    final right = b.deadline;
    if (left == null && right == null) return 0;
    if (left == null) return 1;
    if (right == null) return -1;
    return left.compareTo(right);
  }
}

enum OrderSort {
  deadline('По сроку'),
  priority('По приоритету'),
  created('Сначала новые'),
  amount('По сумме'),
  title('По названию');

  const OrderSort(this.label);

  final String label;
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}.'
    '${value.month.toString().padLeft(2, '0')}.${value.year}';
