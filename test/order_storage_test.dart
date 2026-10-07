import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/order_storage.dart';

const _window = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-014',
  windowType: WindowType.lifting,
  material: FilmMaterial.tintedPvc,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  zipperEnabled: true,
  zipperCentered: false,
  zipperOffsetMm: 400,
  pocket: true,
  drainHoles: true,
  rollTop: EdgeRoll.roll200,
);

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory('build/orders_test');
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  });

  test('заказ сохраняется, находится в списке и читается обратно', () async {
    const project = OrderProject(windows: [_window]);
    final saved = await saveOrder(
      project,
      directoryPath: directory.path,
      now: DateTime(2026, 10, 3, 14, 30),
    );

    expect(saved.ref.label, '20261003-1430-Мягкое-окно-веранды.json');

    final orders = await listSavedOrders(directoryPath: directory.path);
    expect(orders, hasLength(1));
    expect(orders.first.windowCount, 1);
    expect(orders.first.filmAreaM2, greaterThan(0));
    expect(orders.first.eyeletTotal, greaterThan(0));
    expect(orders.first.savedAt, DateTime(2026, 10, 3, 14, 30));

    final loaded = await loadOrder(saved);
    final window = loaded.windows.single;
    expect(window.projectName, 'Мягкое окно веранды');
    expect(window.customer, 'Иванов И. И.');
    expect(window.windowType, WindowType.lifting);
    expect(window.material, FilmMaterial.tintedPvc);
    expect(window.bottomWidth, 1500);
    expect(window.leftHeight, 2520);
    expect(window.zipperEnabled, isTrue);
    expect(window.zipperCentered, isFalse);
    expect(window.zipperOffsetMm, 400);
    expect(window.pocket, isTrue);
    expect(window.drainHoles, isTrue);
    expect(window.rollTop, EdgeRoll.roll200);
  });

  test('в файле есть сводка расхода для отчётности', () async {
    const project = OrderProject(windows: [_window, _window]);
    final saved = await saveOrder(
      project,
      directoryPath: directory.path,
      now: DateTime(2026, 10, 3, 9, 5),
    );

    final text = await File(saved.ref.id).readAsString();
    expect(text, contains('"summary"'));
    expect(text, contains('productAreaM2'));
    expect(text, contains('"filmAreaM2"'));
    expect(text, contains('"edgeByRoll"'));
    expect(text, contains('Тент 100 мм'));
  });

  test('удаление заказа убирает его из списка', () async {
    const project = OrderProject(windows: [_window]);
    final saved = await saveOrder(project, directoryPath: directory.path);

    expect((await listSavedOrders(directoryPath: directory.path)), hasLength(1));
    await deleteOrder(saved);
    expect((await listSavedOrders(directoryPath: directory.path)), isEmpty);
  });

  test('битый файл не ломает список заказов', () async {
    directory.createSync(recursive: true);
    File('${directory.path}/broken.json').writeAsStringSync('{это не json');

    expect(await listSavedOrders(directoryPath: directory.path), isEmpty);
  });
}
