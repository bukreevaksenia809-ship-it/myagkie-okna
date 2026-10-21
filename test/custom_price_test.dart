import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';
import 'package:soft_window_drawer/widgets/material_thumb.dart';
import 'package:soft_window_drawer/widgets/price_panel.dart';

import 'test_fonts.dart';

const _pvcWindow = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _screenWindow = WindowParams(
  material: FilmMaterial.screen,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
);

void main() {
  setUpAll(loadRealFonts);

  test('CustomPriceItem: JSON, сумма, безопасный разбор', () {
    const item = CustomPriceItem(
      name: 'Доставка',
      quantity: 2,
      unit: 'шт',
      unitPrice: 500,
    );
    expect(item.isFilled, isTrue);
    expect(item.amount, 1000);
    expect(item.copyWith(name: 'Монтаж').name, 'Монтаж');

    final restored = CustomPriceItem.fromJson({
      'name': 'Монтаж',
      'quantity': 3,
      'unit': 'м',
      'unitPrice': 250,
    });
    expect(restored.name, 'Монтаж');
    expect(restored.quantity, 3);
    expect(restored.unit, 'м');
    expect(restored.unitPrice, 250);
    expect(CustomPriceItem.fromJson({'name': 'X', 'unit': 'кг'}).unit, 'шт');
    expect(const CustomPriceItem().isFilled, isFalse);
  });

  test('прайс: свободные позиции сохраняются в JSON', () {
    final prices = const PriceList.defaults().copyWith(
      customItems: const [
        CustomPriceItem(name: 'Доставка', quantity: 2, unitPrice: 500),
        CustomPriceItem(name: 'Монтаж', quantity: 1, unit: 'м', unitPrice: 300),
      ],
    );
    final json = prices.toJson();
    final restored = PriceList.fromJson(json);
    expect(restored.customItems, hasLength(2));
    expect(restored.customItems.first.name, 'Доставка');
    expect(restored.customItems.first.amount, 1000);
    expect(restored.customItems[1].unit, 'м');
    expect(restored.customItems[1].unitPrice, 300);
  });

  test('смета: свободная позиция отдельной строкой и в ИТОГО', () {
    const base = PriceList.defaults();
    final prices = base.copyWith(
      customItems: const [
        CustomPriceItem(
          name: 'Доставка',
          quantity: 2,
          unit: 'шт',
          unitPrice: 500,
        ),
      ],
    );
    final project = const OrderProject(windows: [_pvcWindow]);
    final estimate = Estimate.of(project, prices);
    final line = estimate.lines.firstWhere(
      (line) => line.title == 'Дополнительно: Доставка',
    );
    expect(line.quantity, 2);
    expect(line.unit, 'шт');
    expect(line.unitPrice, 500);
    expect(line.amount, 1000);
    expect(line.group, EstimateGroup.work);
    expect(
      estimate.workSubtotal - Estimate.of(project, base).workSubtotal,
      closeTo(1000, 1e-9),
    );
  });

  testWidgets('прайс: ручной ввод свободной строки', (tester) async {
    tester.view.physicalSize = const Size(420, 4000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var prices = const PriceList.defaults();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: SizedBox(
                width: 420,
                child: PricePanel(
                  prices: prices,
                  materials: const [FilmMaterial.clearPvc],
                  onChanged: (value) => setState(() => prices = value),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ПРАЙС-ЛИСТ'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('add-custom-item')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-custom-item')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('custom-name-0')), 'Доставка');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-qty-0')), '2');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-price-0')), '500');
    await tester.pumpAndSettle();

    expect(prices.customItems, hasLength(1));
    expect(prices.customItems.single.name, 'Доставка');
    expect(prices.customItems.single.quantity, 2);
    expect(prices.customItems.single.unitPrice, 500);
    expect(find.textContaining('1 000,00 ₽'), findsWidgets);

    await tester.ensureVisible(find.byKey(const Key('delete-custom-item-0')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('delete-custom-item-0')));
    await tester.pumpAndSettle();
    expect(prices.customItems, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('смета: свободная строка видна на листе', (tester) async {
    tester.view.physicalSize = const Size(1720, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prices = const PriceList.defaults().copyWith(
      customItems: const [
        CustomPriceItem(
          name: 'Доставка',
          quantity: 2,
          unit: 'шт',
          unitPrice: 500,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(windows: [_pvcWindow]),
            prices: prices,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Дополнительно: Доставка'), findsOneWidget);
    expect(find.textContaining('1 000,00 ₽'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('пишет превью сметы с материалами и свободной строкой', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1720, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final key = GlobalKey();
    final prices = const PriceList.defaults().copyWith(
      customItems: const [
        CustomPriceItem(
          name: 'Доставка и подъём на этаж',
          quantity: 1,
          unit: 'шт',
          unitPrice: 3500,
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(windows: [_pvcWindow, _screenWindow]),
            prices: prices,
            captureKey: key,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final data = await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes;
    });
    final directory = Directory('build/preview')..createSync(recursive: true);
    final file = File('${directory.path}/smeta-materialy.png')
      ..writeAsBytesSync(data!.buffer.asUint8List());
    expect(file.lengthSync(), greaterThan(5000));
    // ignore: avoid_print
    print('Превью записано: ${file.path}');
  });

  testWidgets('смета: картинки ПВХ и скрина на листе', (tester) async {
    tester.view.physicalSize = const Size(1720, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(windows: [_pvcWindow, _screenWindow]),
            prices: const PriceList.defaults(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final thumbs = tester
        .widgetList<MaterialThumb>(find.byType(MaterialThumb))
        .toList();
    expect(thumbs, hasLength(2));
    expect(thumbs.where((thumb) => thumb.screen).length, 1);
    expect(thumbs.where((thumb) => !thumb.screen).length, 1);
    expect(tester.takeException(), isNull);
  });
}
