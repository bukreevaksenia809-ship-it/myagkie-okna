import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/main.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';
import 'package:soft_window_drawer/widgets/price_panel.dart';

import 'test_fonts.dart';

const _screen = WindowParams(
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
);

Widget _panel({
  required OrderProject project,
  List<OrderOverview> orders = const [],
  int selected = 0,
  ValueChanged<int>? onSelect,
  VoidCallback? onCreate,
  ValueChanged<int>? onRename,
  ValueChanged<int>? onDelete,
  ValueChanged<OrderProject>? onChanged,
  Widget? ordersSection,
  Widget? pricesSection,
  Widget? techSection,
}) {
  return MaterialApp(
    home: Scaffold(
      body: StatefulBuilder(
        builder: (context, setState) => ParamsPanel(
          project: project,
          issues: const [],
          prices: const PriceList.defaults(),
          orderOverviews: orders,
          selectedOrderIndex: selected,
          onSelectOrder: onSelect,
          onCreateOrder: onCreate,
          onRenameOrder: onRename,
          onDeleteOrder: onDelete,
          onChanged: onChanged ?? (_) {},
          onReset: () {},
          ordersSection: ordersSection,
          pricesSection: pricesSection,
          techSection: techSection,
        ),
      ),
    ),
  );
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

void main() {
  setUpAll(loadRealFonts);

  testWidgets('верхний порядок блоков: заказы → материал → тип → размеры → '
      'крепёж → окантовка → крепление → молния → низ', (tester) async {
    tester.view.physicalSize = const Size(420, 20000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _panel(
        project: const OrderProject(),
        orders: const [
          OrderOverview(name: 'Заказ 1', windowCount: 1),
          OrderOverview(name: 'Заказ 2', windowCount: 2),
        ],
        ordersSection: const Text('СОХРАНЁННЫЕ ФАЙЛЫ'),
        techSection: const Text('ТЕХНОЛОГ'),
        pricesSection: const Text('ПРАЙС-ЛИСТ'),
      ),
    );
    await tester.pumpAndSettle();

    final order = [
      'ЗАКАЗЫ',
      'ОКНА В ЗАКАЗЕ',
      'Материал окна',
      'ТИП ОКНА',
      'РАЗМЕРЫ, ММ',
      'Крепёж',
      'Окантовка',
      'Крепление сверху и снизу',
      'Молния и фартук',
      'Ширина рулона',
      'ЦВЕТА',
    ];
    for (var i = 1; i < order.length; i++) {
      expect(
        _top(tester, order[i]),
        greaterThan(_top(tester, order[i - 1])),
        reason: '«${order[i]}» должен идти после «${order[i - 1]}»',
      );
    }
    // «Цвета» — ниже маркировки и пресетов.
    expect(_top(tester, 'ЦВЕТА'), greaterThan(_top(tester, 'ПРЕСЕТЫ')));
    expect(_top(tester, 'ЦВЕТА'), greaterThan(_top(tester, 'МАРКИРОВКА')));
    // Припуски остались в рабочем порядке; цвета, файлы, технолог и прайс —
    // в самом низу.
    expect(find.text('Припуски на раскрой'), findsOneWidget);
    expect(
      _top(tester, 'СОХРАНЁННЫЕ ФАЙЛЫ'),
      greaterThan(_top(tester, 'ЦВЕТА')),
    );
    expect(_top(tester, 'ТЕХНОЛОГ'), greaterThan(_top(tester, 'ЦВЕТА')));
    expect(_top(tester, 'ПРАЙС-ЛИСТ'), greaterThan(_top(tester, 'ТЕХНОЛОГ')));

    // Старые блоки кромок убраны полностью.
    expect(find.text('Верхняя кромка'), findsNothing);
    expect(find.text('Длины боковых кромок'), findsNothing);
    expect(find.textContaining('ПВХ-тент'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('материал: ПВХ с видами и скрин без подвыбора', (tester) async {
    tester.view.physicalSize = const Size(420, 12000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var project = const OrderProject();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ParamsPanel(
              project: project,
              issues: const [],
              onChanged: (value) => setState(() => project = value),
              onReset: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('material-screen')));
    await tester.pumpAndSettle();
    expect(project.selected.material, FilmMaterial.screen);
    expect(find.text('Вид ПВХ'), findsNothing);
    expect(
      find.text(
        'Скрин — сетчатая ткань для проветривания. Подвороты, шов 3 мм '
        'и крепёж по подвороту задаются ниже.',
      ),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('material-pvc')));
    await tester.pumpAndSettle();
    expect(project.selected.material, FilmMaterial.clearPvc);
    expect(find.text('Вид ПВХ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('material-tinted')));
    await tester.pumpAndSettle();
    expect(project.selected.material, FilmMaterial.tintedPvc);
    await tester.tap(find.byKey(const Key('material-mesh')));
    await tester.pumpAndSettle();
    expect(project.selected.material, FilmMaterial.mosquitoNet);
    expect(tester.takeException(), isNull);
  });

  testWidgets('тип окна и цены всех крепежей', (tester) async {
    tester.view.physicalSize = const Size(420, 14000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var project = const OrderProject();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ParamsPanel(
              project: project,
              issues: const [],
              prices: const PriceList.defaults(),
              onChanged: (value) => setState(() => project = value),
              onReset: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Подъёмное').first);
    await tester.pumpAndSettle();
    expect(project.selected.windowType, WindowType.lifting);

    // В блоке крепежа видны цены: люверсы и все виды крепежа.
    expect(find.textContaining('90,00 ₽/шт'), findsWidgets);
    expect(find.textContaining('135,00 ₽/шт'), findsWidgets);
    expect(find.textContaining('220,00 ₽/шт'), findsWidgets);
    expect(find.textContaining('400,00 ₽/шт'), findsWidgets);
    expect(find.textContaining('190,00 ₽/шт'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('заказы сверху: создать, переключить, переименовать, удалить', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1720, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: BuilderScreen()));
    await tester.pumpAndSettle();

    // Создать заказ с именем.
    await tester.tap(find.byKey(const Key('create-order')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('order-name-field')), 'Дача');
    await tester.tap(find.byKey(const Key('save-order-name')));
    await tester.pumpAndSettle();
    expect(find.text('Дача'), findsOneWidget);
    final row1 = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('order-row-1')),
        matching: find.byType(ListTile),
      ),
    );
    expect(row1.selected, isTrue);

    // В новом заказе создаём второе окно.
    await tester.tap(find.byKey(const Key('add-window')));
    await tester.pumpAndSettle();
    expect(find.text('окон: 2'), findsOneWidget);

    // Переименовать.
    await tester.tap(find.byKey(const Key('rename-order-1')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('order-name-field')),
      'Беседка',
    );
    await tester.tap(find.byKey(const Key('save-order-name')));
    await tester.pumpAndSettle();
    expect(find.text('Беседка'), findsOneWidget);
    expect(find.text('Дача'), findsNothing);

    // Переключиться на первый заказ.
    await tester.tap(find.byKey(const Key('order-row-0')));
    await tester.pumpAndSettle();
    final row0 = tester.widget<ListTile>(
      find.descendant(
        of: find.byKey(const Key('order-row-0')),
        matching: find.byType(ListTile),
      ),
    );
    expect(row0.selected, isTrue);

    // Удалить второй заказ.
    await tester.tap(find.byKey(const Key('delete-order-1')));
    await tester.pumpAndSettle();
    expect(find.text('Беседка'), findsNothing);
    expect(find.byKey(const Key('order-row-1')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('прайс: превью ПВХ / скрин / оба и продающие подписи', (
    tester,
  ) async {
    Future<void> pump(List<FilmMaterial> materials) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: PricePanel(
                  prices: const PriceList.defaults(),
                  materials: materials,
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(const [FilmMaterial.clearPvc]);
    expect(find.byKey(const Key('price-material-pvc')), findsOneWidget);
    expect(find.byKey(const Key('price-material-screen')), findsNothing);
    expect(find.textContaining('Срок службы 10 лет'), findsOneWidget);

    await pump(const [FilmMaterial.screen]);
    expect(find.byKey(const Key('price-material-pvc')), findsNothing);
    expect(find.byKey(const Key('price-material-screen')), findsOneWidget);
    expect(find.textContaining('проветривается'), findsOneWidget);

    await pump(const [FilmMaterial.tintedPvc, FilmMaterial.screen]);
    expect(find.byKey(const Key('price-material-pvc')), findsOneWidget);
    expect(find.byKey(const Key('price-material-screen')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('смета: блока «Цены прайса» нет', (tester) async {
    tester.view.physicalSize = const Size(1720, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(windows: [_screen]),
            prices: const PriceList.defaults(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Цены прайса'), findsNothing);
    expect(find.textContaining('Смета на заказ'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('техкарта скрина: блок про УФ и технологию', (tester) async {
    final card = TechCard.forWindow(_screen);
    final material = card.operations.firstWhere(
      (operation) => operation.kind == TechOperationKind.material,
    );
    expect(material.title, contains('скрин'));
    expect(material.text, contains('УФ'));
    expect(material.text, contains('подворот'));
    expect(material.text, contains('шов 3 мм'));
  });

  testWidgets('пишет превью панели', (tester) async {
    tester.view.physicalSize = const Size(840, 8000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final panelKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: panelKey,
            child: SizedBox(
              width: 420,
              height: 4000,
              child: ParamsPanel(
                project: const OrderProject(windows: [_screen, _screen]),
                issues: const [],
                prices: const PriceList.defaults(),
                orderOverviews: const [
                  OrderOverview(name: 'Заказ 1 — Дача', windowCount: 2),
                  OrderOverview(name: 'Заказ 2 — Беседка', windowCount: 1),
                ],
                selectedOrderIndex: 0,
                onSelectOrder: (_) {},
                onCreateOrder: () {},
                onRenameOrder: (_) {},
                onDeleteOrder: (_) {},
                onChanged: (_) {},
                onReset: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(panelKey),
    );
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes;
    });
    final directory = Directory('build/preview')..createSync(recursive: true);
    final file = File('${directory.path}/menu-panel.png')
      ..writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('Превью записано: ${file.path}');
  });

  testWidgets('пишет превью прайса', (tester) async {
    tester.view.physicalSize = const Size(840, 2200);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final priceKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: RepaintBoundary(
            key: priceKey,
            child: SizedBox(
              width: 420,
              height: 1100,
              child: SingleChildScrollView(
                child: PricePanel(
                  prices: const PriceList.defaults(),
                  materials: const [FilmMaterial.clearPvc, FilmMaterial.screen],
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ПРАЙС-ЛИСТ'));
    await tester.pump();
    final boundary = tester.firstRenderObject<RenderRepaintBoundary>(
      find.byKey(priceKey),
    );
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes;
    });
    final directory = Directory('build/preview')..createSync(recursive: true);
    final file = File('${directory.path}/menu-price.png')
      ..writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('Превью записано: ${file.path}');
  });

  test('расчёт не изменился: скрин 2000 × 2000, подворот 40', () {
    final spec = WindowSpec.of(_screen);
    expect(spec.filmCutWidth, 2040);
    expect(spec.filmCutHeight, 2060);
    expect(spec.filmCutAreaM2, closeTo(4.2024, 1e-9));
    final summary = CostsSummary(OrderProject(windows: [_screen]));
    expect(summary.filmAreaM2, closeTo(4.2024, 1e-9));
    final estimate = Estimate.of(
      OrderProject(windows: [_screen]),
      const PriceList.defaults(),
    );
    expect(estimate.lines, isNotEmpty);
    expect(estimate.total, greaterThan(0));
  });
}
