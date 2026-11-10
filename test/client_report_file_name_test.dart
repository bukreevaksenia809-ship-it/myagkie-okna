import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/services/client_report_pdf.dart';

void main() {
  test('клиентский отчёт сохраняется под введённым именем', () {
    expect(
      clientReportFileName(name: 'Елена Иванова'),
      'Елена Иванова.pdf',
    );
  });

  test('пустое имя даёт безопасный fallback', () {
    expect(clientReportFileName(name: ''), 'Отчёт клиенту.pdf');
    expect(clientReportFileName(name: '   '), 'Отчёт клиенту.pdf');
    expect(
      clientReportFileName(name: '///:::***'),
      'Отчёт клиенту.pdf',
    );
  });

  test('дилерский отчёт помечается «Отчёт дилеру — имя»', () {
    expect(
      clientReportFileName(name: 'Елена', dealer: true),
      'Отчёт дилеру — Елена.pdf',
    );
    expect(
      clientReportFileName(name: '', dealer: true),
      'Отчёт дилеру.pdf',
    );
  });

  test('запрещённые символы вычищаются, расширение всегда .pdf', () {
    final name = clientReportFileName(name: r'Отчёт: клиент/№1*?"<>|');
    expect(name, 'Отчёт клиент №1.pdf');
    expect(name.endsWith('.pdf'), isTrue);
    expect(
      '/\\:*?"<>|'.split('').any(name.contains),
      isFalse,
    );
  });

  test('длинное имя не превышает разумный предел', () {
    final name = clientReportFileName(name: 'А' * 400);
    expect(name.length, lessThanOrEqualTo(125));
    expect(name.endsWith('.pdf'), isTrue);
  });

  test('точки и пробелы в конце не остаются', () {
    expect(
      clientReportFileName(name: 'Отчёт ... '),
      'Отчёт.pdf',
    );
  });
}
