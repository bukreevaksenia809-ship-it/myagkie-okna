import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/client_report_pdf.dart';
import 'package:soft_window_drawer/services/company_branding.dart';
import 'package:soft_window_drawer/widgets/client_report_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const window = WindowParams(
    projectName: 'Веранда',
    customer: 'Елена 89775223927',
    drawingNumber: 'TO1',
  );

  testWidgets('диалог подставляет клиента из заказа и возвращает данные', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    ClientReportInfo? info;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              info = await showClientReportDialog(
                context,
                project: const OrderProject(windows: [window]),
                company: const CompanyBrandingState(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Отчёт для клиента'), findsOneWidget);
    final nameField = tester.widget<TextField>(
      find.byKey(const Key('client-report-name')),
    );
    expect(nameField.controller!.text, 'Елена');
    final phoneField = tester.widget<TextField>(
      find.byKey(const Key('client-report-phone')),
    );
    expect(phoneField.controller!.text, '89775223927');

    await tester.enterText(
      find.byKey(const Key('client-report-address')),
      'Москва, Ленина 1',
    );
    await tester.enterText(
      find.byKey(const Key('client-report-name')),
      'Елена Иванова',
    );
    await tester.ensureVisible(find.byKey(const Key('client-report-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('client-report-submit')));
    await tester.pumpAndSettle();

    expect(info, isNotNull);
    expect(info!.name, 'Елена Иванова');
    expect(info!.address, 'Москва, Ленина 1');
    expect(info!.comment, 'Веранда');
  });

  testWidgets('без имени сохраняет с безопасным именем файла', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    ClientReportInfo? info;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              info = await showClientReportDialog(
                context,
                project: const OrderProject(windows: [window]),
                company: const CompanyBrandingState(),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('client-report-name')), '');
    await tester.ensureVisible(find.byKey(const Key('client-report-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('client-report-submit')));
    await tester.pumpAndSettle();
    // Пустое имя допустимо: файл всё равно получит безопасное имя.
    expect(find.text('Отчёт для клиента'), findsNothing);
    expect(clientReportFileName(name: '', dealer: false), 'Отчёт клиенту.pdf');
    expect(
      clientReportFileName(name: '  Елена  ', dealer: true),
      'Отчёт дилеру — Елена.pdf',
    );
    expect(
      clientReportFileName(name: 'a/b:c*?', dealer: false),
      'a b c.pdf',
    );
    expect(info, isNotNull);
    expect(info!.name, isEmpty);
  });
}
