import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

void main() {
  testWidgets('нажатие на третье и четвёртое окно выбирает его в панели', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var selected = -1;
    final project = OrderProject(
      windows: [
        for (var i = 0; i < 4; i++)
          WindowParams(
            bottomWidth: 1500,
            topWidth: 1500,
            leftHeight: 2200,
            rightHeight: 2200,
          ),
      ],
      sheetMode: SheetMode.grid,
      gridColumns: 0,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: project,
            onSelectWindow: (index) => selected = index,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('drawing-cell-3')));
    expect(selected, 2);
    await tester.tap(find.byKey(const Key('drawing-cell-4')));
    expect(selected, 3);
  });
}
