import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

void main() {
  const base = WindowParams(
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 2000,
    rightHeight: 2000,
    pvcHeightAllowanceEnabled: false,
    zippers: [ZipperSpec(centered: true, zipWidthMm: 50)],
  );

  testWidgets('подпись размера молнии перетаскивается и сохраняет смещение', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1720, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var project = const OrderProject(windows: [base]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => DrawingSheet(
              project: project,
              onParamsChanged: (params) =>
                  setState(() => project = project.updateSelected(params)),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('drawing-zipper-layer')), findsOneWidget);

    final canvasFinder = find.byKey(const Key('drawing-canvas'));
    final paint = tester.widget<CustomPaint>(canvasFinder);
    final layout = (paint.painter! as WindowDrawingPainter).layout;
    final spec = WindowSpec.of(base);
    final bounds = spec.layers.filmVisibleBounds;
    final band = spec.layers.zipperBands.first;
    final lineY = bounds.bottom - bounds.height * 0.13;
    final p1 = layout.toPx(band.left, lineY);
    final p2 = layout.toPx(band.right, lineY);
    final label = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2 - 18);
    final box = tester.renderObject<RenderBox>(canvasFinder);
    final start = box.localToGlobal(label);

    await tester.dragFrom(start, const Offset(40, 18));
    await tester.pumpAndSettle();

    final offsets = project.selected.zipperLabelOffsets;
    expect(offsets, isNotEmpty);
    final saved = offsets.values.first;
    expect(saved.dxMm.abs() + saved.dyMm.abs(), greaterThan(1));
    expect(tester.takeException(), isNull);
  });
}
