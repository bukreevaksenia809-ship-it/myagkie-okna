// Единицы отображения: миллиметры / сантиметры.
//
// Модель и расчёты остаются в миллиметрах; переключатель меняет только
// подписи. Тесты проверяют форматтер, сохранение выбора, перерисовку панели
// и то, что смета/JSON не зависят от единицы.
//
// Запуск: flutter test test/units_test.dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/fastener_spans.dart';
import 'package:soft_window_drawer/main.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';


const _window = WindowParams(
  projectName: 'Мягкое окно веранды',
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DisplayUnits.resetForTest();
  });

  tearDown(() => DisplayUnits.resetForTest());

  group('formatLength', () {
    test('миллиметры: 2 080 мм', () {
      expect(formatLength(2080, LengthUnit.mm), '2\u202F080 мм');
    });

    test('сантиметры: 208,0 см', () {
      expect(formatLength(2080, LengthUnit.cm), '208,0 см');
    });

    test('278,6 мм и 27,9 см', () {
      expect(formatLength(278.6, LengthUnit.mm), '278,6 мм');
      expect(formatLength(278.6, LengthUnit.cm), '27,9 см');
    });

    test('подпись единицы и площадь', () {
      expect(unitSuffix(LengthUnit.mm), 'мм');
      expect(unitSuffix(LengthUnit.cm), 'см');
      expect(formatArea(1.7572), '1,76 м²');
    });
  });

  group('текущая единица', () {
    test('по умолчанию мм, прежние подписи не меняются', () {
      expect(DisplayUnits.unit, LengthUnit.mm);
      expect(formatMm(2080), '2\u202F080');
      expect(formatMm(278.6, decimals: 1), '278,6');
      expect(formatSignedMm(120), '+120');
    });

    test('в см formatMm пересчитывает, подпись — см', () async {
      await DisplayUnits.setUnit(LengthUnit.cm);
      expect(DisplayUnits.unit, LengthUnit.cm);
      expect(formatMm(2080), '208,0');
      expect(formatMm(278.6), '27,9');
      expect(formatSignedMm(-120), '−12,0');
      expect(unitSuffix(), 'см');
      expect(formatFastenerSpanMm(278.6), '27,9');
    });

    test('выбор сохраняется в shared_preferences и читается при запуске', () async {
      await DisplayUnits.setUnit(LengthUnit.cm);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(DisplayUnits.storageKey), 'cm');

      DisplayUnits.resetForTest();
      await DisplayUnits.load();
      expect(DisplayUnits.unit, LengthUnit.cm);
    });
  });

  group('расчёты не зависят от единицы', () {
    const project = OrderProject(windows: [_window]);
    final prices = const PriceList.defaults();

    test('JSON заказа одинаков в мм и в см', () async {
      final inMm = jsonEncode(orderToJson(project));
      await DisplayUnits.setUnit(LengthUnit.cm);
      final inCm = jsonEncode(orderToJson(project));
      expect(inCm, inMm);
    });

    test('смета и площади одинаковы в мм и в см', () async {
      final inMm = Estimate.of(project, prices);
      final specMm = WindowSpec.of(_window);
      final filmMm = specMm.filmCutAreaWithShrinkageM2;
      final productMm = specMm.productAreaM2;

      await DisplayUnits.setUnit(LengthUnit.cm);
      final inCm = Estimate.of(project, prices);
      final specCm = WindowSpec.of(_window);

      expect(inCm.total, inMm.total);
      expect(inCm.subtotal, inMm.subtotal);
      expect(specCm.filmCutAreaWithShrinkageM2, filmMm);
      expect(specCm.productAreaM2, productMm);
      // Названия строк могут содержать подписи в см/мм — это отображение.
      // Количества, цены и суммы обязаны совпасть до копейки.
      expect(
        [for (final line in inCm.lines) (line.quantity, line.amount)],
        [for (final line in inMm.lines) (line.quantity, line.amount)],
      );
    });

    test('лист «Раскрой»: размеры прямоугольника в см, площадь та же', () async {
      final pieceMm = CutPiece.ofSpec(WindowSpec.of(_window));
      await DisplayUnits.setUnit(LengthUnit.cm);
      final pieceCm = CutPiece.ofSpec(WindowSpec.of(_window));

      expect(pieceCm.widthMm, pieceMm.widthMm);
      expect(pieceCm.heightMm, pieceMm.heightMm);
      expect(pieceCm.areaM2, pieceMm.areaM2);
      expect(
        '${formatMm(pieceCm.widthMm)} ${unitSuffix()}',
        '${(pieceMm.widthMm / 10).toStringAsFixed(1).replaceAll('.', ',')} см',
      );
      // Подписи чертежа/раскроя используют те же formatMm и unitSuffix.
      final spec = WindowSpec.of(_window);
      expect(
        '${formatMm(spec.filmCutWidthWithShrinkage)} ${unitSuffix()}',
        contains('см'),
      );
    });
  });

  test('подписи чертежа, раскроя и техкарты переходят в см', () async {
    await DisplayUnits.setUnit(LengthUnit.cm);
    final spec = WindowSpec.of(_window);

    // Чертёж: шаг люверсов и расстояния между креплениями.
    expect(spec.eyeletStepLabel, contains('см'));
    final labels = fastenerSpanLabels(spec, pxPerMm: 0.377);
    expect(labels, isNotEmpty);
    expect(labels.any((label) => label.text.contains('см')), isTrue);

    // «Расходы»: расход окантовки больше не прибит к сантиметрам.
    final summary = CostsSummary(const OrderProject(windows: [_window]));
    expect(summary.edgeConsumptionLabels, isNotEmpty);
    expect(summary.edgeConsumptionLabels.first, contains('см'));

    // «Техкарта»: габарит и размеры операций — в см.
    final card = TechCard.forWindow(_window);
    expect(card.dimensionsLabel, endsWith('см'));
    expect(
      card.operations
          .expand((operation) => operation.materials)
          .any((material) => material.size.contains('см')),
      isTrue,
    );
  });

  testWidgets('переключатель внизу экрана сохраняет выбор и перерисовывает', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    DisplayUnits.resetForTest();
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('length-unit-switch'));
    expect(switchFinder, findsOneWidget);

    await tester.tap(find.byKey(const Key('unit-cm')));
    await tester.pumpAndSettle();

    expect(DisplayUnits.unit, LengthUnit.cm);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(DisplayUnits.storageKey), 'cm');
    // Нижняя строка и панель перестроились: размеры показаны в см.
    expect(find.textContaining('см'), findsWidgets);
    expect(
      find.textContaining('150,0×252,0 см'),
      findsWidgets,
      reason: 'выбранное окно в нижней строке пересчитано в см',
    );

    await tester.tap(find.byKey(const Key('unit-mm')));
    await tester.pumpAndSettle();
    expect(DisplayUnits.unit, LengthUnit.mm);
    expect(prefs.getString(DisplayUnits.storageKey), 'mm');
  });
}
