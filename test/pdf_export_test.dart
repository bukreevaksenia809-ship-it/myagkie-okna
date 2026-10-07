import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/file_saver.dart';
import 'package:soft_window_drawer/services/image_slice.dart';
import 'package:soft_window_drawer/services/pdf_export.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

const _params = WindowParams(
  projectName: 'Мягкое окно веранды',
  drawingNumber: 'МО-014',
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

void main() {
  setUpAll(loadRealFonts);

  testWidgets('сохраняет лист чертежа в PDF-файл', (tester) async {
    final captureKey = GlobalKey();
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: const OrderProject(windows: [_params]),
            captureKey: captureKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final directory = Directory('build/export_test');
    if (directory.existsSync()) directory.deleteSync(recursive: true);

    final saved = await tester.runAsync(
      () => exportSheetToPdf(
        captureKey: captureKey,
        params: _params,
        pixelRatio: 2,
        directoryPath: directory.path,
      ),
    );

    expect(saved, isNotNull);
    final file = File(saved!.path!);
    expect(file.existsSync(), isTrue);
    expect(file.lengthSync(), greaterThan(20000));

    final bytes = file.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    // ignore: avoid_print
    print('PDF записан: ${file.absolute.path} (${file.lengthSync()} байт)');
  });

  testWidgets('длинный подробный лист сохраняется на несколько страниц A3',
      (tester) async {
    const viewport = Size(1500, 900);
    final project = const OrderProject()
        .addWindow()
        .addWindow()
        .addWindow()
        .addWindow()
        .setSheetMode(SheetMode.grid)
        .setGridColumns(1);
    final sheetSize = DrawingSheet.detailedSheetSize(project, viewport)!;

    final captureKey = GlobalKey();
    tester.view.physicalSize = Size(sheetSize.width, sheetSize.height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DrawingSheet(
            project: project,
            captureKey: captureKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final directory = Directory('build/export_test_tall');
    if (directory.existsSync()) directory.deleteSync(recursive: true);

    final saved = await tester.runAsync(
      () => exportSheetToPdf(
        captureKey: captureKey,
        params: project.selected,
        pixelRatio: 1.5,
        directoryPath: directory.path,
        // Режем только между окнами — окно не должно разрываться пополам.
        safeBreakFractions: DrawingSheet.safeBreakFractions(project, viewport),
      ),
    );

    expect(saved, isNotNull);
    final bytes = File(saved!.path!).readAsBytesSync();
    final text = String.fromCharCodes(bytes);
    final pages = RegExp(r'/Type\s*/Page[^s]').allMatches(text).length;
    expect(pages, greaterThan(1),
        reason: 'длинный лист должен резаться на страницы');

    // Ни одна страница не выше A3 (297 мм) — значит, ничего не «размазано».
    for (final match in RegExp(r'/MediaBox\s*\[([^\]]+)\]').allMatches(text)) {
      final box = match.group(1)!.trim().split(RegExp(r'\s+'));
      final heightMm =
          (double.parse(box[3]) - double.parse(box[1])) / 72 * 25.4;
      expect(heightMm, lessThanOrEqualTo(298));
    }
  });

  test('вырезание куска листа даёт именно этот кусок, а не пустоту', () async {
    // Картинка: сверху красная половина, снизу синяя.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
      const Rect.fromLTWH(0, 0, 100, 100),
      Paint()..color = const Color(0xFFFF0000),
    );
    canvas.drawRect(
      const Rect.fromLTWH(0, 100, 100, 100),
      Paint()..color = const Color(0xFF0000FF),
    );
    final picture = recorder.endRecording();
    final source = await picture.toImage(100, 200);

    final lowerPng = await cropImageToPng(
      source,
      const Rect.fromLTWH(0, 100, 100, 100),
    );
    final decoded = await decodeImageFromList(lowerPng);
    final data = await decoded.toByteData();

    // Центр нижнего куска — синий, а не белый (то есть страница не пустая).
    final offset = (50 * decoded.width + 50) * 4;
    expect(data!.getUint8(offset), lessThan(60));
    expect(data.getUint8(offset + 1), lessThan(60));
    expect(data.getUint8(offset + 2), greaterThan(200));
  });

  test('имя файла содержит номер чертежа, префикс и дату', () {
    expect(
      exportFileName(_params, now: DateTime(2026, 9, 30, 21, 15)),
      'Чертёж-МО-014-20260930-2115.pdf',
    );
    expect(
      exportFileName(
        _params,
        now: DateTime(2026, 9, 30, 21, 15),
        prefix: 'Раскладка',
      ),
      'Раскладка-МО-014-20260930-2115.pdf',
    );
  });

  test('каталог экспорта по умолчанию — ~/Downloads/Мягкие окна', () {
    expect(exportFolderDescription(), endsWith('/Downloads/Мягкие окна'));
  });
}
