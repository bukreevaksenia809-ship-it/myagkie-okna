// Размеры между центрами креплений для чертежа.
//
// Заказчик: «нужно чтобы на чертеже показывались внутри канта маленькие
// стрелочки с написанным расстоянием между креплениями (люверсами), скобами
// и замками. Показывать от центра крепления до другого центра (цифра между
// двумя центрами). Желательно так, чтобы это было видно на листе А4 при
// печати».
//
// Здесь считается ЧИСТАЯ геометрия подписей, без пикселей: где стоит каждая
// размерная линия, между какими центрами и какое число писать. Пейнтер
// ([WindowDrawingPainter]) берёт этот же список и рисует по нему стрелки и
// текст — поэтому тест проверяет ровно то, что попадает на лист.
//
// Правила (из задачи):
//  * для каждой стороны, где есть крепёж, — расстояние от центра до центра;
//  * если шаг на стороне одинаковый, достаточно ОДНОЙ подписи с числом
//    повторений: «шаг 285,7 мм × 7» — лист не засоряется;
//  * если подписи не помещаются (промежуток на экране меньше ~22 px),
//    вместо цепочки — тоже одна сводная подпись на сторону;
//  * для стороны без крепежа (кнопки «не ставить сверху/снизу») подписей нет.
import 'dart:ui' show Offset;

import 'window_geometry.dart';
import 'window_params.dart';

/// Допуск, с которым шаг на стороне считается одинаковым, мм.
///
/// Расстановка люверсов делит сторону на равные промежутки, поэтому у
/// обычного окна шаг на стороне одинаков до тысячных. Разные промежутки
/// появляются только у фартука, который сдвигает крайние точки, — тогда
/// на стороне честно показывается цепочка (если она читается).
const double fastenerSpanEqualToleranceMm = 0.5;

/// Одна размерная подпись между центрами креплений.
class FastenerSpanLabel {
  const FastenerSpanLabel({
    required this.edgeIndex,
    required this.side,
    required this.startMm,
    required this.endMm,
    required this.centerMm,
    required this.spanMm,
    required this.count,
    required this.summary,
    this.approximate = false,
    this.compact = false,
  });

  /// Номер кромки наружного контура (0 — низ, 1 — право, …).
  final int edgeIndex;

  /// Сторона окна; null у кромки Т-образного контура, которую нельзя
  /// однозначно назвать низом/правом/верхом/лезом.
  final WindowSide? side;

  /// Центр первого крепления, мм (модельные координаты, ось Y вверх).
  final Offset startMm;

  /// Центр последнего крепления, мм.
  final Offset endMm;

  /// Где ставить подпись: середина между крайними центрами, мм.
  final Offset centerMm;

  /// Расстояние между соседними центрами, мм (шаг).
  final double spanMm;

  /// Сколько промежутков описывает подпись (у цепочки — 1).
  final int count;

  /// Одна сводная подпись на сторону: «шаг 285,7 мм × 7».
  final bool summary;

  /// Шаг на стороне неодинаковый, поэтому число примерное («шаг ≈…»).
  final bool approximate;

  /// Узкий кант: подпись без слов «шаг … мм», только цифры и число
  /// повторений — иначе длинная строка не встаёт между двумя креплениями.
  final bool compact;

  /// Подпись для листа.
  String get text => summary
      ? compact
            ? '${approximate ? '≈' : ''}${formatFastenerSpanMm(spanMm)} × $count'
            : 'шаг ${approximate ? '≈' : ''}'
                  '${formatFastenerSpanMm(spanMm)} мм × $count'
      : formatFastenerSpanMm(spanMm);

  @override
  String toString() =>
      'FastenerSpanLabel(${side?.name ?? edgeIndex}, $text, '
      'span=$spanMm, count=$count)';
}

/// Формат расстояния между креплениями: «290», «285,7».
///
/// Целые числа печатаем без дробной части — на листе А4 это читается лучше,
/// а «285,7» оставляем, когда шаг действительно дробный (2000 мм / 7).
String formatFastenerSpanMm(double millimeters) {
  if (!millimeters.isFinite) return '—';
  final rounded = (millimeters * 10).round() / 10;
  final whole = rounded == rounded.roundToDouble();
  return formatMm(rounded, decimals: whole ? 0 : 1);
}

/// Ширина полосы (канта), в которой стоят крепления, мм.
///
/// У ПВХ это готовая (сложенная пополам) окантовка стороны, у скрина —
/// подворот. По ней выбирается кегль подписи и решается, влезает ли полная
/// строка «шаг … мм × N» между двумя креплениями.
double fastenerBandWidthMm(
  WindowSpec spec, {
  WindowSide? side,
  int edgeIndex = 0,
}) {
  final params = spec.params;
  final layers = spec.layers;
  if (params.isScreen) {
    return switch (side) {
      WindowSide.bottom => params.hemBottomMm,
      WindowSide.right => params.hemRightMm,
      WindowSide.top => params.hemTopMm,
      WindowSide.left => params.hemLeftMm,
      null => 50.0,
    };
  }
  final widths = layers.finishedWidths;
  if (widths.isEmpty) return 50.0;
  if (edgeIndex >= 0 && edgeIndex < widths.length) {
    return widths[edgeIndex];
  }
  return widths.reduce((left, right) => left < right ? left : right);
}

/// Оценка ширины строки в точках чертежа — без TextPainter, чтобы модель
/// оставалась чистой и тестируемой.
double _estimatedTextWidth(String text, double fontSize) {
  var units = 0.0;
  for (final rune in text.runes) {
    final char = String.fromCharCode(rune);
    if (char == ' ') {
      units += 0.28;
    } else if (char == ',' || char == '.') {
      units += 0.28;
    } else if (char == '×') {
      units += 0.62;
    } else if (char == '≈') {
      units += 0.6;
    } else {
      units += 0.56;
    }
  }
  return units * fontSize;
}

/// Размерные подписи между центрами креплений для окна [spec].
///
/// [pxPerMm] — сколько пикселей листа приходится на миллиметр модели: по нему
/// решается, помещается ли цепочка подписей или нужна одна сводная.
/// [minSpanPx] — минимальный читаемый промежуток между центрами (22 px:
/// короче — цифры сливаются).
List<FastenerSpanLabel> fastenerSpanLabels(
  WindowSpec spec, {
  double minSpanPx = 22,
  double pxPerMm = 1,
}) {
  final outer = spec.layers.outer;
  if (outer.length < 3) return const [];
  if (!pxPerMm.isFinite || pxPerMm <= 0) return const [];
  final eyelets = spec.layers.eyelets;
  if (eyelets.length < 2) return const [];

  final params = spec.params;
  final shapeCenter = boundsOf(outer).center;
  final requestedStep = params.eyeletStep.isFinite && params.eyeletStep > 0
      ? params.eyeletStep
      : 0.0;
  final labels = <FastenerSpanLabel>[];

  for (var i = 0; i < outer.length; i++) {
    final a = outer[i];
    final b = outer[(i + 1) % outer.length];
    final direction = b - a;
    final length = direction.distance;
    if (length < 1) continue;
    final unit = direction / length;

    // Сторона кромки: нужно, чтобы не рисовать размеры для стороны, где
    // крепёж выключен кнопкой «не ставить сверху/снизу».
    final side = _sideOfEdge(a, b, shapeCenter);
    if (side != null && !spec.layers.sideHasEyelets(side)) continue;

    // Кандидаты — крепления в пределах кромки. Ряд креплений — тот, что
    // ближе всех к внешнему контуру (у ПВХ люверсы стоят на середине
    // окантовки, у скрина — на линии подворота).
    final candidates = <_Node>[];
    for (final eyelet in eyelets) {
      final relative = eyelet.center - a;
      final along = relative.dx * unit.dx + relative.dy * unit.dy;
      if (along < -0.75 || along > length + 0.75) continue;
      final perp = (relative - unit * along).distance;
      candidates.add(_Node(along, perp, eyelet.center));
    }
    if (candidates.length < 2) continue;
    final nearest = candidates
        .map((node) => node.perp)
        .reduce((left, right) => left < right ? left : right);
    final row =
        candidates
            .where((node) => (node.perp - nearest).abs() <= 1.0)
            .toList()
          ..sort((left, right) => left.along.compareTo(right.along));

    // Соседние крепления: убираем дубли (угол принадлежит двум сторонам).
    final nodes = <_Node>[];
    for (final node in row) {
      if (nodes.isNotEmpty && (node.along - nodes.last.along).abs() < 1) {
        continue;
      }
      nodes.add(node);
    }
    if (nodes.length < 2) continue;

    final gaps = <double>[
      for (var k = 1; k < nodes.length; k++)
        nodes[k].along - nodes[k - 1].along,
    ]..removeWhere((gap) => gap < 1);
    if (gaps.isEmpty) continue;

    // Ряд «настоящий», а не два угла соседних сторон: если между крайними
    // креплениями пропуск больше двух заданных шагов, значит на этой стороне
    // крепежа нет (например верх без люверсов) — размеры не рисуем.
    if (requestedStep > 0 &&
        gaps.any((gap) => gap > requestedStep * 2 + 1)) {
      continue;
    }

    final first = nodes.first.center;
    final last = nodes.last.center;
    // Подпись ставим МЕЖДУ двумя соседними центрами (а не в середину
    // стороны): тогда цифра не налезает на люверсы.
    final centerGap = gaps.length ~/ 2;
    final middle =
        (nodes[centerGap].center + nodes[centerGap + 1].center) / 2;
    final equal = gaps.every(
      (gap) => (gap - gaps.first).abs() <= fastenerSpanEqualToleranceMm,
    );
    if (equal) {
      // Одинаковый шаг — одна подпись на сторону с числом повторений.
      labels.add(
        FastenerSpanLabel(
          edgeIndex: i,
          side: side,
          startMm: first,
          endMm: last,
          centerMm: middle,
          spanMm: gaps.first,
          count: gaps.length,
          summary: true,
          compact: !_summaryFits(
            gaps.first,
            gaps.length,
            spec,
            side,
            i,
            pxPerMm,
            approximate: false,
          ),
        ),
      );
      continue;
    }

    // Шаг разный (фартук сдвигает крайние точки). Цепочка читается — рисуем
    // каждый промежуток, иначе одна сводная подпись с типичным шагом.
    if (gaps.every((gap) => gap * pxPerMm >= minSpanPx)) {
      for (var k = 1; k < nodes.length; k++) {
        final start = nodes[k - 1].center;
        final end = nodes[k].center;
        labels.add(
          FastenerSpanLabel(
            edgeIndex: i,
            side: side,
            startMm: start,
            endMm: end,
            centerMm: (start + end) / 2,
            spanMm: gaps[k - 1],
            count: 1,
            summary: false,
          ),
        );
      }
      continue;
    }
    labels.add(
      FastenerSpanLabel(
        edgeIndex: i,
        side: side,
        startMm: first,
        endMm: last,
        centerMm: middle,
        spanMm: _median(gaps),
        count: gaps.length,
        summary: true,
        approximate: true,
        compact: !_summaryFits(
          _median(gaps),
          gaps.length,
          spec,
          side,
          i,
          pxPerMm,
          approximate: true,
        ),
      ),
    );
  }

  return labels;
}

/// Влезает ли полная строка «шаг … мм × N» между двумя соседними
/// креплениями на этом масштабе. Если нет — подпись компактная (только
/// цифры), чтобы не налезать на люверсы.
bool _summaryFits(
  double spanMm,
  int count,
  WindowSpec spec,
  WindowSide? side,
  int edgeIndex,
  double pxPerMm, {
  required bool approximate,
}) {
  final bandPx = fastenerBandWidthMm(
        spec,
        side: side,
        edgeIndex: edgeIndex,
      ) *
      pxPerMm;
  final fontSize = fastenerSpanFontSizePx(bandPx);
  final full =
      'шаг ${approximate ? '≈' : ''}${formatFastenerSpanMm(spanMm)} мм '
      '× $count';
  return _estimatedTextWidth(full, fontSize) <= spanMm * pxPerMm - 2;
}

/// Сторона окна для кромки наружного контура.
WindowSide? _sideOfEdge(Offset a, Offset b, Offset shapeCenter) {
  final direction = b - a;
  if (direction.distance < 1e-9) return null;
  if (direction.dx.abs() >= direction.dy.abs()) {
    return (a.dy + b.dy) / 2 >= shapeCenter.dy
        ? WindowSide.top
        : WindowSide.bottom;
  }
  return (a.dx + b.dx) / 2 >= shapeCenter.dx
      ? WindowSide.right
      : WindowSide.left;
}

double _median(List<double> values) {
  final sorted = [...values]..sort();
  final middle = sorted.length ~/ 2;
  if (sorted.length.isOdd) return sorted[middle];
  return (sorted[middle - 1] + sorted[middle]) / 2;
}

class _Node {
  const _Node(this.along, this.perp, this.center);

  /// Координата вдоль кромки, мм.
  final double along;

  /// Расстояние от кромки (наружного контура), мм.
  final double perp;

  final Offset center;
}

/// Минимальный читаемый промежуток между центрами креплений на листе, px.
const double minFastenerSpanPx = 22;

/// Полоса окантовки уже этого размера (px) — подписи не рисуем вовсе:
/// это масштаб ячейки «все окна», на А4 такие цифры уже не читаются.
const double minFastenerSpanBandPx = 6;

/// Минимальный кегль подписей на печати А4, pt.
///
/// На листе А4 (1240 точек на 210 мм) одна точка чертежа 96 dpi даёт
/// 1.562 × 0.1694 мм = 0.2646 мм, то есть 0.75 pt. Подпись «small» 11 px =
/// 8.25 pt, а наши размеры между креплениями не опускаются ниже 9 px =
/// 6.75 pt — это читаемо на бумаге (проверено превью А4).
const double minFastenerSpanPt = 6.5;

/// Кегль подписи размера между креплениями в точках чертежа (96 dpi).
///
/// Подстраивается под ширину канта: в широкой окантовке (1:10, 50 мм)
/// цифра крупнее, в узкой (1:15) — мельче, но не ниже 9 px = 6.75 pt.
double fastenerSpanFontSizePx(double bandPx) => (bandPx * 0.62).clamp(9.0, 11.0);

/// Кегль подписи размера между креплениями в пунктах на бумаге А4.
double fastenerSpanFontSizePt(double bandPx) =>
    fastenerSpanFontSizePx(bandPx) * 0.75;

