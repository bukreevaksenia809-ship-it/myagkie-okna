import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';
import 'package:soft_window_drawer/widgets/tech_card_sheet.dart';

/// Составное окно в UI: панель, чертёж, раскрой, смета и техкарта.
void main() {
  const composite = WindowParams(
    windowType: WindowType.composite,
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 2000,
    rightHeight: 2000,
    composite: CompositeSpec(
      side: EdgeSide.bottom,
      width: 900,
      depth: 500,
      material: FilmMaterial.screen,
    ),
  );
  const project = OrderProject(windows: [composite]);

  Widget host(Widget child) => MaterialApp(home: Scaffold(body: child));

  testWidgets('панель: «Сделать составным» включает блок и меняет модель', (
    tester,
  ) async {
    // Панель — ленивый ListView: даём высокое окно, чтобы блок был построен.
    await tester.binding.setSurfaceSize(const Size(420, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var current = const OrderProject();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setState) => ParamsPanel(
                project: current,
                issues: const [],
                onChanged: (value) => setState(() => current = value),
                onReset: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(find.byKey(const Key('make-composite')));
    await tester.tap(find.byKey(const Key('make-composite')));
    await tester.pumpAndSettle();

    expect(current.selected.windowType, WindowType.composite);
    expect(current.selected.material, FilmMaterial.clearPvc);
    expect(find.byKey(const Key('composite-summary')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('composite-side-left')),
    );
    await tester.tap(find.byKey(const Key('composite-side-left')));
    await tester.pumpAndSettle();
    expect(current.selected.composite.side, EdgeSide.left);

    await tester.ensureVisible(
      find.byKey(const Key('composite-seam-diagonal')),
    );
    await tester.tap(find.byKey(const Key('composite-seam-diagonal')));
    await tester.pumpAndSettle();
    expect(current.selected.composite.seam, CompositeSeam.diagonal);
    expect(current.selected.hasDiagonalSeam, isTrue);
  });

  testWidgets('чертёж составного окна строится без исключений', (
    tester,
  ) async {
    await tester.pumpWidget(host(const DrawingSheet(project: project)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('раскрой составного окна строится без исключений', (
    tester,
  ) async {
    await tester.pumpWidget(host(const CutSheet(project: project)));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('раскрой: у контуров свои материалы — ПВХ и скрин', () {
    final piece = CutPiece.ofSpec(WindowSpec.of(composite));
    expect(piece.contours, hasLength(2));
    expect(piece.materialFor(0), FilmMaterial.clearPvc);
    expect(piece.materialFor(1), FilmMaterial.screen);
  });

  testWidgets('смета: второй материал и спайка отдельными строками', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const EstimateSheet(project: project, prices: PriceList.defaults())),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Спайка составного окна'), findsWidgets);
    expect(find.textContaining('Полотно: Скрин'), findsWidgets);
  });

  testWidgets('техкарта: второй сегмент и шов в операциях', (tester) async {
    await tester.pumpWidget(host(const TechCardSheet(project: project)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('Второй сегмент'), findsWidgets);
    expect(find.textContaining('Спайка составного окна'), findsWidgets);
  });
}
