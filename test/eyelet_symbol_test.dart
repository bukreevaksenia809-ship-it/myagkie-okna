// Люверсы и крепёж на мелком масштабе: символ не превращается в точку.
//
// Раньше при 1:20–1:50 люверс рисовался кружком 5 точек и читался как
// «просто точки». Теперь у символа есть минимальный размер в точках листа:
// кольцо с отверстием и металлическим блеском. Тесты проверяют формулу
// размера и пишут PNG-превью для 1:10 … 1:50.
//
// Запуск: flutter test test/eyelet_symbol_test.dart
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

import 'test_fonts.dart';

/// Окно 2000 × 1500 с люверсами: окантовка 200 мм (готовая 100 мм), шаг
/// 300 мм. На 1:20–1:50 именно такое окно заказчик видел «в точках».
const _eyeletWindow = WindowParams(
  projectName: 'Мягкое окно, люверсы',
  drawingNumber: 'ЛЮВ-2000',
  windowType: WindowType.lifting,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  rollBottom: 200,
  rollRight: 200,
  rollTop: 200,
  rollLeft: 200,
  weldOverlapMm: 5,
  eyeletStep: 300,
  fastenerType: FastenerType.eyeletsOnly,
);

/// Пикселей на миллиметр для знаменателя масштаба.
double _pxPerMm(double denominator) => (96 / 25.4) / denominator;

void main() {
  setUpAll(loadRealFonts);

  group('eyeletDrawSize', () {
    test('на 1:10 размер честный и больше минимума', () {
      final size = eyeletDrawSize(_pxPerMm(10));
      final actual = 22 * _pxPerMm(10);
      expect(size, closeTo(actual, 1e-9));
      expect(size, greaterThanOrEqualTo(minEyeletOuterPx));
    });

    test('на 1:20, 1:30 и 1:50 символ не меньше 7 точек', () {
      for (final denominator in [20.0, 30.0, 50.0]) {
        final size = eyeletDrawSize(_pxPerMm(denominator));
        expect(
          size,
          greaterThanOrEqualTo(minEyeletOuterPx),
          reason: '1:$denominator — люверс не должен стать точкой',
        );
      }
    });

    test('1:50 и 1:10 дают разные размеры, минимум соблюдён', () {
      final small = eyeletDrawSize(_pxPerMm(50));
      final large = eyeletDrawSize(_pxPerMm(10));
      expect(small, isNot(closeTo(large, 1e-6)));
      expect(large, greaterThan(small));
      expect(small, greaterThanOrEqualTo(minEyeletOuterPx));
    });

    test('плотная расстановка ужимает символ только до минимума', () {
      // При 1:10 честный размер 8,3 точки; сосед в 10 точках требует 6,25.
      final dense = eyeletDrawSize(_pxPerMm(10), spacingPx: 10);
      expect(dense, closeTo(minEyeletOuterPx, 1e-9));
      // Совсем плотная — всё равно не меньше минимума.
      final veryDense = eyeletDrawSize(_pxPerMm(10), spacingPx: 3);
      expect(veryDense, closeTo(minEyeletOuterPx, 1e-9));
    });

    test('отверстие не меньше 2,5 точки и оставляет кольцо', () {
      final hole = eyeletHoleDrawSize(
        minEyeletOuterPx,
        actualHoleMm: 10,
        pxPerMm: _pxPerMm(50),
      );
      expect(hole, greaterThanOrEqualTo(minEyeletHolePx));
      expect(hole, lessThanOrEqualTo(minEyeletOuterPx * 0.5));
    });
  });

  group('fastenerDrawSize', () {
    test('скоба/замок на 1:50 не меньше 16 точек', () {
      final size = fastenerDrawSize(
        _pxPerMm(50),
        bandWidthMm: 100,
        factor: 0.7,
      );
      expect(size, greaterThanOrEqualTo(minFastenerPx));
    });

    test('на крупном масштабе размер честный', () {
      final size = fastenerDrawSize(
        _pxPerMm(5),
        bandWidthMm: 100,
        factor: 0.7,
      );
      expect(size, closeTo(100 * 0.7 * _pxPerMm(5), 1e-9));
      expect(size, greaterThan(minFastenerPx));
    });
  });

  testWidgets('пишет PNG-превью люверсов на 1:10 … 1:50', (tester) async {
    final spec = WindowSpec.of(_eyeletWindow);
    final directory = Directory('build/preview')..createSync(recursive: true);

    for (final denominator in [10.0, 15.0, 20.0, 30.0, 50.0]) {
      final scale = _pxPerMm(denominator);
      const padLeft = 84.0;
      const padRight = 84.0;
      const padTop = 60.0;
      const padBottom = 76.0;
      final size = Size(
        padLeft + padRight + spec.geometry.spanX * scale,
        padTop + padBottom + spec.geometry.spanY * scale,
      );
      final layout = DrawingLayout.forScaleDenominator(
        size: size,
        geometry: spec.geometry,
        scaleDenominator: denominator,
      );
      final painter = WindowDrawingPainter(
        params: spec.params,
        layout: layout,
        layers: spec.layers,
        options: const DrawingOptions(),
        labelFontFamily: testFontFamily,
      );
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        const pixelRatio = 4.0;
        final canvas = Canvas(
          recorder,
          Offset.zero & Size(size.width * pixelRatio, size.height * pixelRatio),
        );
        canvas.scale(pixelRatio);
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0xFFFFFFFF),
        );
        painter.paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          (size.width * 4).round(),
          (size.height * 4).round(),
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      final label = denominator
          .toStringAsFixed(0)
          .replaceAll('.', '-');
      final file = File('${directory.path}/lyuversy-1-$label.png')
        ..writeAsBytesSync(bytes!);
      expect(file.lengthSync(), greaterThan(5000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    }
  });
}
