import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';

bool _inside(List<dynamic> polygon, double x, double y) {
  var inside = false;
  for (var i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
    final xi = polygon[i].dx as double, yi = polygon[i].dy as double;
    final xj = polygon[j].dx as double, yj = polygon[j].dy as double;
    final intersect = ((yi > y) != (yj > y)) &&
        (x < (xj - xi) * (y - yi) / (yj - yi) + xi);
    if (intersect) inside = !inside;
  }
  return inside;
}

void main() {
  test('молния на косом окне не выходит за тент', () {
    const params = WindowParams(
      bottomWidth: 2200,
      topWidth: 1400,
      leftHeight: 2000,
      rightHeight: 2000,
      zippers: [
        ZipperSpec(centered: false, offsetMm: 1900),
        ZipperSpec(centered: false, offsetMm: 300),
      ],
    );
    final spec = WindowSpec.of(params);
    final polygon = spec.layers.edgeInnerPolygons.first;
    for (final band in spec.layers.zipperBands) {
      final centerX = (band.left + band.right) / 2;
      final centerY = (band.top + band.bottom) / 2;
      for (final corner in [
        (band.left, band.top),
        (band.right, band.top),
        (band.left, band.bottom),
        (band.right, band.bottom),
      ]) {
        // Чуть внутрь от кромки: точка ровно на границе — не показатель.
        final x = corner.$1 + (centerX - corner.$1) * 0.02;
        final y = corner.$2 + (centerY - corner.$2) * 0.02;
        expect(
          _inside(polygon, x, y),
          isTrue,
          reason: 'угол полосы ${corner.$1},${corner.$2} вне тента',
        );
      }
    }
  });
}
