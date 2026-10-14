// Тесты панели параметров: спайка с соседним окном и припуски на раскрой.
//
// Запуск: flutter test test/panel_ui_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

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
