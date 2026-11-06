import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/crossbar.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

void main() {
  const base = WindowParams(
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 1000,
    rightHeight: 1000,
    rollBottom: 100,
    rollTop: 100,
    rollLeft: 100,
    rollRight: 100,
    crossbars: [
      CrossbarSpec(positionMm: 450, widthMm: 100, weldMm: 30),
    ],
  );

  test('перемычка во всю ширину делит раскрой и даёт зазор', () {
    final spec = WindowSpec.of(base);
    final single = CutPiece.ofSpec(spec);
    final pieces = CutPiece.piecesOfSpec(spec);
    expect(pieces, hasLength(2));
    expect(pieces.first.windowIndex, 0);
    expect(pieces.first.partLabel, '1.1');
    expect(pieces.last.partLabel, '1.2');
    final total = pieces.fold<double>(0, (sum, piece) => sum + piece.heightMm);
    expect(total + 40, closeTo(single.heightMm, 0.6));
    expect(pieces.first.heightMm, closeTo(pieces.last.heightMm, 0.6));
    expect(
      pieces.first.heightMm,
      closeTo((single.heightMm - 40) / 2, 0.6),
    );
  });

  test('перемычка не во всю длину раскрой не делит', () {
    final spec = WindowSpec.of(
      base.copyWith(
        crossbars: const [
          CrossbarSpec(fullSpan: false, lengthMm: 800, widthMm: 100, weldMm: 30),
        ],
      ),
    );
    expect(CutPiece.piecesOfSpec(spec), hasLength(1));
  });

  test('смета: длина перемычки × 2', () {
    final prices = const PriceList.defaults().copyWith(crossbarPerM: 500);
    final estimate = Estimate.of(
      const OrderProject(windows: [base]),
      prices,
    );
    final line = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Перемычка'),
    );
    final visible = WindowSpec.of(base).layers.filmVisibleBounds;
    expect(line.quantity, closeTo(visible.width / 1000 * 2, 1e-6));
    expect(line.amount, closeTo(line.quantity * 500, 1e-6));
  });

  testWidgets('чертёж с перемычкой строится', (tester) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: const OrderProject(windows: [base]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('перемычки сохраняются в JSON', () {
    final restored = windowFromJson(windowToJson(base));
    expect(restored.crossbars, hasLength(1));
    expect(restored.crossbars.first.widthMm, 100);
    expect(restored.crossbars.first.weldMm, 30);
    expect(restored.crossbars.first.gapMm, 40);
  });
}

// Чертёж с перемычкой не должен падать и должен реально перерисовываться.
