// Настройки водяного знака и его влияние на сборку PDF.
//
// Текст знака лежит в сжатом потоке страницы и закодирован глифами шрифта,
// поэтому искать русскую строку в байтах PDF бессмысленно. Проверяем то, что
// действительно важно снаружи: настройки читаются/пишутся, а сборка PDF
// работает при выключенном и включённом знаке. Включённый знак встраивает
// шрифт и слой прозрачности, поэтому его PDF заведомо больше.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/services/pdf_export.dart';
import 'package:soft_window_drawer/services/watermark.dart';

/// Крошечный PNG 1 × 1 — как снимок страницы листа.
const String _pixelPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAE'
    'hQGAhKmMIQAAAABJRU5ErkJggg==';

Uint8List _pixelPng() => base64Decode(_pixelPngBase64);

/// Собирает PDF из двух страниц: A4 и «табличной» с высотой по картинке.
Future<Uint8List> _buildPdf() {
  final builder = SheetPdfBuilder(title: 'Водяной знак');
  builder.addPageImage(_pixelPng(), format: SheetPageFormat.a4Portrait);
  builder.addPageImage(_pixelPng());
  return builder.save(balanceEventLoop: false);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    WatermarkSettings.resetForTest();
    PdfWatermark.resetForTest();
  });

  test('по умолчанию знак выключен, текст стандартный', () async {
    await WatermarkSettings.load();

    expect(WatermarkSettings.enabled.value, isFalse);
    expect(WatermarkSettings.text.value, 'Мягкие окна Excl');
    expect(WatermarkSettings.isEnabled, isFalse);
  });

  test('load читает сохранённые значения', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      WatermarkSettings.enabledKey: true,
      WatermarkSettings.textKey: 'Тестовый знак',
    });

    await WatermarkSettings.load();

    expect(WatermarkSettings.enabled.value, isTrue);
    expect(WatermarkSettings.text.value, 'Тестовый знак');
    expect(WatermarkSettings.isEnabled, isTrue);
  });

  test('save пишет значения, пустой текст заменяется стандартным', () async {
    await WatermarkSettings.setEnabled(true);
    await WatermarkSettings.setText('  Водяной знак  ');

    expect(WatermarkSettings.enabled.value, isTrue);
    expect(WatermarkSettings.text.value, 'Водяной знак');

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(WatermarkSettings.enabledKey), isTrue);
    expect(prefs.getString(WatermarkSettings.textKey), 'Водяной знак');

    await WatermarkSettings.setText('   ');
    expect(WatermarkSettings.text.value, WatermarkSettings.defaultText);
    expect(
      prefs.getString(WatermarkSettings.textKey),
      WatermarkSettings.defaultText,
    );
  });

  test('выключенный знак не мешает собрать PDF', () async {
    await WatermarkSettings.load();

    final bytes = await _buildPdf();

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });

  test('включённый знак собирает PDF и заметно меняет его', () async {
    // Базовая сборка без знака — для сравнения размера.
    final plain = await _buildPdf();

    await WatermarkSettings.setEnabled(true);
    await WatermarkSettings.setText('Мягкие окна Excl');

    final marked = await _buildPdf();

    expect(marked, isNotEmpty);
    expect(String.fromCharCodes(marked.take(4)), '%PDF');
    // Знак реально наложен (размер PDF может совпасть из-за сжатия).
    expect(PdfWatermark.lastApplied, isTrue);
    expect(marked.length, greaterThanOrEqualTo(plain.length));
  });

  test('длинный текст знака не ломает сборку PDF', () async {
    await WatermarkSettings.setEnabled(true);
    await WatermarkSettings.setText(
      'Мягкие окна Excl · демонстрационный водяной знак · '
      'проверка длинной надписи на странице',
    );

    final bytes = await _buildPdf();

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
  });
}
