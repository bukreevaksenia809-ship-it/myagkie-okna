// Тесты панели параметров: спайка с соседним окном и припуски на раскрой.
//
// Запуск: flutter test test/panel_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';
import 'package:soft_window_drawer/widgets/price_panel.dart';

/// Панель шириной 420 px с живым состоянием: правки уходят в проект.
class _PanelHost extends StatefulWidget {
  const _PanelHost({super.key});

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  OrderProject project = const OrderProject();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: ParamsPanel(
            project: project,
            issues: const [],
            onChanged: (value) => setState(() => project = value),
            onReset: () {},
          ),
        ),
      ),
    );
  }
}

void main() {
  _screenAndWeldRules();
  testWidgets('панель 420: спайка добавляет окно, припуски идут в модель', (
    WidgetTester tester,
  ) async {
    // Узкая панель (420) и очень высокое окно: все разделы построены,
    // по ширине ничего не переполняется.
    tester.view.physicalSize = const Size(420, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // 1. Спецэлементы выбранного окна: молния и вырез.
    await tester.tap(find.text('Добавить молнию'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Добавить вырез'));
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.zippers, hasLength(1));
    expect(hostKey.currentState!.project.selected.cutouts, hasLength(1));
    expect(tester.takeException(), isNull);

    // 2. Спайка: четыре чипа по кругу и кнопки добавления окна стороной.
    expect(find.text('Спаяно снизу'), findsOneWidget);
    expect(find.text('Спаяно справа'), findsOneWidget);
    expect(find.text('Спаяно сверху'), findsOneWidget);
    expect(find.text('Спаяно слева'), findsOneWidget);

    await tester.tap(find.byKey(const Key('add-welded-bottom')));
    await tester.pumpAndSettle();

    final welded = hostKey.currentState!.project;
    expect(welded.windowCount, 2);
    expect(welded.selectedIndex, 1, reason: 'выбрано новое окно спайки');
    expect(welded.windows[0].isWelded(EdgeSide.bottom), isTrue);
    expect(welded.windows[1].isWelded(EdgeSide.top), isTrue);
    // Копия повторяет шаблон: те же размеры, молния и вырез.
    expect(welded.windows[1].bottomWidth, welded.windows[0].bottomWidth);
    expect(welded.windows[1].leftHeight, welded.windows[0].leftHeight);
    expect(welded.windows[1].zippers, hasLength(1));
    expect(welded.windows[1].cutouts, hasLength(1));
    expect(tester.takeException(), isNull);

    // 3. Припуски на раскрой: кнопка раскрывает поля, значения — в модель.
    expect(find.text('Припуски на раскрой'), findsOneWidget);
    await tester.tap(find.text('Припуски на раскрой'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('allowance-width-field')),
      '120',
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('allowance-height-field')),
      '80',
    );
    await tester.pumpAndSettle();

    final withAllowance = hostKey.currentState!.project.selected;
    expect(withAllowance.allowanceWidthMm, 120);
    expect(withAllowance.allowanceHeightMm, 80);
    expect(withAllowance.hasAllowance, isTrue);
    expect(withAllowance.effectiveBottomWidth, withAllowance.bottomWidth + 120);
    expect(withAllowance.effectiveLeftHeight, withAllowance.leftHeight + 80);

    // Строка-итог показывает заготовку плёнки с припуском, а не изделие:
    // припуск влияет только на раскрой.
    final spec = WindowSpec.of(withAllowance);
    expect(
      find.text(
        'Плёнка в раскрое с припуском: '
        '${formatMm(spec.filmCutWidthWithAllowance)} × '
        '${formatMm(spec.filmCutHeightWithAllowance)} мм',
      ),
      findsOneWidget,
    );
    expect(find.byKey(const Key('allowance-cut-size')), findsOneWidget);
    expect(find.byKey(const Key('allowance-reset')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 4. Сброс припусков обнуляет модель и убирает кнопку сброса.
    await tester.tap(find.byKey(const Key('allowance-reset')));
    await tester.pumpAndSettle();
    final reset = hostKey.currentState!.project.selected;
    expect(reset.allowanceWidthMm, 0);
    expect(reset.allowanceHeightMm, 0);
    expect(reset.hasAllowance, isFalse);
    expect(find.byKey(const Key('allowance-reset')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

/// Панель: выбор скрина прячет окантовку и крепёж, запайка и карманы
/// вводятся руками.
void _screenAndWeldRules() {
  testWidgets('панель: скрин, подворот, запайка и карманы', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // --- Скрин: чип рядом с ПВХ ---
    final screenChip = find.text('Скрин');
    await tester.ensureVisible(screenChip);
    await tester.tap(screenChip);
    await tester.pumpAndSettle();

    var params = hostKey.currentState!.project.selected;
    expect(params.material, FilmMaterial.screen);
    expect(params.isScreen, isTrue);
    expect(params.tech, WindowTech.screen);
    // Окантовка и крепёж кроме люверсов спрятаны.
    expect(find.text('Окантовка'), findsNothing);
    expect(find.text('Поворотные скобы'), findsNothing);
    // Подворот задаётся на каждую сторону: четыре поля и подпись заготовки.
    expect(find.byKey(const Key('hem-bottom-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-right-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-top-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-left-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-blank-label')), findsOneWidget);
    // Подворот 60 мм на все стороны: заготовка = готовый размер + 2 × 60.
    for (final key in const [
      'hem-bottom-field',
      'hem-right-field',
      'hem-top-field',
      'hem-left-field',
    ]) {
      await tester.enterText(find.byKey(Key(key)), '60');
      await tester.pumpAndSettle();
    }
    params = hostKey.currentState!.project.selected;
    expect(params.hemBottomMm, 60);
    expect(params.hemRightMm, 60);
    expect(params.hemTopMm, 60);
    expect(params.hemLeftMm, 60);
    final screenSpec = WindowSpec.of(params);
    expect(
      screenSpec.filmCutWidthWithAllowance,
      closeTo(params.bottomWidth + 60 + 60, 1e-9),
    );
    expect(
      screenSpec.filmCutHeightWithAllowance,
      closeTo(params.leftHeight + 60 + 60, 1e-9),
    );
    // Готовое окно панели 1500 × 2520 → заготовка 1620 × 2640 мм.
    expect(screenSpec.filmCutWidthWithAllowance, closeTo(1620, 1e-9));
    expect(screenSpec.filmCutHeightWithAllowance, closeTo(2640, 1e-9));
    // Разные подвороты по сторонам дают разный прирост по осям.
    await tester.enterText(find.byKey(const Key('hem-bottom-field')), '40');
    await tester.enterText(find.byKey(const Key('hem-top-field')), '60');
    await tester.enterText(find.byKey(const Key('hem-right-field')), '50');
    await tester.enterText(find.byKey(const Key('hem-left-field')), '40');
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    final mixedSpec = WindowSpec.of(params);
    expect(mixedSpec.filmCutWidthWithAllowance,
        closeTo(params.bottomWidth + 40 + 50, 1e-9));
    expect(mixedSpec.filmCutHeightWithAllowance,
        closeTo(params.leftHeight + 40 + 60, 1e-9));
    expect(tester.takeException(), isNull);

    // --- Карман сверху и снизу ---
    final topPocket = find.text('Карман сверху (по верхней кромке)');
    await tester.ensureVisible(topPocket);
    await tester.tap(topPocket);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocketTop, isTrue);
    expect(params.pocket, isFalse);

    final bottomPocket = find.text('Карман снизу (по нижней кромке)');
    await tester.ensureVisible(bottomPocket);
    await tester.tap(bottomPocket);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isTrue);
    expect(params.pocketTop, isTrue);
    expect(tester.takeException(), isNull);

    // --- Запайка под окантовку: возвращаемся на ПВХ и вводим 10 мм ---
    final pvcChip = find.text('Обычный ПВХ');
    await tester.ensureVisible(pvcChip);
    await tester.tap(pvcChip);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('weld-overlap-field')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('weld-overlap-field')), '10');
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.weldOverlapMm, 10);
    expect(params.material, FilmMaterial.clearPvc);
    // Заготовка ПВХ: готовый размер − 2 × окантовка + 2 × запайка.
    const defaultRoll = 100.0;
    final pvcSpec = WindowSpec.of(params);
    expect(
      pvcSpec.filmCutWidth,
      closeTo(params.bottomWidth - defaultRoll + 2 * 10, 1e-9),
    );
    expect(tester.takeException(), isNull);
  });

  _pricePanelRules();
}

/// Панель «Прайс-лист»: цены скрина видны и уходят в модель.
class _PriceHost extends StatefulWidget {
  const _PriceHost({super.key});

  @override
  State<_PriceHost> createState() => _PriceHostState();
}

class _PriceHostState extends State<_PriceHost> {
  PriceList prices = PriceList.defaults();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 420,
          child: PricePanel(
            prices: prices,
            onChanged: (value) => setState(() => prices = value),
          ),
        ),
      ),
    );
  }
}

void _pricePanelRules() {
  testWidgets('панель прайса: цены скрина показываются и правятся', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PriceHostState>();
    await tester.pumpWidget(_PriceHost(key: hostKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Раздел раскрыт: цены скрина — и полотно, и подворот.
    await tester.tap(find.text('ПРАЙС-ЛИСТ'));
    await tester.pumpAndSettle();
    expect(find.text('Скрин, ₽/м²'), findsOneWidget);
    expect(find.text('Подворот скрина, ₽/м'), findsOneWidget);
    expect(hostKey.currentState!.prices.filmScreenPerM2, 520);
    expect(hostKey.currentState!.prices.screenHemPerM, 180);

    Future<void> setRow(String label, String value) async {
      final row = find
          .ancestor(of: find.text(label), matching: find.byType(Row))
          .first;
      await tester.enterText(
        find.descendant(of: row, matching: find.byType(TextField)),
        value,
      );
      await tester.pumpAndSettle();
    }

    await setRow('Скрин, ₽/м²', '640');
    await setRow('Подворот скрина, ₽/м', '210');
    expect(hostKey.currentState!.prices.filmScreenPerM2, 640);
    expect(hostKey.currentState!.prices.screenHemPerM, 210);
    expect(tester.takeException(), isNull);
  });
}
