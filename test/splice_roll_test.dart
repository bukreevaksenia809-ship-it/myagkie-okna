import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/roll_plan.dart';
import 'package:soft_window_drawer/services/tech_card.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

void main() {
  const params = WindowParams(
    bottomWidth: 2100,
    topWidth: 2100,
    leftHeight: 2000,
    rightHeight: 2000,
    rollBottom: 100,
    rollTop: 100,
    rollLeft: 100,
    rollRight: 100,
    spliceStripMm: 10,
    pvcHeightAllowanceEnabled: false,
  );
  const project = OrderProject(windows: [params]);

  test('раскладка делит полотно на основу и полосу', () {
    final plans = buildRollPlans(project);
    expect(plans, hasLength(1));
    final plan = plans.first;
    expect(plan.layout.placements, hasLength(2));
    expect(plan.layout.warnings, isEmpty);
    final widths = [
      for (final placement in plan.layout.placements) placement.piece.width,
    ]..sort();
    expect(widths, [10, 2000]);
  });

  test('лист раскроя показывает две заготовки', () {
    final spec = WindowSpec.of(params);
    final pieces = CutPiece.piecesOfSpec(spec);
    expect(pieces, hasLength(2));
    expect(
      pieces.map((piece) => piece.widthMm).reduce((a, b) => a + b),
      closeTo(spec.filmCutWidthWithShrinkage, 0.001),
    );
  });

  test('техкарта содержит спайку полотна', () {
    final card = TechCard.forWindow(params);
    expect(
      card.operations.any((operation) => operation.title == 'Спайка полотна'),
      isTrue,
    );
  });
}
