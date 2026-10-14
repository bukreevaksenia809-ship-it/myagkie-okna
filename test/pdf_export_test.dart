import 'dart:io';
import 'dart:typed_data';
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

/// Простой PNG — как будто сняли одну страницу листа.
Future<Uint8List> _solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    const Rect.fromLTWH(0, 0, 200, 100),
    Paint()..color = color,
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 100);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

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

  // ---------------------------------------------------- лимиты разрешения

  test('разрешение снимка ограничено по большей стороне', () {
    // Широкий лист: pixelRatio урезается до 3000 px по большей стороне.
    expect(
      effectiveSheetPixelRatio(
        const Size(4000, 1000),
        pixelRatio: 3,
        maxSide: 3000,
      ),
      0.75,
    );
    // Обычный лист: запрошенный pixelRatio проходит целиком.
    expect(
      effectiveSheetPixelRatio(
        const Size(400, 600),
        pixelRatio: 2,
        maxSide: 3000,
      ),
      2,
    );
    // Совсем длинный лист ниже 0.5 не опускаем — иначе текст не прочитать.
    expect(
      effectiveSheetPixelRatio(
        const Size(100, 100000),
        pixelRatio: 3,
        maxSide: 3000,
      ),
      0.5,
    );
    // Нулевой размер не роняет расчёт.
    expect(
      effectiveSheetPixelRatio(Size.zero, pixelRatio: 3, maxSide: 3000),
      3,
    );
  });

  test('лимиты для веба ниже, чем для десктопа', () {
    expect(kWebSheetImageMaxSide, 3000);
    expect(kDesktopSheetImageMaxSide, 4200);
    expect(kWebSheetImageMaxSide, lessThan(kDesktopSheetImageMaxSide));
    // Тесты идут не в браузере: по умолчанию берётся десктопный набор.
    expect(sheetImageMaxSide(), kDesktopSheetImageMaxSide);
    expect(defaultSheetPixelRatio(), 3);
  });

  // ------------------------------------------ инкрементальная сборка PDF

  testWidgets('сборка PDF из 3 картинок даёт 3 страницы', (tester) async {
    final pages = await tester.runAsync(
      () async => <Uint8List>[
        await _solidPng(const Color(0xFFFF0000)),
        await _solidPng(const Color(0xFF00FF00)),
        await _solidPng(const Color(0xFF0000FF)),
      ],
    );

    // Списка страниц снаружи нет: каждая картинка уходит в документ.
    final builder = SheetPdfBuilder(title: 'Тест');
    for (final png in pages!) {
      builder.addPageImage(png);
    }
    expect(builder.pageCount, 3);
    expect(builder.isEmpty, isFalse);
    expect(builder.isClosed, isFalse);

    final bytes =
        await tester.runAsync(() => builder.save(balanceEventLoop: false));
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(
      RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length,
      3,
    );

    // Документ закрыт: добавлять страницы после сборки нельзя.
    expect(builder.isClosed, isTrue);
    expect(() => builder.addPageImage(pages.first), throwsStateError);
  });

  testWidgets('лист отдаётся по одной странице, список не копится',
      (tester) async {
    final captureKey = GlobalKey();
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: Container(
            color: const Color(0xFFFFFFFF),
            width: 400,
            height: 1200,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Внутри колбэка живёт ровно одна страница за раз: наружу уходит PNG,
    // а не список страниц.
    final seen = <int>[];
    final added = await tester.runAsync(
      () => renderSheetPagesEach(
        captureKey: captureKey,
        pixelRatio: 1,
        onPage: (png, index) {
          expect(png.lengthInBytes, greaterThan(0));
          seen.add(index);
        },
      ),
    );

    expect(added, greaterThan(1), reason: 'длинный лист должен резаться');
    expect(seen, List<dynamic>.generate(added!, (index) => index));
  });

  testWidgets('сборщик добавляет страницы листа по одной', (tester) async {
    final captureKey = GlobalKey();
    tester.view.physicalSize = const Size(400, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: Container(
            color: const Color(0xFFFFFFFF),
            width: 400,
            height: 1200,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final builder = SheetPdfBuilder(title: 'Тест');
    final steps = <int>[];
    final added = await tester.runAsync(
      () => builder.addSheet(
        captureKey: captureKey,
        pixelRatio: 1,
        onPageAdded: (pagesInSheet) => steps.add(pagesInSheet),
      ),
    );

    expect(added, greaterThan(1));
    expect(builder.pageCount, added);
    // Счётчик растёт ровно на единицу за страницу.
    expect(steps, List<dynamic>.generate(added!, (index) => index + 1));

    final bytes =
        await tester.runAsync(() => builder.save(balanceEventLoop: false));
    expect(bytes!.length, greaterThan(1000));
    expect(
      RegExp(r'/Type\s*/Page[^s]').allMatches(String.fromCharCodes(bytes)).length,
      added,
    );
  });
}
