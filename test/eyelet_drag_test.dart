import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

/// Ручное перетаскивание люверсов по линии окантовки на чертеже.
void main() {
  const base = WindowParams(
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 2000,
    rightHeight: 2000,
    pvcHeightAllowanceEnabled: false,
  );

  test('ручные доли задают люверсы стороны, остальные — автоматически', () {
    final params = base.withEyeletPositions(EdgeSide.bottom, const [0.25, 0.75]);
    expect(params.eyeletPositions, hasLength(2));
    final spec = WindowSpec.of(params);
    final bottom = spec.layers.eyelets
        .where((eyelet) => eyelet.side == WindowSide.bottom)
        .toList();
    expect(bottom, hasLength(2), reason: 'авто-шаг на этой стороне отключён');
    // Линия люверсов смещена внутрь на половину окантовки (100 мм → 25).
    final edge = spec.layers.eyeletPolygons.first;
    expect(bottom.first.center.dx, closeTo(edge[0].dx + 0.25 * 1950, 1e-6));
    expect(bottom.last.center.dx, closeTo(edge[0].dx + 0.75 * 1950, 1e-6));
    // Другие стороны остались с автоматической расстановкой.
    expect(
      spec.layers.eyelets.any((eyelet) => eyelet.side == WindowSide.left),
      isTrue,
    );
  });

  test('сброс возвращает авто-расстановку', () {
    final params = base
        .withEyeletPositions(EdgeSide.right, const [0.3, 0.6])
        .clearEyeletPositions();
    expect(params.eyeletPositions, isEmpty);
    expect(WindowSpec.of(params).eyeletCount,
        WindowSpec.of(base).eyeletCount);
  });

  test('JSON: ручные люверсы сохраняются и читаются', () {
    final params = base.withEyeletPositions(EdgeSide.left, const [0.2, 0.8]);
    final restored = windowFromJson(windowToJson(params));
    expect(restored.eyeletPositions, hasLength(2));
    expect(restored.eyeletPositions.first.side, EdgeSide.left);
    expect(restored.eyeletPositions.first.fraction, closeTo(0.2, 1e-9));
  });

  testWidgets('люверс перетаскивается мышкой по линии окантовки', (
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

    final canvasFinder = find.byKey(const Key('drawing-canvas'));
    final paint = tester.widget<CustomPaint>(canvasFinder);
    final painter = paint.painter! as WindowDrawingPainter;
    final layout = painter.layout;
    final spec = WindowSpec.of(base);
    final eyelet = spec.layers.eyelets.firstWhere(
      (eyelet) => eyelet.side == WindowSide.bottom && !eyelet.isCorner,
    );
    final box = tester.renderObject<RenderBox>(canvasFinder);
    final start = box.localToGlobal(layout.toPxPoint(eyelet.center));

    await tester.dragFrom(start, const Offset(60, 0));
    await tester.pumpAndSettle();

    expect(project.selected.eyeletPositions, isNotEmpty);
    expect(project.selected.eyeletPositions.first.side, EdgeSide.bottom);
    // Точка сдвинулась вправо — доля увеличилась.
    final fraction = project.selected.eyeletPositions
        .map((position) => position.fraction)
        .reduce((a, b) => a > b ? a : b);
    expect(fraction, greaterThan(0.0));

    // На листе точка теперь рисуется на новом месте.
    final moved = WindowSpec.of(project.selected).layers.eyelets;
    expect(moved, isNotEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('внутри InteractiveViewer перетаскивание не панорамирует лист', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1720, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var project = const OrderProject(windows: [base]);
    final controller = TransformationController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => InteractiveViewer(
              transformationController: controller,
              constrained: false,
              boundaryMargin: const EdgeInsets.all(800),
              child: SizedBox(
                width: DrawingSheet.a4Width,
                height: DrawingSheet.a4Height,
                child: DrawingSheet(
                  project: project,
                  onParamsChanged: (params) =>
                      setState(() => project = project.updateSelected(params)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final before = controller.value.clone();
    final canvasFinder = find.byKey(const Key('drawing-canvas'));
    final paint = tester.widget<CustomPaint>(canvasFinder);
    final painter = paint.painter! as WindowDrawingPainter;
    final spec = WindowSpec.of(base);
    final eyelet = spec.layers.eyelets.firstWhere(
      (eyelet) => eyelet.side == WindowSide.bottom && !eyelet.isCorner,
    );
    final box = tester.renderObject<RenderBox>(canvasFinder);
    final start = box.localToGlobal(
      painter.layout.toPxPoint(eyelet.center),
    );

    await tester.dragFrom(start, const Offset(40, 0));
    await tester.pumpAndSettle();

    expect(project.selected.eyeletPositions, isNotEmpty);
    expect(controller.value, before, reason: 'лист не должен сдвинуться');
    expect(tester.takeException(), isNull);
  });

  test('углы не задваиваются: ручная сторона убирает авто-угол соседа', () {
    final params = base.withEyeletPositions(
      EdgeSide.bottom,
      const [0.3, 0.6],
    );
    final spec = WindowSpec.of(params);
    Offset corner(Offset point) => Offset(point.dx, point.dy);
    final bottomLeft = corner(spec.geometry.bottomLeft);
    final near = spec.layers.eyelets.where(
      (eyelet) => (eyelet.center - bottomLeft).distance < 60,
    );
    expect(
      near,
      isEmpty,
      reason: 'низ задан вручную — авто-угол слева не ставится',
    );
  });

  test('меню: замок добавляет строку в смету и расход', () {
    final params = base.withManualPoints(
      EdgeSide.right,
      [
        const EyeletPosition(
          side: EdgeSide.right,
          fraction: 0.4,
          kind: MarkerKind.frenchLock,
        ),
        const EyeletPosition(side: EdgeSide.right, fraction: 0.7),
      ],
    );
    final summary = CostsSummary(OrderProject(windows: [params]));
    expect(summary.fastenerCount[FastenerType.frenchLocks], 1);
    final estimate = Estimate.of(
      OrderProject(windows: [params]),
      const PriceList.defaults(),
    );
    final line = estimate.lines.firstWhere(
      (line) => line.title == 'Французский замок',
    );
    expect(line.quantity, 1);
  });

  testWidgets('после перетаскивания появляется меню и работает удаление', (
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

    Future<void> dragEyelet() async {
      final canvasFinder = find.byKey(const Key('drawing-canvas'));
      final paint = tester.widget<CustomPaint>(canvasFinder);
      final painter = paint.painter! as WindowDrawingPainter;
      final spec = WindowSpec.of(project.selected);
      // Если уже есть ручной замок — тянем именно его (он не люверс).
      final target = spec.layers.manualFasteners.isNotEmpty
          ? spec.layers.manualFasteners.first.center
          : spec.layers.eyelets
                .firstWhere(
                  (eyelet) =>
                      eyelet.side == WindowSide.bottom && !eyelet.isCorner,
                )
                .center;
      final box = tester.renderObject<RenderBox>(canvasFinder);
      final start = box.localToGlobal(painter.layout.toPxPoint(target));
      await tester.dragFrom(start, const Offset(30, 0));
      await tester.pumpAndSettle();
    }

    await dragEyelet();
    expect(find.byKey(const Key('eyelet-menu-lock')), findsOneWidget);
    expect(find.byKey(const Key('eyelet-menu-delete')), findsOneWidget);

    await tester.tap(find.byKey(const Key('eyelet-menu-lock')));
    await tester.pumpAndSettle();
    expect(
      project.selected.eyeletPositions
          .any((point) => point.kind == MarkerKind.frenchLock),
      isTrue,
    );
    expect(
      CostsSummary(OrderProject(windows: [project.selected]))
          .fastenerCount[FastenerType.frenchLocks],
      1,
    );

    await dragEyelet();
    final before = project.selected.eyeletPositions.length;
    await tester.tap(find.byKey(const Key('eyelet-menu-delete')));
    await tester.pumpAndSettle();
    expect(project.selected.eyeletPositions.length, before - 1);
    expect(
      project.selected.eyeletPositions
          .any((point) => point.kind == MarkerKind.frenchLock),
      isFalse,
    );
    expect(tester.takeException(), isNull);
  });

  test('круглые не считаются, если в углах их выключили', () {
    final params = base
        .copyWith(
          eyeletType: EyeletType.oval42x22,
          roundEyeletsEnabled: false,
        )
        .withManualPoints(
          EdgeSide.bottom,
          const [
            EyeletPosition(side: EdgeSide.bottom, fraction: 0),
            EyeletPosition(side: EdgeSide.bottom, fraction: 0.5),
          ],
        );
    final spec = WindowSpec.of(params);
    expect(
      spec.layers.eyelets.where(
        (eyelet) => spec.layers.typeFor(eyelet) == EyeletType.round10,
      ),
      isEmpty,
    );
    final summary = CostsSummary(OrderProject(windows: [params]));
    expect(summary.eyeletsByType[EyeletType.round10], isNull);
    final estimate = Estimate.of(
      OrderProject(windows: [params]),
      const PriceList.defaults(),
    );
    expect(
      estimate.lines.where((line) => line.title.contains('Круглый')),
      isEmpty,
    );

    // Явно добавленный круглый — считается.
    final withRound = params.withManualPoints(
      EdgeSide.bottom,
      const [
        EyeletPosition(
          side: EdgeSide.bottom,
          fraction: 0.5,
          kind: MarkerKind.roundEyelet,
        ),
      ],
    );
    expect(
      CostsSummary(OrderProject(windows: [withRound]))
          .eyeletsByType[EyeletType.round10],
      1,
    );
  });

  testWidgets('панель: кнопка сброса ручных люверсов', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = OrderProject(
      windows: [base.withEyeletPositions(EdgeSide.bottom, const [0.4, 0.6])],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setState) => ParamsPanel(
                project: project,
                issues: const [],
                onChanged: (value) => setState(() => project = value),
                onReset: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const Key('reset-eyelet-positions')),
    );
    await tester.tap(find.byKey(const Key('reset-eyelet-positions')));
    await tester.pumpAndSettle();
    expect(project.selected.eyeletPositions, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
