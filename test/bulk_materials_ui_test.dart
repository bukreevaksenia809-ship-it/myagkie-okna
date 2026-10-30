import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/widgets/warehouse/bulk_materials_dialog.dart';

Widget _host() => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: ElevatedButton(
          onPressed: () => showBulkMaterialsDialog(context, orders: const []),
          child: const Text('Открыть'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('диалог потребности открывается на широком экране', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Потребность по заказам'), findsOneWidget);
    expect(find.text('Списать в заказы'), findsOneWidget);
    expect(find.text('Рассчитать'), findsOneWidget);
  });

  testWidgets('диалог потребности открывается на телефоне', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_host());
    await tester.tap(find.text('Открыть'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Потребность по заказам'), findsOneWidget);
  });
}
