import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/file_saver.dart';
import 'package:soft_window_drawer/services/image_slice.dart';
import 'package:soft_window_drawer/services/pdf_export.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
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
  canvas.drawRect(const Rect.fromLTWH(0, 0, 200, 100), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(200, 100);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Точка PDF в миллиметрах: 72 / 25,4.
const double _mmToPt = 72 / 25.4;

/// A4 в точках PDF: 210 × 297 мм → 595,28 × 841,89.
const double _a4WidthPt = 210 * _mmToPt;
const double _a4HeightPt = 297 * _mmToPt;

/// Размеры страниц PDF: ширина и высота MediaBox каждой страницы, в точках.
List<({double widthPt, double heightPt})> _mediaBoxes(Uint8List bytes) {
  final text = String.fromCharCodes(bytes);
  return [
    for (final match in RegExp(r'/MediaBox\s*\[([^\]]+)\]').allMatches(text))
      _mediaBox(match.group(1)!),
  ];
}

({double widthPt, double heightPt}) _mediaBox(String raw) {
  final parts = raw.trim().split(RegExp(r'\s+'));
  final left = double.parse(parts[0]);
  final bottom = double.parse(parts[1]);
  final right = double.parse(parts[2]);
  final top = double.parse(parts[3]);
  return (widthPt: right - left, heightPt: top - bottom);
}

/// Цвет центра страницы-картинки: (красный, зелёный, синий).
Future<(int, int, int)> _centerRgb(Uint8List png) async {
  final image = await decodeImageFromList(png);
  final data = await image.toByteData();
  final x = image.width ~/ 2;
  final y = image.height ~/ 2;
  final offset = (y * image.width + x) * 4;
  final rgb = (
    data!.getUint8(offset),
    data.getUint8(offset + 1),
    data.getUint8(offset + 2),
  );
  image.dispose();
  return rgb;
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

  testWidgets('длинный подробный лист сохраняется на несколько страниц A4', (
    tester,
  ) async {
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
        pixelRatio: 1,
        directoryPath: directory.path,
        // Режем только между окнами — окно не должно разрываться пополам.
        safeBreakFractions: DrawingSheet.safeBreakFractions(project, viewport),
      ),
    );

    expect(saved, isNotNull);
    final bytes = File(saved!.path!).readAsBytesSync();
    final boxes = _mediaBoxes(bytes);
    expect(
      boxes.length,
      greaterThan(1),
      reason: 'длинный лист должен резаться на страницы',
    );

    // Каждая страница — ровно A4 (210 × 297 мм): ничего не «размазано»
    // и не обрезано.
    for (final box in boxes) {
      expect(box.widthPt, closeTo(_a4WidthPt, 2));
      expect(box.heightPt, closeTo(_a4HeightPt, 2));
    }
  });

  testWidgets('чертёж на 5 окон — несколько страниц A4, окно не разрезано', (
    tester,
  ) async {
    const viewport = Size(1500, 900);
    // 5 окон по три в ряд — два ряда, две страницы A4.
    final project = const OrderProject()
        .addWindow()
        .addWindow()
        .addWindow()
        .addWindow()
        .setSheetMode(SheetMode.grid)
        .setGridColumns(3);
    expect(DrawingSheet.a4PageCount(project), 2);
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

    // Режем только по границам страниц A4 — окно не должно разорваться.
    final breaks = DrawingSheet.safeBreakFractions(project, viewport);
    expect(breaks, [closeTo(0.5, 1e-9)]);

    final directory = Directory('build/export_test_a4');
    if (directory.existsSync()) directory.deleteSync(recursive: true);

    final saved = await tester.runAsync(
      () => exportSheetToPdf(
        captureKey: captureKey,
        params: project.selected,
        pixelRatio: 1,
        directoryPath: directory.path,
        safeBreakFractions: breaks,
      ),
    );
    expect(saved, isNotNull);

    final bytes = File(saved!.path!).readAsBytesSync();
    final boxes = _mediaBoxes(bytes);
    // По странице на ряд окон: ровно две страницы A4.
    expect(boxes.length, 2);
    for (final box in boxes) {
      expect(box.widthPt, closeTo(_a4WidthPt, 2));
      expect(box.heightPt, closeTo(_a4HeightPt, 2));
    }
  });

  testWidgets(
    'чертёж на 5 окон в колонку: пять страниц A4, без разрезанных окон',
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

      final breaks = DrawingSheet.safeBreakFractions(project, viewport);
      expect(breaks, [
        closeTo(0.2, 1e-9),
        closeTo(0.4, 1e-9),
        closeTo(0.6, 1e-9),
        closeTo(0.8, 1e-9),
      ]);

      final pages = await tester.runAsync(
        () => renderSheetPages(
          captureKey: captureKey,
          pixelRatio: 1,
          safeBreakFractions: breaks,
          pageFormat: SheetPageFormat.a4Portrait,
        ),
      );

      expect(pages, isNotNull);
      // Пять рядов — пять страниц A4: ни один ряд не разрезан пополам.
      expect(pages!.length, 5);
      for (final png in pages) {
        final image = await tester.runAsync(() => decodeImageFromList(png));
        // Каждая страница — ровно пропорции A4, а не «обрезок» на пол-ряда.
        expect(
          image!.height / image.width,
          closeTo(_a4HeightPt / _a4WidthPt, 0.01),
        );
      }
    },
  );

  testWidgets('лист чертежа — A4 в портретной ориентации', (tester) async {
    final captureKey = GlobalKey();
    // Окно программы заведомо меньше листа: размер листа от него не зависит.
    tester.view.physicalSize = const Size(1200, 800);
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

    final boundary =
        captureKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    expect(boundary.size.width, DrawingSheet.a4Width);
    expect(boundary.size.height, DrawingSheet.a4Height);
    // Пропорции A4 — 1 : 1,4142 (допуск 0,5 %).
    expect(
      boundary.size.height / boundary.size.width,
      closeTo(DrawingSheet.a4Aspect, DrawingSheet.a4Aspect * 0.005),
    );
    expect(DrawingSheet.a4Aspect, closeTo(1.4142, 0.005));
  });

  testWidgets('в PDF чертежа первая страница — A4 (595 × 842 pt)', (
    tester,
  ) async {
    final captureKey = GlobalKey();
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
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

    final bytes = await tester.runAsync(
      () =>
          buildSheetPdf(captureKey: captureKey, params: _params, pixelRatio: 1),
    );
    expect(bytes, isNotNull);
    final boxes = _mediaBoxes(bytes!);
    expect(boxes, isNotEmpty);
    // 210 × 297 мм в точках PDF: 595,28 × 841,89.
    expect(boxes.first.widthPt, closeTo(_a4WidthPt, 2));
    expect(boxes.first.heightPt, closeTo(_a4HeightPt, 2));
  });

  testWidgets('раскрой на 24 окна — ровно одна страница A4', (tester) async {
    final project = OrderProject(
      windows: [for (var i = 0; i < 24; i++) _params],
    );
    final sheetSize = CutSheet.sheetSize(project, const Size(1720, 1080));
    tester.view.physicalSize = sheetSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final captureKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CutSheet(
            project: project,
            captureKey: captureKey,
            labelFontFamily: testFontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pages = await tester.runAsync(
      () => renderSheetPages(
        captureKey: captureKey,
        pixelRatio: 1,
        pageFormat: SheetPageFormat.a4Portrait,
      ),
    );
    expect(pages, isNotNull);
    expect(pages!.length, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('табличный лист остаётся на широкой странице A3', (tester) async {
    final pages = await tester.runAsync(
      () async => <Uint8List>[await _solidPng(const Color(0xFFFF0000))],
    );

    // По умолчанию (как у расходов, сметы, техкарты и раскроя) — широкая
    // страница A3, высота — по пропорциям снимка.
    final builder = SheetPdfBuilder(title: 'Таблица');
    builder.addPageImage(pages!.first);
    final bytes = await tester.runAsync(
      () => builder.save(balanceEventLoop: false),
    );

    final boxes = _mediaBoxes(bytes!);
    expect(boxes.length, 1);
    expect(boxes.first.widthPt, closeTo(420 * _mmToPt, 2));
    // Картинка 200 × 100: высота страницы вдвое меньше ширины.
    expect(boxes.first.heightPt, closeTo(210 * _mmToPt, 2));
  });

  testWidgets('смешанный PDF: чертёж на A4 и таблица на широкой странице', (
    tester,
  ) async {
    final pages = await tester.runAsync(
      () async => <Uint8List>[
        await _solidPng(const Color(0xFFFF0000)),
        await _solidPng(const Color(0xFF0000FF)),
      ],
    );

    // В одном документе у каждой страницы свой формат.
    final builder = SheetPdfBuilder(title: 'Заказ');
    builder.addPageImage(pages!.first, format: SheetPageFormat.a4Portrait);
    builder.addPageImage(pages.last);
    expect(builder.pageCount, 2);

    final bytes = await tester.runAsync(
      () => builder.save(balanceEventLoop: false),
    );
    final boxes = _mediaBoxes(bytes!);
    expect(boxes.length, 2);
    // Чертёж — A4 в портретной ориентации.
    expect(boxes[0].widthPt, closeTo(_a4WidthPt, 2));
    expect(boxes[0].heightPt, closeTo(_a4HeightPt, 2));
    // Таблица — широкая страница.
    expect(boxes[1].widthPt, closeTo(420 * _mmToPt, 2));
    expect(boxes[1].widthPt, greaterThan(boxes[1].heightPt));
  });

  testWidgets('рез идёт ровно по границе страницы A4: ряд не рвётся', (
    tester,
  ) async {
    final captureKey = GlobalKey();
    const pageHeight = DrawingSheet.a4Height;
    tester.view.physicalSize = const Size(DrawingSheet.a4Width, pageHeight * 2);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Лист из двух страниц: верхняя красная, нижняя синяя.
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: captureKey,
          child: Column(
            children: [
              Container(
                width: DrawingSheet.a4Width,
                height: pageHeight,
                color: const Color(0xFFFF0000),
              ),
              Container(
                width: DrawingSheet.a4Width,
                height: pageHeight,
                color: const Color(0xFF0000FF),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final pages = await tester.runAsync(
      () => renderSheetPages(
        captureKey: captureKey,
        pixelRatio: 0.25,
        safeBreakFractions: const [0.5],
        pageFormat: SheetPageFormat.a4Portrait,
      ),
    );

    expect(pages, isNotNull);
    expect(pages!.length, 2);
    // Каждая страница однотонная: рез пришёлся ровно на границу страниц,
    // а не на середину ряда.
    final first = await tester.runAsync(() => _centerRgb(pages[0]));
    final second = await tester.runAsync(() => _centerRgb(pages[1]));
    expect(first!.$1, greaterThan(200), reason: 'верхняя страница красная');
    expect(first.$2, lessThan(60));
    expect(first.$3, lessThan(60));
    expect(second!.$3, greaterThan(200), reason: 'нижняя страница синяя');
    expect(second.$1, lessThan(60));
    expect(second.$2, lessThan(60));
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

    final bytes = await tester.runAsync(
      () => builder.save(balanceEventLoop: false),
    );
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    expect(
      RegExp(
        r'/Type\s*/Page[^s]',
      ).allMatches(String.fromCharCodes(bytes)).length,
      3,
    );

    // Документ закрыт: добавлять страницы после сборки нельзя.
    expect(builder.isClosed, isTrue);
    expect(() => builder.addPageImage(pages.first), throwsStateError);
  });

  testWidgets('лист отдаётся по одной странице, список не копится', (
    tester,
  ) async {
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

    final bytes = await tester.runAsync(
      () => builder.save(balanceEventLoop: false),
    );
    expect(bytes!.length, greaterThan(1000));
    expect(
      RegExp(
        r'/Type\s*/Page[^s]',
      ).allMatches(String.fromCharCodes(bytes)).length,
      added,
    );
  });
}
