import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/window_params.dart';

/// Модель составного окна: значения по умолчанию, JSON и обратная
/// совместимость со старыми заказами.
void main() {
  group('CompositeSpec', () {
    test('по умолчанию: скрин справа, прямой шов', () {
      const spec = CompositeSpec();
      expect(spec.side, EdgeSide.right);
      expect(spec.material, FilmMaterial.screen);
      expect(spec.isScreen, isTrue);
      expect(spec.isDiagonal, isFalse);
      expect(spec.width, greaterThan(0));
      expect(spec.depth, greaterThan(0));
    });

    test('диагональный шов: угол переводится в радианы', () {
      const spec = CompositeSpec(seam: CompositeSeam.diagonal, seamAngleDeg: 30);
      expect(spec.isDiagonal, isTrue);
      expect(spec.seamAngleRad, closeTo(0.5236, 1e-4));
    });

    test('copyWith меняет только заданные поля', () {
      const spec = CompositeSpec(width: 700, depth: 500);
      final changed = spec.copyWith(material: FilmMaterial.clearPvc, width: 900);
      expect(changed.material, FilmMaterial.clearPvc);
      expect(changed.isScreen, isFalse);
      expect(changed.width, 900);
      expect(changed.depth, 500);
      expect(changed.side, spec.side);
    });

    test('равенство по значению', () {
      expect(const CompositeSpec(), const CompositeSpec());
      expect(
        const CompositeSpec(width: 800),
        isNot(const CompositeSpec(width: 900)),
      );
    });
  });

  group('Составное окно в JSON', () {
    const composite = WindowParams(
      windowType: WindowType.composite,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      composite: CompositeSpec(
        side: EdgeSide.bottom,
        material: FilmMaterial.screen,
        width: 900,
        depth: 400,
        offset: 50,
        seam: CompositeSeam.diagonal,
        seamOffset: 0.4,
        seamAngleDeg: 30,
      ),
    );

    test('round-trip сохраняет второй сегмент', () {
      final restored = windowFromJson(windowToJson(composite));
      expect(restored.windowType, WindowType.composite);
      expect(restored.isComposite, isTrue);
      expect(restored.hasDiagonalSeam, isTrue);
      expect(restored.composite, composite.composite);
    });

    test('у обычного окна поля composite в JSON нет', () {
      const fixed = WindowParams();
      expect(windowToJson(fixed).containsKey('composite'), isFalse);
      final restored = windowFromJson(windowToJson(fixed));
      expect(restored.isComposite, isFalse);
      expect(restored.composite, const CompositeSpec());
    });

    test('старый заказ без composite открывается с умолчаниями', () {
      final restored = windowFromJson({
        'windowType': 'composite',
        'bottomWidth': 1500,
        'topWidth': 1500,
        'leftHeight': 2520,
        'rightHeight': 2520,
      });
      expect(restored.isComposite, isTrue);
      expect(restored.composite.side, EdgeSide.right);
      expect(restored.composite.material, FilmMaterial.screen);
    });

    test('битые значения composite не роняют чтение', () {
      final restored = windowFromJson({
        'windowType': 'composite',
        'composite': {'side': 'нет-такой', 'width': 'abc', 'seam': 42},
      });
      expect(restored.composite.side, EdgeSide.right);
      expect(restored.composite.width, const CompositeSpec().width);
      expect(restored.composite.seam, CompositeSeam.straight);
    });

    test('copyWith сохраняет composite, пока его не заменили', () {
      final resized = composite.copyWith(bottomWidth: 1800);
      expect(resized.composite, composite.composite);
      final other = resized.copyWith(
        composite: const CompositeSpec(side: EdgeSide.left),
      );
      expect(other.composite.side, EdgeSide.left);
    });
  });

  group('Тип окна', () {
    test('составное окно — не Т-образное и не подъёмное', () {
      const params = WindowParams(windowType: WindowType.composite);
      expect(params.isComposite, isTrue);
      expect(params.isTShape, isFalse);
      expect(params.isLifting, isFalse);
      expect(params.hasDiagonalSeam, isFalse);
      expect(WindowType.composite.label, 'Составное');
      expect(WindowType.composite.hint, isNotEmpty);
    });
  });
}
