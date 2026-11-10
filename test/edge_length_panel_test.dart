// Панель «4 размера»: верх/низ, противоположный «Ровно», вводится как длина
// кромки; поле автозаполняется, ручная правка пересчитывает проекцию, а
// «↺ авто» возвращает к ширине опорной кромки.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

class _PanelHost extends StatefulWidget {
  const _PanelHost({super.key, required this.initial});

  final OrderProject initial;

  @override
  State<_PanelHost> createState() => _PanelHostState();
}

class _PanelHostState extends State<_PanelHost> {
  late OrderProject project = widget.initial;

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

String? _label(WidgetTester tester, String key) {
  final field = tester.widget<TextField>(find.byKey(Key(key)));
  return field.decoration?.labelText;
}

double? _textValue(WidgetTester tester, String key) {
  final field = tester.widget<TextField>(find.byKey(Key(key)));
  return parseMm(field.controller?.text ?? '');
}

void main() {
  testWidgets('поля переключаются по «Ровно», авто и ручная правка работают', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const order = OrderProject(
      windows: [
        WindowParams(
          bottomWidth: 800,
          topWidth: 1000,
          leftHeight: 2000,
          rightHeight: 1800,
          pvcHeightAllowanceEnabled: false,
        ),
      ],
    );
    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey, initial: order));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('four-sizes-toggle')));
    await tester.tap(find.byKey(const Key('four-sizes-toggle')));
    await tester.pumpAndSettle();

    Future<void> tapMode(String name) async {
      final finder = find.byKey(Key('level-edge-$name'));
      await tester.ensureVisible(finder);
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    WindowParams current() => hostKey.currentState!.project.selected;

    // «Ровно низ»: низ — ширина, верх — длина кромки. Проекция верха
    // сбрасывается на ширину низа (боковины вертикальные).
    await tapMode('bottom');
    expect(current().levelEdge, LevelEdge.bottom);
    expect(current().topWidth, closeTo(800, 1e-9));
    expect(_label(tester, 'bottomWidth-field'), 'Ширина низ');
    expect(_label(tester, 'topWidth-field'), 'Верх (длина кромки)');
    expect(
      _textValue(tester, 'topWidth-field'),
      closeTo(math.sqrt(800 * 800 + 200 * 200), 0.11),
    );

    // «Ровно верх»: верх — ширина, низ — длина кромки. Проекция низа
    // сбрасывается на ширину верха.
    await tapMode('top');
    expect(current().levelEdge, LevelEdge.top);
    expect(current().bottomWidth, closeTo(800, 1e-9));
    expect(_label(tester, 'topWidth-field'), 'Ширина верх');
    expect(_label(tester, 'bottomWidth-field'), 'Низ (длина кромки)');
    expect(
      _textValue(tester, 'bottomWidth-field'),
      closeTo(math.sqrt(800 * 800 + 200 * 200), 0.11),
    );

    // Ручная правка длины нижней кромки: проекция = √(900² − 200²).
    await tester.ensureVisible(find.byKey(const Key('bottomWidth-field')));
    await tester.enterText(find.byKey(const Key('bottomWidth-field')), '900');
    await tester.pumpAndSettle();
    expect(current().bottomWidth, closeTo(math.sqrt(900 * 900 - 200 * 200), 1e-6));

    // «↺ авто» возвращает проекцию к ширине верха.
    await tester.ensureVisible(find.byKey(const Key('edge-length-auto')));
    await tester.tap(find.byKey(const Key('edge-length-auto')));
    await tester.pumpAndSettle();
    expect(current().bottomWidth, closeTo(800, 1e-9));
    expect(
      _textValue(tester, 'bottomWidth-field'),
      closeTo(math.sqrt(800 * 800 + 200 * 200), 0.11),
    );

    // «Нет»: обе кромки — длины кромок.
    await tapMode('none');
    expect(current().levelEdge, LevelEdge.none);
    expect(_label(tester, 'topWidth-field'), 'Верх (длина кромки)');
    expect(_label(tester, 'bottomWidth-field'), 'Низ (длина кромки)');

    // Ручная верхняя кромка 900 при перепаде ±100.
    await tester.ensureVisible(find.byKey(const Key('topWidth-field')));
    await tester.enterText(find.byKey(const Key('topWidth-field')), '900');
    await tester.pumpAndSettle();
    expect(current().topWidth, closeTo(math.sqrt(900 * 900 - 100 * 100), 1e-6));

    // Возвращаемся на «низ» и проверяем пересчёт при смене высоты:
    // ручная кромка сбрасывается к авто, проекция = ширине низа.
    await tapMode('bottom');
    await tester.ensureVisible(find.byKey(const Key('topWidth-field')));
    await tester.enterText(find.byKey(const Key('topWidth-field')), '900');
    await tester.pumpAndSettle();
    expect(current().topWidth, closeTo(math.sqrt(900 * 900 - 200 * 200), 1e-6));

    await tester.ensureVisible(find.byKey(const Key('leftHeight-field')));
    await tester.enterText(find.byKey(const Key('leftHeight-field')), '1900');
    await tester.pumpAndSettle();
    expect(current().leftHeight, 1900);
    expect(current().topWidth, closeTo(800, 1e-9));
    expect(
      _textValue(tester, 'topWidth-field'),
      closeTo(math.sqrt(800 * 800 + 100 * 100), 0.11),
    );

    // Валидация: длина кромки меньше перепада высот — понятная ошибка,
    // модель не меняется.
    final before = current().topWidth;
    await tester.ensureVisible(find.byKey(const Key('topWidth-field')));
    await tester.enterText(find.byKey(const Key('topWidth-field')), '50');
    await tester.pumpAndSettle();
    expect(find.textContaining('меньше перепада высот'), findsOneWidget);
    expect(current().topWidth, closeTo(before, 1e-9));
    expect(tester.takeException(), isNull);
  });
}
