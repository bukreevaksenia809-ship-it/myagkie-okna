// Масштаб чертежа Т-окна с пристройками.
//
// Заказчик: «когда добавляешь вторую пристройку на Т-образное окно — масштаб
// чертежа сильно меняется, становится мелким, а надписи обычные».
//
// Причина — грубый ряд стандартных масштабов: между 1:25 и 1:50 не было
// ступени. Т-окно 2000 × 1500 с пристройкой 800 мм сбоку требует 1:27,7 —
// масштаб округлялся до 1:50, и чертёж разом уменьшался вдвое, хотя габарит
// вырос на 100 мм. После второй пристройки (ещё 700 мм) — то же самое.
//
// Теперь ряд масштабов плотнее (соседние ступени отличаются не более чем в
// 1,33 раза), поэтому чертёж всегда крупный и заполняет поле листа так же,
// как обычное окно, а кегль подписей остаётся читаемым на А4.
//
// Запуск: flutter test test/t_shape_scale_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

import 'test_fonts.dart';

/// Обычное окно — точка отсчёта.
const _plain = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  pvcHeightAllowanceEnabled: false,
);

/// Т-окно с одной пристройкой справа.
const _tOne = WindowParams(
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: TShapeSide.right,
  tWidth: 800,
  tHeight: 600,
  tOffset: 200,
  pvcHeightAllowanceEnabled: false,
);

/// То же Т-окно со второй пристройкой снизу — случай из письма заказчика.
const _tTwo = WindowParams(
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: TShapeSide.right,
  tWidth: 800,
  tHeight: 600,
  tOffset: 200,
  t2Enabled: true,
  t2Side: TShapeSide.bottom,
  t2Width: 700,
  t2Height: 500,
  t2Offset: 300,
  pvcHeightAllowanceEnabled: false,
);

/// Две пристройки по бокам: 3500 мм габарита — здесь старый ряд масштабов
/// давал 1:50 вместо 1:30 и чертёж уменьшался вдвое.
const _tTwoSides = WindowParams(
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: TShapeSide.right,
  tWidth: 800,
  tHeight: 600,
  tOffset: 200,
  t2Enabled: true,
  t2Side: TShapeSide.left,
  t2Width: 700,
  t2Height: 500,
  t2Offset: 300,
  pvcHeightAllowanceEnabled: false,
);

/// Скрин-Т с двумя пристройками.
const _screenTTwo = WindowParams(
  material: FilmMaterial.screen,
  windowType: WindowType.tShape,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  tSide: TShapeSide.right,
  tWidth: 800,
  tHeight: 600,
  tOffset: 200,
  t2Enabled: true,
  t2Side: TShapeSide.bottom,
  t2Width: 700,
  t2Height: 500,
  t2Offset: 300,
);

/// Окно с фартуками сверху и снизу: они добавляют поля на листе.
const _aprons = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  pocket: true,
  pocketTop: true,
  pvcHeightAllowanceEnabled: false,
);

DrawingSheetMetrics _metrics(WindowParams params) =>
    DrawingSheet.metricsFor(OrderProject(windows: [params]));

/// Отношение площадей заполнения: во сколько раз один лист «полнее» другого.
double _ratio(double a, double b) => a > b ? a / b : b / a;

void main() {
  setUpAll(loadRealFonts);

  group('заполнение листа А4', () {
    test('обычное окно, Т с одной и с двумя пристройками — сопоставимо', () {
      final plain = _metrics(_plain);
      final one = _metrics(_tOne);
      final two = _metrics(_tTwo);
      // ignore: avoid_print
      print('обычное: $plain, Т-1: $one, Т-2: $two');

      // Масштаб не «прыгает» через ступень: 1:20 → 1:25 максимум.
      expect(plain.scaleDenominator, 20);
      expect(one.scaleDenominator, lessThanOrEqualTo(30));
      expect(two.scaleDenominator, lessThanOrEqualTo(30));

      // Рамка чертежа занимает сопоставимую долю листа.
      expect(
        _ratio(one.frameFill, plain.frameFill),
        lessThanOrEqualTo(1.35),
        reason: 'Т с одной пристройкой не должен быть мельче обычного окна',
      );
      expect(
        _ratio(two.frameFill, plain.frameFill),
        lessThanOrEqualTo(1.35),
        reason: 'вторая пристройка не должна уменьшать чертёж',
      );
      // И само изделие на листе — тоже.
      expect(_ratio(two.productFill, plain.productFill), lessThanOrEqualTo(1.4));
      // Чертёж крупный: рамка занимает не меньше трети поля листа.
      for (final metrics in [plain, one, two]) {
        expect(metrics.frameFill, greaterThan(0.33));
      }
    });

    test('регрессия: две пристройки по бокам (3500 мм) — не 1:50', () {
      final plain = _metrics(_plain);
      final two = _metrics(_tTwoSides);
      // ignore: avoid_print
      print('две по бокам: $two');
      expect(
        two.scaleDenominator,
        lessThanOrEqualTo(40),
        reason: 'раньше здесь был 1:50 — чертёж уменьшался вдвое',
      );
      expect(_ratio(two.frameFill, plain.frameFill), lessThanOrEqualTo(1.35));
      expect(two.frameFill, greaterThan(0.33));
    });

    test('большое Т-окно 2500 + пристройка 800 — не мельчает', () {
      final plain = _metrics(
        _plain.copyWith(bottomWidth: 2500, topWidth: 2500),
      );
      final t = _metrics(
        _plain
            .copyWith(bottomWidth: 2500, topWidth: 2500)
            .copyWith(
              windowType: WindowType.tShape,
              tSide: TShapeSide.right,
              tWidth: 800,
              tHeight: 600,
              tOffset: 200,
            ),
      );
      // ignore: avoid_print
      print('2500: обычное $plain, Т $t');
      expect(t.scaleDenominator, lessThanOrEqualTo(40));
      expect(_ratio(t.frameFill, plain.frameFill), lessThanOrEqualTo(1.35));
    });

    test('скрин-Т с двумя пристройками и фартуки — тоже сопоставимо', () {
      final plain = _metrics(_plain);
      final screen = _metrics(_screenTTwo);
      final aprons = _metrics(_aprons);
      // ignore: avoid_print
      print('скрин-Т: $screen, фартуки: $aprons');
      expect(_ratio(screen.frameFill, plain.frameFill), lessThanOrEqualTo(1.4));
      expect(_ratio(aprons.frameFill, plain.frameFill), lessThanOrEqualTo(1.35));
      expect(screen.frameFill, greaterThan(0.33));
      expect(aprons.frameFill, greaterThan(0.33));
    });

    test('масштабы идут ступенями не больше 1,33 раза', () {
      // Ряд масштабов: между соседними ступенями нет провала в два раза —
      // именно из-за него «прыгал» масштаб при добавлении пристройки.
      final densities = <double>[];
      for (var mm = 200.0; mm <= 6000; mm += 10) {
        densities.add(niceScaleDenominator(450 / mm));
      }
      final sorted = densities.toSet().toList()..sort();
      for (var i = 1; i < sorted.length; i++) {
        expect(
          sorted[i] / sorted[i - 1],
          lessThanOrEqualTo(1.35),
          reason:
              'между 1:${sorted[i - 1]} и 1:${sorted[i]} слишком большой скачок',
        );
      }
      // Крупные подписи остаются читаемыми на А4.
      expect(drawingLabelFontPt, greaterThanOrEqualTo(minDrawingLabelPt));
    });
  });

  testWidgets('пишет PNG-превью масштаба: обычное, Т-1, Т-2', (tester) async {
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = Directory('build/preview')..createSync(recursive: true);
    final cases = <String, WindowParams>{
      'shkala-obyknoe': _plain,
      'shkala-t-1': _tOne,
      'shkala-t-2': _tTwo,
      'shkala-t-2-boka': _tTwoSides,
      'shkala-t-2-skrin': _screenTTwo,
      'shkala-fartuki': _aprons,
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
}
