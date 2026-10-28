// Пример заказчика: косое окно 3 050/3 050 × 2 140/2 800, полоса 50,
// запайка 20. Проверяем формулу «каждая сторона заготовки = сторона изделия
// − 2 × (готовая полоса) + 2 × запайка» и площадь по формуле Гаусса.
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

/// Пример заказчика. Авто-припуск +10 мм к высоте выключен, чтобы числа
/// совпадали с ручным расчётом: 3 050 − 60 = 2 990 и т. д.
const _customer = WindowParams(
  projectName: 'Косое окно 305',
  drawingNumber: 'КОС-305',
  bottomWidth: 3050,
  topWidth: 3050,
  leftHeight: 2140,
  rightHeight: 2800,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
  weldOverlapMm: 20,
  pvcHeightAllowanceEnabled: false,
);

void main() {
  group('заготовка косого окна по формуле заказчика', () {
    final spec = WindowSpec.of(_customer);

    test(
      'd = 50 − 20 = 30, стороны заготовки 2 990 / 2 740 / 2 990 / 2 080',
      () {
        // Готовая полоса — половина рулона, вычет каждой стороны d = 30 мм.
        expect(WindowParams.finishedEdgeWidth(100), 50);
        expect(_customer.weldOverlapMm, 20);
        expect(spec.blankSideLengths, [2990, 2740, 2990, 2080]);
        expect(spec.filmCutWidth, closeTo(2990, 1e-9));
        expect(spec.filmCutHeight, closeTo(2740, 1e-9));
        // Без припуска и усадки стороны к раскрою те же.
        expect(spec.filmCutSideLengths, [2990, 2740, 2990, 2080]);
      },
    );

    test('форма — та же косая трапеция, а не прямоугольник', () {
      final geometry = spec.layers.blankGeometry;
      expect(geometry.corners, hasLength(4));
      expect(geometry.bottomWidth, closeTo(2990, 1e-9));
      expect(geometry.topWidth, closeTo(2990, 1e-9));
      expect(geometry.leftHeight, closeTo(2080, 1e-9));
      expect(geometry.rightHeight, closeTo(2740, 1e-9));
      // Верх наклонён: фактическая длина верхней кромки больше ширины 2 990
      // (как и у изделия, где «верх 3 050» — ширина, а не длина наклонной).
      final topEdge = (geometry.corners[2] - geometry.corners[3]).distance;
      expect(topEdge, greaterThan(2990));
      expect(topEdge, closeTo(3061.9765, 1e-3));
      // Правая и левая кромки вертикальны и равны высотам заготовки.
      expect(
        (geometry.corners[1] - geometry.corners[2]).distance,
        closeTo(2740, 1e-9),
      );
      expect(
        (geometry.corners[0] - geometry.corners[3]).distance,
        closeTo(2080, 1e-9),
      );
    });

    test('площадь по Гауссу = средняя высота × ширину = 7,2059 м²', () {
      // Ручной расчёт: трапеция с основаниями 2 990 и 2 990 (по ширине) и
      // высотами 2 080 слева и 2 740 справа.
      final manualMm2 = (2080 + 2740) / 2 * 2990;
      expect(manualMm2, closeTo(7205900, 1e-6));
      expect(spec.layers.blankAreaMm2, closeTo(manualMm2, 1e-6));
      expect(spec.filmAreaM2, closeTo(7.2059, 1e-9));
      expect(spec.filmCutAreaM2, closeTo(7.2059, 1e-9));
      // Ручная проверка формулой Гаусса по вершинам.
      final corners = spec.layers.blankCorners;
      var sum = 0.0;
      for (var i = 0; i < corners.length; i++) {
        final a = corners[i];
        final b = corners[(i + 1) % corners.length];
        sum += a.dx * b.dy - b.dx * a.dy;
      }
      expect(sum.abs() / 2, closeTo(manualMm2, 1e-6));
    });

    test('лист «Раскрой»: трапеция с четырьмя подписанными сторонами', () {
      final piece = CutPiece.ofSpec(spec);
      expect(piece.widthMm, closeTo(2990, 1e-9));
      expect(piece.heightMm, closeTo(2740, 1e-9));
      expect(piece.allContours, hasLength(1));
      expect(piece.allContours.first, hasLength(4));
      expect(piece.sideLengths, [2990, 2740, 2990, 2080]);
      expect(piece.areaMm2, closeTo(7205900, 1e-6));
      expect(piece.areaM2, closeTo(7.2059, 1e-9));
      // Контур не прямоугольный: верхняя кромка длиннее нижней по построению.
      final contour = piece.allContours.first;
      final bottom = (contour[1] - contour[0]).distance;
      final top = (contour[3] - contour[2]).distance;
      expect(bottom, closeTo(2990, 1e-6));
      expect(top, greaterThan(bottom + 50));
    });

    test('припуск по ширине растягивает низ и верх, высоты — по высоте', () {
      final withAllowance = WindowSpec.of(
        _customer.copyWith(allowanceWidthMm: 100, allowanceHeightMm: 100),
      );
      // Ширины 2 990 + 100 = 3 090, высоты 2 080/2 740 → 2 180/2 840.
      expect(withAllowance.filmCutWidth, closeTo(2990, 1e-9));
      expect(withAllowance.filmCutHeight, closeTo(2740, 1e-9));
      expect(withAllowance.filmCutWidthWithAllowance, closeTo(3090, 1e-9));
      expect(withAllowance.filmCutHeightWithAllowance, closeTo(2840, 1e-9));
      expect(
        withAllowance.filmCutAreaM2,
        closeTo(7.2059 * 3090 / 2990 * 2840 / 2740, 1e-6),
      );
    });

    test('усадка применяется к обеим осям, площадь растёт в квадрате', () {
      final withShrink = WindowSpec.of(
        _customer.copyWith(shrinkageEnabled: true, shrinkagePercent: 2),
      );
      expect(
        withShrink.filmCutAreaWithShrinkageM2,
        closeTo(withShrink.filmCutAreaM2 * 1.02 * 1.02, 1e-6),
      );
    });

    test('полоса молнии вычитается из ширины, форма остаётся косой', () {
      final withZipper = WindowSpec.of(
        _customer.copyWith(zippers: const [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)]),
      );
      // Молния по центру делит раскрой на два сегмента; габарит не меняется.
      expect(withZipper.zipperBandTotalMm, 0);
      expect(withZipper.filmCutWidth, closeTo(2990, 1e-9));
      expect(withZipper.filmCutHeight, closeTo(2740, 1e-9));
      final piece = CutPiece.ofSpec(withZipper);
      expect(piece.widthMm, closeTo(2990, 1e-9));
      expect(piece.allContours, hasLength(2));
      final contour = piece.allContours.first;
      expect((contour[1] - contour[0]).distance, greaterThan(0));
      final top = (contour[3] - contour[2]).distance;
      expect(top, greaterThan(0));
    });

    test('прямоугольное окно остаётся прямоугольником', () {
      const rect = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        pvcHeightAllowanceEnabled: false,
      );
      final rectSpec = WindowSpec.of(rect);
      expect(rectSpec.blankSideLengths, [1910, 1410, 1910, 1410]);
      final piece = CutPiece.ofSpec(rectSpec);
      final contour = piece.allContours.first;
      for (var i = 0; i < contour.length; i++) {
        final next = contour[(i + 1) % contour.length];
        final side = (next - contour[i]).distance;
        final horizontal = (next.dy - contour[i].dy).abs() < 1e-6;
        expect(horizontal ? side : side, greaterThan(0));
      }
      expect(piece.areaMm2, closeTo(piece.widthMm * piece.heightMm, 1e-6));
    });
  });

  test('документы: расходы, смета и техкарта — та же площадь по контуру', () {
    final project = const OrderProject(windows: [_customer]);
    final summary = CostsSummary(project);
    expect(summary.filmAreaM2, closeTo(7.2059, 1e-9));
    expect(summary.filmAreaWithShrinkageM2, closeTo(7.2059, 1e-9));
    expect(summary.filmNetAreaM2, closeTo(7.2059, 1e-9));
    expect(summary.productAreaM2, closeTo(7.5335, 1e-6));

    final estimate = Estimate.ofWindow(_customer, PriceList.defaults());
    expect(estimate.filmAreaM2, closeTo(7.2059, 1e-9));
    final filmLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    // В смете одна строка «Полотно»: контур 7,2059 + отход
    // прямоугольника 8,1926 − 7,2059 = 8,1926 м².
    expect(filmLine.quantity, closeTo(8.1926, 1e-9));
    expect(filmLine.note, contains('отход'));

    final card = TechCard.forWindow(_customer);
    final areaMaterial = card.operations
        .expand((operation) => operation.materials)
        .firstWhere((material) => material.name.contains('Площадь заготовки'));
    expect(areaMaterial.size, contains('7,21'));
    expect(areaMaterial.note, contains('косой'));
    // В техкарте видны все четыре стороны заготовки, а не только габарит.
    final firstOperation = card.operations.first;
    expect(firstOperation.control, contains('2\u202F990'));
    expect(firstOperation.control, contains('косой'));
  });

  test('Offset из примера: углы заготовки совпадают с ручными', () {
    final spec = WindowSpec.of(_customer);
    final corners = spec.layers.blankCorners;
    // Заготовка вписана в изделие симметрично: вычет 30 мм по каждой
    // кромке, поэтому углы сдвинуты на (30, 30).
    expect(corners[0], const Offset(30, 30));
    expect(corners[1], const Offset(3020, 30));
    expect(corners[2], const Offset(3020, 2770));
    expect(corners[3], const Offset(30, 2110));
  });
}
