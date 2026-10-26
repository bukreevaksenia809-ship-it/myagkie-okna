import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

void main() {
  const triangle = WindowParams(
    windowType: WindowType.triangle,
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 1500,
    rightHeight: 1500,
    rollBottom: 200,
    rollTop: 200,
    rollLeft: 200,
    rollRight: 200,
  );

  const house = WindowParams(
    windowType: WindowType.house,
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 1800,
    rightHeight: 1800,
    roofHeightMm: 500,
    rollBottom: 200,
    rollTop: 200,
    rollLeft: 200,
    rollRight: 200,
  );

  test('треугольник: площадь, периметр, люверсы и раскрой', () {
    final spec = WindowSpec.of(triangle);
    expect(spec.productAreaM2, closeTo(1.5, 1e-9));
    expect(
      spec.outerPerimeter,
      closeTo(2000 + 2 * 1802.775638, 1e-3),
    );
    expect(spec.eyeletCount, greaterThan(0));
    expect(spec.filmCutAreaM2, lessThan(spec.productAreaM2));
    expect(spec.filmCutWidth, lessThan(2000));
    final piece = CutPiece.ofSpec(spec);
    expect(piece.allContours, hasLength(1));
    expect(piece.widthMm, lessThan(2000));
    expect(spec.edgeConsumption.keys, contains(200.0));
    expect(spec.edgeConsumption[200.0], closeTo(spec.outerPerimeter, 1e-3));
  });

  test('домик: стена + крыша, площадь и раскрой', () {
    final spec = WindowSpec.of(house);
    expect(spec.productAreaM2, closeTo(3.1, 1e-9));
    expect(
      spec.outerPerimeter,
      closeTo(2000 + 2 * 1300 + 2 * 1118.033988, 1e-3),
    );
    // Углы ската при инсете срезаются сильнее вертикальной стены.
    expect(spec.filmCutWidth, lessThan(2000));
    expect(spec.filmCutWidth, greaterThan(1700));
    expect(spec.eyeletCount, greaterThan(0));
    expect(CutPiece.ofSpec(spec).allContours, hasLength(1));
  });

  test('смета фигуры: полотно, окантовка и люверсы', () {
    final estimate = Estimate.of(
      const OrderProject(windows: [house]),
      const PriceList.defaults(),
    );
    final titles = estimate.lines.map((line) => line.title).join(' | ');
    expect(titles, contains('Полотно'));
    expect(titles, contains('Окантовка'));
    expect(titles, contains('Люверс'));
    expect(estimate.total, greaterThan(0));
  });

  test('поля формы переживают JSON', () {
    final restored = windowFromJson(windowToJson(house));
    expect(restored.windowType, WindowType.house);
    expect(restored.roofHeightMm, 500);
    expect(restored.roofOverhangMm, 0);
  });

  test('аварийные размеры не дают миллионы люверсов', () {
    final huge = WindowSpec.of(
      triangle.copyWith(bottomWidth: 20000, leftHeight: 20000),
    );
    expect(huge.eyeletCount, lessThanOrEqualTo(6000));
    final tiny = WindowSpec.of(
      triangle.copyWith(bottomWidth: 100, leftHeight: 100),
    );
    expect(tiny.eyeletCount, greaterThan(0));
    expect(tiny.productAreaM2, greaterThan(0));
  });

  test('смещение вершины и свес меняют контур, площадь остаётся корректной', () {
    final shifted = WindowSpec.of(
      triangle.copyWith(apexOffsetMm: 300),
    );
    expect(shifted.productAreaM2, closeTo(1.5, 1e-9));
    final overhang = WindowSpec.of(house.copyWith(roofOverhangMm: 100));
    expect(overhang.productAreaM2, greaterThan(3.1));
  });
}
