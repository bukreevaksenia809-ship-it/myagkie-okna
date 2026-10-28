import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/inner_size.dart';

void main() {
  test('внутренний 1000×1000 + окантовка 100/200 → наружный', () {
    const params = WindowParams(
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2000,
      rightHeight: 2000,
      rollBottom: 200,
      rollTop: 200,
      rollLeft: 100,
      rollRight: 100,
    );
    final outer = outerSizeFromInner(params, 1000, 1000);
    // Готовые полосы: низ/верх 100, лево/право 50.
    expect(outer.width, 1100);
    expect(outer.height, 1200);
  });

  test('обратный пересчёт даёт те же 1000×1000', () {
    const params = WindowParams(
      bottomWidth: 1100,
      topWidth: 1100,
      leftHeight: 1200,
      rightHeight: 1200,
      rollBottom: 200,
      rollTop: 200,
      rollLeft: 100,
      rollRight: 100,
    );
    final inner = innerSizeFromOuter(params);
    expect(inner.width, 1000);
    expect(inner.height, 1000);
  });
}
