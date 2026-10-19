// Размеры между центрами креплений на чертеже.
//
// Заказчик: «нужно чтобы на чертеже показывались внутри канта маленькие
// стрелочки с написанным расстоянием между креплениями (люверсами), скобами
// и замками. Показывать от центра крепления до другого центра (цифра между
// двумя центрами). Желательно так, чтобы это было видно на листе А4».
//
// Проверяем ту же функцию [fastenerSpanLabels], которой пользуется пейнтер:
// число подписей, стороны, значения в мм и совпадение с фактическим шагом
// люверсов. Плюс превью A4, чтобы посмотреть на цифры глазами.
//
// Запуск: flutter test test/fastener_spans_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/fastener_spans.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';

import 'test_fonts.dart';

/// Окно из задачи: 2000 × 1500, шаг люверсов 300 мм.
const _window2000x1500 = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  eyeletStep: 300,
  pvcHeightAllowanceEnabled: false,
);

/// Ближайший люверс к точке [point] — чтобы проверить, что подпись стоит
/// ровно между центрами настоящих креплений.
double _nearestEyeletDistance(WindowSpec spec, Offset point) {
  var best = double.infinity;
  for (final eyelet in spec.layers.eyelets) {
    final distance = (eyelet.center - point).distance;
    if (distance < best) best = distance;
  }
  return best;
}

void main() {
  setUpAll(loadRealFonts);

  group('подписи между креплениями: 2000 × 1500, шаг 300', () {
    final spec = WindowSpec.of(_window2000x1500);
    final labels = fastenerSpanLabels(
      spec,
      pxPerMm: 0.378, // масштаб 1:10 на листе А4
    );

    test('подпись на каждой стороне, всего четыре', () {
      expect(labels.length, 4);
      expect(
        labels.map((label) => label.side).toSet(),
        {WindowSide.bottom, WindowSide.right, WindowSide.top, WindowSide.left},
      );
    });

    // Люверсы стоят на середине окантовки (50 мм готовой), поэтому линия
    // центров короче замера на 2 × 25 мм: (2000 − 50) / 7 = 278,6 мм.
    test('низ и верх: (2000 − 50) / 7 = 278,6 мм, шаг повторён 7 раз', () {
      for (final label in labels.where(
        (label) =>
            label.side == WindowSide.bottom || label.side == WindowSide.top,
      )) {
        expect(label.summary, isTrue);
        expect(label.count, 7);
        expect(label.spanMm, closeTo(1950 / 7, 1e-9));
        expect(label.text, 'шаг 278,6 мм × 7');
      }
    });

    test('лево и право: (1500 − 50) / 5 = 290 мм, шаг повторён 5 раз', () {
      for (final label in labels.where(
        (label) =>
            label.side == WindowSide.left || label.side == WindowSide.right,
      )) {
        expect(label.summary, isTrue);
        expect(label.count, 5);
        expect(label.spanMm, closeTo(1450 / 5, 1e-9));
        expect(label.text, 'шаг 290 мм × 5');
      }
    });

    test('значения совпадают с фактическим расстоянием между центрами', () {
      for (final label in labels) {
        // В сводной подписи подписано несколько одинаковых промежутков.
        final between = (label.endMm - label.startMm).distance / label.count;
        expect(
          between,
          closeTo(label.spanMm, 0.02),
          reason: '${label.side?.name}: подпись должна совпадать с шагом',
        );
        // Концы размерной линии — настоящие центры люверсов.
        expect(_nearestEyeletDistance(spec, label.startMm), lessThan(1e-6));
        expect(_nearestEyeletDistance(spec, label.endMm), lessThan(1e-6));
        // Шаг не больше заданного (расстановка округляет число промежутков
        // вверх, поэтому фактический шаг всегда ≤ 300 мм).
        expect(label.spanMm, lessThanOrEqualTo(300 + 1e-9));
        expect(label.spanMm, greaterThan(50));
        // Подпись стоит МЕЖДУ двумя соседними центрами: цифра не налезает
        // на люверс и читается как расстояние между ними.
        final nearest = [...spec.layers.eyelets]
          ..sort(
            (left, right) => (left.center - label.centerMm)
                .distance
                .compareTo((right.center - label.centerMm).distance),
          );
        expect(
          (label.centerMm - (nearest[0].center + nearest[1].center) / 2)
              .distance,
          lessThan(1e-6),
        );
        // ...и эта пара — внутри подписанной стороны.
        final direction = label.endMm - label.startMm;
        final length = direction.distance;
        for (final eyelet in nearest.take(2)) {
          final along =
              ((eyelet.center - label.startMm).dx * direction.dx +
                  (eyelet.center - label.startMm).dy * direction.dy) /
              length;
          expect(along, inInclusiveRange(0, length + 1e-9));
        }
      }
    });

    test('фактический шаг совпадает с eyeletSteps модели', () {
      final steps = spec.layers.eyeletSteps..sort();
      final spans = labels.map((label) => label.spanMm).toList()..sort();
      // В модели по одному шагу на сторону — столько же, сколько подписей.
      expect(steps.length, spans.length);
      for (var i = 0; i < steps.length; i++) {
        expect(spans[i], closeTo(steps[i], 1e-6));
      }
    });
  });

  group('подписи и выключенные стороны', () {
    test('верх без люверсов — подписи сверху нет', () {
      final spec = WindowSpec.of(_window2000x1500.copyWith(noEyeletsTop: true));
      final labels = fastenerSpanLabels(spec, pxPerMm: 0.378);
      expect(
        labels.map((label) => label.side),
        isNot(contains(WindowSide.top)),
        reason: 'нет крепежа — нет и расстояний между ним',
      );
      expect(labels.length, 3);
    });

    test('верх и низ без люверсов — только лево и право', () {
      final spec = WindowSpec.of(
        _window2000x1500.copyWith(noEyeletsTop: true, noEyeletsBottom: true),
      );
      final labels = fastenerSpanLabels(spec, pxPerMm: 0.378);
      expect(labels.length, 2);
      expect(
        labels.map((label) => label.side).toSet(),
        {WindowSide.left, WindowSide.right},
      );
    });

    test('круглые люверсы в углах выключены — шаг всё равно считается', () {
      final spec = WindowSpec.of(
        _window2000x1500.copyWith(roundEyeletsEnabled: false),
      );
      final labels = fastenerSpanLabels(spec, pxPerMm: 0.378);
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(_nearestEyeletDistance(spec, label.startMm), lessThan(1e-6));
        expect(_nearestEyeletDistance(spec, label.endMm), lessThan(1e-6));
      }
    });
  });

  group('сводная подпись вместо цепочки', () {
    test('на мелком масштабе — одна сводная подпись на сторону', () {
      // Фартук сдвигает крайние точки, поэтому шаг на стороне разный и
      // появляется цепочка. На мелком масштабе она не читается — заменяем
      // одной сводной подписью с числом повторений.
      final pocket = WindowSpec.of(
        _window2000x1500.copyWith(pocket: true),
      );
      final chain = fastenerSpanLabels(pocket, pxPerMm: 1.0);
      final compact = fastenerSpanLabels(pocket, pxPerMm: 0.01);
      expect(
        chain.where((label) => !label.summary),
        isNotEmpty,
        reason: 'крупный масштаб — цепочка между соседними креплениями',
      );
      expect(
        compact.every((label) => label.summary),
        isTrue,
        reason: 'мелкий масштаб — только сводные подписи',
      );
      // Сводная подпись считает те же промежутки и помечает шаг как примерный.
      final right = compact.firstWhere(
        (label) => label.side == WindowSide.right,
      );
      expect(right.approximate, isTrue);
      expect(right.count, 5);
      expect(right.text, contains('≈'));
      expect(right.text, endsWith('× 5'));
    });

    test('короткий промежуток не подписывается цепочкой', () {
      final spec = WindowSpec.of(_window2000x1500.copyWith(pocket: true));
      // 22 px на промежуток 240 мм — порог 15.7 px, цепочка ещё помещается.
      final fits = fastenerSpanLabels(spec, pxPerMm: 0.12, minSpanPx: 22);
      // 8 px на промежуток 240 мм — уже нет, остаются сводные подписи.
      final tight = fastenerSpanLabels(spec, pxPerMm: 0.03, minSpanPx: 22);
      expect(tight.length, lessThan(fits.length));
      expect(tight.every((label) => label.summary), isTrue);
    });
  });

  group('Т-образное окно', () {
    const tShape = WindowParams(
      windowType: WindowType.tShape,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      tSide: TShapeSide.right,
      tWidth: 800,
      tHeight: 600,
      tOffset: 200,
      eyeletStep: 300,
      pvcHeightAllowanceEnabled: false,
    );

    test('размеры строятся по кромкам частей и не берут пустые стороны', () {
      final spec = WindowSpec.of(tShape);
      final labels = fastenerSpanLabels(spec, pxPerMm: 0.378);
      expect(labels, isNotEmpty);
      for (final label in labels) {
        expect(_nearestEyeletDistance(spec, label.startMm), lessThan(1e-6));
        expect(_nearestEyeletDistance(spec, label.endMm), lessThan(1e-6));
        expect(label.spanMm, lessThanOrEqualTo(300 + 1e-9));
      }
      // Все стороны контура с крепежом подписаны, всего их семь.
      expect(labels.length, 7);
    });
  });

  group('длина подписи и узкий кант', () {
    test('в узком канте (1:20) — компактная подпись без слова «шаг»', () {
      // Полоса 50 мм в масштабе 1:20 — около 12,6 точки: длинная строка
      // «шаг 278,6 мм × 7» между двумя люверсами не встаёт и налезала бы на
      // кольца. Тогда подпись — только цифры и число повторений.
      final narrow = fastenerSpanLabels(
        WindowSpec.of(_window2000x1500),
        pxPerMm: 0.189,
      );
      final bottom = narrow.firstWhere(
        (label) => label.side == WindowSide.bottom,
      );
      expect(bottom.compact, isTrue);
      expect(bottom.text, '278,6 × 7');
      // В широком канте (1:10) помещается подробная подпись.
      final wide = fastenerSpanLabels(
        WindowSpec.of(_window2000x1500),
        pxPerMm: 0.378,
      );
      final wideBottom = wide.firstWhere(
        (label) => label.side == WindowSide.bottom,
      );
      expect(wideBottom.compact, isFalse);
      expect(wideBottom.text, 'шаг 278,6 мм × 7');
    });
  });

  group('кегль подписи', () {
    test('не мельче 6,5 pt там, где подписи вообще рисуются', () {
      for (final bandPx in [6.0, 8.0, 12.6, 18.9, 30.0, 60.0]) {
        expect(
          fastenerSpanFontSizePt(bandPx),
          greaterThanOrEqualTo(minFastenerSpanPt),
          reason: 'полоса $bandPx px',
        );
      }
      // В узкой окантовке (1:15) цифры всё ещё читаются на А4.
      expect(fastenerSpanFontSizePt(12.6), greaterThanOrEqualTo(6.5));
      // В широкой (1:10) — крупнее.
      expect(
        fastenerSpanFontSizePt(18.9),
        greaterThan(fastenerSpanFontSizePt(12.6)),
      );
    });
  });

  testWidgets('пишет PNG-превью размеров между креплениями', (tester) async {
    tester.view.physicalSize = const Size(
      DrawingSheet.a4Width + 40,
      DrawingSheet.a4Height + 40,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final directory = Directory('build/preview')..createSync(recursive: true);
    final cases = <String, WindowParams>{
      'razmery-krepezha-2000x1500': _window2000x1500,
      'razmery-krepezha-fartuk': _window2000x1500.copyWith(pocket: true),
      'razmery-krepezha-skrin': WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 1500,
        rightHeight: 1500,
        eyeletStep: 300,
        hemBottomMm: 40,
        hemRightMm: 40,
        hemTopMm: 60,
        hemLeftMm: 40,
      ),
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
  });
}
