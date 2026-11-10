import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_json.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/estimate.dart';

const _fixed = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
);

const _lifting = WindowParams(
  windowType: WindowType.lifting,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2000,
  rightHeight: 2000,
);

void main() {
  test('глухое окно: без флага люверсы есть', () {
    final spec = WindowSpec.of(_fixed);
    expect(spec.layers.eyelets, isNotEmpty);
    expect(_fixed.eyeletFree, isFalse);
  });

  test('убрать все люверсы: на чертеже не остаётся ни одного', () {
    final params = _fixed.copyWith(noEyeletsAll: true);
    final spec = WindowSpec.of(params);
    expect(params.eyeletFree, isTrue);
    expect(spec.layers.eyelets, isEmpty);
    expect(spec.layers.cornerEyelets, isEmpty);
    expect(spec.layers.standaloneEyelets, isEmpty);
    expect(spec.layers.eyeletlessSidesLabel, 'все стороны');
  });

  test('смета без люверсов: строки люверсов нет', () {
    final estimate = Estimate.of(
      OrderProject(windows: [_fixed.copyWith(noEyeletsAll: true)]),
      const PriceList.defaults(),
    );
    expect(
      estimate.lines.where((line) => line.title.startsWith('Люверсы')),
      isEmpty,
    );
    // Другие позиции не ломаются.
    expect(
      estimate.lines.any((line) => line.title == 'Окантовка Тент 100 мм'),
      isTrue,
    );
  });

  test('отмена возвращает автоматическую расстановку', () {
    final removed = WindowSpec.of(_fixed.copyWith(noEyeletsAll: true));
    final restored = WindowSpec.of(
      _fixed.copyWith(noEyeletsAll: true).copyWith(noEyeletsAll: false),
    );
    expect(removed.layers.eyelets, isEmpty);
    expect(restored.layers.eyelets, isNotEmpty);
    expect(
      restored.layers.eyelets.length,
      WindowSpec.of(_fixed).layers.eyelets.length,
    );
  });

  test('ручной замок не является люверсом и остаётся', () {
    final params = _fixed.copyWith(
      noEyeletsAll: true,
      manualEyeletSides: const [EdgeSide.bottom],
      eyeletPositions: const [
        EyeletPosition(side: EdgeSide.bottom, fraction: 0.5),
        EyeletPosition(
          side: EdgeSide.bottom,
          fraction: 0.25,
          kind: MarkerKind.frenchLock,
        ),
      ],
    );
    final spec = WindowSpec.of(params);
    expect(spec.layers.eyelets, isEmpty);
    expect(spec.layers.manualFasteners, hasLength(1));
    expect(spec.layers.manualFasteners.single.type, FastenerType.frenchLocks);
  });

  test('подъёмное окно: флаг не ломает верхний ряд и нижние углы', () {
    final params = _lifting.copyWith(noEyeletsAll: true);
    expect(params.eyeletFree, isFalse);
    final spec = WindowSpec.of(params);
    expect(spec.layers.eyelets, isNotEmpty);
    expect(spec.layers.topEyelets, isNotEmpty);
    expect(spec.layers.cornerEyelets, isNotEmpty);
  });

  test('флаг сохраняется в JSON и читается старой записью как false', () {
    final project = OrderProject(
      windows: [_fixed.copyWith(noEyeletsAll: true)],
    );
    final json = orderToJson(project);
    final windows = json['windows'] as List;
    expect((windows.first as Map)['noEyeletsAll'], isTrue);
    final restored = orderFromJson(json);
    expect(restored.selected.noEyeletsAll, isTrue);
    expect(restored.selected.eyeletFree, isTrue);

    final old = orderFromJson({
      ...json,
      'windows': [
        {
          for (final entry in (windows.first as Map).entries)
            if (entry.key != 'noEyeletsAll') entry.key: entry.value,
        },
      ],
    });
    expect(old.selected.noEyeletsAll, isFalse);
  });
}
