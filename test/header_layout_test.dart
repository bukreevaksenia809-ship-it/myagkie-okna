import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/widgets/design/app_kit.dart';

Widget _host(double width) => MaterialApp(
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(
        width: width,
        child: AppPageHeader(
          eyebrow: 'Производство · склад',
          title: 'Склад',
          subtitle:
              'Номенклатура, партии по FIFO, движение, резервы под заказы '
              'и отчёты. Остаток всегда считается по журналу.',
          actions: [
            for (var i = 0; i < 5; i++)
              OutlinedButton.icon(
                onPressed: () {},
                icon: const Icon(Icons.circle, size: 16),
                label: Text('Действие $i'),
              ),
          ],
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('много действий уходят под заголовок', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(1200));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Склад'), findsOneWidget);
    expect(find.text('Действие 4'), findsOneWidget);
  });

  testWidgets('на телефоне заголовок и действия не ломаются', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host(360));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
