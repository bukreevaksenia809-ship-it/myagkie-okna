import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

/// Раскрой всегда делится на сегменты по молниям (отдельной настройки больше
/// нет). Молния у края не делит полотно, а вычитается из ширины.
void main() {
  WindowParams base([ZipperSpec zipper = const ZipperSpec(centered: true)]) =>
      WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        zippers: [zipper],
      );

  test('молния по центру делит раскрой на два сегмента', () {
    final spec = WindowSpec.of(base());
    expect(spec.layers.zipperSegmentLayout, hasLength(1));
    expect(spec.filmCutPolygons, hasLength(2));
    // Полоса целиком уходит в зазор, из ширины ничего не вычитается.
    expect(spec.zipperBandTotalMm, 0);
    expect(spec.layers.zipperSegmentLayout.single.gapEnd -
        spec.layers.zipperSegmentLayout.single.gapStart, closeTo(75, 1e-9));
    final widths = spec.zipperSegmentWidths;
    expect(widths, hasLength(2));
    expect(widths.every((width) => width > 100), isTrue);
  });

  test('две молнии — три сегмента', () {
    final spec = WindowSpec.of(
      WindowParams(
        bottomWidth: 2400,
        topWidth: 2400,
        leftHeight: 2000,
        rightHeight: 2000,
        zippers: const [
          ZipperSpec(centered: false, offsetMm: 600),
          ZipperSpec(centered: false, offsetMm: 1800),
        ],
      ),
    );
    expect(spec.filmCutPolygons, hasLength(3));
    expect(spec.zipperSegmentsLabel, contains('сегментов 3'));
    expect(spec.zipperSegmentsLabel, contains('общая ширина'));
  });

  test('молния у края не делит полотно и вычитается полосой', () {
    final spec = WindowSpec.of(
      base(const ZipperSpec(centered: false, offsetMm: 0, atEdge: true)),
    );
    expect(spec.filmCutPolygons, hasLength(1));
    // Окантовка 50 + молния 15 + тент 50 − напайка 20 = 95 мм.
    expect(spec.zipperBandTotalMm, closeTo(95, 1e-9));
    expect(spec.layers.zipperSegmentLayout.single.edge, isTrue);
  });

  test('две молнии у краёв: обе вычитаются', () {
    final spec = WindowSpec.of(
      WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        zippers: const [
          ZipperSpec(centered: false, offsetMm: 0, atEdge: true),
          ZipperSpec(
            centered: false,
            offsetMm: 2000,
            atEdge: true,
            edgeRight: true,
          ),
        ],
      ),
    );
    expect(spec.filmCutPolygons, hasLength(1));
    expect(spec.zipperBandTotalMm, closeTo(190, 1e-9));
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
    final spec = WindowSpec.of(params);
    expect(spec.zipperSegmentsLabel, contains('сегментов 6'));
  });
}
