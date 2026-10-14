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
        // Заготовка — прямоугольник по габаритам раскроя: припуск на раскрой
        // и усадка уже внутри filmCut*WithShrinkage.
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
        // Площадь заготовки — это площадь к раскрою (с припуском) с усадкой.
        final factor = 1 + spec.params.shrinkagePercent / 100;
        expect(
          placement.widthMm * placement.heightMm / 1000000,
          closeTo(spec.filmCutAreaM2 * factor * factor, 1e-9),
          reason: 'Окно №${i + 1}, площадь',
        );
      }
    });

    test('крупная заготовка выглядит крупнее мелкой', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));

      final first = layout.placements[0].rect;
      final second = layout.placements[1].rect;
      // 2000 × 2000 против 1500 × 2000: шире, значит и площадь на листе больше.
      expect(first.width, greaterThan(second.width));
      expect(first.width * first.height, greaterThan(second.width * second.height));
    });

    test('заготовки не пересекаются и не выходят за ширину листа', () {
      for (final width in <double>[900, 1280, 1632]) {
        final layout = CutLayout.place(pieces, Size(width, 460));
        _expectNoOverlaps(layout);
        expect(layout.contentWidth, lessThanOrEqualTo(width + 1e-6),
            reason: 'ширина листа $width');
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
      expect(narrow.placements[2].rect.top,
          greaterThan(narrow.placements[0].rect.bottom));
    });

    test('мелкие заготовки остаются различимыми', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));
      expect(layout.smallestSidePx, greaterThanOrEqualTo(CutLayout.minSmallSidePx));
    });

    test('самая крупная заготовка занимает около 75 % полосы ряда', () {
      final layout = CutLayout.place(pieces, const Size(1632, 460));
      final tallest = layout.placements
          .map((placement) => placement.rect.height)
          .reduce(math.max);
      // Полоса ряда 460 точек, самая крупная заготовка — 75 % полосы.
      expect(tallest / CutLayout.preferredRowHeight, closeTo(0.75, 1e-9));
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
      final zero = CutPiece.ofSpec(WindowSpec.of(const WindowParams(
        bottomWidth: 0,
        topWidth: 0,
        leftHeight: 0,
        rightHeight: 0,
      )));

      expect(zero.widthMm, greaterThan(0));
      expect(zero.heightMm, greaterThan(0));

      final layout = CutLayout.place([zero, ...pieces], const Size(1200, 460));
      expect(layout.placements, hasLength(4));
      expect(layout.scale, greaterThan(0));
      _expectNoOverlaps(layout);
    });
  });

  group('CutSheet.sheetSize', () {
    test('одно окно: null или непустой размер', () {
      const single = OrderProject(windows: [_w2000]);
      final size = CutSheet.sheetSize(single, const Size(1720, 1080));

      // Одно окно влезает — лист заполняет окно программы.
      expect(size, isNull);

      // В низком окне лист растёт, но остаётся корректным.
      final small = CutSheet.sheetSize(single, const Size(900, 300));
      expect(small, isNotNull);
      expect(small!.width, greaterThan(0));
      expect(small.height, greaterThan(300));
    });

    test('лист растёт, когда заготовок много', () {
      const single = OrderProject(windows: [_w2000]);
      final many = OrderProject(
        windows: [for (var i = 0; i < 24; i++) _w2000],
      );

      final oneSize = CutSheet.sheetSize(single, const Size(1720, 1080));
      final manySize = CutSheet.sheetSize(many, const Size(1720, 1080));

      expect(manySize, isNotNull);
      expect(manySize!.height, greaterThan(1080));
      expect(manySize.height, greaterThan(oneSize?.height ?? 0));
      expect(manySize.width, greaterThan(0));
    });

    test('рост листа согласован с раскладкой', () {
      final many = OrderProject(windows: [for (var i = 0; i < 24; i++) _w2000]);
      final size = CutSheet.sheetSize(many, const Size(1720, 1080))!;
      final contentWidth = size.width - 80;
      final layout = CutLayout.natural(
        [for (final window in many.windows) CutPiece.ofSpec(WindowSpec.of(window))],
        contentWidth,
      );

      // Лист ровно вмещает раскладку: заготовки не обрезаны, обвязка — это
      // подпись листа, итоги, штамп и поля вокруг.
      expect(layout.rows, greaterThan(1));
      expect(size.height - layout.contentHeight, inInclusiveRange(200, 400));
    });
  });

  group('CutSheet', () {
    testWidgets('строится для заказа из трёх окон', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1720, 1080);

      await tester.pumpWidget(const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: CutSheet(project: _order)),
      ));
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
      // «Площадь заготовок» есть и в итогах, и в штампе.
      expect(find.text('ПЛОЩАДЬ ЗАГОТОВОК'), findsWidgets);
      expect(find.text('С УЧЁТОМ УСАДКИ'), findsOneWidget);
    });

    testWidgets('не падает на пустом заказе', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: CutSheet(project: OrderProject(windows: []))),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.textContaining('нет окон'), findsOneWidget);
      expect(find.text('Заготовок: 0 шт'), findsOneWidget);
    });

    testWidgets('строится для длинного заказа', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final many = OrderProject(windows: [for (var i = 0; i < 24; i++) _w2000]);
      final viewport =
          CutSheet.sheetSize(many, const Size(1720, 1080)) ?? const Size(1720, 1080);
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = viewport;

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(body: CutSheet(project: many)),
      ));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Заготовок: 24 шт'), findsOneWidget);
    });

    testWidgets('пишет PNG-превью листа раскроя', (tester) async {
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await loadRealFonts();

      final many = OrderProject(windows: [for (var i = 0; i < 12; i++) _w2000]);
      const allowanceOrder =
          OrderProject(windows: [_w2000, _w2000Allowance]);
      final cases = <String, ({Size viewport, OrderProject project})>{
        'raskroy': (
          viewport:
              CutSheet.sheetSize(_order, const Size(1720, 1080)) ?? const Size(1720, 1080),
          project: _order,
        ),
        // Припуск на раскрой: заготовка справа крупнее изделия слева.
        'raskroy-pripusk': (
          viewport:
              CutSheet.sheetSize(allowanceOrder, const Size(1720, 1080)) ??
                  const Size(1720, 1080),
          project: allowanceOrder,
        ),
        // Заказ на несколько рядов: лист растёт, заготовки не обрезаются.
        'raskroy-zakaz': (
          viewport:
              CutSheet.sheetSize(many, const Size(1720, 1080)) ?? const Size(1720, 1080),
          project: many,
        ),
      };

      final directory = Directory('build/preview')..createSync(recursive: true);

      for (final entry in cases.entries) {
        final captureKey = GlobalKey();
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = entry.value.viewport;

        await tester.pumpWidget(MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: CutSheet(
              project: entry.value.project,
              captureKey: captureKey,
              labelFontFamily: testFontFamily,
            ),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final bytes = await tester.runAsync(() async {
          final boundary = captureKey.currentContext!.findRenderObject()!
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
