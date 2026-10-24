import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

/// Подъёмные ремни: ручное добавление и привязка к линии тента (в т.ч. косой).
void main() {
  WindowParams lifting({
    double leftHeight = 2000,
    double rightHeight = 2000,
    List<double> offsets = const [],
  }) =>
      WindowParams(
        windowType: WindowType.lifting,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: leftHeight,
        rightHeight: rightHeight,
        liftStrapOffsets: offsets,
      );

  test('без ручных положений — прежняя автоматическая расстановка', () {
    final layers = WindowLayers(lifting(), WindowGeometry.of(lifting()));
    expect(layers.liftStraps, hasLength(WindowSpec.of(lifting()).strapCount));
  });

  test('ручные положения задают число и центры ремней', () {
    final params = lifting(offsets: [400, 1000, 1600]);
    final spec = WindowSpec.of(params);
    final straps = spec.layers.liftStraps;
    expect(straps, hasLength(3));
    expect(spec.strapCount, 3);
    // Центры: левый край видимой плёнки + смещение.
    final left = spec.layers.filmVisibleBounds.left;
    expect(straps[0].center.dx, closeTo(left + 400, 1e-6));
    expect(straps[1].center.dx, closeTo(left + 1000, 1e-6));
    expect(straps[2].center.dx, closeTo(left + 1600, 1e-6));
  });

  test('косое окно: ремень начинается на линии тента, а не выше', () {
    final params = lifting(leftHeight: 2000, rightHeight: 2500, offsets: [500, 1500]);
    final spec = WindowSpec.of(params);
    final straps = spec.layers.liftStraps;
    expect(straps, hasLength(2));

    // Верхний край ремня = верх Rect (ось Y в модели растёт вверх).
    final firstTop = straps[0].top;
    final secondTop = straps[1].top;
    // Кромка наклонена: правый ремень выше левого примерно на 250 мм.
    expect(secondTop - firstTop, closeTo(250, 15));

    // Линия тента под каждым ремнём: верх ремня не выше неё.
    final inner = spec.layers.edgeInnerPolygons.first;
    double lineY(double x) {
      var best = 0.0;
      for (var i = 0; i < inner.length; i++) {
        final a = inner[i];
        final b = inner[(i + 1) % inner.length];
        final minX = a.dx < b.dx ? a.dx : b.dx;
        final maxX = a.dx < b.dx ? b.dx : a.dx;
        if (x < minX - 1e-6 || x > maxX + 1e-6) continue;
        final t = (x - a.dx) / (b.dx - a.dx);
        final y = a.dy + (b.dy - a.dy) * t;
        if (y > best) best = y;
      }
      return best;
    }

    expect(firstTop, lessThanOrEqualTo(lineY(straps[0].center.dx) + 1e-6));
    expect(secondTop, lessThanOrEqualTo(lineY(straps[1].center.dx) + 1e-6));
    // Нижний конец — на длину ремня ниже верхнего.
    expect(straps[0].bottom - straps[0].top, closeTo(liftStrapLength, 1e-6));
  });

  test('JSON: ручные положения сохраняются и читаются', () {
    final params = lifting(offsets: [300, 900]);
    final restored = windowFromJson(windowToJson(params));
    expect(restored.liftStrapOffsets, [300, 900]);
  });

  testWidgets('панель: добавить, поправить и удалить ремень', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = OrderProject(windows: [lifting()]);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setState) => ParamsPanel(
                project: project,
                issues: const [],
                onChanged: (value) => setState(() => project = value),
                onReset: () {},
              ),
            ),
          ),
        ),
      ),
    );

    await tester.ensureVisible(find.byKey(const Key('add-lift-strap')));
    await tester.tap(find.byKey(const Key('add-lift-strap')));
    await tester.pumpAndSettle();
    expect(project.selected.liftStrapOffsets, hasLength(1));

    await tester.tap(find.byKey(const Key('add-lift-strap')));
    await tester.pumpAndSettle();
    expect(project.selected.liftStrapOffsets, hasLength(2));

    await tester.enterText(find.byKey(const Key('lift-strap-0')), '300');
    await tester.pumpAndSettle();
    expect(project.selected.liftStrapOffsets.first, closeTo(300, 1e-6));

    await tester.tap(find.byKey(const Key('reset-lift-straps')));
    await tester.pumpAndSettle();
    expect(project.selected.liftStrapOffsets, isEmpty);
    expect(tester.takeException(), isNull);
  });
}
