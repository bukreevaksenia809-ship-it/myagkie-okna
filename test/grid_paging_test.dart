import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

const _window = WindowParams(
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 2000,
  rightHeight: 2000,
);

OrderProject _project(int count) => OrderProject(
  windows: [for (var i = 0; i < count; i++) _window],
  sheetMode: SheetMode.grid,
  gridColumns: 0,
);

void main() {
  setUpAll(loadRealFonts);

  test(
    '5 окон — две страницы A4: первые четыре на первой, пятое на второй',
    () {
      final project = _project(5);
      expect(DrawingSheet.a4PageCount(project), 2);
    },
  );

  test('8 окон — две страницы по четыре, а не ряды по три', () {
    final project = _project(8);
    expect(DrawingSheet.a4PageCount(project), 2);
    expect(DrawingSheet.a4PageCount(_project(9)), 3);
  });

  testWidgets('5 окон: 2×2 на первой странице, пятое — крупно на второй', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height * 2 + 40,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: _project(5),
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final r1 = tester.getRect(find.byKey(const Key('drawing-cell-1')));
    final r2 = tester.getRect(find.byKey(const Key('drawing-cell-2')));
    final r3 = tester.getRect(find.byKey(const Key('drawing-cell-3')));
    final r4 = tester.getRect(find.byKey(const Key('drawing-cell-4')));
    final r5 = tester.getRect(find.byKey(const Key('drawing-cell-5')));

    // Первая страница — 2×2: 1 и 2 в одной строке, 3 и 4 во второй.
    expect(r1.top, closeTo(r2.top, 1.5));
    expect(r3.top, closeTo(r4.top, 1.5));
    expect(r3.top, greaterThanOrEqualTo(r1.bottom - 0.5));
    expect(r1.left, closeTo(r3.left, 1.5));
    expect(r2.left, closeTo(r4.left, 1.5));
    expect(r2.right, greaterThan(r1.right));

    // Пятое окно начинается ниже первой страницы (вторая страница).
    expect(r5.top, greaterThanOrEqualTo(r4.bottom - 0.5));
    // И занимает заметно больше ширины, чем ячейка 2×2.
    expect(r5.width, greaterThan(r1.width));
  });
}
