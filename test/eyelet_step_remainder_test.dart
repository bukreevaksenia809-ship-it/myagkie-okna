import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  const base = WindowParams(
    bottomWidth: 2000,
    topWidth: 2000,
    leftHeight: 2000,
    rightHeight: 2000,
    eyeletStep: 300,
    rollBottom: 100,
    rollTop: 100,
    rollLeft: 100,
    rollRight: 100,
  );

  List<double> bottomXs(WindowParams params) {
    final xs = WindowSpec.of(params)
        .layers
        .eyelets
        .where((eyelet) => eyelet.side == WindowSide.bottom)
        .map((eyelet) => eyelet.center.dx)
        .toList()
      ..sort();
    return xs;
  }

  test('режим «равномерно» делит сторону без остатка', () {
    final xs = bottomXs(base);
    expect(xs, hasLength(8));
    final gaps = [
      for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1],
    ];
    for (final gap in gaps) {
      expect(gap, closeTo(1950 / 7, 0.01));
      expect(gap, lessThanOrEqualTo(300));
    }
  });

  test('режим «шаг + остаток»: остаток 150 в начале, далее 300 мм', () {
    // Линия люверсов у ПВХ идёт по середине окантовки: 2000 − 2 × 25 = 1950.
    // 1950 = 6 × 300 + 150, поэтому первый промежуток от стартового угла —
    // остаток 150, а дальше ровный шаг 300 (раньше остаток стоял в конце).
    final xs = bottomXs(base.copyWith(eyeletEvenSpacing: false));
    expect(xs, hasLength(8));
    final gaps = [
      for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1],
    ];
    expect(gaps.first, closeTo(150, 0.01));
    expect(gaps.skip(1), everyElement(closeTo(300, 0.01)));
    expect(xs.first, closeTo(25, 0.01));
    expect(xs.last, closeTo(1975, 0.01));
  });

  test('режим сохраняется в JSON', () {
    expect(
      windowFromJson(windowToJson(base.copyWith(eyeletEvenSpacing: false)))
          .eyeletEvenSpacing,
      isFalse,
    );
  });
}
