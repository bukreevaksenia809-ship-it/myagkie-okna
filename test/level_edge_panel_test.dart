// Тесты надёжности переключателя «Ровно»: нажатие любого сегмента всегда
// пишет в модель и перерисовывает контур. Раньше SegmentedButton не вызывал
// обработчик, если нажали уже выбранный сегмент, — из-за этого нажатие
// «иногда не работало».
//
// Запуск: flutter test test/level_edge_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

/// Панель шириной 420 px с живым состоянием: правки уходят в проект.
class _PanelHost extends StatefulWidget {
  const _PanelHost({super.key, this.initial});

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
  testWidgets('панель: низ → верх → нет → низ всегда меняют модель и контур', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 7200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const order = OrderProject(
      windows: [
        WindowParams(
          bottomWidth: 1200,
          topWidth: 1200,
          leftHeight: 1000,
          rightHeight: 1400,
          pvcHeightAllowanceEnabled: false,
        ),
      ],
    );
    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey, initial: order));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    Future<void> tapMode(String name) async {
      final finder = find.byKey(Key('level-edge-$name'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }

    void expectHighlighted(String name) {
      final finder = find.byKey(Key('level-edge-$name'));
      expect(finder, findsOneWidget);
      // Выбранная кнопка помечена галочкой — по ней видно фактическое
      // состояние модели, а не «нажатость».
      expect(
        find.descendant(
          of: finder,
          matching: find.byKey(const Key('level-edge-check')),
        ),
        findsOneWidget,
        reason: 'выбран сегмент «$name»',
      );
    }

    void expectNotHighlighted(String name) {
      final finder = find.byKey(Key('level-edge-$name'));
      expect(
        find.descendant(
          of: finder,
          matching: find.byKey(const Key('level-edge-check')),
        ),
        findsNothing,
        reason: 'не выбран сегмент «$name»',
      );
    }

    // 1. «Низ» — низ горизонтален, верх наклонён.
    await tapMode('bottom');
    var params = hostKey.currentState!.project.selected;
    var geometry = WindowSpec.of(params).geometry;
    expect(params.levelEdge, LevelEdge.bottom);
    expect(geometry.bottomLeft, const Offset(0, 0));
    expect(geometry.bottomRight, const Offset(1200, 0));
    expect(geometry.topLeft, const Offset(0, 1000));
    expect(geometry.topRight, const Offset(1200, 1400));
    expectHighlighted('bottom');
    expectNotHighlighted('top');
    expectNotHighlighted('none');

    // 2. «Верх» — верх на 1400, нижние углы смещены.
    await tapMode('top');
    params = hostKey.currentState!.project.selected;
    geometry = WindowSpec.of(params).geometry;
    expect(params.levelEdge, LevelEdge.top);
    expect(geometry.topLeft, const Offset(0, 1400));
    expect(geometry.topRight, const Offset(1200, 1400));
    expect(geometry.bottomLeft, const Offset(0, 400));
    expect(geometry.bottomRight, const Offset(1200, 0));
    expectHighlighted('top');
    expectNotHighlighted('bottom');
    expectNotHighlighted('none');

    // 3. «Нет» — перепад делится поровну: верх +200, низ −200.
    await tapMode('none');
    params = hostKey.currentState!.project.selected;
    geometry = WindowSpec.of(params).geometry;
    expect(params.levelEdge, LevelEdge.none);
    expect(geometry.bottomLeft, const Offset(0, 0));
    expect(geometry.bottomRight.dy, closeTo(-200, 1e-9));
    expect(geometry.topLeft, const Offset(0, 1000));
    expect(geometry.topRight.dy, closeTo(1200, 1e-9));
    expectHighlighted('none');
    expectNotHighlighted('bottom');
    expectNotHighlighted('top');

    // 4. Снова «Низ» — модель и контур возвращаются к первому режиму.
    await tapMode('bottom');
    params = hostKey.currentState!.project.selected;
    geometry = WindowSpec.of(params).geometry;
    expect(params.levelEdge, LevelEdge.bottom);
    expect(geometry.bottomLeft, const Offset(0, 0));
    expect(geometry.topLeft, const Offset(0, 1000));
    expect(geometry.topRight, const Offset(1200, 1400));
    expectHighlighted('bottom');

    // 5. Повторное нажатие уже выбранного сегмента не «глотается»: модель
    // обновляется (новая копия параметров), панель перерисовывается.
    final before = hostKey.currentState!.project.selected;
    await tapMode('bottom');
    final after = hostKey.currentState!.project.selected;
    expect(identical(before, after), isFalse,
        reason: 'нажатие выбранного сегмента тоже пишет в модель');
    expect(after.levelEdge, LevelEdge.bottom);
    expectHighlighted('bottom');
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель: у Т-окна «Ровно» заблокировано с явной подсказкой', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const order = OrderProject(
      windows: [
        WindowParams(
          windowType: WindowType.tShape,
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 1500,
          rightHeight: 1500,
          pvcHeightAllowanceEnabled: false,
        ),
      ],
    );
    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey, initial: order));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Замок и подпись «недоступно» видны, кнопки действительно отключены.
    final lock = find.byKey(const Key('level-edge-lock'));
    await tester.ensureVisible(lock);
    expect(lock, findsOneWidget);
    expect(find.byKey(const Key('level-edge-locked')), findsOneWidget);
    expect(find.text('недоступно'), findsOneWidget);
    for (final name in const ['bottom', 'top', 'none']) {
      final button = tester.widget<OutlinedButton>(
        find.byKey(Key('level-edge-$name')),
      );
      expect(button.onPressed, isNull, reason: 'кнопка «$name» заблокирована');
    }

    // Нажатие по заблокированной кнопке не меняет модель.
    final before = hostKey.currentState!.project.selected.levelEdge;
    await tester.tap(
      find.byKey(const Key('level-edge-top')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.project.selected.levelEdge, before);
    expect(tester.takeException(), isNull);
  });
}

