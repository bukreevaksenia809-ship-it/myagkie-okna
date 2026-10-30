import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/tech_card.dart';

void main() {
  const cutout = Cutout(
    width: 300,
    height: 400,
    centerXMm: 500,
    centerYMm: 700,
    edgingMm: 40,
    eyeletCount: 8,
  );

  test('окантовка и люверсы выреза сохраняются в JSON', () {
    final params = const WindowParams().addCutout(cutout);
    final restored = windowFromJson(windowToJson(params));
    expect(restored.cutouts.single.edgingMm, 40);
    expect(restored.cutouts.single.eyeletCount, 8);
  });

  test('смета добавляет окантовку и люверсы только при их наличии', () {
    const base = OrderProject(windows: [WindowParams()]);
    final withCutout = OrderProject(
      windows: [const WindowParams().addCutout(cutout)],
    );
    final prices = const PriceList.defaults();
    final before = Estimate.of(base, prices);
    final after = Estimate.of(withCutout, prices);
    expect(after.total, greaterThan(before.total));
    expect(after.lines.any((line) => line.title == 'Окантовка вырезов'), isTrue);
    expect(after.lines.any((line) => line.title == 'Люверсы в вырезах'), isTrue);

    final plainCutout = OrderProject(
      windows: [
        const WindowParams().addCutout(
          const Cutout(width: 300, height: 300, centerXMm: 500, centerYMm: 500),
        ),
      ],
    );
    final plain = Estimate.of(plainCutout, prices);
    expect(plain.lines.any((line) => line.title == 'Окантовка вырезов'), isFalse);
    expect(plain.lines.any((line) => line.title == 'Люверсы в вырезах'), isFalse);
  });

  test('техкарта перечисляет окантовку и люверсы выреза', () {
    final card = TechCard.forWindow(const WindowParams().addCutout(cutout));
    final materialText = card.operations
        .expand((operation) => operation.materials)
        .map((material) => '${material.name} ${material.note}')
        .join('\n');
    expect(materialText, contains('окантовка 40'));
    expect(materialText, contains('люверсов 8'));
  });
}
