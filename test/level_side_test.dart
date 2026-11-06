import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  const base = WindowParams(
    bottomWidth: 1200,
    topWidth: 1000,
    leftHeight: 1000,
    rightHeight: 1200,
  );

  double topOffset(WindowParams params) =>
      WindowGeometry.of(params).topOffset;

  test('левая кромка ровно — верх прижат к левому краю', () {
    expect(topOffset(base.copyWith(levelLeft: true)), 0);
  });

  test('правая кромка ровно — верх прижат к правому краю', () {
    expect(topOffset(base.copyWith(levelRight: true)), 200);
  });

  test('обе кромки ровно — верх по центру', () {
    expect(
      topOffset(base.copyWith(levelLeft: true, levelRight: true)),
      100,
    );
  });

  test('комбинация с «низ ровно» сохраняется в JSON', () {
    final params = base.copyWith(
      levelEdge: LevelEdge.bottom,
      levelLeft: true,
      levelRight: true,
    );
    final restored = windowFromJson(windowToJson(params));
    expect(restored.levelEdge, LevelEdge.bottom);
    expect(restored.levelLeft, isTrue);
    expect(restored.levelRight, isTrue);
  });
}
