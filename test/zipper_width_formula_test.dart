import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  WindowParams base({double edge = 100, List<ZipperSpec> zippers = const []}) =>
      WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        rollBottom: edge,
        rollRight: edge,
        rollTop: edge,
        rollLeft: edge,
        zippers: zippers,
      );

  test('молния посередине: 15 + 2×50 − 2×20 = 75 мм', () {
    final spec = WindowSpec.of(
      base(
        zippers: const [
          ZipperSpec(centered: false, offsetMm: 1000),
        ],
      ),
    );
    // Полоса 75 мм уходит в зазор между сегментами, ширина не меняется.
    expect(spec.zipperBandTotalMm, 0);
    expect(spec.filmCutPolygons, hasLength(2));
    expect(spec.layers.zipperSegmentLayout.single.gapEnd -
        spec.layers.zipperSegmentLayout.single.gapStart, closeTo(75, 1e-9));
    expect(spec.filmCutWidth, closeTo(1910, 1e-9));
  });

  test('молния у края: 150 + 15 + 50 − 20 = 195 мм', () {
    final spec = WindowSpec.of(
      base(
        edge: 300,
        zippers: const [
          ZipperSpec(centered: false, offsetMm: 0, atEdge: true),
        ],
      ),
    );
    expect(spec.zipperBandTotalMm, closeTo(195, 1e-9));
    // Полоса прижата к левой окантовке.
    final band = spec.layers.zippers.first;
    expect(
      band.start.dx - band.bandWidth / 2,
      closeTo(spec.layers.filmVisibleBounds.left, 1e-6),
    );
  });

  test('молния у правого края прижимается вправо', () {
    final spec = WindowSpec.of(
      base(
        edge: 300,
        zippers: const [
          ZipperSpec(
            centered: false,
            offsetMm: 2000,
            atEdge: true,
            edgeRight: true,
          ),
        ],
      ),
    );
    final band = spec.layers.zippers.first;
    expect(
      band.start.dx + band.bandWidth / 2,
      closeTo(spec.layers.filmVisibleBounds.right, 1e-6),
    );
  });

  test('окно 4200×2350, бока 150: молния слева даёт 3745 мм', () {
    const params = WindowParams(
      bottomWidth: 4200,
      topWidth: 4200,
      leftHeight: 2350,
      rightHeight: 2350,
      rollBottom: 400,
      rollRight: 300,
      rollTop: 400,
      rollLeft: 300,
      weldOverlapMm: 20,
      zippers: [
        ZipperSpec(centered: false, offsetMm: 0, atEdge: true),
      ],
    );
    final spec = WindowSpec.of(params);
    expect(spec.layers.finishedWidths, [200, 150, 200, 150]);
    expect(spec.zipperBandTotalMm, closeTo(195, 1e-9));
    expect(spec.filmCutWidth, closeTo(4200 - 300 + 40 - 195, 1e-9));
    expect(spec.filmCutWidth, closeTo(3745, 1e-9));
    expect(spec.filmCutHeight, closeTo(2350 - 400 + 40, 1e-9));
  });

  test('две молнии у краёв считаются обе', () {
    final spec = WindowSpec.of(
      const WindowParams(
        bottomWidth: 4200,
        topWidth: 4200,
        leftHeight: 2350,
        rightHeight: 2350,
        rollBottom: 400,
        rollRight: 300,
        rollTop: 400,
        rollLeft: 300,
        weldOverlapMm: 20,
        zippers: [
          ZipperSpec(centered: false, offsetMm: 0, atEdge: true),
          ZipperSpec(
            centered: false,
            offsetMm: 4200,
            atEdge: true,
            edgeRight: true,
          ),
        ],
      ),
    );
    expect(spec.zipperBandTotalMm, closeTo(390, 1e-9));
    expect(spec.filmCutWidth, closeTo(3940 - 390, 1e-9));
    final bands = spec.layers.zippers;
    expect(bands, hasLength(2));
    expect(bands[0].bandWidth, closeTo(195, 1e-9));
    expect(bands[1].bandWidth, closeTo(195, 1e-9));
  });

  test('свои значения ширины молнии и тента', () {
    final spec = WindowSpec.of(
      base(
        edge: 300,
        zippers: const [
          ZipperSpec(
            centered: false,
            offsetMm: 0,
            atEdge: true,
            zipWidthMm: 20,
            tentWidthMm: 40,
            weldMm: 10,
          ),
        ],
      ),
    );
    expect(spec.zipperBandTotalMm, closeTo(150 + 20 + 40 - 10, 1e-9));
  });
}
