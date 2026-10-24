import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';

/// Французские замки считаются по вертикали:
/// `ceilEven(Σ(левая + правая высота) / шаг) + 2` — один раз на заказ.
void main() {
  WindowParams lockWindow({
    double height = 2520,
    double step = 350,
    FilmMaterial material = FilmMaterial.clearPvc,
    FastenerType fastener = FastenerType.frenchLocks,
  }) =>
      WindowParams(
        bottomWidth: 1500,
        topWidth: 1500,
        leftHeight: height,
        rightHeight: height,
        eyeletStep: step,
        material: material,
        fastenerType: fastener,
      );

  int count(OrderProject project) =>
      CostsSummary(project).fastenerCount[FastenerType.frenchLocks] ?? 0;

  test('одно окно 2520: сумма высот 5040 / 350 → 15 → чётное 16 + 2 = 18', () {
    final project = OrderProject(windows: [lockWindow()]);
    expect(count(project), 18);
  });

  test('ровно чётное не увеличивается: 3500 / 350 = 10 + 2 = 12', () {
    final project = OrderProject(windows: [lockWindow(height: 1750)]);
    expect(count(project), 12);
  });

  test('нечётное округляется вверх до чётного: 4000 / 350 = 11,43 → 12 + 2', () {
    final project = OrderProject(windows: [lockWindow(height: 2000)]);
    // 4000 / 350 = 11.43 → ceil 12 → чётное 12 → +2.
    expect(count(project), 14);
  });

  test('несколько окон: высоты складываются, +2 один раз на заказ', () {
    final project = OrderProject(
      windows: [lockWindow(height: 2520), lockWindow(height: 2000)],
    );
    // 2 × (2520 + 2000) = 9040; 9040 / 350 = 25.83 → 26 → +2 = 28.
    expect(count(project), 28);
  });

  test('шаг крепления берётся из окна (300 мм)', () {
    final project = OrderProject(windows: [lockWindow(step: 300)]);
    // 5040 / 300 = 16.8 → 17 → 18 + 2 = 20.
    expect(count(project), 20);
  });

  test('скрин считается по той же формуле', () {
    final project = OrderProject(
      windows: [lockWindow(material: FilmMaterial.screen, height: 2000)],
    );
    expect(count(project), 14);
  });

  test('без французских замков строки и счётчика нет', () {
    final project = OrderProject(
      windows: [lockWindow(fastener: FastenerType.turnBuckles)],
    );
    expect(
      CostsSummary(project).fastenerCount.containsKey(FastenerType.frenchLocks),
      isFalse,
    );
    final lines = Estimate.of(project, const PriceList.defaults()).lines;
    expect(
      lines.where((line) => line.title == 'Французский замок'),
      isEmpty,
    );
  });

  test('в смете: количество по формуле и цена из прайса', () {
    final project = OrderProject(windows: [lockWindow()]);
    const prices = PriceList.defaults();
    final line = Estimate.of(project, prices).lines.firstWhere(
      (line) => line.title == 'Французский замок',
    );
    expect(line.quantity, 18);
    expect(line.unitPrice, prices.frenchLockPrice);
    expect(line.note, contains('по вертикали'));
    expect(line.note, isNot(contains('в точках люверсов')));
  });

  test('выключенная позиция прайса убирает строку', () {
    final project = OrderProject(windows: [lockWindow()]);
    const prices = PriceList.defaults();
    final disabled = prices.copyWith(
      disabledItems: {...prices.disabledItems, PriceItemKeys.frenchLock},
    );
    final lines = Estimate.of(project, disabled).lines;
    expect(
      lines.where((line) => line.title == 'Французский замок'),
      isEmpty,
    );
  });
}
