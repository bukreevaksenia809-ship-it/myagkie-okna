import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';

import 'test_fonts.dart';

const _pvc = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  pocket: true,
  pocketTop: true,
);

const _pvcWithoutPocket = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _w1500 = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
);

void main() {
  setUpAll(loadRealFonts);

  testWidgets('чертёж: крупная плашка про фартук', (tester) async {
    tester.view.physicalSize = const Size(DrawingSheet.a4Width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<void> pump(WindowParams params) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: OrderProject(windows: [params]),
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await pump(_pvc);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('apron-banner')), findsOneWidget);
    expect(find.text('ФАРТУК СНИЗУ И СВЕРХУ'), findsOneWidget);

    await pump(_pvcWithoutPocket);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('apron-banner')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('алюминиевый бокс: одна ширина на окно, цена за метр', () {
    final project = const OrderProject(windows: [_pvcWithoutPocket, _w1500]);
    final prices = const PriceList.defaults().copyWith(aluminumBoxPerM: 450);
    final estimate = Estimate.of(project, prices);
    final line = estimate.lines.firstWhere(
      (line) => line.title == 'Алюминиевый бокс',
    );
    expect(line.quantity, closeTo(3.5, 1e-9));
    expect(line.unit, 'м');
    expect(line.unitPrice, 450);
    expect(line.amount, closeTo(1575, 1e-9));
    expect(line.group, EstimateGroup.hardware);

    // Нулевая цена — позиция не начисляется.
    final free = Estimate.of(project, const PriceList.defaults());
    expect(
      free.lines.where((line) => line.title == 'Алюминиевый бокс'),
      isEmpty,
    );
  });

  test('монтаж: процент от суммы позиций', () {
    final project = const OrderProject(windows: [_pvcWithoutPocket]);
    final base = Estimate.of(project, const PriceList.defaults());
    final prices = const PriceList.defaults().copyWith(installationPercent: 10);
    final estimate = Estimate.of(project, prices);
    expect(estimate.installationPercent, 10);
    expect(estimate.installationBase, closeTo(base.subtotal, 1e-9));
    expect(
      estimate.installationAmount,
      closeTo(roundMoney(base.subtotal * 0.10), 1e-9),
    );
    expect(estimate.total, greaterThan(base.total));
    expect(
      estimate.taxableAmount,
      closeTo(base.taxableAmount + estimate.installationAmount, 1e-9),
    );
  });

  testWidgets('смета: монтаж, алюминиевый бокс и материалы', (tester) async {
    tester.view.physicalSize = const Size(1720, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final prices = const PriceList.defaults().copyWith(
      aluminumBoxPerM: 450,
      installationPercent: 10,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(windows: [_pvc, _w1500]),
            prices: prices,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Алюминиевый бокс'), findsOneWidget);
    expect(find.textContaining('Монтаж 10 %'), findsOneWidget);
    expect(find.textContaining('МАТЕРИАЛЫ ЗАКАЗА'), findsOneWidget);
    expect(find.textContaining('Защита от снега и дождя'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('дополнительные позиции идут в раздел «Доп»', () {
    final prices = const PriceList.defaults().copyWith(
      customItems: const [
        CustomPriceItem(name: 'Доставка', quantity: 1, unitPrice: 1000),
      ],
    );
    final estimate = Estimate.of(
      const OrderProject(windows: [_pvcWithoutPocket]),
      prices,
    );
    final line = estimate.lines.firstWhere(
      (line) => line.title == 'Дополнительно: Доставка',
    );
    expect(line.group, EstimateGroup.extra);
    expect(EstimateGroup.extra.label, 'Доп');
    expect(estimate.extraSubtotal, closeTo(1000, 1e-9));
  });
}
