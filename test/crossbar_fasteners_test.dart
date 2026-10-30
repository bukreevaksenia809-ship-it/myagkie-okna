import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/crossbar.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';

void main() {
  const crossbar = CrossbarSpec(
    positionMm: 1000,
    widthMm: 100,
    fastenerCount: 5,
  );

  test('крепления на перемычке сохраняются в JSON', () {
    final json = crossbar.toJson();
    expect(json['fastenerCount'], 5);
    expect(CrossbarSpec.fromJson(json).fastenerCount, 5);
  });

  test('смета считает крепления на перемычке', () {
    final project = OrderProject(
      windows: [
        const WindowParams(
          crossbars: [crossbar],
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
        ),
      ],
    );
    final estimate = Estimate.of(project, const PriceList.defaults());
    final line = estimate.lines
        .where((line) => line.title == 'Крепления на перемычках')
        .single;
    expect(line.quantity, 5);
    expect(line.amount, greaterThan(0));
  });
}
