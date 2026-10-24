import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/cut_sheet.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

/// «Доп. настройка молнии»: ширина 11 см, деление раскроя на сегменты,
/// зазор 7 см, молния впритык к канту — без деления.
void main() {
  WindowParams base() => const WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        zippers: [ZipperSpec(centered: false, offsetMm: 0)],
      );

  test('по умолчанию — прежний расчёт: одна заготовка, без сегментов', () {
    final params = base().copyWith(
      zippers: [const ZipperSpec(centered: false, offsetMm: 666)],
    );
    final spec = WindowSpec.of(params);
    expect(spec.layers.zipperSegmentLayout, isEmpty);
    expect(spec.filmCutPolygons.length, 1);
    expect(spec.zipperBandTotalMm, defaultZipperBandWidth);
    expect(spec.zipperSegmentsLabel, isEmpty);
  });

  test('тумблер включает 11 см и делит полотно на два сегмента', () {
    final params = base()
        .copyWith(zippers: [const ZipperSpec(centered: false, offsetMm: 1000)])
        .withZipperSegments(true);
    expect(params.zipperSegments, isTrue);
    expect(params.zippers.first.bandWidth, zipperSegmentBandWidth);

    final spec = WindowSpec.of(params);
    final layout = spec.layers.zipperSegmentLayout;
    expect(layout, hasLength(1));
    expect(layout.first.edge, isFalse);
    expect(
      layout.first.gapEnd - layout.first.gapStart,
      closeTo(zipperSegmentBandWidth - 2 * defaultZipperTentOverlapMm, 1e-6),
      reason: '11 − 2 − 2 = 7 см',
    );

    expect(spec.filmCutPolygons.length, 2);
    // Полоса молнии не вычитается из ширины: вместо неё зазор 7 см.
    expect(spec.zipperBandTotalMm, 0);
    final widths = spec.zipperSegmentWidths;
    expect(widths, hasLength(2));
    expect(widths.every((width) => width > 100), isTrue);
    // Сумма сегментов меньше полной ширины ровно на зазор.
    final gapInCut = widths.first + widths.last;
    expect(
      gapInCut,
      lessThan(spec.filmCutWidth),
      reason: 'между сегментами зазор, а не сплошное полотно',
    );
    // Площадь раскроя = сумма площадей сегментов, без двойного счёта.
    final area = spec.filmCutPolygons.fold<double>(
      0,
      (sum, polygon) => sum + polygonArea(polygon).abs(),
    );
    expect(spec.filmCutAreaM2, closeTo(area / 1000000, 1e-9));
    expect(spec.zipperSegmentsLabel, contains('сегментов 2'));
  });

  test('две молнии между кантами — три сегмента', () {
    final params = const WindowParams(
      bottomWidth: 2400,
      topWidth: 2400,
      leftHeight: 2000,
      rightHeight: 2000,
    )
        .copyWith(
          zippers: const [
            ZipperSpec(centered: false, offsetMm: 600),
            ZipperSpec(centered: false, offsetMm: 1800),
          ],
        )
        .withZipperSegments(true);
    final spec = WindowSpec.of(params);
    expect(spec.filmCutPolygons.length, 3);
    expect(spec.zipperSegmentsLabel, contains('сегментов 3'));
    final widths = spec.zipperSegmentWidths;
    expect(widths, hasLength(3));
    expect(widths[0], greaterThan(0));
    expect(widths[2], greaterThan(0));
  });

  test('молния впритык к канту — без сегментов, ширина вычитается', () {
    final params = base().withZipperSegments(true);
    final spec = WindowSpec.of(params);
    final layout = spec.layers.zipperSegmentLayout;
    expect(layout, hasLength(1));
    expect(layout.first.edge, isTrue);
    expect(spec.filmCutPolygons.length, 1);
    // У края тоже учитываем напайку тента на боковой тент: 11 − 2 − 2 = 7 см.
    expect(
      spec.zipperBandTotalMm,
      closeTo(zipperSegmentBandWidth - 2 * defaultZipperTentOverlapMm, 1e-6),
    );
    expect(spec.zipperBandTotalMm, closeTo(70, 1e-6));
    expect(spec.zipperSegmentsLabel, isEmpty);
  });

  test('напайка тента из меню меняет и зазор, и вычет у края', () {
    final params = base()
        .copyWith(
          zippers: [const ZipperSpec(centered: false, offsetMm: 1000)],
          zipperTentOverlap: 30,
        )
        .withZipperSegments(true);
    final spec = WindowSpec.of(params);
    final layout = spec.layers.zipperSegmentLayout.single;
    expect(layout.gapEnd - layout.gapStart, closeTo(110 - 60, 1e-6));

    final edge = base()
        .copyWith(zipperTentOverlap: 30)
        .withZipperSegments(true);
    expect(WindowSpec.of(edge).zipperBandTotalMm, closeTo(110 - 60, 1e-6));
  });

  test('до пяти молний: шестая не добавляется', () {
    var params = const WindowParams(
      bottomWidth: 3000,
      topWidth: 3000,
      leftHeight: 2000,
      rightHeight: 2000,
    );
    for (var i = 0; i < 5; i++) {
      params = params.addZipper();
    }
    expect(params.zippers, hasLength(5));
    expect(params.addZipper().zippers, hasLength(5));
    // Все пять режут полотно на шесть сегментов, если ни одна не у края.
    final segmented = params
        .copyWith(zipperTentOverlap: 20)
        .withZipperSegments(true);
    final spec = WindowSpec.of(segmented);
    final edges = spec.layers.zipperSegmentLayout
        .where((line) => line.edge)
        .length;
    expect(spec.filmCutPolygons.length, 6 - edges);
  });

  test('скрин с доп. настройкой тоже делится на сегменты', () {
    final params = const WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
    )
        .copyWith(
          zippers: const [ZipperSpec(centered: false, offsetMm: 1000)],
        )
        .withZipperSegments(true);
    final spec = WindowSpec.of(params);
    expect(spec.filmCutPolygons.length, 2);
    expect(spec.zipperSegmentWidths.every((width) => width > 100), isTrue);
  });

  test('смета: площадь сегментов без двойного счёта', () {
    final params = base()
        .copyWith(zippers: [const ZipperSpec(centered: false, offsetMm: 1000)])
        .withZipperSegments(true);
    final project = OrderProject(windows: [params]);
    final summary = Estimate.of(project, const PriceList.defaults());
    final material = summary.lines.firstWhere(
      (line) => line.itemKey == PriceItemKeys.filmClear,
    );
    expect(material.quantity, closeTo(WindowSpec.of(params).filmCutAreaM2, 1e-9));
  });

  testWidgets('раскрой рисует сегменты: три контура на листе', (tester) async {
    final params = const WindowParams(
      bottomWidth: 2400,
      topWidth: 2400,
      leftHeight: 2000,
      rightHeight: 2000,
    )
        .copyWith(
          zippers: const [
            ZipperSpec(centered: false, offsetMm: 600),
            ZipperSpec(centered: false, offsetMm: 1800),
          ],
        )
        .withZipperSegments(true);
    final piece = CutPiece.ofSpec(WindowSpec.of(params));
    expect(piece.contours, hasLength(3));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CutSheet(project: OrderProject(windows: [params])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('панель: тумблер включает 11 см', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 6000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    var project = OrderProject(
      windows: [
        const WindowParams().copyWith(
          zippers: const [ZipperSpec(centered: true)],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 420,
            child: StatefulBuilder(
              builder: (context, setState) => ParamsPanel(
                project: project,
                issues: const [],
                onChanged: (value) => setState(() => project = value),
                onReset: () {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.ensureVisible(
      find.byKey(const Key('zipper-segments-toggle')),
    );
    await tester.tap(find.byKey(const Key('zipper-segments-toggle')));
    await tester.pumpAndSettle();
    expect(project.selected.zipperSegments, isTrue);
    expect(project.selected.zippers.first.bandWidth, zipperSegmentBandWidth);
  });
}
