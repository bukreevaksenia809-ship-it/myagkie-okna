import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
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
  zippers: [ZipperSpec(centered: false, offsetMm: 400)],
  pocket: true,
  drainHoles: true,
  rollTop: 200,
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
    expect(window.rollTop, 200);
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

  test('свои ширины окантовки сохраняются и читаются без потерь', () async {
    const custom = WindowParams(
      projectName: 'Свои ширины',
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2520,
      rightHeight: 2520,
      rollBottom: 150,
      rollTop: 210,
      rollLeft: 95,
      rollRight: 240,
    );
    final saved = await saveOrder(
      const OrderProject(windows: [custom]),
      directoryPath: directory.path,
      now: DateTime(2026, 10, 4, 10, 0),
    );

    // В файле ширина записана числом.
    final text = await File(saved.ref.id).readAsString();
    expect(text, contains(RegExp(r'"rollBottom":\s*150')));
    expect(text, contains(RegExp(r'"rollTop":\s*210')));

    final loaded = (await loadOrder(saved)).windows.single;
    expect(loaded.rollBottom, 150);
    expect(loaded.rollTop, 210);
    expect(loaded.rollLeft, 95);
    expect(loaded.rollRight, 240);

    // Прямой round-trip JSON тоже без потерь.
    final restored = windowFromJson(windowToJson(custom));
    expect(restored.rollBottom, 150);
    expect(restored.rollTop, 210);
    expect(restored.rollLeft, 95);
    expect(restored.rollRight, 240);
  });

  test('припуск на раскрой сохраняется и читается без потерь', () async {
    const window = WindowParams(
      projectName: 'Припуск',
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      allowanceWidthMm: 120,
      allowanceHeightMm: 80,
    );
    final saved = await saveOrder(
      const OrderProject(windows: [window]),
      directoryPath: directory.path,
      now: DateTime(2026, 10, 14, 12, 0),
    );

    final text = await File(saved.ref.id).readAsString();
    expect(text, contains(RegExp(r'"allowanceWidthMm":\s*120')));
    expect(text, contains(RegExp(r'"allowanceHeightMm":\s*80')));

    // Прямой round-trip JSON тоже без потерь.
    final restored = windowFromJson(windowToJson(window));
    expect(restored.allowanceWidthMm, 120);
    expect(restored.allowanceHeightMm, 80);
    expect(restored.effectiveBottomWidth, 2120);
    expect(restored.effectiveLeftHeight, 2080);
  });

  test('старый JSON с именем пресета читается как ширина в мм', () {
    // Формат прежних версий: ширина писалась именем enum.
    final old = windowFromJson(const <String, dynamic>{
      'bottomWidth': 1500,
      'topWidth': 1500,
      'leftHeight': 2520,
      'rightHeight': 2520,
      'rollBottom': 'roll200',
      'rollTop': 'roll100',
      'rollLeft': 'roll240',
    });

    expect(old.rollBottom, 200);
    expect(old.rollTop, 100);
    expect(old.rollLeft, 240);
    // Незнакомое и битое значение откатывается к 100 мм.
    expect(old.rollRight, 100);
    expect(
      windowFromJson(const <String, dynamic>{'rollBottom': 'roll500'}).rollBottom,
      100,
    );
    expect(
      windowFromJson(const <String, dynamic>{'rollBottom': -50}).rollBottom,
      100,
    );
  });
}
