// Тесты ползунков выреза в панели параметров.
//
// Панель шириной 420 px с одним вырезом: ползунки X и Y двигают вырез в
// модели, числовое поле и ползунок синхронизируются в обе стороны, вёрстка
// не переполняется (takeException пуст).
//
// Запуск: flutter test test/cutout_slider_test.dart
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
  // Один вырез в центре полотна: положение заведомо внутри видимой плёнки,
  // чтобы ползунок ходил в обе стороны.
  OrderProject project = const OrderProject(
    windows: [
      WindowParams(cutouts: [Cutout(centerXMm: 700, centerYMm: 400)]),
    ],
  );

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
  testWidgets('ползунки выреза двигают его и синхронизируются с полями', (
    WidgetTester tester,
  ) async {
    // Высокий вьюпорт: панель строится целиком, ползунки не нужно
    // прокручивать перед перетаскиванием.
    tester.view.physicalSize = const Size(420, 8000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_PanelHostState>();
    await tester.pumpWidget(_PanelHost(key: hostKey));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    const xSliderKey = Key('cutout-0-x-slider');
    const ySliderKey = Key('cutout-0-y-slider');
    const xFieldKey = Key('cutout-0-x-field');
    const yFieldKey = Key('cutout-0-y-field');
    expect(find.byKey(xSliderKey), findsOneWidget);
    expect(find.byKey(ySliderKey), findsOneWidget);

    final spec = WindowSpec.of(hostKey.currentState!.project.selected);
    // Диапазон ползунков — видимая плёнка изделия, а не габарит окна.
    expect(spec.filmVisibleWidth, greaterThan(0));
    expect(spec.filmVisibleHeight, greaterThan(0));

    // 1. Ползунок стоит ровно на значении модели, шаг — 10 мм, подпись
    //    показывает то же число, что и числовое поле.
    final xSlider = tester.widget<Slider>(find.byKey(xSliderKey));
    expect(xSlider.min, 0);
    expect(xSlider.max, spec.filmVisibleWidth);
    expect(xSlider.divisions, (spec.filmVisibleWidth / 10).round());
    expect(xSlider.value, 700);
    expect(find.text('по горизонтали: 700 мм'), findsOneWidget);
    expect(
      tester.widget<Slider>(find.byKey(ySliderKey)).max,
      spec.filmVisibleHeight,
    );
    expect(find.text('по вертикали: 400 мм'), findsOneWidget);

    // 2. Перетаскивание ползунка X меняет положение выреза в модели.
    final beforeX =
        hostKey.currentState!.project.selected.cutouts.first.centerXMm;
    await tester.drag(find.byKey(xSliderKey), const Offset(60, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final afterDrag = hostKey.currentState!.project.selected.cutouts.first;
    expect(afterDrag.centerXMm, isNot(beforeX));
    // Значение всегда кратно шагу 10 мм и не выходит за видимую плёнку.
    expect(afterDrag.centerXMm % 10, 0);
    expect(afterDrag.centerXMm, inInclusiveRange(0, spec.filmVisibleWidth));
    // Ввод других полей выреза при этом не потерялся.
    expect(afterDrag.width, 300);
    expect(afterDrag.height, 300);
    // Числовое поле подстроилось под ползунок.
    final xFieldAfterDrag = tester.widget<TextField>(find.byKey(xFieldKey));
    expect(parseMm(xFieldAfterDrag.controller!.text), afterDrag.centerXMm);

    // 3. Ввод числа в поле X ставит ползунок на это значение.
    await tester.enterText(find.byKey(xFieldKey), '900');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(hostKey.currentState!.project.selected.cutouts.first.centerXMm, 900);
    expect(tester.widget<Slider>(find.byKey(xSliderKey)).value, 900);
    expect(find.text('по горизонтали: 900 мм'), findsOneWidget);

    // 4. Ползунок Y двигает вырез по вертикали и не трогает X.
    final beforeY =
        hostKey.currentState!.project.selected.cutouts.first.centerYMm;
    await tester.drag(find.byKey(ySliderKey), const Offset(80, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final afterY = hostKey.currentState!.project.selected.cutouts.first;
    expect(afterY.centerYMm, isNot(beforeY));
    expect(afterY.centerYMm % 10, 0);
    expect(afterY.centerYMm, inInclusiveRange(0, spec.filmVisibleHeight));
    expect(afterY.centerXMm, 900, reason: 'ползунок Y не двигает X');
    final yFieldAfterDrag = tester.widget<TextField>(find.byKey(yFieldKey));
    expect(parseMm(yFieldAfterDrag.controller!.text), afterY.centerYMm);

    // 5. Значение из модели за пределами плёнки не роняет ползунок:
    //    он просто упирается в край диапазона.
    await tester.enterText(find.byKey(xFieldKey), '9999');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      tester.widget<Slider>(find.byKey(xSliderKey)).value,
      spec.filmVisibleWidth,
    );

    // 6. Панель 420 px: ни одного переполнения за весь сценарий.
    expect(tester.takeException(), isNull);
  });
}
