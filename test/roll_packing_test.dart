import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/services/roll_packing.dart';

/// Создаёт заготовку с подписью по умолчанию.
RollPiece _piece(
  String id,
  double width,
  double height, {
  bool allowRotation = true,
  String? label,
}) {
  return RollPiece(
    id: id,
    label: label ?? 'Заготовка №$id',
    width: width,
    height: height,
    allowRotation: allowRotation,
  );
}

/// Проверяет, что заготовки не выходят за границы рулона по оси X.
void _expectInsideRollWidth(RollLayout layout) {
  for (final placement in layout.placements) {
    expect(
      placement.x,
      greaterThanOrEqualTo(-1e-9),
      reason: 'Заготовка «${placement.piece.label}» уехала левее рулона',
    );
    expect(
      placement.x + placement.width,
      lessThanOrEqualTo(layout.rollWidth + 1e-9),
      reason: 'Заготовка «${placement.piece.label}» выходит за рулон по X',
    );
  }
}

/// Проверяет попарное отсутствие пересечений; касание краями допускается.
void _expectNoOverlaps(List<RollPlacement> placements) {
  for (var i = 0; i < placements.length; i++) {
    for (var j = i + 1; j < placements.length; j++) {
      final a = placements[i];
      final b = placements[j];
      final overlapX = a.x < b.x + b.width && b.x < a.x + a.width;
      final overlapY = a.y < b.y + b.height && b.y < a.y + a.height;
      expect(
        overlapX && overlapY,
        isFalse,
        reason: 'Заготовки «${a.piece.label}» и «${b.piece.label}» '
            'пересекаются: (${a.x}, ${a.y}) и (${b.x}, ${b.y})',
      );
    }
  }
}

void main() {
  group('packOnRoll', () {
    test('размещает каждую заготовку ровно один раз', () {
      final pieces = <RollPiece>[
        _piece('1', 1450, 650, label: 'Окно №1'),
        _piece('2', 1450, 650, label: 'Окно №2'),
        _piece('3', 1400, 700, label: 'Окно №3'),
        _piece('4', 900, 400, label: 'Окно №4'),
      ];

      final layout = packOnRoll(rollWidth: 1500, pieces: pieces);

      expect(layout.placements, hasLength(pieces.length));
      expect(
        layout.placements.map((placement) => placement.piece.id).toSet(),
        pieces.map((piece) => piece.id).toSet(),
      );
    });

    test('ни одна заготовка не выходит за границы рулона по X', () {
      final pieces = <RollPiece>[
        _piece('1', 1450, 650, label: 'Окно №1'),
        _piece('2', 1450, 650, label: 'Окно №2'),
        _piece('3', 1400, 700, label: 'Окно №3'),
        _piece('4', 300, 1200, label: 'Окно №4'),
        _piece('5', 700, 700, label: 'Окно №5'),
      ];

      final layout = packOnRoll(rollWidth: 1500, pieces: pieces);

      expect(layout.placements, hasLength(pieces.length));
      _expectInsideRollWidth(layout);
    });

    test('заготовки не пересекаются, касание краями допускается', () {
      // gap = 0, поэтому полка заполняется вплотную: 400 + 400 + 200 = 1000 мм.
      // Третья заготовка 300×200 влезает только повёрнутой (200×300) и
      // касается второй ровно по границе x = 800.
      final pieces = <RollPiece>[
        _piece('1', 400, 300, label: 'Окно №1'),
        _piece('2', 400, 300, label: 'Окно №2'),
        _piece('3', 300, 200, label: 'Окно №3'),
      ];

      final layout = packOnRoll(rollWidth: 1000, pieces: pieces, gap: 0);

      expect(layout.placements, hasLength(pieces.length));
      _expectInsideRollWidth(layout);
      _expectNoOverlaps(layout.placements);

      final third = layout.placements
          .singleWhere((placement) => placement.piece.id == '3');
      expect(third.rotated, isTrue);
      expect(third.x, 800);
      // Все три заготовки поместились в одну полку высотой 300 мм.
      expect(layout.requiredLength, closeTo(300, 1e-6));
    });

    test('поворот применяется, когда без него заготовка не влезает', () {
      final layout = packOnRoll(
        rollWidth: 500,
        pieces: <RollPiece>[_piece('1', 2000, 400, label: 'Окно №1')],
      );

      expect(layout.placements, hasLength(1));
      final placement = layout.placements.single;
      expect(placement.rotated, isTrue);
      expect(placement.width, 400);
      expect(placement.height, 2000);
      expect(placement.x, 0);
      expect(layout.requiredLength, closeTo(2000, 1e-6));
      expect(layout.warnings, isEmpty);
      _expectInsideRollWidth(layout);
    });

    test('пример: рулон 1500 мм, заготовки 1450×650, 1450×650, 1400×700', () {
      final pieces = <RollPiece>[
        _piece('1', 1450, 650, label: 'Окно №1'),
        _piece('2', 1450, 650, label: 'Окно №2'),
        _piece('3', 1400, 700, label: 'Окно №3'),
      ];

      final layout = packOnRoll(rollWidth: 1500, pieces: pieces);

      // Ручной расчёт при gap = 20 мм (заготовки отсортированы по длинной
      // стороне: №1 и №2 по 1450, затем №3 — 1400):
      //   полка 1: 1450×650, остаток 1500 − 1450 = 50 мм — больше не влезает;
      //   полка 2: 1450×650, y = 650 + 20 = 670, остаток снова 50 мм;
      //   полка 3: 1400×700, y = 670 + 650 + 20 = 1340;
      //   requiredLength = 650 + 650 + 700 + 2 × 20 = 2040 мм.
      expect(layout.placements, hasLength(3));
      expect(
        layout.placements.map((placement) => placement.y).toList(),
        <double>[0, 670, 1340],
      );
      expect(layout.requiredLength, closeTo(2040, 1e-6));
      expect(layout.wastePercent, inInclusiveRange(0, 100));
      expect(layout.warnings, isEmpty);
      _expectInsideRollWidth(layout);
      _expectNoOverlaps(layout.placements);
    });

    test('предупреждает, если заготовка шире рулона в любой ориентации', () {
      final layout = packOnRoll(
        rollWidth: 1500,
        pieces: <RollPiece>[_piece('1', 2400, 2400, label: 'Окно №3')],
      );

      // Заготовку всё равно размещаем, но с понятным предупреждением.
      expect(layout.placements, hasLength(1));
      expect(layout.warnings, hasLength(1));
      expect(layout.warnings.single, contains('Окно №3'));
      expect(layout.warnings.single, contains('2400 мм'));
      expect(layout.warnings.single, contains('шире рулона 1500 мм'));
      expect(layout.warnings.single, contains('сшивка'));
    });

    test('предупреждает, когда поворот запрещён и заготовка шире рулона', () {
      final layout = packOnRoll(
        rollWidth: 500,
        pieces: <RollPiece>[
          _piece('1', 2000, 400, label: 'Окно №7', allowRotation: false),
        ],
      );

      expect(layout.placements, hasLength(1));
      expect(layout.placements.single.rotated, isFalse);
      expect(layout.warnings, hasLength(1));
      expect(layout.warnings.single, contains('Окно №7'));
    });

    test('пустой список заготовок даёт пустую раскладку', () {
      final layout = packOnRoll(rollWidth: 1500, pieces: const <RollPiece>[]);

      expect(layout.placements, isEmpty);
      expect(layout.requiredLength, 0);
      expect(layout.wastePercent, 0);
      expect(layout.warnings, isEmpty);
    });

    test('некорректная ширина рулона не роняет раскладку', () {
      final widths = <double>[0, -100, double.nan, double.infinity];
      for (final rollWidth in widths) {
        final layout = packOnRoll(
          rollWidth: rollWidth,
          pieces: <RollPiece>[_piece('1', 400, 300)],
        );

        expect(layout.placements, isEmpty, reason: 'rollWidth = $rollWidth');
        expect(layout.requiredLength, 0, reason: 'rollWidth = $rollWidth');
        expect(layout.wastePercent, 0, reason: 'rollWidth = $rollWidth');
        expect(layout.warnings, isNotEmpty, reason: 'rollWidth = $rollWidth');
      }
    });

    test('стресс-тест: много полок без пересечений и выходов за рулон', () {
      const rollWidth = 1600.0;
      final random = math.Random(20260930);
      // Длины и высоты от 150 до 1550 мм — все заготовки влезают в рулон
      // хотя бы в одной ориентации.
      final pieces = <RollPiece>[
        for (var i = 0; i < 60; i++)
          _piece(
            '$i',
            (150 + random.nextInt(1400)).toDouble(),
            (150 + random.nextInt(1400)).toDouble(),
            label: 'Окно №${i + 1}',
          ),
      ];

      final layout = packOnRoll(rollWidth: rollWidth, pieces: pieces);

      expect(layout.placements, hasLength(pieces.length));
      expect(layout.requiredLength, greaterThan(0));
      expect(layout.warnings, isEmpty);
      expect(layout.wastePercent, inInclusiveRange(0, 100));
      _expectInsideRollWidth(layout);
      _expectNoOverlaps(layout.placements);
    });
  });

  group('Выбор ориентации', () {
    test('на новой полке берётся ориентация, влезающая в рулон', () {
      // Плёнка окна 1401 × 1979 мм: если повернуть, ширина станет 1979 мм —
      // это шире рулона 1500 мм, поэтому поворот недопустим.
      final layout = packOnRoll(
        rollWidth: 1500,
        pieces: const [
          RollPiece(id: '1', label: 'Окно №1', width: 1401, height: 1979),
        ],
      );

      expect(layout.warnings, isEmpty);
      final placement = layout.placements.single;
      expect(placement.rotated, isFalse);
      expect(placement.width, 1401);
      expect(placement.x + placement.width, lessThanOrEqualTo(1500));
      expect(layout.requiredLength, 1979);
    });

    test('заказ из трёх окон раскладывается без предупреждений на рулоне 1500', () {
      final layout = packOnRoll(
        rollWidth: 1500,
        pieces: const [
          RollPiece(id: '1', label: 'Окно №1', width: 1472, height: 2507),
          RollPiece(id: '2', label: 'Окно №2', width: 1372, height: 1803),
          RollPiece(id: '3', label: 'Окно №3', width: 1401, height: 1979),
        ],
      );

      expect(layout.warnings, isEmpty);
      expect(layout.placements, hasLength(3));
      for (final placement in layout.placements) {
        expect(placement.x + placement.width, lessThanOrEqualTo(1500 + 1e-6));
      }
      expect(layout.wastePercent, greaterThan(0));
      expect(layout.wastePercent, lessThan(50));
    });
  });
}
