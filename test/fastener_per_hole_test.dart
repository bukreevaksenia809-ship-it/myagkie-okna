import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';

WindowParams _manualBottom() {
  final positions = <EyeletPosition>[
    for (var i = 0; i < 10; i++)
      EyeletPosition(
        side: EdgeSide.bottom,
        fraction: 0.1 + i * 0.08,
        kind: MarkerKind.roundEyelet,
      ),
    const EyeletPosition(
      side: EdgeSide.bottom,
      fraction: 0.92,
      kind: MarkerKind.metalFrenchLock,
    ),
  ];
  return WindowParams(
    windowType: WindowType.lifting,
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 2000,
    rightHeight: 2000,
    fastenerType: FastenerType.metalFrenchLock,
    eyeletPositions: positions,
    manualEyeletSides: const [EdgeSide.bottom],
  );
}

void main() {
  test('ручные люверсы и замок считаются отдельно, без задвоения', () {
    final spec = WindowSpec.of(_manualBottom());
    final bottomEyelets = spec.layers.standaloneEyelets
        .where((eyelet) => eyelet.side == WindowSide.bottom)
        .toList();
    expect(bottomEyelets, hasLength(10));
    expect(
      spec.layers.manualFasteners
          .where((fastener) => fastener.type == FastenerType.metalFrenchLock)
          .length,
      1,
    );
    final single = CostsSummary(OrderProject(windows: [_manualBottom()]));
    expect(
      single.eyeletsByType.values.fold<int>(0, (a, b) => a + b),
      lessThan(11 + 20),
    );
    expect(
      single.fastenerCount[FastenerType.metalFrenchLock] ?? 0,
      greaterThanOrEqualTo(1),
    );
  });

  test('смета пишет отдельно люверсы и французский замок', () {
    final estimate = Estimate.of(
      OrderProject(
        windows: [
          _manualBottom().copyWith(fastenerType: FastenerType.eyeletsOnly),
        ],
      ),
      const PriceList.defaults(),
    );
    final eyelets = estimate.lines.where(
      (line) => line.title.startsWith('Люверсы'),
    );
    final locks = estimate.lines.where(
      (line) => line.title == 'Французский замок',
    );
    expect(eyelets, isNotEmpty);
    expect(
      eyelets.fold<double>(0, (sum, line) => sum + line.quantity),
      greaterThanOrEqualTo(19),
    );
    expect(locks, isNotEmpty);
    expect(locks.fold<double>(0, (sum, line) => sum + line.quantity), 1);
  });

  test('автоматический крепёж не остаётся в строке люверсов', () {
    const params = WindowParams(
      windowType: WindowType.lifting,
      fastenerType: FastenerType.turnBuckles,
    );
    final spec = WindowSpec.of(params);
    expect(spec.layers.autoFastenerEyelets, isNotEmpty);
    final bottomOrSide = spec.layers.standaloneEyelets.where(
      (eyelet) => eyelet.side != WindowSide.top && !eyelet.isCorner,
    );
    expect(bottomOrSide, isEmpty);
  });
}
