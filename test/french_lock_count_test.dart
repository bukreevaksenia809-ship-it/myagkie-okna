import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';

/// Крепёж считается по чертежу: сколько символов нарисовано, столько и в
/// смете. Люверс под замком отдельной строкой не идёт — замок его заменяет.
void main() {
  WindowParams lockWindow({
    double height = 2520,
    double step = 350,
    FilmMaterial material = FilmMaterial.clearPvc,
    FastenerType fastener = FastenerType.frenchLocks,
  }) => WindowParams(
    bottomWidth: 1500,
    topWidth: 1500,
    leftHeight: height,
    rightHeight: height,
    eyeletStep: step,
    material: material,
    windowType: WindowType.lifting,
    fastenerType: fastener,
  );

  int count(OrderProject project) =>
      CostsSummary(project).fastenerCount[FastenerType.frenchLocks] ?? 0;

  int drawn(OrderProject project) =>
      WindowSpec.of(project.windows.first).layers.movableSideEyelets.length;

  test('замки: сколько точек на чертеже — столько и в смете', () {
    final project = OrderProject(windows: [lockWindow()]);
    expect(drawn(project), greaterThan(0));
    expect(count(project), drawn(project));
  });

  test('люверсы считаются отдельно от замков', () {
    final project = OrderProject(windows: [lockWindow()]);
    final summary = CostsSummary(project);
    final spec = summary.specs.first;
    final eyelets = summary.eyeletsByType.values.fold<int>(
      0,
      (sum, value) => sum + value,
    );
    expect(eyelets, spec.layers.standaloneEyelets.length);
    expect(eyelets, lessThan(spec.layers.eyelets.length));
  });

  test('несколько окон: количество складывается по чертежам', () {
    final project = OrderProject(
      windows: [lockWindow(), lockWindow(height: 2000)],
    );
    final expected = [
      for (final window in project.windows)
        WindowSpec.of(window).layers.movableSideEyelets.length,
    ].fold<int>(0, (sum, value) => sum + value);
    expect(count(project), expected);
  });

  test('скрин считается по чертежу', () {
    final project = OrderProject(
      windows: [lockWindow(material: FilmMaterial.screen, height: 2000)],
    );
    expect(drawn(project), greaterThan(0));
    expect(count(project), drawn(project));
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

  test('в смете: количество по чертежу и цена из прайса', () {
    final project = OrderProject(windows: [lockWindow()]);
    const prices = PriceList.defaults();
    final line = Estimate.of(project, prices).lines.firstWhere(
      (line) => line.title == 'Французский замок',
    );
    expect(line.quantity, count(project));
    expect(line.unitPrice, prices.frenchLockPrice);
    expect(line.note, contains('по чертежу'));
    expect(line.note, isNot(contains('по вертикали')));
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
