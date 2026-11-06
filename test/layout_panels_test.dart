import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/main.dart';
import 'package:soft_window_drawer/widgets/app_navigation.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('боковое меню сворачивается и разворачивается', (tester) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();
    expect(find.text('Конструктор'), findsOneWidget);
    final rail = find.byType(AppNavigationRail);
    final wide = tester.getSize(rail).width;

    await tester.tap(find.byKey(const Key('nav-rail-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Конструктор'), findsNothing);
    final narrow = tester.getSize(rail).width;
    expect(narrow, lessThan(wide));

    await tester.tap(find.byKey(const Key('nav-rail-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('Конструктор'), findsOneWidget);
    expect(tester.getSize(rail).width, closeTo(wide, 0.1));
  });

  testWidgets('меню и панель параметров меняют ширину перетаскиванием', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();

    final rail = find.byType(AppNavigationRail);
    final beforeRail = tester.getSize(rail).width;
    await tester.drag(find.byKey(const Key('nav-rail-resize')), const Offset(30, 0));
    await tester.pumpAndSettle();
    expect(tester.getSize(rail).width, greaterThan(beforeRail));

    final panel = find.byType(ParamsPanel);
    final beforePanel = tester.getSize(panel).width;
    await tester.drag(
      find.byKey(const Key('builder-panel-resize')),
      const Offset(35, 0),
    );
    await tester.pumpAndSettle();
    expect(tester.getSize(panel).width, greaterThan(beforePanel));
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель параметров сворачивается, раскладка сохраняется', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1500, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();
    expect(find.text('ЗАКАЗЫ'), findsOneWidget);

    await tester.tap(find.byKey(const Key('builder-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('ЗАКАЗЫ'), findsNothing);
    await tester.pump(const Duration(milliseconds: 350));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('builder_panel_collapsed'), isTrue);

    await tester.tap(find.byKey(const Key('builder-panel-toggle')));
    await tester.pumpAndSettle();
    expect(find.text('ЗАКАЗЫ'), findsOneWidget);
  });
}
