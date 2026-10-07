import 'dart:math' as math;

/// Допуск сравнения размеров в миллиметрах: габариты приходят из double.
const double _epsilon = 1e-9;

/// Заготовка для раскладки на рулоне. Размеры в миллиметрах.
class RollPiece {
  const RollPiece({
    required this.id,
    required this.label,
    required this.width,
    required this.height,
    this.allowRotation = true,
  });

  /// Идентификатор заготовки, например '1'.
  final String id;

  /// Подпись заготовки, например 'Окно №1'.
  final String label;

  /// Ширина заготовки в миллиметрах.
  final double width;

  /// Высота заготовки в миллиметрах.
  final double height;

  /// Можно ли повернуть заготовку на 90°.
  final bool allowRotation;
}

/// Размещённая на рулоне заготовка.
///
/// [x] — поперёк рулона (от левого края), [y] — вдоль рулона (от начала).
class RollPlacement {
  const RollPlacement({
    required this.piece,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.rotated,
  });

  /// Исходная заготовка.
  final RollPiece piece;

  /// Смещение поперёк рулона, мм.
  final double x;

  /// Смещение вдоль рулона, мм.
  final double y;

  /// Фактическая ширина после возможного поворота, мм.
  final double width;

  /// Фактическая высота после возможного поворота, мм.
  final double height;

  /// Был ли применён поворот на 90°.
  final bool rotated;
}

/// Результат раскладки заготовок на рулоне.
class RollLayout {
  const RollLayout({
    required this.rollWidth,
    required this.requiredLength,
    required this.placements,
    required this.wastePercent,
    required this.warnings,
  });

  /// Ширина рулона, мм.
  final double rollWidth;

  /// Необходимая длина рулона, мм.
  final double requiredLength;

  /// Размещённые заготовки в порядке укладки.
  final List<RollPlacement> placements;

  /// Процент отхода, 0..100.
  final double wastePercent;

  /// Предупреждения, например о заготовке шире рулона.
  final List<String> warnings;
}

/// Раскладывает заготовки на рулоне шириной [rollWidth] мм.
///
/// Раскладка полочная (shelf packing) с поворотом заготовок: заготовки
/// укладываются слева направо, а когда очередная не влезает в остаток полки —
/// открывается новая полка ниже по оси Y. Длина рулона не ограничена, поэтому
/// возвращается минимально необходимая длина при выбранном порядке укладки.
/// Отступ [gap] мм выдерживается между заготовками в полке и между полками.
RollLayout packOnRoll({
  required double rollWidth,
  required List<RollPiece> pieces,
  double gap = 20,
}) {
  // Пустой список — пустая раскладка без падений.
  if (pieces.isEmpty) {
    return RollLayout(
      rollWidth: rollWidth,
      requiredLength: 0,
      placements: const <RollPlacement>[],
      wastePercent: 0,
      warnings: const <String>[],
    );
  }

  // Некорректная ширина рулона: раскладывать нечего, сообщаем об этом.
  if (!rollWidth.isFinite || rollWidth <= 0) {
    return RollLayout(
      rollWidth: rollWidth,
      requiredLength: 0,
      placements: const <RollPlacement>[],
      wastePercent: 0,
      warnings: <String>[
        'Некорректная ширина рулона: ${_formatMm(rollWidth)} мм — '
            'раскладка невозможна',
      ],
    );
  }

  // Не конечный или отрицательный отступ считаем отсутствием отступа.
  final spacing = gap.isFinite && gap > 0 ? gap : 0.0;

  // Сортировка по убыванию наибольшей стороны; при равенстве — по id.
  final ordered = List<RollPiece>.of(pieces)..sort(_comparePieces);

  final placements = <RollPlacement>[];
  final warnings = <String>[];

  var hasShelf = false;
  var shelfTop = 0.0; // координата Y начала текущей полки
  var shelfHeight = 0.0; // высота текущей полки
  var shelfUsed = 0.0; // занятая ширина текущей полки
  var closedLength = 0.0; // длина закрытых полок вместе с отступами

  for (final piece in ordered) {
    final canRotate = piece.allowRotation && piece.width != piece.height;
    // Минимальная сторона среди доступных ориентаций.
    final bestSide = canRotate
        ? math.min(piece.width, piece.height)
        : piece.width;
    if (bestSide > rollWidth + _epsilon) {
      warnings.add(
        'Заготовка «${piece.label}» (${_formatMm(bestSide)} мм) шире рулона '
        '${_formatMm(rollWidth)} мм — нужна сшивка',
      );
    }

    final candidateX = shelfUsed <= 0 ? 0.0 : shelfUsed + spacing;
    final originalFits = candidateX + piece.width <= rollWidth + _epsilon;
    final rotatedFits =
        canRotate && candidateX + piece.height <= rollWidth + _epsilon;

    var rotated = false;
    double x;
    if (originalFits || rotatedFits) {
      x = candidateX;
      // Из влезающих ориентаций берём более низкую — полка получится ниже.
      // Высота исходной ориентации — piece.height, повёрнутой — piece.width.
      // При равенстве высот остаётся исходная ориентация.
      rotated = rotatedFits && (!originalFits || piece.width < piece.height);
    } else {
      // В остаток полки заготовка не влезает — открываем новую полку ниже.
      if (hasShelf) {
        shelfTop += shelfHeight + spacing;
        closedLength += shelfHeight + spacing;
      }
      shelfUsed = 0;
      shelfHeight = 0;
      x = 0;
      // На новой полке сначала выбираем ориентацию, которая влезает в рулон,
      // и только среди влезающих — более низкую. Если не влезает ни одна,
      // ставим более низкую и предупреждаем (warning добавлен выше).
      final originalFitsShelf = piece.width <= rollWidth + _epsilon;
      final rotatedFitsShelf = canRotate && piece.height <= rollWidth + _epsilon;
      if (originalFitsShelf && rotatedFitsShelf) {
        rotated = piece.width < piece.height;
      } else if (rotatedFitsShelf) {
        rotated = true;
      } else if (originalFitsShelf) {
        rotated = false;
      } else {
        rotated = canRotate && piece.width < piece.height;
      }
    }

    final width = rotated ? piece.height : piece.width;
    final height = rotated ? piece.width : piece.height;
    placements.add(
      RollPlacement(
        piece: piece,
        x: x,
        y: shelfTop,
        width: width,
        height: height,
        rotated: rotated,
      ),
    );
    shelfUsed = x + width;
    shelfHeight = math.max(shelfHeight, height);
    hasShelf = true;
  }

  final requiredLength = hasShelf ? closedLength + shelfHeight : 0.0;
  final rollArea = rollWidth * requiredLength;
  var waste = 0.0;
  if (rollArea > 0) {
    final piecesArea = placements.fold<double>(
      0.0,
      (sum, placement) => sum + placement.width * placement.height,
    );
    waste = ((rollArea - piecesArea) / rollArea * 100)
        .clamp(0.0, 100.0)
        .toDouble();
  }

  return RollLayout(
    rollWidth: rollWidth,
    requiredLength: requiredLength,
    placements: placements,
    wastePercent: waste,
    warnings: warnings,
  );
}

/// Сравнивает заготовки: сначала более длинная сторона, затем id.
int _comparePieces(RollPiece a, RollPiece b) {
  final byLongest = math
      .max(b.width, b.height)
      .compareTo(math.max(a.width, a.height));
  if (byLongest != 0) {
    return byLongest;
  }
  return a.id.compareTo(b.id);
}

/// Печатает размер в миллиметрах без лишних нулей: 1450, 1450.5, NaN.
String _formatMm(double value) {
  if (!value.isFinite) {
    return value.toString();
  }
  if (value == value.roundToDouble()) {
    return value.round().toString();
  }
  return value.toStringAsFixed(1);
}
