import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

void main() {
  testWidgets('четыре окна помещаются на одну A4', (tester) async {
    const project = OrderProject(
      windows: [WindowParams(), WindowParams(), WindowParams(), WindowParams()],
      sheetMode: SheetMode.grid,
      gridColumns: 0,
    );
    expect(DrawingSheet.a4PageCount(project), 1);
    final plan = DrawingSheet.optimizedGridPlan(
      project,
      DrawingSheet.optimizedGridArea(),
    );
    expect(plan, isNotNull);
    expect(plan!.cells, hasLength(4));
    expect(plan.minScale, greaterThan(0));
    expect(testFontFamily, isNotEmpty);
  });
}
