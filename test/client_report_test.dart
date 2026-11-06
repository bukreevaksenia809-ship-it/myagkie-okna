import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/document.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/client_report_pdf.dart';
import 'package:soft_window_drawer/services/company_branding.dart';

import 'test_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const window = WindowParams(
    projectName: 'Мягкое окно веранды',
    customer: 'Елена 89775223927',
    drawingNumber: 'TO60604017',
    bottomWidth: 1540,
    topWidth: 1540,
    leftHeight: 2250,
    rightHeight: 2250,
    windowType: WindowType.lifting,
  );

  test('отчёт клиенту: обложка + страница на каждое окно', () async {
    await loadRealFonts();
    const project = OrderProject(windows: [window, window]);
    final branding = CompanyBrandingState(
      details: const CompanyDetails(
        name: 'ООО «Мягкие окна»',
        inn: '7701234567',
        phone: '+7 999 123-45-67',
        address: 'Москва, ул. Примерная, 1',
      ),
      showOnSheets: true,
    );
    final bytes = await ClientReportBuilder(
      project: project,
      prices: const PriceList.defaults(),
      company: branding,
    ).build();
    expect(bytes.length, greaterThan(10000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final file = File('build/preview/client-report.pdf')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes);
    // ignore: avoid_print
    print('Отчёт записан: ${file.path} (${bytes.length} байт)');
  });
}
