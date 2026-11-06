import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/main.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('ввод размеров: крайние значения не роняют экран', (tester) async {
    tester.view.physicalSize = const Size(1700, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();

    final width = find.byKey(const Key('bottomWidth-field'));
    expect(width, findsOneWidget);

    await tester.enterText(width, '20000');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(width, '1000000');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.textContaining('до 20 000'), findsOneWidget);

    await tester.enterText(width, '0');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(width, '2500');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Треугольник'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('shape-apex')), '600');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Домик'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.enterText(find.byKey(const Key('shape-roof')), '900');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('shape-overhang')), '150');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
