// Тесты панели «Молния и фартук»: переименование «карман» → «фартук»,
// явные кнопки-переключатели сторон и общее поле ширины.
//
// Запуск: flutter test test/apron_panel_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

/// Акцентный цвет выбранной кнопки фартука.
const _accent = Color(0xFF0B62C4);

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

/// Высокая панель 420 px: все разделы построены, по ширине ничего не течёт.
Future<void> _pumpPanel(
  WidgetTester tester,
  GlobalKey<_PanelHostState> hostKey,
) async {
  tester.view.physicalSize = const Size(420, 9000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(_PanelHost(key: hostKey));
  await tester.pumpAndSettle();
}

/// Цвет заливки кнопки-переключателя: подсветка выбранного состояния.
Color? _buttonColor(WidgetTester tester, String key) {
  final button = tester.widget<OutlinedButton>(find.byKey(Key(key)));
  return button.style?.backgroundColor?.resolve(const <WidgetState>{});
}

void main() {
  testWidgets('раздел переименован: «фартук» вместо «карман»', (
    WidgetTester tester,
  ) async {
    final hostKey = GlobalKey<_PanelHostState>();
    await _pumpPanel(tester, hostKey);

    expect(find.text('Молния и фартук'), findsOneWidget);
    expect(find.text('Добавить фартук'), findsOneWidget);
    expect(find.text('Фартук снизу'), findsOneWidget);
    expect(find.text('Фартук сверху'), findsOneWidget);
    expect(find.text('Ширина фартука, мм'), findsOneWidget);
    expect(
      find.text('Фартук идёт от внутреннего края окантовки наружу и ниже кромки'),
      findsOneWidget,
    );

    // Пользовательских подписей «карман» в панели больше нет.
    expect(find.textContaining('Карман'), findsNothing);
    expect(find.textContaining('карман'), findsNothing);
    expect(find.text('Карман снизу (по нижней кромке)'), findsNothing);
    expect(find.text('Карман сверху (по верхней кромке)'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('кнопки фартука включают и выключают флаги, состояние видно', (
    WidgetTester tester,
  ) async {
    final hostKey = GlobalKey<_PanelHostState>();
    await _pumpPanel(tester, hostKey);

    final top = find.byKey(const Key('apron-top-toggle'));
    final bottom = find.byKey(const Key('apron-bottom-toggle'));

    // По умолчанию фартука нет: обе кнопки не подсвечены.
    var params = hostKey.currentState!.project.selected;
    expect(params.pocket, isFalse);
    expect(params.pocketTop, isFalse);
    expect(find.text('Фартук не включён'), findsOneWidget);
    expect(_buttonColor(tester, 'apron-bottom-toggle'), Colors.white);
    expect(_buttonColor(tester, 'apron-top-toggle'), Colors.white);

    // «Фартук снизу» включает только pocket.
    await tester.ensureVisible(bottom);
    await tester.tap(bottom);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isTrue);
    expect(params.pocketTop, isFalse);
    expect(find.text('Сейчас: фартук снизу'), findsOneWidget);
    expect(_buttonColor(tester, 'apron-bottom-toggle'), _accent);
    expect(
      find.descendant(of: bottom, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(_buttonColor(tester, 'apron-top-toggle'), Colors.white);

    // «Фартук сверху» включает ещё и pocketTop — обе кнопки подсвечены.
    await tester.ensureVisible(top);
    await tester.tap(top);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isTrue);
    expect(params.pocketTop, isTrue);
    expect(find.text('Сейчас: фартук снизу и сверху'), findsOneWidget);
    expect(_buttonColor(tester, 'apron-bottom-toggle'), _accent);
    expect(_buttonColor(tester, 'apron-top-toggle'), _accent);

    // Повторный тап по нижней кнопке выключает ровно её флаг.
    await tester.tap(bottom);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isFalse);
    expect(params.pocketTop, isTrue);
    expect(find.text('Сейчас: фартук сверху'), findsOneWidget);
    expect(_buttonColor(tester, 'apron-bottom-toggle'), Colors.white);
    expect(_buttonColor(tester, 'apron-top-toggle'), _accent);

    // И верхняя кнопка тоже выключается повторным тапом.
    await tester.tap(top);
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isFalse);
    expect(params.pocketTop, isFalse);
    expect(find.text('Фартук не включён'), findsOneWidget);
    expect(_buttonColor(tester, 'apron-top-toggle'), Colors.white);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ширина фартука общая для обеих сторон и уходит в модель', (
    WidgetTester tester,
  ) async {
    final hostKey = GlobalKey<_PanelHostState>();
    await _pumpPanel(tester, hostKey);

    final field = find.byKey(const Key('apron-width-field'));
    expect(field, findsOneWidget);
    expect(find.text('Ширина фартука, мм'), findsOneWidget);

    var params = hostKey.currentState!.project.selected;
    expect(params.pocketWidth, pocketFinishedWidth);

    // Поле доступно до включения фартука: ширину можно задать заранее.
    await tester.enterText(field, '120');
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocketWidth, 120);

    // После включения обеих сторон ширина остаётся общей и прежней.
    await tester.ensureVisible(find.byKey(const Key('apron-bottom-toggle')));
    await tester.tap(find.byKey(const Key('apron-bottom-toggle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('apron-top-toggle')));
    await tester.pumpAndSettle();
    params = hostKey.currentState!.project.selected;
    expect(params.pocket, isTrue);
    expect(params.pocketTop, isTrue);
    expect(params.pocketWidth, 120);
    expect(find.text('Сейчас: фартук снизу и сверху'), findsOneWidget);

    // Некорректный ноль не уходит в модель: остаётся прежняя ширина и ошибка.
    await tester.enterText(field, '0');
    await tester.pumpAndSettle();
    expect(find.text('Значение должно быть больше нуля'), findsOneWidget);
    params = hostKey.currentState!.project.selected;
    expect(params.pocketWidth, 120);
    expect(tester.takeException(), isNull);
  });
}
