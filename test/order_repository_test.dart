import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/order_repository.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/order_record.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late OrderRepository repo;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase.instance;
    database.configureForTesting(databaseFactoryFfi, inMemoryDatabasePath);
    await database.open();
    repo = OrderRepository(database: database);
  });

  tearDown(() async {
    await database.close();
  });

  test('создание заказа: номер, сумма, проект и событие', () async {
    final order = await repo.create(
      title: 'Беседка',
      customer: 'Иванов',
      phone: '+7 900 000-00-00',
      address: 'Лесная 12',
      deadline: DateTime(2026, 11, 10),
    );
    expect(order.number, 'МО-0001');
    expect(order.amount, greaterThan(0));
    expect(order.customer, 'Иванов');
    expect(order.deadline, DateTime(2026, 11, 10));

    final details = await repo.details(order.id);
    expect(details.events, isNotEmpty);
    expect(details.events.first.text, contains('создан'));
    expect(repo.projectOf(order).windowCount, 1);
  });

  test('смена статуса и метаданных пишет историю', () async {
    final order = await repo.create(title: 'Тест');
    final changed = await repo.updateMetadata(
      order.copyWith(
        title: 'Тест 2',
        priority: OrderPriority.urgent,
        assignee: 'Пётр',
        labels: const ['срочно', 'монтаж'],
      ),
    );
    expect(changed.ok, isTrue);
    final status = await repo.setStatus(order.id, OrderStatus.production);
    expect(status.ok, isTrue);
    final details = await repo.details(order.id);
    final fields = details.events.map((event) => event.field).toList();
    expect(fields, contains('Название'));
    expect(fields, contains('Статус'));
    expect(fields, contains('Приоритет'));
    expect(fields, contains('Ответственный'));
    expect(fields, contains('Метки'));
    expect(details.order.status, OrderStatus.production);
    expect(details.order.statusChangedAt, isNotNull);
    expect(await repo.assignees(), contains('Пётр'));
    expect(await repo.labels(), containsAll(['срочно', 'монтаж']));
  });

  test('чек-лист, комментарии и вложения сохраняются', () async {
    final order = await repo.create(title: 'Тест');
    await repo.addDefaultChecklist(order.id);
    var details = await repo.details(order.id);
    expect(details.checklist, hasLength(6));
    await repo.toggleChecklistItem(details.checklist.first);
    details = await repo.details(order.id);
    expect(details.doneCount, 1);

    await repo.addComment(order.id, 'Позвонить клиенту');
    await repo.addChecklistItem(order.id, 'Замерить проём');
    await repo.addAttachmentBytes(
      order.id,
      name: 'фото.png',
      bytes: Uint8List.fromList(const [1, 2, 3, 4]),
      mime: 'image/png',
    );
    details = await repo.details(order.id);
    expect(details.comments.single.text, 'Позвонить клиенту');
    expect(details.checklist, hasLength(7));
    expect(details.attachments.single.name, 'фото.png');
    expect(details.attachments.single.data, Uint8List.fromList(const [1, 2, 3, 4]));

    final stats = await repo.stats();
    expect(stats[order.id]!.checklistTotal, 7);
    expect(stats[order.id]!.checklistDone, 1);
    expect(stats[order.id]!.comments, 1);
    expect(stats[order.id]!.attachments, 1);
  });

  test('фильтры доски: поиск, статус, приоритет, срок, архив', () async {
    final first = await repo.create(
      title: 'Беседка',
      customer: 'Иванов',
      priority: OrderPriority.high,
      deadline: DateTime.now().subtract(const Duration(days: 2)),
    );
    final second = await repo.create(
      title: 'Терраса',
      customer: 'Петров',
      priority: OrderPriority.low,
      deadline: DateTime.now().add(const Duration(days: 1)),
    );
    final third = await repo.create(title: 'Архивный');
    await repo.archive(third.id, true);

    final all = await repo.list();
    expect(
      const OrderFilter().apply(all).map((order) => order.id),
      containsAll([first.id, second.id]),
    );
    expect(
      const OrderFilter().apply(all).map((order) => order.id),
      isNot(contains(third.id)),
    );
    expect(
      const OrderFilter(query: 'иванов').apply(all).single.id,
      first.id,
    );
    expect(
      const OrderFilter(
        statuses: {OrderStatus.newOrder},
        priorities: {OrderPriority.high},
      ).apply(all).single.id,
      first.id,
    );
    expect(const OrderFilter(onlyOverdue: true).apply(all).single.id, first.id);
    expect(
      const OrderFilter(onlySoon: true).apply(all).single.id,
      second.id,
    );
    expect(
      const OrderFilter(includeArchived: true).apply(all).map((o) => o.id),
      contains(third.id),
    );
  });

  test('массовые действия обновляют выбранные заказы', () async {
    final first = await repo.create(title: 'Первый');
    final second = await repo.create(title: 'Второй');
    final result = await repo.bulkUpdate(
      [first.id, second.id],
      status: OrderStatus.ready,
      priority: OrderPriority.urgent,
      assignee: 'Анна',
    );
    expect(result.ok, isTrue);
    final list = await repo.list();
    expect(
      list.where((order) => order.status == OrderStatus.ready).length,
      2,
    );
    expect(list.every((order) => order.assignee == 'Анна'), isTrue);
  });

  test('дублирование и удаление заказа', () async {
    final order = await repo.create(
      title: 'Оригинал',
      customer: 'Клиент',
      project: const OrderProject(),
    );
    final copy = await repo.duplicateOrder(order.id);
    expect(copy, isNotNull);
    expect(copy!.title, contains('копия'));
    expect(await repo.count(), 2);
    await repo.deleteOrder(order.id);
    expect(await repo.count(), 1);
    expect(await repo.get(order.id), isNull);
  });

  test('проект заказа переживает сохранение и чтение', () async {
    final project = const OrderProject().copyWith(
      status: OrderStatus.production,
      deadline: DateTime(2026, 12, 1),
    );
    final order = await repo.create(title: 'Проект', project: project);
    final restored = repo.projectOf(order);
    expect(restored.status, OrderStatus.production);
    expect(restored.deadline, DateTime(2026, 12, 1));
  });
}
