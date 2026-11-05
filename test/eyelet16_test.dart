import 'package:flutter_test/flutter_test.dart';

import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  test('люверс Ø16 — отдельный тип и круглая геометрия', () {
    final type = EyeletType.round16;
    expect(type.isRound, isTrue);
    expect(type.holeWidth, 16);
    expect(type.label, contains('16'));
    expect(type.displayLabel, contains('Ø16'));
    expect(type.sizeLabel, contains('16'));
    expect(
      const PriceList.defaults().eyeletPerEach(type),
      const PriceList.defaults().eyeletPerEach(EyeletType.round10),
    );
  });

  test('масштаб креплений ограничен 60–180 %', () {
    const options = DrawingOptions();
    expect(options.copyWith(fastenerScale: 2.5).fastenerScale, 1.8);
    expect(options.copyWith(fastenerScale: 0.1).fastenerScale, 0.6);
    expect(options.copyWith(fastenerScale: 1.3).fastenerScale, 1.3);
  });
}
