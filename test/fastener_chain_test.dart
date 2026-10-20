// Накопительная цепочка расстояний между креплениями и настройка размеров
// подписей.
//
// Заказчик: «сделать цифрами расстояние люверсов друг от друга, писать НЕ на
// люверсе, а немного сбоку от канта... на втором люверсе пишем расстояние от
// первого; на третьем — сумму... то есть накопленное расстояние от угла».
// Высоты — сверху вниз, ширины — слева направо.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/fastener_spans.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/label_settings.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/drawing_sheet.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

import 'test_fonts.dart';

const _window2000x1500 = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  eyeletStep: 300,
  pvcHeightAllowanceEnabled: false,
);

const _windowOffset50 = WindowParams(
  projectName: 'Окно с отступом люверсов',
  drawingNumber: 'КРЕП-50',
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
  eyeletStep: 300,
  eyeletCornerOffset: 50,
  pvcHeightAllowanceEnabled: false,
);

List<FastenerChainLabel> _side(
  List<FastenerChainLabel> labels,
  WindowSide side,
) =>
    labels.where((label) => label.side == side).toList()
      ..sort((a, b) => a.positionMm.compareTo(b.positionMm));

void main() {
  setUpAll(loadRealFonts);

  group('накопительная цепочка: окно 2000 × 1500, шаг 300, отступ 0', () {
    final spec = WindowSpec.of(_window2000x1500);
    final labels = fastenerChainLabels(spec);
    final bottom = _side(labels, WindowSide.bottom);
    final right = _side(labels, WindowSide.right);
    final top = _side(labels, WindowSide.top);
    final left = _side(labels, WindowSide.left);

    test('на каждой стороне по 8 подписей: углы и 7 промежутков', () {
      expect(bottom, hasLength(8));
      expect(right, hasLength(6));
      expect(top, hasLength(8));
      expect(left, hasLength(6));
    });

    test('низ: 0, 278,6, 557,1, … — накопленное расстояние от угла', () {
      // Люверсы стоят на середине канта, линия центров 1 950 мм, 7 шагов.
      expect(bottom.first.cumulativeMm, closeTo(0, 1e-9));
      expect(bottom[1].cumulativeMm, closeTo(1950 / 7, 1e-9));
      expect(bottom[2].cumulativeMm, closeTo(2 * 1950 / 7, 1e-9));
      expect(bottom[3].cumulativeMm, closeTo(3 * 1950 / 7, 1e-9));
      expect(bottom.last.cumulativeMm, closeTo(1950, 1e-9));
      expect(bottom.first.text, '0');
      expect(bottom[1].text, '278,6');
      expect(bottom[2].text, '557,1');
      expect(bottom[3].text, '835,7');
      // «Расстояние от угла» — это и есть позиция вдоль стороны.
      for (final label in bottom) {
        expect(label.cumulativeMm, closeTo(label.positionMm, 1e-9));
      }
    });

    test('право и лево: 0 сверху, дальше вниз (высоты сверху вниз)', () {
      for (final side in [right, left]) {
        expect(side.first.cumulativeMm, closeTo(0, 1e-9));
        expect(side[1].cumulativeMm, closeTo(1450 / 5, 1e-9));
        expect(side.last.cumulativeMm, closeTo(1450, 1e-9));
        // Первая точка — у ВЕРХНЕГО угла, последняя — у нижнего.
        expect(side.first.pointMm.dy, greaterThan(side.last.pointMm.dy));
      }
    });

    test('низ и верх идут слева направо', () {
      for (final side in [bottom, top]) {
        expect(side.first.pointMm.dx, lessThan(side.last.pointMm.dx));
        expect(side.first.pointMm.dx, closeTo(25, 1e-6));
      }
    });

    test('подписи стоят в центрах настоящих люверсов', () {
      for (final label in labels) {
        final nearest = spec.layers.eyelets
            .map((eyelet) => (eyelet.center - label.pointMm).distance)
            .reduce((a, b) => a < b ? a : b);
        expect(nearest, lessThan(1e-6));
      }
    });
  });

  group('отступ 50 мм: первая подпись — величина отступа', () {
    final spec = WindowSpec.of(_windowOffset50);
    final labels = fastenerChainLabels(spec);

    test('низ: 50, 314,3, 578,6, …', () {
      final bottom = _side(labels, WindowSide.bottom);
      final step = (1950 - 100) / 7;
      expect(bottom.first.cumulativeMm, closeTo(50, 1e-9));
      expect(bottom.first.text, '50');
      expect(bottom[1].cumulativeMm, closeTo(50 + step, 1e-9));
      expect(bottom.last.cumulativeMm, closeTo(1900, 1e-9));
    });

    test('лево и право: 50 от верхнего угла, затем накопление вниз', () {
      for (final side in [
        _side(labels, WindowSide.left),
        _side(labels, WindowSide.right),
      ]) {
        final step = (1450 - 100) / 5;
        expect(side.first.cumulativeMm, closeTo(50, 1e-9));
        expect(side[1].cumulativeMm, closeTo(50 + step, 1e-9));
        expect(side.first.pointMm.dy, greaterThan(side.last.pointMm.dy));
      }
    });
  });

  group('стороны без крепежа и выключенные углы', () {
    test('верх без люверсов — подписей сверху нет', () {
      final spec = WindowSpec.of(_window2000x1500.copyWith(noEyeletsTop: true));
      final labels = fastenerChainLabels(spec);
      expect(
        labels.map((label) => label.side),
        isNot(contains(WindowSide.top)),
      );
    });

    test('верх и низ без люверсов — только лево и право', () {
      final spec = WindowSpec.of(
        _window2000x1500.copyWith(noEyeletsTop: true, noEyeletsBottom: true),
      );
      final labels = fastenerChainLabels(spec);
      expect(labels.map((label) => label.side).toSet(), {
        WindowSide.left,
        WindowSide.right,
      });
    });

    test('круглые угловые люверсы выключены — первая цифра не 0', () {
      final spec = WindowSpec.of(
        _window2000x1500.copyWith(roundEyeletsEnabled: false),
      );
      final bottom = _side(fastenerChainLabels(spec), WindowSide.bottom);
      expect(bottom.first.cumulativeMm, closeTo(1950 / 7, 1e-9));
    });
  });

  group('настройка размеров подписей', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      LabelSettings.resetForTest();
    });

    tearDown(LabelSettings.resetForTest);

    test('изменение размера сохраняется и загрузка возвращает его', () async {
      await LabelSettings.setSize(LabelKind.fastenerChain, 14.5);
      await LabelSettings.setSize(LabelKind.stamp, 22);
      expect(LabelSettings.value.ptFor(LabelKind.fastenerChain), 14.5);
      expect(LabelSettings.value.ptFor(LabelKind.stamp), 22);
      // Новая «сессия»: сбрасываем память и читаем из shared_preferences.
      LabelSettings.resetForTest();
      await LabelSettings.load();
      expect(LabelSettings.value.ptFor(LabelKind.fastenerChain), 14.5);
      expect(LabelSettings.value.ptFor(LabelKind.stamp), 22);
      // Остальные — стандартные.
      expect(
        LabelSettings.value.ptFor(LabelKind.dimensionChain),
        LabelKind.dimensionChain.defaultPt,
      );
    });

    test('сброс к стандартным возвращает все восемь размеров', () async {
      await LabelSettings.setSize(LabelKind.legend, 24);
      await LabelSettings.resetToDefaults();
      expect(LabelSettings.value.isDefault, isTrue);
      LabelSettings.resetForTest();
      await LabelSettings.load();
      expect(LabelSettings.value.isDefault, isTrue);
    });

    test('границы 5…24 pt соблюдаются', () async {
      await LabelSettings.setSize(LabelKind.notes, 100);
      expect(LabelSettings.value.ptFor(LabelKind.notes), 24);
      await LabelSettings.setSize(LabelKind.notes, -5);
      expect(LabelSettings.value.ptFor(LabelKind.notes), 5);
    });

    test('shouldRepaint реагирует на новый размер подписей', () {
      final params = _window2000x1500;
      final spec = WindowSpec.of(params);
      final layout = DrawingLayout(
        size: const Size(800, 800),
        geometry: spec.geometry,
      );
      final base = LabelSettings.defaults();
      WindowDrawingPainter painter(LabelSettings settings) =>
          WindowDrawingPainter(
            params: params,
            layout: layout,
            layers: spec.layers,
            options: const DrawingOptions(),
            labelSettings: settings,
          );
      expect(painter(base).shouldRepaint(painter(base)), isFalse);
      expect(
        painter(
          base.withSize(LabelKind.dimensionChain, 16),
        ).shouldRepaint(painter(base)),
        isTrue,
      );
      expect(
        painter(
          base.withSize(LabelKind.fastenerChain, 16),
        ).shouldRepaint(painter(base)),
        isTrue,
      );
      expect(
        painter(
          base.withSize(LabelKind.cutSheet, 16),
        ).shouldRepaint(painter(base)),
        isTrue,
        reason: 'размер листа «Раскрой» тоже участвует в сравнении',
      );

      final piece = CutPiece.ofSpec(spec);
      final cutLayout = CutLayout.place([piece], const Size(900, 600));
      final specs = [spec];
      CutSheetPainter cutPainter(LabelSettings settings) => CutSheetPainter(
        specs: specs,
        layout: cutLayout,
        labelSettings: settings,
      );
      expect(cutPainter(base).shouldRepaint(cutPainter(base)), isFalse);
      expect(
        cutPainter(
          base.withSize(LabelKind.cutSheet, 18),
        ).shouldRepaint(cutPainter(base)),
        isTrue,
      );
    });
  });

  testWidgets('превью: цепочка сбоку от канта и максимальные подписи', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(LabelSettings.resetForTest);
    SharedPreferences.setMockInitialValues({});
    LabelSettings.resetForTest();

    final a4 = Size(DrawingSheet.a4Width + 40, DrawingSheet.a4Height + 40);

    Future<void> shoot(String name, String? fontFamily) async {
      tester.view.physicalSize = a4;
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: DrawingSheet(
              project: const OrderProject(windows: [_windowOffset50]),
              captureKey: key,
              labelFontFamily: fontFamily,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final bytes = await tester.runAsync(() async {
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        return data!.buffer.asUint8List();
      });
      final file = File('build/preview/$name.png')..writeAsBytesSync(bytes!);
      expect(file.lengthSync(), greaterThan(5000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    }

    await shoot('krepezh-tsepochka', testFontFamily);

    // Максимум 24 pt по всем восьми типам: подписи не должны вылезать за
    // лист и ронять отрисовку. Смотрим глазами по podpisi-max.png.
    for (final kind in LabelKind.values) {
      await LabelSettings.setSize(kind, 24);
    }
    await shoot('podpisi-max', testFontFamily);
  });
}
