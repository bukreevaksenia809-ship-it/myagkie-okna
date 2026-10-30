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

  test('режим «шаг + остаток» держит 300 мм, последний промежуток 200 мм', () {
    final xs = bottomXs(base.copyWith(eyeletEvenSpacing: false));
    expect(xs, hasLength(8));
    final gaps = [
      for (var i = 1; i < xs.length; i++) xs[i] - xs[i - 1],
    ];
    expect(gaps.take(6), everyElement(closeTo(300, 0.01)));
    expect(gaps.last, closeTo(150, 0.01));
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
