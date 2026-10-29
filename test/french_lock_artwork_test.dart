// Пластиковая скоба — фотографией заказчика.
//
// Фото: металлическая овальная пластина-окантовка с продетым коричневым
// ремешком. Файл лежит в assets/fasteners/french_lock.webp, объявлен в
// pubspec.yaml и рисуется на чертеже через canvas.drawImageRect — с
// поворотом по стороне и размером по ширине канта. Пока картинка не
// загрузилась, рисуется прежний векторный замок (fallback).
//
// Запуск: flutter test test/french_lock_artwork_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/fastener_spans.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/fastener_artwork.dart';
import 'package:soft_window_drawer/services/pdf_export.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

import 'test_fonts.dart';

/// Окно с французским замком по низу и бокам.
const _frenchWindow = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-050',
  windowType: WindowType.lifting,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  fastenerType: FastenerType.frenchLocks,
  eyeletStep: 300,
  pvcHeightAllowanceEnabled: false,
);

/// То же на скрине: подворот вместо окантовки.
const _frenchScreen = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-051',
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  fastenerType: FastenerType.frenchLocks,
  eyeletStep: 300,
  hemBottomMm: 70,
  hemRightMm: 70,
  hemTopMm: 70,
  hemLeftMm: 70,
);

WindowDrawingPainter _painter(
  WindowParams params, {
  ui.Image? image,
  DrawingOptions options = const DrawingOptions(),
}) {
  final spec = WindowSpec.of(params);
  final layout = DrawingLayout(
    size: const Size(560, 420),
    geometry: spec.geometry,
  );
  return WindowDrawingPainter(
    params: spec.params,
    layout: layout,
    layers: spec.layers,
    options: options,
    labelFontFamily: testFontFamily,
    fastenerImage: image,
  );
}

Future<Uint8List> _render(
  WidgetTester tester,
  WindowDrawingPainter painter, {
  Size size = const Size(560, 420),
  int pixelRatio = 1,
}) async {
  final bytes = await tester.runAsync(() async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Offset.zero & Size(size.width * pixelRatio, size.height * pixelRatio),
    );
    canvas.scale(pixelRatio.toDouble());
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    painter.paint(canvas, size);
    final picture = recorder.endRecording();
    final image = await picture.toImage(
      (size.width * pixelRatio).round(),
      (size.height * pixelRatio).round(),
    );
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    picture.dispose();
    return data!.buffer.asUint8List();
  });
  return bytes!;
}

bool _sameBytes(Uint8List a, Uint8List b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  setUpAll(loadRealFonts);

  group('ассет французского замка', () {
    test('объявлен в pubspec.yaml и лежит в проекте', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains('assets/fasteners/'),
        reason: 'без секции assets картинка не попадёт в бандл',
      );
      final file = File(FastenerArtwork.frenchLockAsset);
      expect(file.existsSync(), isTrue, reason: 'файл ассета на месте');
      final bytes = file.readAsBytesSync();
      expect(bytes.length, greaterThan(5000));
      // WebP: RIFF….WEBP
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(
        String.fromCharCodes(bytes.sublist(8, 12)),
        'WEBP',
      );
    });

    testWidgets('декодируется из бандла в картинку 299 × 369', (tester) async {
      FastenerArtwork.reset();
      final image = await tester.runAsync(
        () => FastenerArtwork.ensureFrenchLock(),
      );
      expect(image, isNotNull, reason: 'картинка грузится из rootBundle');
      expect(image!.width, 299);
      expect(image.height, 369);
      // Кэш: второй вызов отдаёт ту же картинку, без повторного декодирования.
      final again = await FastenerArtwork.ensureFrenchLock();
      expect(identical(again, image), isTrue);
    });
  });

  group('отрисовка замка', () {
    testWidgets('без картинки работает векторный fallback', (tester) async {
      FastenerArtwork.reset();
      final fallback = await _render(tester, _painter(_frenchWindow));
      expect(fallback.length, greaterThan(2000));
      // Тот же лист ещё раз — стабильно, без исключений.
      final again = await _render(tester, _painter(_frenchWindow));
      expect(_sameBytes(fallback, again), isTrue);
    });

    testWidgets('с картинкой рисуется фотография, а не вектор', (tester) async {
      FastenerArtwork.reset();
      final image = await tester.runAsync(
        () => FastenerArtwork.ensureFrenchLock(),
      );
      expect(image, isNotNull);

      final fallback = await _render(tester, _painter(_frenchWindow));
      final photo = await _render(
        tester,
        _painter(_frenchWindow, image: image),
      );
      expect(
        _sameBytes(fallback, photo),
        isFalse,
        reason: 'с картинкой лист обязан отличаться от векторного fallback',
      );
    });

    testWidgets('скрин и ПВХ рисуют замок одинаково (фотографией)', (
      tester,
    ) async {
      FastenerArtwork.reset();
      final image = await tester.runAsync(
        () => FastenerArtwork.ensureFrenchLock(),
      );
      final pvc = await _render(tester, _painter(_frenchWindow, image: image));
      final screen = await _render(
        tester,
        _painter(_frenchScreen, image: image),
      );
      expect(pvc.length, greaterThan(2000));
      expect(screen.length, greaterThan(2000));
      expect(_sameBytes(pvc, screen), isFalse);
    });

    testWidgets('у замка есть размеры между креплениями', (tester) async {
      final labels = fastenerSpanLabels(
        WindowSpec.of(_frenchWindow),
        pxPerMm: 0.378,
      );
      expect(labels, isNotEmpty);
      // Замок стоит по низу и бокам, сверху — саморезы по кромке; размеры
      // между креплениями нужны по всем четырём сторонам.
      expect(
        labels.map((label) => label.side).toSet(),
        {
          WindowSide.bottom,
          WindowSide.right,
          WindowSide.top,
          WindowSide.left,
        },
      );
    });
  });

  group('перерисовка и печать', () {
    testWidgets('shouldRepaint реагирует на смену типа крепежа', (tester) async {
      final french = _painter(_frenchWindow);
      final buckles = _painter(
        _frenchWindow.copyWith(fastenerType: FastenerType.turnBuckles),
      );
      expect(
        french.shouldRepaint(buckles),
        isTrue,
        reason: 'пластиковая скоба → скоба обязана перерисовать лист',
      );
      expect(
        buckles.shouldRepaint(french),
        isTrue,
        reason: 'скоба → пластиковая скоба тоже',
      );
    });

    testWidgets('shouldRepaint реагирует на появление картинки', (tester) async {
      FastenerArtwork.reset();
      final image = await tester.runAsync(
        () => FastenerArtwork.ensureFrenchLock(),
      );
      expect(image, isNotNull);
      final vector = _painter(_frenchWindow);
      final photo = _painter(_frenchWindow, image: image);
      expect(photo.fastenerImage, isNotNull);
      expect(
        photo.shouldRepaint(vector),
        isTrue,
        reason: 'когда фото догрузилось, лист перерисовывается фотографией',
      );
      expect(
        vector.shouldRepaint(_painter(_frenchWindow)),
        isFalse,
        reason: 'без изменений перерисовки нет',
      );
    });

    testWidgets('PDF-путь снимает лист, когда фото уже декодировано', (
      tester,
    ) async {
      FastenerArtwork.reset();
      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final captureKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: DrawingSheet(
              project: const OrderProject(windows: [_frenchWindow]),
              captureKey: captureKey,
              labelFontFamily: testFontFamily,
            ),
          ),
        ),
      );
      // Лист впервые нарисован ещё без фото (идёт загрузка ассета).
      await tester.pump();
      final pages = <Uint8List>[];
      final count = await tester.runAsync(
        () => renderSheetPagesEach(
          captureKey: captureKey,
          onPage: (png, index) async => pages.add(png),
          pageFormat: SheetPageFormat.a4Portrait,
        ),
      );
      expect(count, greaterThanOrEqualTo(1));
      expect(pages, isNotEmpty);
      expect(pages.first.length, greaterThan(5000));
      expect(tester.takeException(), isNull);
    });
  });

  group('лист чертежа', () {
    testWidgets('лист получает картинку и перерисовывается один раз', (
      tester,
    ) async {
      FastenerArtwork.reset();
      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: DrawingSheet(
              project: OrderProject(windows: [_frenchWindow]),
              labelFontFamily: testFontFamily,
            ),
          ),
        ),
      );
      // Даём картинке декодироваться и листу перерисоваться.
      await tester.runAsync(() => FastenerArtwork.ensureFrenchLock());
      await tester.runAsync(() => FastenerArtwork.ensurePlasticClip());
      await tester.pumpAndSettle();

      expect(FastenerArtwork.frenchLock.value, isNotNull);
      final paint = tester.widget<CustomPaint>(
        find
            .descendant(
              of: find.byType(DrawingSheet),
              matching: find.byType(CustomPaint),
            )
            .first,
      );
      final painter = paint.painter;
      expect(painter, isA<WindowDrawingPainter>());
      expect(
        (painter as WindowDrawingPainter).fastenerImage,
        isNotNull,
        reason: 'пейнтер получает декодированную картинку',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('крупный план замка: видно овальную пластину и ремешок', (
      tester,
    ) async {
      FastenerArtwork.reset();
      final image = await tester.runAsync(
        () => FastenerArtwork.ensureFrenchLock(),
      );
      // Маленькое окно с широким подворотом: масштаб получается 1:1, замок
      // на превью крупный — по нему видно, что рисуется именно фото.
      const closeUp = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 400,
        topWidth: 400,
        leftHeight: 300,
        rightHeight: 300,
        fastenerType: FastenerType.frenchLocks,
        eyeletStep: 300,
        hemBottomMm: 100,
        hemRightMm: 100,
        hemTopMm: 100,
        hemLeftMm: 100,
      );
      final bytes = await _render(
        tester,
        _painter(closeUp, image: image),
        size: const Size(560, 420),
      );
      final file = File('build/preview/zamok-krupno.png')
        ..writeAsBytesSync(bytes);
      expect(file.lengthSync(), greaterThan(2000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    });

    testWidgets('пишет крупные превью замка: низ и бок — фотографией', (
      tester,
    ) async {
      FastenerArtwork.reset();
      final image = await tester.runAsync(
        () => FastenerArtwork.ensureFrenchLock(),
      );
      expect(image, isNotNull);

      const bottom = WindowParams(
        windowType: WindowType.lifting,
        bottomWidth: 1800,
        topWidth: 1800,
        leftHeight: 600,
        rightHeight: 600,
        rollBottom: 200,
        rollRight: 200,
        rollTop: 200,
        rollLeft: 200,
        fastenerType: FastenerType.frenchLocks,
        eyeletStep: 400,
        pvcHeightAllowanceEnabled: false,
      );
      const side = WindowParams(
        windowType: WindowType.lifting,
        bottomWidth: 600,
        topWidth: 600,
        leftHeight: 1800,
        rightHeight: 1800,
        rollBottom: 200,
        rollRight: 200,
        rollTop: 200,
        rollLeft: 200,
        fastenerType: FastenerType.frenchLocks,
        eyeletStep: 400,
        pvcHeightAllowanceEnabled: false,
      );
      // Только изделие и крепёж: подписи и сетка не мешают разглядеть фото.
      const options = DrawingOptions(
        showDimensions: false,
        showGrid: false,
        showEdgeLengths: false,
        showCallouts: false,
      );
      final cases = <String, WindowParams>{
        'zamok-francuzskiy-niz': bottom,
        'zamok-francuzskiy-bok': side,
      };
      for (final entry in cases.entries) {
        final bytes = await _render(
          tester,
          _painter(entry.value, image: image, options: options),
          pixelRatio: 4,
        );
        final file = File('build/preview/${entry.key}.png')
          ..writeAsBytesSync(bytes);
        expect(file.lengthSync(), greaterThan(5000));
        // ignore: avoid_print
        print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
      }
    });

    testWidgets('пишет PNG-превью листа с французским замком', (tester) async {
      tester.view.physicalSize = const Size(
        DrawingSheet.a4Width + 40,
        DrawingSheet.a4Height + 40,
      );
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      FastenerArtwork.reset();
      final directory = Directory('build/preview')..createSync(recursive: true);
      final cases = <String, WindowParams>{
        'zamok-francuzskiy-pvh': _frenchWindow,
        'zamok-francuzskiy-skrin': _frenchScreen,
      };
      for (final entry in cases.entries) {
        final captureKey = GlobalKey();
        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: DrawingSheet(
                project: OrderProject(windows: [entry.value]),
                captureKey: captureKey,
                labelFontFamily: testFontFamily,
              ),
            ),
          ),
        );
        await tester.runAsync(() => FastenerArtwork.ensureFrenchLock());
        await tester.pumpAndSettle();

        final bytes = await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final longest = math.max(boundary.size.width, boundary.size.height);
          final ratio = math.min(2.2, 10000 / longest);
          final image = await boundary.toImage(pixelRatio: ratio);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          image.dispose();
          return data!.buffer.asUint8List();
        });
        final file = File('${directory.path}/${entry.key}.png')
          ..writeAsBytesSync(bytes!);
        expect(file.lengthSync(), greaterThan(5000));
        // ignore: avoid_print
        print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
      }
      expect(tester.takeException(), isNull);
    });
  });
}
