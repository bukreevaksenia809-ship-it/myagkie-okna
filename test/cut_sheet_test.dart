// Тесты листа «Раскрой плёнки»: один общий масштаб заготовок, их порядок,
// отсутствие пересечений, рост листа и PNG-превью.
//
// Запуск: flutter test test/cut_sheet_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';

import 'test_fonts.dart';

/// Заказ из трёх окон: 200 × 200, 150 × 200 и 170 × 300 см.
///
/// Материалы разные, чтобы на превью были видны все три палитры: светлый ПВХ,
/// тонированный ПВХ и москитная сетка с клеткой.
const _w2000 = WindowParams(
  projectName: 'Мягкое окно террасы',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-021',
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _w1500 = WindowParams(
  projectName: 'Мягкое окно террасы',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-022',
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
  material: FilmMaterial.tintedPvc,
);

const _w1700 = WindowParams(
  projectName: 'Мягкое окно террасы',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-023',
  bottomWidth: 1700,
  topWidth: 1700,
  leftHeight: 3000,
  rightHeight: 3000,
  material: FilmMaterial.mosquitoNet,
);

const _order = OrderProject(windows: [_w2000, _w1500, _w1700]);

/// Окно 2000 × 2000 мм с припуском на раскрой +100/+100: изделие остаётся
/// 2000 × 2000, а заготовка к раскрою — 2050 × 2050 мм (до усадки).
const _w2000Allowance = WindowParams(
  projectName: 'Мягкое окно террасы',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-024',
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  allowanceWidthMm: 100,
  allowanceHeightMm: 100,
);

/// Косое окно-трапеция: низ 2000, верх 1000, высота 1000 мм.
const _trapezoid = WindowParams(
  projectName: 'Мягкое окно террасы',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-040',
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  weldOverlapMm: 25,
);

/// Скрин 2000 × 2000 с подворотом 40 и молнией: заготовка на листе «Раскрой»
/// должна быть 1990 × 2060 мм — уже на полосу молнии 50 мм.
const _screenZipper = WindowParams(
  projectName: 'Мягкое окно террасы',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-050',
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2000,
  rightHeight: 2000,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
  zippers: [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)],
);

/// Заказ заказчика: скрин без молнии и с молнией — видно, что заготовка
/// справа уже на полосу (2 080 → 2 030 мм).
const _screenZipperOrder = OrderProject(
  windows: [
    WindowParams(
      projectName: 'Мягкое окно террасы',
      customer: 'Иванов И. И.',
      drawingNumber: 'МО-051',
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      hemBottomMm: 40,
      hemRightMm: 40,
      hemTopMm: 40,
      hemLeftMm: 40,
    ),
    _screenZipper,
  ],
);

/// Порядок для превью: трапеция рядом с прямоугольником — видно, что лист
/// рисует фактическую форму, а не габарит.
const _trapezoidOrder = OrderProject(windows: [_trapezoid, _w2000]);

/// Проверяет, что прямоугольники заготовок не пересекаются.
void _expectNoOverlaps(CutLayout layout) {
  for (var i = 0; i < layout.placements.length; i++) {
    for (var j = i + 1; j < layout.placements.length; j++) {
      final a = layout.placements[i];
      final b = layout.placements[j];
      expect(
        a.rect.overlaps(b.rect),
        isFalse,
        reason: 'Заготовки №${a.index + 1} и №${b.index + 1} пересекаются',
      );
    }
  }
}

void main() {
  final specs = [for (final window in _order.windows) WindowSpec.of(window)];
  final pieces = [for (final spec in specs) CutPiece.ofSpec(spec)];

  group('CutLayout.place', () {
    test('порядок заготовок сохранён, масштаб общий', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));

      expect(layout.placements, hasLength(3));
      expect(layout.scale, greaterThan(0));
      expect(
        [for (final placement in layout.placements) placement.index],
        [0, 1, 2],
      );
      // Один масштаб на все заготовки: стороны прямоугольников относятся
      // так же, как стороны заготовок.
      for (final placement in layout.placements) {
        expect(
          placement.rect.width,
          closeTo(placement.widthMm * layout.scale, 1e-9),
        );
        expect(
          placement.rect.height,
          closeTo(placement.heightMm * layout.scale, 1e-9),
        );
        expect(
          placement.rect.width / placement.rect.height,
          closeTo(placement.piece.aspect, 1e-9),
        );
      }
    });

    test('заготовка равна раскрою плёнки с припуском и усадкой', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));

      for (var i = 0; i < specs.length; i++) {
        final placement = layout.placements[i];
        final spec = specs[i];
        // Заготовка — габарит контура раскроя: припуск на раскрой и усадка
        // уже внутри filmCut*WithShrinkage.
        expect(
          placement.widthMm,
          closeTo(spec.filmCutWidthWithShrinkage, 1e-9),
          reason: 'Окно №${i + 1}, ширина',
        );
        expect(
          placement.heightMm,
          closeTo(spec.filmCutHeightWithShrinkage, 1e-9),
          reason: 'Окно №${i + 1}, высота',
        );
        // Площадь в документе — фактическая, по контуру (у прямоугольника
        // она совпадает с габаритной).
        expect(
          placement.piece.areaM2,
          closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9),
          reason: 'Окно №${i + 1}, площадь по контуру',
        );
        // Без вырезов площадь полигона совпадает с площадью в документах.
        expect(
          placement.piece.areaMm2 / 1000000,
          closeTo(placement.piece.areaM2, 1e-9),
          reason: 'Окно №${i + 1}, площадь полигона заготовки',
        );
      }
    });

    test('трапеция: заготовка — косой четырёхугольник по формуле', () {
      // Окно 2000/1000 × 1000 с запайкой 25 мм: вычет 50 − 25 = 25 мм
      // с каждой стороны. Стороны заготовки считаются по формуле заказчика:
      // низ 2000 − 50 = 1950, верх 1000 − 50 = 950, высоты по 950.
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 1000,
        leftHeight: 1000,
        rightHeight: 1000,
        weldOverlapMm: 25,
      );
      final spec = WindowSpec.of(params);
      final piece = CutPiece.ofSpec(spec);

      expect(piece.hasContour, isTrue);
      expect(piece.outline, hasLength(4));
      // Это трапеция: низ шире верха, боковые стороны уже не прямоугольник.
      expect(spec.blankSideLengths, [1950, 950, 950, 950]);
      final sides = piece.sideLengths;
      expect(sides[0], closeTo(1950, 1e-9));
      expect(sides[1], closeTo(960, 1e-9));
      expect(sides[2], closeTo(950, 1e-9));
      expect(sides[3], closeTo(960, 1e-9));
      expect(piece.widthMm, closeTo(1950, 1e-9));
      expect(piece.heightMm, closeTo(960, 1e-9));
      // Площадь — по формуле Гаусса для трапеции, а не габарит 1950 × 960.
      expect(piece.areaMm2 / 1000000, closeTo(spec.filmCutAreaM2, 1e-9));
      expect(piece.areaMm2 / 1000000, closeTo(1.392, 1e-9));
      expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));
      expect(piece.areaMm2, lessThan(piece.widthMm * piece.heightMm));
      // Раскладка пакует по габариту — это упаковка.
      final layout = CutLayout.place([piece], const Size(1632, 460));
      expect(
        layout.placements.single.rect.width,
        closeTo(piece.widthMm * layout.scale, 1e-9),
      );
      expect(
        layout.placements.single.rect.height,
        closeTo(piece.heightMm * layout.scale, 1e-9),
      );
    });

    test('крупная заготовка выглядит крупнее мелкой', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));

      final first = layout.placements[0].rect;
      final second = layout.placements[1].rect;
      // 2000 × 2000 против 1500 × 2000: шире, значит и площадь на листе больше.
      expect(first.width, greaterThan(second.width));
      expect(
        first.width * first.height,
        greaterThan(second.width * second.height),
      );
    });

    test('заготовки не пересекаются и не выходят за ширину листа', () {
      for (final width in <double>[900, 1280, 1632]) {
        final layout = CutLayout.place(pieces, Size(width, 460));
        _expectNoOverlaps(layout);
        expect(
          layout.contentWidth,
          lessThanOrEqualTo(width + 1e-6),
          reason: 'ширина листа $width',
        );
        for (final placement in layout.placements) {
          expect(placement.rect.left, greaterThanOrEqualTo(-1e-6));
          expect(placement.rect.right, lessThanOrEqualTo(width + 1e-6));
        }
      }
    });

    test('при нехватке ширины заготовки переносятся на следующий ряд', () {
      final wide = CutLayout.place(pieces, const Size(1632, 460));
      final narrow = CutLayout.place(pieces, const Size(600, 900));

      expect(wide.rows, 1);
      expect(narrow.rows, greaterThan(1));
      _expectNoOverlaps(narrow);
      // Порядок окон сохраняется и при переносе.
      expect(
        [for (final placement in narrow.placements) placement.index],
        [0, 1, 2],
      );
      // Второй ряд ниже первого.
      expect(
        narrow.placements[2].rect.top,
        greaterThan(narrow.placements[0].rect.bottom),
      );
    });

    test('мелкие заготовки остаются различимыми', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));
      expect(
        layout.smallestSidePx,
        greaterThanOrEqualTo(CutLayout.minSmallSidePx),
      );
    });

    test('самая крупная заготовка занимает около 75 % полосы ряда', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));
      final tallest = layout.placements
          .map((placement) => placement.rect.height)
          .reduce(math.max);
      // Полоса ряда 460 точек, самая крупная заготовка — 75 % полосы.
      expect(
        tallest / CutLayout.preferredRowHeight,
        inInclusiveRange(0.5, 0.8),
      );
      expect(layout.contentHeight, lessThanOrEqualTo(460 + 1e-6));
    });

    test('пустой заказ даёт пустую раскладку', () {
      final layout = CutLayout.place(const [], const Size(800, 460));

      expect(layout.placements, isEmpty);
      expect(layout.rows, 0);
      expect(layout.contentWidth, 0);
      expect(layout.contentHeight, 0);
    });

    test('нулевые размеры окна не роняют раскладку', () {
      final zero = CutPiece.ofSpec(
        WindowSpec.of(
          const WindowParams(
            bottomWidth: 0,
            topWidth: 0,
            leftHeight: 0,
            rightHeight: 0,
          ),
        ),
      );

      expect(zero.widthMm, greaterThan(0));
      expect(zero.heightMm, greaterThan(0));

      final layout = CutLayout.place([zero, ...pieces], const Size(1200, 460));
      expect(layout.placements, hasLength(4));
      expect(layout.scale, greaterThan(0));
      _expectNoOverlaps(layout);
    });
  });

  group('CutPiece: полоса молнии сужает заготовку скрина', () {
    // Скрин 2000 × 2000, подворот 40 на все стороны: заготовка 2040 × 2060.
    const screen2000 = WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      hemBottomMm: 40,
      hemRightMm: 40,
      hemTopMm: 40,
      hemLeftMm: 40,
    );

    test('прямоугольник: молния по центру делит на два сегмента', () {
      final without = CutPiece.ofSpec(WindowSpec.of(screen2000));
      expect(without.widthMm, closeTo(2040, 1e-9));
      expect(without.heightMm, closeTo(2060, 1e-9));
      expect(without.areaM2, closeTo(4.2024, 1e-9));

      final spec = WindowSpec.of(
        screen2000.copyWith(zippers: const [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)]),
      );
      final piece = CutPiece.ofSpec(spec);

      // Ширина заготовки не меняется: молния уходит в зазор между
      // сегментами, а не вычитается из габарита.
      expect(piece.widthMm, closeTo(2040, 1e-9));
      expect(piece.widthMm, closeTo(spec.filmCutWidthWithShrinkage, 1e-9));
      expect(piece.heightMm, closeTo(2060, 1e-9));
      expect(spec.filmCutPolygons, hasLength(2));
      expect(piece.areaM2, closeTo(4.0994, 1e-9));
      expect(piece.areaM2, lessThan(without.areaM2));
      expect(piece.areaMm2 / 1000000, closeTo(piece.areaM2, 1e-9));
    });

    test('ПВХ: молния по центру делит на сегменты, ширина не меняется', () {
      // ПВХ 2000 × 2000, окантовка 100 (готовая 50), запайка 5:
      // ширина 1910, высота 1910 + авто +10 = 1920.
      const pvc = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
      );
      final plainSpec = WindowSpec.of(pvc);
      final plain = CutPiece.ofSpec(plainSpec);
      expect(plain.widthMm, closeTo(1910, 1e-9));
      expect(plain.heightMm, closeTo(1920, 1e-9));
      expect(plain.areaM2, closeTo(1910 * 1920 / 1e6, 1e-9));

      final spec = WindowSpec.of(
        pvc.copyWith(zippers: const [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)]),
      );
      final piece = CutPiece.ofSpec(spec);
      expect(spec.zipperBandTotalMm, 0);
      expect(piece.widthMm, closeTo(plain.widthMm, 1e-9));
      expect(piece.heightMm, closeTo(1920, 1e-9));
      expect(spec.filmCutPolygons, hasLength(2));
      expect(piece.areaM2, lessThan(plain.areaM2));
      expect(spec.zipperWidthReductionLabel, isNull);
    });

    test('трапеция: молния делит на сегменты, ширина не меняется', () {
      // Трапеция: низ 2000, верх 1000, высота 1000, подворот 40.
      const trapezoid = WindowParams(
        material: FilmMaterial.screen,
        bottomWidth: 2000,
        topWidth: 1000,
        leftHeight: 1000,
        rightHeight: 1000,
        hemBottomMm: 40,
        hemRightMm: 40,
        hemTopMm: 40,
        hemLeftMm: 40,
      );
      final withoutSpec = WindowSpec.of(trapezoid);
      final without = CutPiece.ofSpec(withoutSpec);
      final spec = WindowSpec.of(
        trapezoid.copyWith(zippers: const [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)]),
      );
      final piece = CutPiece.ofSpec(spec);

      expect(without.hasContour, isTrue);
      expect(piece.hasContour, isTrue);
      expect(piece.widthMm, closeTo(without.widthMm, 1e-9));
      expect(piece.heightMm, closeTo(without.heightMm, 1e-9));
      expect(spec.filmCutPolygons, hasLength(2));
      expect(piece.areaM2, lessThan(without.areaM2));
      expect(piece.areaM2, closeTo(spec.filmCutAreaWithShrinkageM2, 1e-9));
      // Раскладка по-прежнему пакует по габариту, но уже узкому.
      final layout = CutLayout.place([piece], const Size(1632, 460));
      expect(
        layout.placements.single.rect.width,
        closeTo(piece.widthMm * layout.scale, 1e-9),
      );
    });
  });

  group('CutSheet.sheetSize — строго один A4', () {
    test('размер не зависит от числа окон и окна программы', () {
      const single = OrderProject(windows: [_w2000]);
      final many = OrderProject(windows: [for (var i = 0; i < 24; i++) _w2000]);

      for (final project in [single, many]) {
        for (final viewport in const [
          Size(1720, 1080),
          Size(900, 300),
          Size(2400, 1800),
        ]) {
          final size = CutSheet.sheetSize(project, viewport);
          expect(size.width, CutSheet.a4Width + 40);
          expect(size.height, CutSheet.a4Height + 40);
        }
      }
    });

    test('24 заготовки помещаются в свободную часть A4', () {
      final many = OrderProject(windows: [for (var i = 0; i < 24; i++) _w2000]);
      final pieces = [
        for (final window in many.windows)
          CutPiece.ofSpec(WindowSpec.of(window)),
      ];
      final area = const Size(
        CutSheet.a4ContentWidth,
        CutSheet.a4ContentHeight,
      );
      final layout = CutLayout.place(pieces, area);
      expect(layout.rows, greaterThan(1));
      expect(layout.contentHeight, lessThanOrEqualTo(area.height + 0.01));
      expect(layout.contentWidth, lessThanOrEqualTo(area.width + 0.01));
    });
  });

  group('CutSheet', () {
    testWidgets('строится для заказа из трёх окон', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1720, 1080);

      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: CutSheet(project: _order)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Раскрой плёнки'), findsOneWidget);
      expect(find.text('Заготовок: 3 шт'), findsOneWidget);
      expect(find.textContaining('Материалы:'), findsOneWidget);
      expect(
        find.textContaining('раскладка на рулоне — на отдельном листе'),
        findsOneWidget,
      );
      expect(find.text('ЗАГОТОВОК'), findsOneWidget);
      // «Площадь заготовок с усадкой» есть и в итогах, и в штампе.
      expect(find.text('ПЛОЩАДЬ ЗАГОТОВОК С УСАДКОЙ'), findsWidgets);
      expect(find.text('БЕЗ УСАДКИ (ПО КОНТУРУ)'), findsOneWidget);
    });

    testWidgets('не падает на пустом заказе', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        const MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: CutSheet(project: OrderProject(windows: [])),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('нет окон'), findsOneWidget);
      expect(find.text('Заготовок: 0 шт'), findsOneWidget);
    });

    testWidgets('строится для длинного заказа', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final many = OrderProject(windows: [for (var i = 0; i < 24; i++) _w2000]);
      final viewport = CutSheet.sheetSize(many, const Size(1720, 1080));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(body: CutSheet(project: many)),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Заготовок: 24 шт'), findsOneWidget);
    });

    testWidgets('пишет PNG-превью листа раскроя', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadRealFonts();

      final many = OrderProject(windows: [for (var i = 0; i < 12; i++) _w2000]);
      const allowanceOrder = OrderProject(windows: [_w2000, _w2000Allowance]);
      final cases = <String, ({Size viewport, OrderProject project})>{
        'raskroy': (
          viewport: CutSheet.sheetSize(_order, const Size(1720, 1080)),
          project: _order,
        ),
        // Припуск на раскрой: заготовка справа крупнее изделия слева.
        'raskroy-pripusk': (
          viewport: CutSheet.sheetSize(allowanceOrder, const Size(1720, 1080)),
          project: allowanceOrder,
        ),
        // Заказ на несколько рядов: лист растёт, заготовки не обрезаются.
        'raskroy-zakaz': (
          viewport: CutSheet.sheetSize(many, const Size(1720, 1080)),
          project: many,
        ),
        // Трапеция рядом с прямоугольником: форма, все четыре стороны и
        // фактическая площадь по контуру.
        'raskroy-trapetsiya': (
          viewport: CutSheet.sheetSize(_trapezoidOrder, const Size(1720, 1080)),
          project: _trapezoidOrder,
        ),
        // Скрин с молнией: заготовка уже на полосу — 1990 × 2060 мм, под
        // площадью и под заготовкой подписано «полоса молнии 50 мм».
        'raskroy-skrin-molniya': (
          viewport: CutSheet.sheetSize(
            _screenZipperOrder,
            const Size(1720, 1080),
          ),
          project: _screenZipperOrder,
        ),
      };

      final directory = Directory('build/preview')..createSync(recursive: true);

      for (final entry in cases.entries) {
        final captureKey = GlobalKey();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = entry.value.viewport;

        await tester.pumpWidget(
          MaterialApp(
            debugShowCheckedModeBanner: false,
            home: Scaffold(
              body: CutSheet(
                project: entry.value.project,
                captureKey: captureKey,
                labelFontFamily: testFontFamily,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final bytes = await tester.runAsync(() async {
          final boundary =
              captureKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 2.0);
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          return data!.buffer.asUint8List();
        });

        final file = File('${directory.path}/${entry.key}.png')
          ..writeAsBytesSync(bytes!);
        expect(file.lengthSync(), greaterThan(5000));
        // ignore: avoid_print
        print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
      }
    });
  });
}
