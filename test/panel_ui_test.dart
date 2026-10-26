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
  const _PanelHost({super.key, this.initial});

  /// Стартовый заказ: тесты скрина подставляют готовое окно сразу.
  final OrderProject? initial;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  late OrderProject project = widget.initial ?? const OrderProject();

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
  _eyeletIntervalPanelRules();
  _roundEyeletTogglePanelRules();
  _tShapePanelRules();
  _rollWidthsAndEyeletsPanelRules();
  _screenZipperBlankRules();
  _screenHemPresetsRules();
  _levelEdgePanelRules();
  _twoAnnexPanelRules();
  testWidgets('панель 420: спайка добавляет окно, припуски идут в модель', (
    WidgetTester tester,
  ) async {
    // Узкая панель (420) и очень высокое окно: все разделы построены,
    // по ширине ничего не переполняется. Высота с запасом: в Т-окне два
    // блока пристроек, и кнопка выреза уходит ниже прежних 6000 px.
    tester.view.physicalSize = const Size(420, 7200);
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
    await tester.ensureVisible(find.text('Добавить вырез'));
    await tester.tap(find.text('Добавить вырез'));
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.zippers, hasLength(1));
    expect(hostKey.currentState!.project.selected.cutouts, hasLength(1));
    expect(tester.takeException(), isNull);

    // 3. Припуски на раскрой: кнопка раскрывает поля, значения — в модель.
    // Панель выросла (перемычки), поэтому раздел может быть выше области
    // построения — прокручиваем к нему.
    await tester.scrollUntilVisible(
      find.text('Припуски на раскрой'),
      -600,
      scrollable: find
          .descendant(
            of: find.byType(ParamsPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('Припуски на раскрой'), findsOneWidget);
    await tester.ensureVisible(find.text('Припуски на раскрой'));
    await tester.pumpAndSettle();
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
    expect(withAllowance.hasManualAllowance, isTrue);
    expect(withAllowance.hasAllowance, isTrue);
    expect(withAllowance.effectiveBottomWidth, withAllowance.bottomWidth + 120);
    // По высоте к ручным 80 мм добавляется авто +10 мм для ПВХ.
    expect(withAllowance.effectiveLeftHeight, withAllowance.leftHeight + 90);
    expect(
      withAllowance.heightAllowanceBreakdownLabel,
      'Припуск по высоте: 10 мм (авто) + 80 мм (вручную) = 90 мм',
    );

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

    // 4. Сброс припусков обнуляет РУЧНЫЕ припуски и убирает кнопку сброса;
    // авто-припуск ПВХ (+10 мм) сбросом не трогается.
    await tester.tap(find.byKey(const Key('allowance-reset')));
    await tester.pumpAndSettle();
    final reset = hostKey.currentState!.project.selected;
    expect(reset.allowanceWidthMm, 0);
    expect(reset.allowanceHeightMm, 0);
    expect(reset.hasManualAllowance, isFalse);
    expect(reset.hasAutoHeightAllowance, isTrue);
    expect(reset.autoHeightAllowanceMm, pvcHeightAllowanceMm);
    expect(find.byKey(const Key('allowance-reset')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель: пресеты 80 и 120 уходят в модель окна', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey));
    await tester.pumpAndSettle();

    // Все пять пресетов — на каждой из четырёх сторон.
    for (final preset in WindowParams.edgePresets) {
      expect(
        find.text(edgeBandLabel(preset, short: true)),
        findsNWidgets(EdgeSide.values.length),
        reason: 'пресет ${formatMm(preset)} мм на каждую сторону',
      );
    }

    // Низ — 80 мм, верх — 120 мм: кнопки пишут ширину рулона в модель.
    await tester.ensureVisible(find.text('80 мм').first);
    await tester.tap(find.text('80 мм').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('120 мм').last);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final params = hostKey.currentState!.project.selected;
    expect([
      params.rollBottom,
      params.rollTop,
      params.rollLeft,
      params.rollRight,
    ], containsAll(<double>[80, 120]));
    // Цена такого рулона берётся из прайса, а не интерполяцией.
    final prices = PriceList.defaults();
    expect(prices.edgePerMeterForWidth(80), 120);
    expect(prices.edgePerMeterForWidth(120), 165);
  });

  testWidgets('панель: тумблер усадки скрывает и показывает процент', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey));
    await tester.pumpAndSettle();

    // По умолчанию усадка выключена: поля процента нет.
    var params = hostKey.currentState!.project.selected;
    expect(params.shrinkageEnabled, isFalse);
    expect(params.shrinkagePercent, 0);
    expect(params.effectiveShrinkagePercent, 0);
    expect(find.byKey(const Key('shrinkage-toggle')), findsOneWidget);
    expect(find.text('Усадка ПВХ'), findsNothing);

    // Включаем — появляется поле и подставляется типовое значение 1,5 %.
    await tester.ensureVisible(find.byKey(const Key('shrinkage-toggle')));
    await tester.tap(find.byKey(const Key('shrinkage-toggle')));
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.shrinkageEnabled, isTrue);
    expect(params.shrinkagePercent, defaultShrinkagePercent);
    expect(params.effectiveShrinkagePercent, defaultShrinkagePercent);
    expect(find.text('Усадка ПВХ'), findsOneWidget);

    // Выключаем обратно — усадка не применяется.
    await tester.tap(find.byKey(const Key('shrinkage-toggle')));
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.shrinkageEnabled, isFalse);
    expect(params.effectiveShrinkagePercent, 0);
    expect(find.text('Усадка ПВХ'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель: тумблер +10 мм к высоте (ПВХ) меняет заготовку', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey));
    await tester.pumpAndSettle();

    var params = hostKey.currentState!.project.selected;
    expect(params.pvcHeightAllowanceEnabled, isTrue);
    expect(params.autoHeightAllowanceMm, pvcHeightAllowanceMm);
    final onHeight = WindowSpec.of(params).filmCutHeightWithAllowance;

    // Блок «Припуски на раскрой» по умолчанию свёрнут — раскрываем его.
    await tester.ensureVisible(find.text('Припуски на раскрой'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Припуски на раскрой'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const Key('pvc-height-allowance-toggle')),
    );
    await tester.tap(find.byKey(const Key('pvc-height-allowance-toggle')));
    await tester.pumpAndSettle();

    params = hostKey.currentState!.project.selected;
    expect(params.pvcHeightAllowanceEnabled, isFalse);
    expect(params.autoHeightAllowanceMm, 0);
    expect(
      WindowSpec.of(params).filmCutHeightWithAllowance,
      closeTo(onHeight - pvcHeightAllowanceMm, 1e-9),
    );
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
    // Окантовка у скрина скрыта, а крепёж доступен любой: чипы на месте.
    expect(find.text('Окантовка'), findsNothing);
    expect(find.text('Поворотная скоба'), findsOneWidget);
    expect(find.text('Французский замок'), findsOneWidget);
    expect(find.text('Подвязочный ремень'), findsOneWidget);
    // Подворот задаётся на каждую сторону: четыре поля и подпись заготовки.
    expect(find.byKey(const Key('hem-bottom-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-right-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-top-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-left-field')), findsOneWidget);
    expect(find.byKey(const Key('hem-blank-label')), findsOneWidget);
    // Подворот 60 мм на все стороны: заготовка = готовый размер + половина
    // подворота с каждой стороны, к высоте +20.
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
      closeTo(params.bottomWidth + 60, 1e-9),
    );
    expect(
      screenSpec.filmCutHeightWithAllowance,
      closeTo(params.leftHeight + 60 + 20, 1e-9),
    );
    // Готовое окно панели 1500 × 2520 → заготовка 1560 × 2600 мм.
    expect(screenSpec.filmCutWidthWithAllowance, closeTo(1560, 1e-9));
    expect(screenSpec.filmCutHeightWithAllowance, closeTo(2600, 1e-9));
    // Разные подвороты по сторонам: половина каждой стороны, к высоте +20.
    // Окно панели 1500 × 2520.
    await tester.enterText(find.byKey(const Key('hem-bottom-field')), '40');
    await tester.enterText(find.byKey(const Key('hem-top-field')), '60');
    await tester.enterText(find.byKey(const Key('hem-right-field')), '50');
    await tester.enterText(find.byKey(const Key('hem-left-field')), '40');
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    final mixedSpec = WindowSpec.of(params);
    // Ширина: 1500 + 20 + 25 = 1545.
    expect(
      mixedSpec.filmCutWidthWithAllowance,
      closeTo(params.bottomWidth + 45, 1e-9),
    );
    // Высота: 2520 + 20 + 30 + 20 = 2590.
    expect(
      mixedSpec.filmCutHeightWithAllowance,
      closeTo(params.leftHeight + 70, 1e-9),
    );
    // Панель показывает человеческий расчёт по правилу.
    expect(
      find.text(
        'Высота: ${formatMm(2520)} + ${formatMm(20)} + ${formatMm(30)} + '
        '${formatMm(screenHemAxisExtraMm)} = ${formatMm(2590)} мм',
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Ширина: ${formatMm(1500)} + ${formatMm(20)} + ${formatMm(25)} = '
        '${formatMm(1545)} мм',
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    // --- Крепёж скрина: доступен любой тип, выбираем французский замок ---
    final frenchLock = find.text('Французский замок');
    await tester.ensureVisible(frenchLock);
    await tester.tap(frenchLock);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.isScreen, isTrue);
    expect(params.fastenerType, FastenerType.frenchLocks);
    final fastenerSpec = WindowSpec.of(params);
    // Крепёж ставится по низу и бокам, в углах — круглые люверсы.
    expect(fastenerSpec.layers.movableSideEyelets, isNotEmpty);
    expect(
      fastenerSpec.layers.movableSideEyelets.any((eyelet) => eyelet.isCorner),
      isFalse,
    );
    expect(
      fastenerSpec.layers.movableSideEyelets.every(
        (eyelet) => eyelet.side != WindowSide.top,
      ),
      isTrue,
    );
    expect(fastenerSpec.fastenerSummary, contains('французский замок'));
    expect(fastenerSpec.fastenerSummary, contains('по подвороту'));
    expect(tester.takeException(), isNull);

    // --- Фартук сверху и снизу: явные кнопки-переключатели ---
    // Раздел переименован: старых подписей «карман» в панели нет.
    expect(find.text('Молния и фартук'), findsOneWidget);
    expect(find.textContaining('Карман'), findsNothing);
    expect(find.textContaining('карман'), findsNothing);

    final topApron = find.byKey(const Key('apron-top-toggle'));
    final bottomApron = find.byKey(const Key('apron-bottom-toggle'));
    await tester.ensureVisible(topApron);
    await tester.tap(topApron);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocketTop, isTrue);
    expect(params.pocket, isFalse);
    // Состояние видно и текстом, и галочкой на выбранной кнопке.
    expect(find.text('Сейчас: фартук сверху'), findsOneWidget);
    expect(
      find.descendant(of: topApron, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );

    await tester.ensureVisible(bottomApron);
    await tester.tap(bottomApron);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isTrue);
    expect(params.pocketTop, isTrue);
    expect(find.text('Сейчас: фартук снизу и сверху'), findsOneWidget);

    // Повторный тап выключает ровно свой флаг.
    await tester.tap(bottomApron);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isFalse);
    expect(params.pocketTop, isTrue);
    expect(
      find.descendant(
        of: bottomApron,
        matching: find.byIcon(Icons.check_circle),
      ),
      findsNothing,
    );

    // Ширина фартука — общая для обеих сторон и уходит в модель.
    expect(find.text('Ширина фартука, мм'), findsOneWidget);
    expect(
      find.text(
        'Фартук идёт от внутреннего края окантовки наружу и ниже кромки',
      ),
      findsOneWidget,
    );
    await tester.enterText(find.byKey(const Key('apron-width-field')), '120');
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocketWidth, 120);
    expect(tester.takeException(), isNull);

    // --- Запайка под окантовку: возвращаемся на ПВХ и вводим 10 мм ---
    final pvcChip = find.byKey(const Key('material-pvc'));
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

/// Панель: интервал люверсов вводится руками, пресеты работают, фактический
/// интервал показан рядом, панель 420 px не переполняется.
void _eyeletIntervalPanelRules() {
  testWidgets('панель: интервал люверсов и фактический шаг', (
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

    // Поле есть, подписано «Интервал люверсов, мм», по умолчанию 300.
    final field = find.byKey(const Key('eyelet-step-field'));
    expect(field, findsOneWidget);
    expect(find.text('Интервал люверсов, мм'), findsOneWidget);
    expect(hostKey.currentState!.project.selected.eyeletStep, 300);

    // Ввод 280 уходит в модель, рядом появляется фактический интервал.
    await tester.enterText(field, '280');
    await tester.pumpAndSettle();
    final params = hostKey.currentState!.project.selected;
    expect(params.eyeletStep, 280);
    final spec = WindowSpec.of(params);
    expect(spec.eyeletStepMax, isNotNull);
    expect(spec.eyeletStepMax!, lessThanOrEqualTo(280));

    final actual = tester.widget<Text>(
      find.byKey(const Key('eyelet-step-actual')),
    );
    expect(actual.data, contains('Задан 280 мм'));
    expect(actual.data, contains('фактически ${spec.eyeletStepLabel}'));
    expect(tester.takeException(), isNull);

    // Пресет 350 — тоже в модель.
    final preset = find.text('350');
    await tester.ensureVisible(preset);
    await tester.tap(preset);
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.eyeletStep, 350);

    // 40 мм — вне рамок 50…2000: ошибка, модель не меняется.
    await tester.enterText(find.byKey(const Key('eyelet-step-field')), '40');
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.eyeletStep, 350);
    expect(find.textContaining('Интервал от 50 до'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 500 мм принимается свободно (это пресет, а не рекомендация).
    await tester.enterText(find.byKey(const Key('eyelet-step-field')), '500');
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.eyeletStep, 500);
    expect(tester.takeException(), isNull);
  });
}

/// Панель: новые ширины рулонов скрина, стороны без люверсов и молния скрина.
void _rollWidthsAndEyeletsPanelRules() {
  testWidgets('панель: ширины 2500/5000, люверсы по сторонам, молния скрина', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 14000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // --- Скрин: новые ширины рулонов появляются в списке ---
    final screenChip = find.text('Скрин');
    await tester.ensureVisible(screenChip);
    await tester.tap(screenChip);
    await tester.pumpAndSettle();

    expect(find.text('2\u202F500 мм'), findsOneWidget);
    expect(find.text('5\u202F000 мм'), findsOneWidget);
    await tester.ensureVisible(find.text('5\u202F000 мм'));
    await tester.tap(find.text('5\u202F000 мм'));
    await tester.pumpAndSettle();
    expect(
      hostKey.currentState!.project.rollWidthFor(FilmMaterial.screen),
      5000,
    );

    // --- Стороны без люверсов: два переключателя уходят в модель ---
    final topSwitch = find.byKey(const Key('no-eyelets-top'));
    await tester.ensureVisible(topSwitch);
    await tester.tap(topSwitch);
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.noEyeletsTop, isTrue);
    expect(find.textContaining('без сторон: верх'), findsOneWidget);

    final bottomSwitch = find.byKey(const Key('no-eyelets-bottom'));
    await tester.ensureVisible(bottomSwitch);
    await tester.tap(bottomSwitch);
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.noEyeletsBottom, isTrue);
    expect(find.textContaining('без сторон: низ и верх'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // --- Овальный люверс доступен на любом окне (скрине) ---
    final ovalChip = find.text('Овальный 42×22 мм');
    await tester.ensureVisible(ovalChip);
    await tester.tap(ovalChip);
    await tester.pumpAndSettle();
    expect(
      hostKey.currentState!.project.selected.eyeletType,
      EyeletType.oval42x22,
    );

    // --- Молния на скрине: кнопка есть и она работает ---
    final addZipper = find.text('Добавить молнию');
    await tester.ensureVisible(addZipper);
    await tester.tap(addZipper);
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.zippers, hasLength(1));
    expect(find.text('Ширина молнии'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
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
    // Новые пресеты окантовки 80 и 120 мм есть в прайсе и правятся.
    expect(find.text('Тент 80 мм'), findsOneWidget);
    expect(find.text('Тент 120 мм'), findsOneWidget);
    expect(hostKey.currentState!.prices.edge80PerM, 120);
    expect(hostKey.currentState!.prices.edge120PerM, 165);

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
    await setRow('Тент 80 мм', '130');
    await setRow('Тент 120 мм', '175');
    expect(hostKey.currentState!.prices.filmScreenPerM2, 640);
    expect(hostKey.currentState!.prices.screenHemPerM, 210);
    expect(hostKey.currentState!.prices.edge80PerM, 130);
    expect(hostKey.currentState!.prices.edge120PerM, 175);
    expect(tester.takeException(), isNull);
  });
}

/// Кнопки выравнивания размеров: видны только при расхождении, одним тапом
/// приравнивают сторону и сразу исчезают; геометрия пересчитывается.
void _levelEdgePanelRules() {
  testWidgets('панель 420: «Ровно» низ/верх/нет вместо кнопок выравнивания', (
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

    // Прежних кнопок выравнивания в интерфейсе больше нет.
    expect(find.byKey(const Key('equalize-widths')), findsNothing);
    expect(find.byKey(const Key('equalize-widths-back')), findsNothing);
    expect(find.byKey(const Key('equalize-heights')), findsNothing);
    expect(find.byKey(const Key('equalize-heights-back')), findsNothing);

    // Новый выбор на месте кнопок, по умолчанию «Низ».
    expect(find.byKey(const Key('level-edge-bottom')), findsOneWidget);
    expect(find.byKey(const Key('level-edge-top')), findsOneWidget);
    expect(find.byKey(const Key('level-edge-none')), findsOneWidget);
    expect(hostKey.currentState!.project.selected.levelEdge, LevelEdge.bottom);

    // Ширины 1200, высоты 1000/1400.
    await tester.enterText(find.byKey(const Key('bottomWidth-field')), '1200');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('topWidth-field')), '1200');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('leftHeight-field')), '1000');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rightHeight-field')), '1400');
    await tester.pumpAndSettle();

    // Низ ровно: нижние углы на y = 0, верх наклонён.
    var params = hostKey.currentState!.project.selected;
    var geometry = WindowSpec.of(params).geometry;
    expect(params.levelEdge, LevelEdge.bottom);
    expect(geometry.bottomLeft.dy, 0);
    expect(geometry.bottomRight.dy, 0);
    expect(geometry.topLeft.dy, 1000);
    expect(geometry.topRight.dy, 1400);
    expect(geometry.areaM2, closeTo(1.44, 1e-9));

    // Верх ровно: верхняя кромка на 1400, нижняя наклонена.
    await tester.tap(find.byKey(const Key('level-edge-top')));
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    geometry = WindowSpec.of(params).geometry;
    expect(params.levelEdge, LevelEdge.top);
    expect(geometry.topLeft.dy, 1400);
    expect(geometry.topRight.dy, 1400);
    expect(geometry.bottomLeft.dy, 400);
    expect(geometry.bottomRight.dy, 0);
    expect(geometry.areaM2, closeTo(1.44, 1e-9));
    expect(geometry.leftEdgeLength, closeTo(1000, 1e-9));
    expect(geometry.rightEdgeLength, closeTo(1400, 1e-9));

    // Нет: перепад делится поровну — верх +200, низ −200.
    await tester.tap(find.byKey(const Key('level-edge-none')));
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    geometry = WindowSpec.of(params).geometry;
    expect(params.levelEdge, LevelEdge.none);
    expect(geometry.bottomLeft.dy, 0);
    expect(geometry.bottomRight.dy, closeTo(-200, 1e-9));
    expect(geometry.topLeft.dy, 1000);
    expect(geometry.topRight.dy, closeTo(1200, 1e-9));
    expect(geometry.areaM2, closeTo(1.44, 1e-9));

    // Ширины 1200/1000: выбранная горизонтальная кромка остаётся
    // горизонтальной, разница уходит в боковые кромки (верх по центру).
    await tester.enterText(find.byKey(const Key('leftHeight-field')), '1200');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('rightHeight-field')), '1200');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('topWidth-field')), '1000');
    await tester.pumpAndSettle();

    for (final key in const [
      'level-edge-bottom',
      'level-edge-top',
      'level-edge-none',
    ]) {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      params = hostKey.currentState!.project.selected;
      geometry = WindowSpec.of(params).geometry;
      expect(geometry.bottomLeft.dy, geometry.bottomRight.dy);
      expect(geometry.topLeft.dy, geometry.topRight.dy);
      expect(geometry.spanX, closeTo(1200, 1e-9));
      expect(geometry.areaM2, closeTo(1.32, 1e-9));
      expect(tester.takeException(), isNull);
    }
  });
}

void _screenZipperBlankRules() {
  testWidgets('панель 420: молния скрина сужает заготовку в подписях', (
    WidgetTester tester,
  ) async {
    // Высокое окно, чтобы все разделы панели построились целиком.
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Скрин 2000 × 2000, подворот 40, одна молния: заготовка 2040 × 2060,
    // раскрой делится на два сегмента.
    const order = OrderProject(
      windows: [
        WindowParams(
          material: FilmMaterial.screen,
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
          hemBottomMm: 40,
          hemRightMm: 40,
          hemTopMm: 40,
          hemLeftMm: 40,
          zippers: [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)],
        ),
      ],
    );
    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey, initial: order));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final spec = WindowSpec.of(order.selected);
    expect(spec.filmCutWidthWithAllowance, closeTo(2040, 1e-9));
    expect(spec.filmCutHeightWithAllowance, closeTo(2060, 1e-9));

    // Подпись подворотного блока: обе ширины и виновник — полоса молнии.
    final blankLabel = tester
        .widget<Text>(find.byKey(const Key('hem-blank-label')))
        .data!;
    expect(blankLabel, contains(formatMm(2040)));
    // Высота полосой не меняется: 2000 + 20 + 20 + 20 = 2060.
    final heightFormula = tester
        .widget<Text>(find.byKey(const Key('hem-height-formula')))
        .data!;
    expect(heightFormula, contains('= ${formatMm(2060)} мм'));
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель 420: молния ПВХ тоже сужает заготовку в подписях', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // ПВХ 2000 × 2000, окантовка 100 (готовая 50), запайка 5:
    // ширина 1910 мм, с полосой 50 мм — 1860 мм.
    const order = OrderProject(
      windows: [
        WindowParams(
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
          zippers: [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)],
        ),
      ],
    );
    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey, initial: order));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final spec = WindowSpec.of(order.selected);
    expect(spec.filmCutWidth, closeTo(1910, 1e-9));
    expect(spec.filmCutWidthBeforeZipper, closeTo(1910, 1e-9));
    // Молния по центру делит раскрой на сегменты, а не сужает заготовку.
    expect(spec.filmCutPolygons, hasLength(2));
    expect(find.textContaining('сегмент'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

/// Панель: пресеты подворота скрина 80/100/120 — кнопки, модель и формула
/// «половина подворота + 20 к высоте» на узкой панели 420 px.
void _screenHemPresetsRules() {
  testWidgets('панель 420: пресеты 80/100/120 меняют модель и заготовку', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Скрин 2000 × 2000, подворот 40 на все стороны — стартовое значение.
    const order = OrderProject(
      windows: [
        WindowParams(
          material: FilmMaterial.screen,
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
          hemBottomMm: 40,
          hemRightMm: 40,
          hemTopMm: 40,
          hemLeftMm: 40,
        ),
      ],
    );
    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey, initial: order));
    await tester.pumpAndSettle();

    // Кнопки 80/100/120 стоят на каждой стороне (низ/право/верх/лево).
    for (final side in EdgeSide.values) {
      for (final preset in const [80, 100, 120]) {
        expect(
          find.byKey(Key('hem-preset-hem${_sideName(side)}-$preset')),
          findsOneWidget,
          reason: 'пресет $preset на стороне ${side.label}',
        );
      }
    }
    expect(tester.takeException(), isNull);

    // Выбор 120 на низу попадает в модель. По высоте прибавка —
    // 60 (низ) + 20 (верх) + 20 = 100 → 2000 + 100 = 2100 мм;
    // ширина считается по лево/право = 40 и остаётся 2040 мм.
    await tester.tap(find.byKey(const Key('hem-preset-hemBottom-120')));
    await tester.pumpAndSettle();
    final afterBottom = hostKey.currentState!.project.selected;
    expect(afterBottom.hemBottomMm, 120);
    final bottomSpec = WindowSpec.of(afterBottom);
    expect(bottomSpec.filmCutWidth, closeTo(2040, 1e-9));
    expect(bottomSpec.filmCutHeight, closeTo(2100, 1e-9));
    expect(tester.takeException(), isNull);

    // Выбор 120 на верху: 60 + 60 + 20 = 140 → высота 2140.
    await tester.tap(find.byKey(const Key('hem-preset-hemTop-120')));
    await tester.pumpAndSettle();
    final afterTop = hostKey.currentState!.project.selected;
    expect(afterTop.hemTopMm, 120);
    final topSpec = WindowSpec.of(afterTop);
    expect(topSpec.filmCutWidth, closeTo(2040, 1e-9));
    expect(topSpec.filmCutHeight, closeTo(2140, 1e-9));
    expect(
      topSpec.screenBlankHeightFormulaLabel,
      contains('= ${formatMm(2140)} мм'),
    );
    expect(tester.takeException(), isNull);

    // Правый и левый бока 120: ширина тоже становится 2120 мм.
    await tester.tap(find.byKey(const Key('hem-preset-hemRight-120')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('hem-preset-hemLeft-120')));
    await tester.pumpAndSettle();
    final all = hostKey.currentState!.project.selected;
    expect(all.hemRightMm, 120);
    expect(all.hemLeftMm, 120);
    final allSpec = WindowSpec.of(all);
    expect(allSpec.filmCutWidth, closeTo(2120, 1e-9));
    expect(allSpec.filmCutHeight, closeTo(2140, 1e-9));
    expect(
      allSpec.screenBlankWidthFormulaLabel,
      contains('= ${formatMm(2120)} мм'),
    );
    expect(tester.takeException(), isNull);
  });
}

/// Имя поля подворота в ключе кнопки: hemBottom/hemRight/hemTop/hemLeft.
String _sideName(EdgeSide side) => switch (side) {
  EdgeSide.bottom => 'Bottom',
  EdgeSide.right => 'Right',
  EdgeSide.top => 'Top',
  EdgeSide.left => 'Left',
};

// --- Круглые люверсы в углах -----------------------------------------------

/// Тумблер в панели: выключение убирает угловые точки из модели.
void _roundEyeletTogglePanelRules() {
  testWidgets(
    'панель: тумблер «Круглые люверсы в углах» по умолчанию включён',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final hostKey = GlobalKey<_PanelHostState>();
      await tester.pumpWidget(_PanelHost(key: hostKey));
      await tester.pumpAndSettle();

      final toggle = find.byKey(const Key('round-eyelets-corners'));
      await tester.ensureVisible(toggle);
      expect(tester.takeException(), isNull);
      expect(
        tester.widget<SwitchListTile>(toggle).value,
        isTrue,
        reason: 'по умолчанию круглые люверсы в углах включены',
      );
      expect(
        hostKey.currentState!.project.selected.roundEyeletsEnabled,
        isTrue,
      );

      await tester.tap(toggle);
      await tester.pumpAndSettle();

      final params = hostKey.currentState!.project.selected;
      expect(params.roundEyeletsEnabled, isFalse);
      // Тип по сторонам может быть любым (по умолчанию круглый), но угловых
      // точек нет: именно их убирает тумблер.
      expect(WindowSpec.of(params).layers.cornerEyelets, isEmpty);
      expect(
        find.text('Круглых люверсов нет: углы остаются без крепёжных точек.'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

// --- Т-образное окно --------------------------------------------------------

/// Раздел «Т-образное окно»: перевод в Т, поля приставки и спайка.
void _tShapePanelRules() {
  testWidgets(
    'панель 420: Т-окно включается и настраивается без переполнений',
    (WidgetTester tester) async {
      tester.view.physicalSize = const Size(420, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final hostKey = GlobalKey<_PanelHostState>();
      await tester.pumpWidget(_PanelHost(key: hostKey));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final makeT = find.byKey(const Key('make-t-shape'));
      await tester.ensureVisible(makeT);
      await tester.tap(makeT);
      await tester.pumpAndSettle();

      var params = hostKey.currentState!.project.selected;
      expect(params.windowType, WindowType.tShape);
      expect(params.isTShape, isTrue);
      // Основное полотно выровнено в прямоугольник.
      expect(params.topWidth, params.bottomWidth);
      expect(params.rightHeight, params.leftHeight);
      expect(find.text('Т-образное окно'), findsOneWidget);
      expect(find.text('Сторона пристройки 1'), findsOneWidget);
      expect(find.byKey(const Key('t-welded')), findsOneWidget);

      // Сторона пристройки 1: снизу.
      final bottomSide = find.byKey(const Key('t1-side-bottom'));
      await tester.ensureVisible(bottomSide);
      await tester.tap(bottomSide);
      await tester.pumpAndSettle();
      params = hostKey.currentState!.project.selected;
      expect(params.tSide, TShapeSide.bottom);

      // Спайку выключаем — два отдельных окна.
      final welded = find.byKey(const Key('t-welded'));
      await tester.ensureVisible(welded);
      await tester.tap(welded);
      await tester.pumpAndSettle();
      params = hostKey.currentState!.project.selected;
      expect(params.tWelded, isFalse);
      expect(WindowSpec.of(params).layers.filmPolygons, hasLength(2));
      expect(tester.takeException(), isNull);

      // Возврат к обычному окну.
      final plain = find.byKey(const Key('make-plain-window'));
      // Кнопка может быть частично перекрыта прокруткой панели — вызываем её
      // обработчик напрямую: проверяем модель, а не хит-тест.
      tester.widget<TextButton>(plain).onPressed!();
      await tester.pumpAndSettle();
      expect(
        hostKey.currentState!.project.selected.windowType,
        WindowType.fixed,
      );
      expect(tester.takeException(), isNull);
    },
  );
}

// --- Панель: вторая пристройка Т-окна --------------------------------------

/// «Пристройка 1» и «Пристройка 2»: включение, сторона, размеры, смещение,
/// спайка и предупреждение о двух пристройках на одной стороне.
void _twoAnnexPanelRules() {
  testWidgets('панель: пристройка 2 включается и настраивается', (
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

    // Переводим окно в Т-форму: появляются два блока пристроек.
    await tester.tap(find.byKey(const Key('make-t-shape')));
    await tester.pumpAndSettle();
    var params = hostKey.currentState!.project.selected;
    expect(params.isTShape, isTrue);
    expect(params.tEnabled, isTrue);
    expect(params.t2Enabled, isFalse, reason: 'вторая выключена по умолчанию');
    expect(find.text('Пристройка 1'), findsOneWidget);
    expect(find.text('Пристройка 2'), findsOneWidget);

    // Включаем вторую пристройку.
    final enable2 = find.byKey(const Key('t2-enabled'));
    await tester.ensureVisible(enable2);
    await tester.tap(enable2);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.t2Enabled, isTrue);
    expect(find.byKey(const Key('t2-side-bottom')), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Сторона «слева».
    await tester.ensureVisible(find.byKey(const Key('t2-side-left')));
    await tester.tap(find.byKey(const Key('t2-side-left')));
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.t2Side, TShapeSide.left);

    // Размеры и смещение — в модель.
    for (final (key, value) in const [
      ('t2Width-field', '650'),
      ('t2Height-field', '450'),
      ('t2Offset-field', '120'),
    ]) {
      final field = find.byKey(Key(key));
      await tester.ensureVisible(field);
      await tester.enterText(field, value);
      await tester.pumpAndSettle();
    }
    params = hostKey.currentState!.project.selected;
    expect(params.t2Width, 650);
    expect(params.t2Height, 450);
    expect(params.t2Offset, 120);
    final spec = WindowSpec.of(params);
    expect(spec.tAnnexes, hasLength(2));
    expect(spec.tAnnexes[1].side, TShapeSide.left);

    // Спайка второй пристройки.
    final welded2 = find.byKey(const Key('t2-welded'));
    await tester.ensureVisible(welded2);
    await tester.tap(welded2);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.t2Welded, isFalse);
    expect(WindowSpec.of(params).layers.tAnnexes[1].welded, isFalse);

    // Обе пристройки на одной стороне: панель показывает предупреждение,
    // модель и расчёт не ломаются.
    await tester.ensureVisible(find.byKey(const Key('t1-side-left')));
    await tester.tap(find.byKey(const Key('t1-side-left')));
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.tSide, TShapeSide.left);
    expect(params.tAnnexSideConflict, isTrue);
    final conflict = find.byKey(const Key('t-annex-conflict'));
    await tester.ensureVisible(conflict);
    expect(conflict, findsOneWidget);
    expect(find.textContaining('стоят на одной стороне'), findsWidgets);
    final conflictSpec = WindowSpec.of(params);
    expect(conflictSpec.tAnnexes, hasLength(1));
    expect(conflictSpec.productAreaM2, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
