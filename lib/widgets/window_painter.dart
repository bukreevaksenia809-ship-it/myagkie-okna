import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../models/fastener_spans.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';

/// Перевод миллиметров модели в пиксели листа.
class DrawingLayout {
  DrawingLayout({
    required this.size,
    required this.geometry,
    this.padLeft = 84,
    this.padRight = 84,
    this.padTop = 60,
    this.padBottom = 76,
  }) {
    final spanX = math.max(geometry.spanX, 1.0);
    final spanY = math.max(geometry.spanY, 1.0);
    final availableWidth = math.max(size.width - padLeft - padRight, 40.0);
    final availableHeight = math.max(size.height - padTop - padBottom, 40.0);
    final ideal = math.min(availableWidth / spanX, availableHeight / spanY);
    scaleDenominator = niceScaleDenominator(ideal);
    scale = (96 / 25.4) / scaleDenominator;
    scaleLabelOverride = formatScaleLabel(scale);
  }

  /// Лист с ЗАДАННЫМ знаменателем масштаба — для превью и проверок.
  ///
  /// Обычный конструктор подбирает масштаб по размеру листа; здесь масштаб
  /// известен заранее (1:20, 1:30, 1:50), и по нему выставляются поля.
  DrawingLayout.forScaleDenominator({
    required this.size,
    required this.geometry,
    required this.scaleDenominator,
    this.padLeft = 84,
    this.padRight = 84,
    this.padTop = 60,
    this.padBottom = 76,
  }) {
    scale = (96 / 25.4) / scaleDenominator;
    scaleLabelOverride = formatScaleLabel(scale);
  }

  /// Подпись масштаба для этого листа.
  late final String scaleLabelOverride;

  /// Знаменатель масштаба: 15 для «М 1:15».
  late final double scaleDenominator;

  final Size size;
  final WindowGeometry geometry;
  final double padLeft;
  final double padRight;
  final double padTop;
  final double padBottom;

  /// Пикселей на миллиметр модели.
  late final double scale;

  Offset toPx(double x, double y) => Offset(
    padLeft + (x - geometry.minX) * scale,
    size.height - padBottom - (y - geometry.minY) * scale,
  );

  Offset toPxPoint(Offset point) => toPx(point.dx, point.dy);

  double px(double millimeters) => millimeters * scale;

  String get scaleLabel => scaleLabelOverride;
}

/// Кегль обычных подписей чертежа (стороны, размеры, выноски) в точках
/// листа 96 dpi. На бумаге А4 одна точка листа — 0,75 pt, то есть 11 точек
/// дают 8,25 pt: читается на печати.
const double drawingLabelFontPx = 11;

/// Кегль крупных подписей (масштабная линейка, габариты) в точках листа.
const double drawingTitleFontPx = 13.5;

/// Кегль обычных подписей на бумаге А4, pt.
const double drawingLabelFontPt = drawingLabelFontPx * 0.75;

/// Минимальный кегль, который считается читаемым на печати А4, pt.
const double minDrawingLabelPt = 7;

/// Стандартные знаменатели масштаба чертежа.
///
/// Ряд гостовский (1:1, 1:2, 1:2,5, 1:5, 1:10, 1:15, 1:20, 1:25, 1:50 …), но
/// с промежуточными ступенями. Раньше между 1:25 и 1:50 был провал: у
/// Т-окна с пристройками габарит 3 300 мм требует ровно 1:27,7, масштаб
/// округлялся до 1:50 — и чертёж разом уменьшался вдвое, хотя изделие выросло
/// всего на 100 мм («добавил вторую пристройку — чертёж стал мелким, а
/// надписи обычные»).
///
/// Теперь соседние ступени отличаются не больше чем в 1,33 раза, поэтому при
/// добавлении пристройки чертёж остаётся крупным и заполняет лист так же, как
/// обычное окно. Ступени 30, 40, 60, 125 и т. п. — обычные «круглые»
/// масштабы; честность чертежа не страдает: подпись «М 1:30» и масштабная
/// линейка считаются от фактического знаменателя.
const List<double> _niceScales = [
  1.0,
  1.5,
  2.0,
  2.5,
  3.0,
  4.0,
  5.0,
  6.0,
  7.5,
  10.0,
  12.5,
  15.0,
  20.0,
  25.0,
  30.0,
  40.0,
  50.0,
  60.0,
  75.0,
  100.0,
  125.0,
  150.0,
  200.0,
  250.0,
  300.0,
  400.0,
  500.0,
  600.0,
  750.0,
  1000.0,
];

/// Подгоняет пиксельный масштаб к стандартному ряду 1:10, 1:15, 1:20 …
///
/// Чертим в честном масштабе: подпись на листе совпадает с реальностью,
/// поэтому при измерении линейкой по бумаге размеры сходятся.
double snapToNiceScale(double idealPxPerMm) =>
    (96 / 25.4) / niceScaleDenominator(idealPxPerMm);

/// Подбирает знаменатель масштаба из стандартного ряда (10, 15, 20 …).
double niceScaleDenominator(double idealPxPerMm) {
  if (idealPxPerMm <= 0 || !idealPxPerMm.isFinite) return 1;
  const pxPerPaperMm = 96 / 25.4;
  final modelMmPerPaperMm = pxPerPaperMm / idealPxPerMm;
  for (final candidate in _niceScales) {
    if (candidate >= modelMmPerPaperMm) return candidate;
  }
  return _niceScales.last;
}

/// Подпись масштаба в стиле чертежа, например «М 1:20».
String formatScaleLabel(double pxPerMm) {
  if (pxPerMm <= 0 || !pxPerMm.isFinite) return 'М 1:1';
  const pxPerPaperMm = 96 / 25.4;
  final modelMmPerPaperMm = pxPerPaperMm / pxPerMm;
  var best = _niceScales.first;
  var bestDelta = double.infinity;
  for (final candidate in _niceScales) {
    final delta = (math.log(candidate) - math.log(modelMmPerPaperMm)).abs();
    if (delta < bestDelta) {
      bestDelta = delta;
      best = candidate;
    }
  }
  final text = best == best.roundToDouble()
      ? best.toStringAsFixed(0)
      : best.toString().replaceAll('.', ',');
  return 'М 1:$text';
}

/// Минимальный внешний диаметр люверса на листе, точки.
///
/// На мелком масштабе (1:20, 1:30, 1:50) настоящий люверс Ø22–42 мм
/// превращается в 1–4 точки и перестаёт читаться: заказчик видел вместо
/// кольца «просто точки». Поэтому символ не рисуется меньше этого размера —
/// кольцо с отверстием остаётся кольцом даже на обзорном листе.
const double minEyeletOuterPx = 7.0;

/// Минимальный диаметр отверстия люверса на листе, точки.
const double minEyeletHolePx = 2.5;

/// Минимальный размер крепежа (скоба, замок, ремень, фото замка) по большей
/// стороне, точки. Меньше — и на 1:20–1:30 крепёж уже не узнать.
const double minFastenerPx = 16.0;

/// Внешний диаметр круглого люверса по умолчанию, мм (см. [EyeletType]).
const double _defaultEyeletOuterMm = 22.0;

/// Размер символа люверса на листе, точки: внешний диаметр.
///
/// [pxPerMm] — масштаб листа (например, 0,189 при 1:20). [actualDiameterMm] —
/// фактический внешний диаметр по модели, [spacingPx] — расстояние до
/// ближайшего соседнего люверса на листе.
///
/// Правила:
/// 1. Символ не меньше [minEyeletOuterPx] — иначе вместо кольца точка.
/// 2. Если люверсы стоят плотнее, чем 1,6 минимального диаметра, символ
///    ужимается до минимума (но не меньше): кольца не должны сливаться.
/// 3. На крупном масштабе возвращается честный расчётный размер, без
///    искусственного увеличения.
double eyeletDrawSize(
  double pxPerMm, {
  double actualDiameterMm = _defaultEyeletOuterMm,
  double? spacingPx,
}) {
  final scale = pxPerMm.isFinite ? pxPerMm.abs() : 0.0;
  final diameter = actualDiameterMm.isFinite && actualDiameterMm > 0
      ? actualDiameterMm
      : _defaultEyeletOuterMm;
  var size = math.max(diameter * scale, minEyeletOuterPx);
  if (spacingPx != null && spacingPx.isFinite && spacingPx > 0) {
    // 1,6 диаметра — тот зазор, при котором два кольца ещё видны раздельно.
    final fit = spacingPx / 1.6;
    if (fit < size) size = math.max(fit, minEyeletOuterPx);
  }
  return size;
}

/// Диаметр отверстия люверса на листе, точки.
///
/// Отверстие не меньше [minEyeletHolePx], но всегда оставляет металлическое
/// кольцо: не больше половины внешнего диаметра. На крупном масштабе
/// возвращается фактический размер.
double eyeletHoleDrawSize(
  double outerPx, {
  double actualHoleMm = 10.0,
  double pxPerMm = 0.0,
}) {
  final outer = outerPx.isFinite && outerPx > 0 ? outerPx : minEyeletOuterPx;
  final holeMm = actualHoleMm.isFinite && actualHoleMm > 0 ? actualHoleMm : 10.0;
  final scale = pxPerMm.isFinite ? pxPerMm.abs() : 0.0;
  final actual = holeMm * scale;
  return math.min(math.max(actual, minEyeletHolePx), outer * 0.5);
}

/// Наибольший размер символа крепежа на листе, точки.
///
/// [bandWidthMm] — ширина полосы (окантовка или подворот), [factor] — доля
/// полосы, которую крепёж занимает в норме. На мелком масштабе возвращается
/// [minFastenerPx], чтобы скобу/замок можно было узнать; на крупном —
/// честный расчётный размер.
double fastenerDrawSize(
  double pxPerMm, {
  double bandWidthMm = 50.0,
  double factor = 0.7,
}) {
  final scale = pxPerMm.isFinite ? pxPerMm.abs() : 0.0;
  final band = bandWidthMm.isFinite && bandWidthMm > 0 ? bandWidthMm : 50.0;
  final actual = band * factor * scale;
  return math.max(actual, minFastenerPx);
}

/// Одна сторона окантовки: четырёхугольник между наружной и внутренней
/// линией стороны.
///
/// Сторона рисуется ОДНИМ четырёхугольником, а не набором сегментов: иначе
/// на наклонной стороне трапеции градиент, фактура и строчка повторяются на
/// каждом куске и получается «частокол» коричневых полос.
class EdgeBandQuad {
  const EdgeBandQuad({
    required this.edgeIndex,
    required this.outerStart,
    required this.outerEnd,
    required this.innerEnd,
    required this.innerStart,
    required this.widthMm,
  });

  /// Номер стороны в обходе контура (0 — низ, 1 — право, …).
  final int edgeIndex;

  /// Углы четырёхугольника в координатах модели, мм.
  final Offset outerStart;
  final Offset outerEnd;
  final Offset innerEnd;
  final Offset innerStart;

  /// Ширина полосы на этой стороне, мм.
  final double widthMm;

  /// Четырёхугольник в порядке обхода: наружная кромка → внутренняя.
  List<Offset> get points => [outerStart, outerEnd, innerEnd, innerStart];

  /// Длина наружной кромки, мм.
  double get lengthMm => (outerEnd - outerStart).distance;

  /// Длина внутренней кромки, мм.
  double get innerLengthMm => (innerEnd - innerStart).distance;

  /// Угол наружной кромки, радианы (экранные координаты).
  double get angle => math.atan2(
    outerEnd.dy - outerStart.dy,
    outerEnd.dx - outerStart.dx,
  );

  /// Угол внутренней кромки, радианы.
  double get innerAngle => math.atan2(
    innerEnd.dy - innerStart.dy,
    innerEnd.dx - innerStart.dx,
  );
}

/// Четырёхугольники полосы окантовки — по одному на сторону контура.
///
/// Раньше полоса на наклонной стороне могла собираться из сегментов: на
/// каждом сегменте заново рисовались градиент, тканевая фактура и строчка,
/// из-за чего на косом окне появлялись лишние коричневые полосы. Теперь
/// функция возвращает ровно один четырёхугольник на сторону (у трапеции и
/// окна с разными высотами — четыре), и painter рисует его целиком.
///
/// [widths] — ширина полосы по сторонам, мм. Если не задана, берётся
/// готовая ширина окантовки из модели (без минимальной «читаемой» ширины,
/// которую добавляет painter).
List<EdgeBandQuad> edgeBandQuads(WindowSpec spec, {List<double>? widths}) {
  final outer = spec.layers.outer;
  if (outer.length < 3) return const [];
  final bandWidths = widths ?? [
    for (var i = 0; i < outer.length; i++)
      spec.layers.finishedWidthFor(spec.layers.sideOfEdge(outer, i)),
  ];
  if (bandWidths.length != outer.length) return const [];
  final inner = insetPolygonPerSide(outer, bandWidths);
  return [
    for (var i = 0; i < outer.length; i++)
      EdgeBandQuad(
        edgeIndex: i,
        outerStart: outer[i],
        outerEnd: outer[(i + 1) % outer.length],
        innerEnd: inner[(i + 1) % inner.length],
        innerStart: inner[i],
        widthMm: bandWidths[i],
      ),
  ];
}

/// Рисует мягкое окно слоями: окантовка, шов (напайка), плёнка, крепёж.
/// Все углы прямые.
class WindowDrawingPainter extends CustomPainter {
  WindowDrawingPainter({
    required this.params,
    required this.layout,
    required this.layers,
    required this.options,
    this.labelFontFamily,
    this.showScaleBar = true,
    this.labelScale = 1,
    this.fastenerImage,
  });

  final WindowParams params;
  final DrawingLayout layout;
  final WindowLayers layers;
  final DrawingOptions options;

  /// Семейство шрифта для подписей. null — системный шрифт приложения.
  final String? labelFontFamily;

  /// Показывать масштабную линейку (в ячейках нескольких окон она лишняя).
  final bool showScaleBar;

  /// Множитель размера подписей: в мелких ячейках подписи делаем мельче.
  final double labelScale;

  /// Фото французского замка (декодированное). Пока null — рисуется
  /// прежний векторный замок, чтобы на листе не было пустого места.
  final ui.Image? fastenerImage;

  // Цвета по ТЗ: размеры чёрные, плёнка голубая полупрозрачная,
  // окантовка — цвет материала, люверсы — серый металл.
  static const Color _ink = Color(0xFF1B1F27);
  static const Color _filmEdge = Color(0xFF4C9BE8);
  static const Color _metal = Color(0xFF9AA3AD);
  static const Color _metalDark = Color(0xFF4C545E);
  static const Color _special = Color(0xFF0B62C4);

  /// Цвет размеров между креплениями: тёмный, но чуть мягче основного,
  /// чтобы мелкие цифры не «жирнили» чертёж.
  static const Color _spanInk = Color(0xFF24313F);
  static const Color _gridMinor = Color(0xFFE8ECF3);
  static const Color _gridMajor = Color(0xFFCFD9E8);

  /// Минимальная видимая толщина окантовки, пиксели. На мелком масштабе
  /// (несколько окон на листе) настоящая ширина превращается в пару точек,
  /// поэтому слегка утрируем — чертёж должен читаться без лупы.
  static const double _minBandPx = 5.0;

  /// Минимальная ширина канта, когда на нём стоят люверсы, пиксели.
  ///
  /// Символ люверса не меньше [minEyeletOuterPx], и кольцо должно помещаться
  /// ВНУТРИ полосы, а не свисать с неё. На 1:50 настоящие 50–100 мм канта —
  /// это 4–8 точек, поэтому полосу слегка расширяем только в этом случае.
  static const double _minBandWithEyeletsPx = 8.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (options.showGrid) _paintGrid(canvas, size);
    // Т-образное окно рисуется своей веткой: у него не четыре вершины, а
    // 6–8, и подписи/размеры относятся к двум частям.
    if (params.windowType == WindowType.tShape) {
      _paintTShape(canvas, size);
      if (showScaleBar) _paintScaleBar(canvas, size);
      return;
    }
    _paintFilm(canvas);
    _paintEdgeBand(canvas);
    if (params.isScreen) _paintScreenHem(canvas);
    _paintSeamBand(canvas);
    _paintCutouts(canvas);
    _paintVisibleFilmEdge(canvas);
    _paintZipper(canvas);
    _paintZipperDimensions(canvas);
    _paintPocket(canvas);
    _paintLiftStraps(canvas);
    _paintEyelets(canvas);
    _paintFasteners(canvas);
    _paintFastenerSpans(canvas);
    _paintDrains(canvas);
    if (options.showDimensions) _paintDimensions(canvas);
    if (options.showCallouts) _paintCallouts(canvas);
    if (options.showCallouts &&
        (params.isScreen || layers.zipperBandTotalMm > 0)) {
      _paintBlankNote(canvas, size);
    }
    if (showScaleBar) _paintScaleBar(canvas, size);
  }

  @override
  bool shouldRepaint(covariant WindowDrawingPainter oldDelegate) =>
      oldDelegate.params.signature != params.signature ||
      // Тип крепежа сравниваем отдельно: signature его включает, но
      // перерисовка при смене «скоба → французский замок» не должна
      // зависеть от того, как собран signature.
      oldDelegate.params.fastenerType != params.fastenerType ||
      oldDelegate.options.signature != options.signature ||
      oldDelegate.layout.size != layout.size ||
      oldDelegate.layout.scale != layout.scale ||
      oldDelegate.labelFontFamily != labelFontFamily ||
      oldDelegate.showScaleBar != showScaleBar ||
      oldDelegate.labelScale != labelScale ||
      // Картинка крепежа догружается после первой сборки листа — по этому
      // сравнению лист один раз перерисуется уже с фотографией.
      oldDelegate.fastenerImage != fastenerImage;

  // ---------------------------------------------------------------- геометрия

  Color get _edgeColor => Color(params.edgeColor.value);

  Color get _edgeDark => Color.lerp(_edgeColor, const Color(0xFF15181C), 0.55)!;

  void _addPolygon(Path path, List<Offset> points) {
    final px = points.map(layout.toPxPoint).toList();
    if (px.isEmpty) return;
    path.moveTo(px.first.dx, px.first.dy);
    for (final point in px.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
  }

  // ------------------------------------------------------- Т-образное окно

  /// Отрисовка Т-образного окна: фактический контур из двух частей,
  /// окантовка только по внешним сторонам, шов по общей стороне.
  void _paintTShape(Canvas canvas, Size size) {
    final t = layers.tLayout;
    if (t == null) return;

    // 1. Полотно: у Т-окна без спайки это два контура, со спайкой — один.
    //    Вырезы — настоящие отверстия, как у обычного окна.
    final film = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in layers.filmPolygons) {
      _addPolygon(film, polygon);
    }
    for (final cutout in layers.cutouts) {
      _addCutout(film, cutout);
    }
    final bounds = film.getBounds();
    if (bounds.isEmpty) return;
    canvas.drawPath(
      film,
      Paint()
        ..shader = _filmGradient(bounds)
        ..isAntiAlias = true,
    );

    // 2. Окантовка/подворот — только по внешнему контуру.
    if (params.isScreen) {
      _paintTShapeHem(canvas);
    } else {
      final minBandPx = layers.eyelets.isEmpty
          ? _minBandPx
          : _minBandWithEyeletsPx;
      final widths = [
        for (var i = 0; i < layers.outer.length; i++)
          math.max(
            layers.finishedWidthFor(layers.sideOfEdge(layers.outer, i)),
            minBandPx / layout.scale,
          ),
      ];
      final spec = WindowSpec(params, layout.geometry, layers);
      // Ровно один четырёхугольник на сторону: на наклонной стороне
      // Т-окна полоса не распадается на сегменты.
      for (final quad in edgeBandQuads(spec, widths: widths)) {
        final side = layers.sideOfEdge(layers.outer, quad.edgeIndex);
        if (params.isWelded(WindowLayers.edgeSideOf(side))) {
          continue;
        }
        _paintTentQuad(canvas, quad);
      }
      canvas.drawPath(
        _polygonPath(layers.outer),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.4
          ..strokeJoin = StrokeJoin.miter
          ..color = _ink,
      );
    }

    // 3. Общая сторона: шов спайки или пометка «два отдельных окна».
    _paintTShapeSeam(canvas, t);

    // 4. Видимая кромка полотна, вырезы, молния, фартук, люверсы, крепёж.
    _paintCutouts(canvas);
    for (final polygon in layers.edgeInnerPolygons) {
      canvas.drawPath(
        _polygonPath(polygon),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4
          ..color = _filmStrokeColor,
      );
    }
    _paintZipper(canvas);
    _paintPocket(canvas);
    _paintEyelets(canvas);
    _paintFasteners(canvas);
    _paintFastenerSpans(canvas);
    _paintDrains(canvas);

    // 5. Размеры обеих частей, смещение и площадь.
    if (options.showDimensions) _paintTShapeDimensions(canvas);
    if (options.showCallouts) _paintTShapeCallouts(canvas);
  }

  /// Подворот скрина по внешним сторонам Т-окна.
  void _paintTShapeHem(Canvas canvas) {
    final band = Path()..fillType = PathFillType.evenOdd;
    for (final polygon in layers.filmPolygons) {
      _addPolygon(band, polygon);
    }
    for (final polygon in layers.screenHemPolygons) {
      _addPolygon(band, polygon);
    }
    canvas.drawPath(
      band,
      Paint()..color = const Color(0xFF8C9298).withValues(alpha: 0.16),
    );

    final blankPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF5B6B80).withValues(alpha: 0.65);
    for (final polygon in layers.filmPolygons) {
      for (var i = 0; i < polygon.length; i++) {
        _dashedLine(
          canvas,
          layout.toPxPoint(polygon[i]),
          layout.toPxPoint(polygon[(i + 1) % polygon.length]),
          blankPaint,
          dash: 6,
          gap: 5,
        );
      }
    }
    for (final polygon in layers.screenHemPolygons) {
      canvas.drawPath(
        _polygonPath(polygon),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = const Color(0xFF33465E),
      );
    }
    for (final polygon in layers.screenSeamPolygons) {
      canvas.drawPath(
        _polygonPath(polygon),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = const Color(0xFF2F6FA8),
      );
    }
  }

  /// Швы по общим сторонам пристроек (или пометка, что часть не спаяна).
  void _paintTShapeSeam(Canvas canvas, TShapeLayout t) {
    for (final annex in t.annexes) {
      final a = layout.toPxPoint(annex.sharedStart);
      final b = layout.toPxPoint(annex.sharedEnd);
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = annex.welded ? 4.2 : 2.0
        ..color = annex.welded
            ? _special.withValues(alpha: 0.85)
            : _metalDark;
      _dashedLine(canvas, a, b, paint, dash: 9, gap: 5);
      // Подпись ставим не на середину шва, а ближе к началу: у угловой формы
      // два шва рядом, и подписи на серединах пересекались бы.
      final anchor = Offset.lerp(a, b, 0.3)!;
      final normal = _uprightNormal(a, b);
      _label(
        canvas,
        annex.welded
            ? '${annex.label}: спайка ${formatMm(annex.sharedLength)} мм'
            : '${annex.label}: не спаяно — отдельное окно',
        anchor + normal * 16,
        angle: _uprightAngle(b - a),
        small: true,
        color: annex.welded ? _special : _metalDark,
      );
    }
  }

  /// Единичная нормаль к отрезку (для подписи шва).
  Offset _uprightNormal(Offset a, Offset b) {
    final direction = b - a;
    final length = direction.distance;
    if (length < 0.01) return const Offset(0, 1);
    final unit = direction / length;
    return Offset(unit.dy, -unit.dx);
  }

  /// Размеры Т-окна: обе части (основное полотно и каждая пристройка),
  /// смещение пристроек и площадь полотна.
  void _paintTShapeDimensions(Canvas canvas) {
    final t = layers.tLayout;
    if (t == null) return;
    final main = t.mainRect;
    final width = main.width;
    final height = main.height;
    final anyBottomAnnex = t.annexes.any(
      (annex) => annex.side == TShapeSide.bottom,
    );

    // Основное полотно: ширина и высота.
    final widthY = anyBottomAnnex ? height : 0.0;
    _dimension(
      canvas,
      layout.toPx(width, widthY),
      layout.toPx(0, widthY),
      Offset(0, anyBottomAnnex ? -34 : 34),
      'Основное ${formatMm(width)}',
    );
    _dimension(
      canvas,
      layout.toPx(0, 0),
      layout.toPx(0, height),
      const Offset(-42, 0),
      formatMm(height),
    );

    // Каждая пристройка: ширина, высота и смещение вдоль общей стороны.
    for (final annex in t.annexes) {
      final annexBottom = annex.rect.top;
      final annexTop = annex.rect.bottom;
      final annexLeft = annex.rect.left;
      final annexRight = annex.rect.right;
      final side = annex.side;
      // Ширину пристройки подписываем со стороны, свободной от шва, чтобы
      // подпись не легла на подпись шва.
      final widthLineY = switch (side) {
        TShapeSide.top => annexTop,
        TShapeSide.bottom => annexBottom,
        TShapeSide.right || TShapeSide.left => annexBottom,
      };
      final widthOffset = switch (side) {
        TShapeSide.bottom => const Offset(0, 32),
        _ => const Offset(0, -32),
      };
      _dimension(
        canvas,
        layout.toPx(annexLeft, widthLineY),
        layout.toPx(annexRight, widthLineY),
        widthOffset,
        '${annex.label} ${formatMm(annex.rect.width)}',
      );
      final heightOffset = side == TShapeSide.left
          ? const Offset(-36, 0)
          : const Offset(36, 0);
      _dimension(
        canvas,
        layout.toPx(side == TShapeSide.left ? annexLeft : annexRight, annexBottom),
        layout.toPx(side == TShapeSide.left ? annexLeft : annexRight, annexTop),
        heightOffset,
        formatMm(annex.rect.height),
      );

      // Смещение показываем снаружи пристройки, а не поверх неё.
      if (annex.offset.abs() > 0.5) {
        switch (side) {
          case TShapeSide.right:
            _dimension(
              canvas,
              layout.toPx(annexRight, 0),
              layout.toPx(annexRight, annex.rect.top),
              const Offset(46, 0),
              'Смещение ${formatMm(annex.offset)}',
            );
          case TShapeSide.left:
            _dimension(
              canvas,
              layout.toPx(annexLeft, 0),
              layout.toPx(annexLeft, annex.rect.top),
              const Offset(-46, 0),
              'Смещение ${formatMm(annex.offset)}',
            );
          case TShapeSide.top:
            _dimension(
              canvas,
              layout.toPx(0, annexTop),
              layout.toPx(annex.rect.left, annexTop),
              const Offset(0, -48),
              'Смещение ${formatMm(annex.offset)}',
            );
          case TShapeSide.bottom:
            _dimension(
              canvas,
              layout.toPx(0, annexBottom),
              layout.toPx(annex.rect.left, annexBottom),
              const Offset(0, 48),
              'Смещение ${formatMm(annex.offset)}',
            );
        }
      }
    }

    // Площадь — в центре основного полотна (штамп листа считает её же).
    _label(
      canvas,
      '${formatMeters(layers.geometry.areaM2)} м²',
      layout.toPxPoint(
        Offset(main.left + main.width / 2, main.top + main.height * 0.62),
      ),
      small: true,
      color: _ink,
    );
  }

  /// Подписи сторон: окантовка или подворот у самой длинной кромки стороны.
  void _paintTShapeCallouts(Canvas canvas) {
    final outer = layers.outer;
    final longest = <WindowSide, int>{};
    final lengths = <WindowSide, double>{};
    for (var i = 0; i < outer.length; i++) {
      final side = layers.sideOfEdge(outer, i);
      final length = (outer[(i + 1) % outer.length] - outer[i]).distance;
      if (length > (lengths[side] ?? 0)) {
        lengths[side] = length;
        longest[side] = i;
      }
    }
    for (final entry in longest.entries) {
      final index = entry.value;
      final a = outer[index];
      final b = outer[(index + 1) % outer.length];
      final side = entry.key;
      final aPx = layout.toPxPoint(a);
      final bPx = layout.toPxPoint(b);
      final normal = _uprightNormal(aPx, bPx);
      final text = params.isScreen
          ? '${side.label}: подворот ${formatMm(layers.hemWidthFor(side))} мм'
          : '${side.label}: окантовка ${formatMm(layers.finishedWidthFor(side))} мм';
      final halfLength = _textPainter(
        text,
        color: _metalDark,
        small: true,
      ).width / 2;
      // Подпись стороны уступает место размерам между креплениями: на
      // Т-окне у пристроек стороны короткие, и две подписи на середине
      // налезали бы друг на друга.
      Offset? position;
      for (final fraction in const [0.5, 0.3, 0.7, 0.18, 0.82]) {
        final point = Offset.lerp(aPx, bPx, fraction)! + normal * 20;
        if (!_spanClashesAt(_spans(), index, point, halfLength)) {
          position = point;
          break;
        }
      }
      if (position == null) continue;
      _label(canvas, text, position, small: true, color: _metalDark);
    }
  }

  /// Штриховая линия — для строчек и невидимых контуров.
  void _dashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    double dash = 5,
    double gap = 4,
  }) {
    final total = (to - from).distance;
    if (total < 0.5) return;
    final unit = (to - from) / total;
    for (var d = 0.0; d < total; d += dash + gap) {
      final end = math.min(d + dash, total);
      canvas.drawLine(from + unit * d, from + unit * end, paint);
    }
  }

  /// Прямые углы: контур строится по точкам без скруглений.
  Path _polygonPath(List<Offset> points) {
    final px = points.map(layout.toPxPoint).toList();
    final path = Path();
    if (px.isEmpty) return path;
    path.moveTo(px.first.dx, px.first.dy);
    for (final point in px.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
    return path;
  }

  // ------------------------------------------------------------------- слои

  Color get _filmStrokeColor => switch (params.material) {
    FilmMaterial.clearPvc => _filmEdge,
    FilmMaterial.tintedPvc => const Color(0xFF3D4A5C),
    FilmMaterial.mosquitoNet => const Color(0xFF6B7480),
    FilmMaterial.screen => const Color(0xFF8C9298),
  };

  /// Плёнка в раскрое: она заходит под окантовку, поэтому рисуется первой,
  /// а окантовка перекрывает её край. Вырезы — настоящие отверстия в полотне.
  void _paintFilm(Canvas canvas) {
    final film = _filmPath();
    final bounds = film.getBounds();
    if (bounds.isEmpty) return;

    // Полупрозрачный ПВХ: под ним видно сетку листа, как на реальном просвете.
    final base = Paint()
      ..shader = _filmGradient(bounds)
      ..isAntiAlias = true;
    canvas.drawPath(film, base);

    // Косой блик — стеклянный отблеск плёнки. У скрина заливка простая
    // серая, без блика и без клетки: это ткань, а не прозрачный ПВХ.
    if (!params.isScreen) {
      canvas.save();
      canvas.clipPath(film);
      final glare = Path()
        ..moveTo(bounds.left, bounds.bottom)
        ..lineTo(bounds.left + bounds.width * 0.45, bounds.top)
        ..lineTo(bounds.left + bounds.width * 0.68, bounds.top)
        ..lineTo(bounds.left + bounds.width * 0.23, bounds.bottom)
        ..close();
      canvas.drawPath(
        glare,
        Paint()..color = Colors.white.withValues(alpha: 0.22),
      );
      final glare2 = Path()
        ..moveTo(bounds.left + bounds.width * 0.72, bounds.bottom)
        ..lineTo(bounds.left + bounds.width * 0.95, bounds.top)
        ..lineTo(bounds.left + bounds.width * 1.05, bounds.top)
        ..lineTo(bounds.left + bounds.width * 0.82, bounds.bottom)
        ..close();
      canvas.drawPath(
        glare2,
        Paint()..color = Colors.white.withValues(alpha: 0.12),
      );

      // Москитная сетка — мелкая клетка по всей площади плёнки.
      if (params.material == FilmMaterial.mosquitoNet) {
        final mesh = Paint()
          ..color = const Color(0x33606A76)
          ..strokeWidth = 0.8;
        const step = 3.2;
        for (var x = bounds.left; x < bounds.right; x += step) {
          canvas.drawLine(
            Offset(x, bounds.top),
            Offset(x, bounds.bottom),
            mesh,
          );
        }
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          canvas.drawLine(
            Offset(bounds.left, y),
            Offset(bounds.right, y),
            mesh,
          );
        }
      }
      canvas.restore();
    }
  }

  /// Путь плёнки: наружный контур в раскрое минус отверстия вырезов.
  Path _filmPath() {
    final path = Path()..fillType = PathFillType.evenOdd;
    _addPolygon(path, layers.filmEdge);
    for (final cutout in layers.cutouts) {
      _addCutout(path, cutout);
    }
    return path;
  }

  void _addCutout(Path path, CutoutGeometry cutout) {
    if (cutout.isCircle) {
      final center = layout.toPxPoint(cutout.center);
      path.addOval(
        Rect.fromCircle(center: center, radius: layout.px(cutout.radius!)),
      );
      return;
    }
    final rect = cutout.rect!;
    _addPolygon(path, [
      Offset(rect.left, rect.top),
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.bottom),
      Offset(rect.left, rect.bottom),
    ]);
  }

  /// Градиент плёнки: полупрозрачный, с холодным оттенком по материалу.
  Shader _filmGradient(Rect bounds) {
    final (Color light, Color deep) = switch (params.material) {
      FilmMaterial.clearPvc => (
        const Color(0x66DCEBFB),
        const Color(0x4A7FB8E8),
      ),
      FilmMaterial.tintedPvc => (
        const Color(0x6639424F),
        const Color(0x5A22282F),
      ),
      FilmMaterial.mosquitoNet => (
        const Color(0x33858E99),
        const Color(0x22858E99),
      ),
      // Скрин — простая серая полупрозрачная заливка.
      FilmMaterial.screen => (const Color(0x66B9BEC4), const Color(0x4AB9BEC4)),
    };
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [light, deep],
    ).createShader(bounds);
  }

  /// Толщина окантовки для рисования: настоящая, но не тоньше пары точек.
  List<double> get _drawWidths {
    final minPx = layers.eyelets.isEmpty ? _minBandPx : _minBandWithEyeletsPx;
    return [
      for (final width in layers.finishedWidths)
        math.max(width, minPx / layout.scale),
    ];
  }

  /// Внутренний контур окантовки для рисования.
  List<Offset> get _drawInner => insetPolygonPerSide(layers.outer, _drawWidths);

  /// Окантовка — коричневый тент: по стороне с градиентом, тканевой фактурой
  /// и строчкой по сгибу. Спаянные стороны вместо окантовки получают спайку.
  ///
  /// У скрина окантовки нет: рисуется только наружный контур, а подворот и
  /// шов добавляет [_paintScreenHem].
  void _paintEdgeBand(Canvas canvas) {
    final outer = layers.outer;
    final widths = _drawWidths;

    if (!params.isScreen) {
      final spec = WindowSpec(params, layout.geometry, layers);
      for (final quad in edgeBandQuads(spec, widths: widths)) {
        if (layers.isSideWelded(quad.edgeIndex)) {
          _paintWeldSeam(canvas, quad.edgeIndex, widths);
          continue;
        }
        _paintTentQuad(canvas, quad);
      }
    }

    canvas.drawPath(
      _polygonPath(outer),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.miter
        ..color = _ink,
    );
  }

  /// Скрин: полоса подворота по периметру, линия сгиба, шов
  /// [screenSeamMm] мм по каждой стороне и косые складки в углах.
  ///
  /// Коричневого тента нет — материал подворачивается сам. Лист должен читаться
  /// без пояснений, поэтому здесь только три акцента: светлая полоса подворота
  /// с редкой штриховкой, сплошная линия сгиба и тонкий шов внутри неё. Все
  /// мелкие подписи собраны в одном месте у своих сторон, а не разбросаны по
  /// полотну.
  void _paintScreenHem(Canvas canvas) {
    final hem = layers.screenHemLine;
    final blank = layers.filmEdge;
    if (hem.length < 3 || blank.length != hem.length) return;

    // 1. Полоса подворота: полупрозрачная заливка и РЕДКАЯ штриховка между
    //    краем заготовки (filmEdge) и линией сгиба (screenHemLine). Частую
    //    сетку не делаем — она превращает полосу в шум.
    final band = Path()..fillType = PathFillType.evenOdd;
    _addPolygon(band, blank);
    _addPolygon(band, hem);
    canvas.drawPath(
      band,
      Paint()..color = const Color(0xFF8C9298).withValues(alpha: 0.16),
    );
    canvas.save();
    canvas.clipPath(band);
    final bandBounds = band.getBounds();
    final hatch = Paint()
      ..color = const Color(0xFF5B6B80).withValues(alpha: 0.22)
      ..strokeWidth = 0.8;
    final hatchStep = math.max(bandBounds.height * 0.55, 16.0);
    for (
      var x = bandBounds.left - bandBounds.height;
      x < bandBounds.right;
      x += hatchStep
    ) {
      canvas.drawLine(
        Offset(x, bandBounds.bottom),
        Offset(x + bandBounds.height, bandBounds.top),
        hatch,
      );
    }
    canvas.restore();

    // 2. Край заготовки — штриховой, линия сгиба — сплошная и чуть толще:
    //    это главный контур, по нему ставятся люверсы.
    final blankPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..color = const Color(0xFF5B6B80).withValues(alpha: 0.65);
    for (var i = 0; i < blank.length; i++) {
      _dashedLine(
        canvas,
        layout.toPxPoint(blank[i]),
        layout.toPxPoint(blank[(i + 1) % blank.length]),
        blankPaint,
        dash: 6,
        gap: 5,
      );
    }
    canvas.drawPath(
      _polygonPath(hem),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = const Color(0xFF33465E),
    );

    // 3. Шов 3 мм: на честном масштабе он почти сливается с линией сгиба,
    //    поэтому отступ снизу слегка утрируем (не меньше 2,4 px) — иначе шов
    //    не видно на печати. Подпись «шов 3 мм» называет настоящее значение.
    final seamOffset = math.max(screenSeamMm, 2.4 / layout.scale);
    final seam = insetPolygonPerSide(hem, [
      seamOffset,
      seamOffset,
      seamOffset,
      seamOffset,
    ]);
    const seamColor = Color(0xFF2F6FA8);
    canvas.drawPath(
      _polygonPath(seam),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3.2
        ..color = seamColor.withValues(alpha: 0.16),
    );
    canvas.drawPath(
      _polygonPath(seam),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = seamColor,
    );

    // 4. Углы подворота: короткие косые штрихи от линии сгиба к краю
    //    заготовки — деликатно показывают, как материал уходит на изнанку.
    final cornerPaint = Paint()
      ..color = const Color(0xFF5B6B80).withValues(alpha: 0.5)
      ..strokeWidth = 0.9;
    for (var i = 0; i < hem.length; i++) {
      _dashedLine(
        canvas,
        layout.toPxPoint(Offset.lerp(hem[i], blank[i], 0.2)!),
        layout.toPxPoint(Offset.lerp(hem[i], blank[i], 0.8)!),
        cornerPaint,
        dash: 4,
        gap: 3,
      );
    }

    // 5. Подпись шва — одна, у верхней стороны и ближе к левому углу: там
    //    полотно свободно от люверсов, подписи подворота и размеров.
    final seamA = seam[2];
    final seamB = seam[3];
    final seamPoint = Offset.lerp(
      layout.toPxPoint(seamA),
      layout.toPxPoint(seamB),
      0.28,
    )!;
    _label(
      canvas,
      'шов ${formatMm(screenSeamMm)} мм',
      seamPoint + const Offset(0, 17),
      small: true,
      color: seamColor,
    );

    // 6. Линия сгиба — один раз, у левой стороны: это граница, по которой
    //    материал уходит на изнанку. Подпись стоит внутри полотна, ближе к
    //    нижнему углу, и не спорит с подписью подворота в середине стороны.
    final foldA = layout.toPxPoint(hem[3]);
    final foldB = layout.toPxPoint(hem[0]);
    final foldMid = Offset.lerp(foldA, foldB, 0.74)!;
    _label(
      canvas,
      'линия сгиба',
      foldMid + _inwardNormal(foldA, foldB) * 30,
      angle: _uprightAngle(foldB - foldA),
      small: true,
      color: const Color(0xFF33465E),
    );
  }

  /// Угол подписи вдоль отрезка, повёрнутый так, чтобы текст читался слева
  /// направо (а не вверх ногами).
  double _uprightAngle(Offset direction) {
    var angle = math.atan2(direction.dy, direction.dx);
    if (angle > math.pi / 2) angle -= math.pi;
    if (angle < -math.pi / 2) angle += math.pi;
    return angle;
  }

  /// Металлический градиент для люверсов, скоб и замков.
  Shader _metalShader(Rect rect, {bool dull = false}) => RadialGradient(
    center: const Alignment(-0.45, -0.5),
    radius: 1.15,
    colors: dull
        ? const [
            Color(0xFFE7EBF0),
            Color(0xFFC2C9D2),
            Color(0xFF98A1AC),
            Color(0xFF6C747F),
            Color(0xFF5A626C),
          ]
        : const [
            Color(0xFFFFFFFF),
            Color(0xFFE8EDF3),
            Color(0xFFAFB7C1),
            Color(0xFF6E7681),
            Color(0xFF454C56),
          ],
    stops: const [0, 0.3, 0.62, 0.86, 1],
  ).createShader(rect);

  /// Тень под металлической деталью.
  void _metalShadow(Canvas canvas, Rect rect, double radius) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        rect.shift(Offset(0, radius * 0.16)),
        Radius.circular(radius),
      ),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(
          BlurStyle.normal,
          math.max(radius * 0.28, 0.8),
        ),
    );
  }

  /// Одна сторона окантовки: полоса тента со сгибом пополам.
  ///
  /// Сторона рисуется ОДНИМ четырёхугольником [band] между наружной и
  /// внутренней линией. Полоса строится в локальной системе стороны: по X —
  /// длина кромки, по Y — толщина окантовки. Все точки сначала переводятся
  /// в экранные, иначе модельные координаты дают растянутые полосы.
  void _paintTentQuad(Canvas canvas, EdgeBandQuad band) {
    final start = layout.toPxPoint(band.outerStart);
    final finish = layout.toPxPoint(band.outerEnd);
    final innerStart = layout.toPxPoint(band.innerStart);
    final innerFinish = layout.toPxPoint(band.innerEnd);

    final direction = finish - start;
    final length = direction.distance;
    if (length < 1) return;
    final angle = math.atan2(direction.dy, direction.dx);
    final cos = math.cos(angle);
    final sin = math.sin(angle);

    Offset toLocal(Offset screen) {
      final dx = screen.dx - start.dx;
      final dy = screen.dy - start.dy;
      return Offset(dx * cos + dy * sin, -dx * sin + dy * cos);
    }

    final p0 = Offset.zero;
    final p1 = toLocal(finish);
    final p2 = toLocal(innerFinish);
    final p3 = toLocal(innerStart);
    final quad = Path()
      ..moveTo(p0.dx, p0.dy)
      ..lineTo(p1.dx, p1.dy)
      ..lineTo(p2.dx, p2.dy)
      ..lineTo(p3.dx, p3.dy)
      ..close();

    final yMin = math.min(math.min(p0.dy, p1.dy), math.min(p2.dy, p3.dy));
    final yMax = math.max(math.max(p0.dy, p1.dy), math.max(p2.dy, p3.dy));
    final thickness = math.max(yMax - yMin, 1.0);
    final rect = Rect.fromLTWH(0, yMin, length, thickness);

    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);

    canvas.drawPath(
      quad,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _edgeDark,
            _edgeColor,
            Color.lerp(_edgeColor, Colors.white, 0.18)!,
            _edgeColor,
            _edgeDark,
          ],
          stops: const [0, 0.18, 0.42, 0.78, 1],
        ).createShader(rect),
    );

    // Тканевая фактура: частые поперечные и продольные нити.
    canvas.save();
    canvas.clipPath(quad);
    final texture = Paint()
      ..color = _edgeDark.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    final textureLight = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..strokeWidth = 1;
    for (var x = 0.0; x < length; x += 4) {
      canvas.drawLine(Offset(x, yMin), Offset(x, yMax), texture);
      canvas.drawLine(
        Offset(x + 1.6, yMin),
        Offset(x + 1.6, yMax),
        textureLight,
      );
    }
    final warp = Paint()
      ..color = _edgeDark.withValues(alpha: 0.06)
      ..strokeWidth = 1;
    for (var y = yMin + 1; y < yMax; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(length, y), warp);
    }
    canvas.restore();

    // Строчка по сгибу — тент сложен пополам.
    _dashedLine(
      canvas,
      Offset(0, (yMin + yMax) / 2),
      Offset(length, (yMin + yMax) / 2),
      Paint()
        ..color = _edgeDark.withValues(alpha: 0.55)
        ..strokeWidth = math.max(thickness * 0.09, 0.8),
      dash: math.max(thickness * 0.5, 4),
      gap: math.max(thickness * 0.4, 3),
    );

    // Кромки: наружная и внутренняя.
    canvas.drawLine(
      Offset(p0.dx, p0.dy),
      Offset(p1.dx, p1.dy),
      Paint()
        ..color = _edgeDark.withValues(alpha: 0.75)
        ..strokeWidth = 1,
    );
    canvas.drawLine(
      Offset(p3.dx, p3.dy),
      Offset(p2.dx, p2.dy),
      Paint()
        ..color = _edgeDark.withValues(alpha: 0.6)
        ..strokeWidth = 1,
    );
    canvas.restore();
  }

  /// Спайка с соседним окном: окантовки нет, полотна сварены внахлёст.
  void _paintWeldSeam(Canvas canvas, int index, List<double> widths) {
    final outer = layers.outer;
    final a1 = outer[index];
    final b1 = outer[(index + 1) % outer.length];
    final start = layout.toPxPoint(a1);
    final finish = layout.toPxPoint(b1);
    final direction = finish - start;
    final length = direction.distance;
    if (length < 1) return;

    final angle = math.atan2(direction.dy, direction.dx);
    final thickness = math.max(
      layout.px(math.max(windowWeldWidth, widths[index] * 0.5)),
      _minBandPx,
    );

    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);
    final quad = Path()..addRect(Rect.fromLTWH(0, 0, length, thickness));
    canvas.drawPath(quad, Paint()..color = _filmEdge.withValues(alpha: 0.18));
    canvas.save();
    canvas.clipPath(quad);
    final hatch = Paint()
      ..color = _filmEdge.withValues(alpha: 0.75)
      ..strokeWidth = 1.1;
    for (var x = -thickness; x < length + thickness; x += 7) {
      canvas.drawLine(Offset(x, thickness), Offset(x + thickness, 0), hatch);
    }
    canvas.restore();
    canvas.drawRect(
      Rect.fromLTWH(0, 0, length, thickness),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _filmEdge.withValues(alpha: 0.9),
    );
    canvas.restore();

    _label(
      canvas,
      'спайка ${formatMm(windowWeldWidth)}',
      Offset.lerp(start, finish, 0.5)! +
          _inwardNormal(start, finish) * (thickness + 9),
      angle: angle,
      small: true,
      color: _filmEdge,
    );
  }

  /// Нормаль внутрь окна для отрезка кромки.
  Offset _inwardNormal(Offset a, Offset b) {
    final direction = b - a;
    final length = direction.distance;
    if (length < 0.01) return const Offset(0, -1);
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    final middle = (a + b) / 2;
    final center = layout.toPxPoint(boundsOf(layers.outer).center);
    return ((center - middle).dx * normal.dx +
                (center - middle).dy * normal.dy) >=
            0
        ? normal
        : -normal;
  }

  /// Зона напайки: кольцо, на которое плёнка заходит под окантовку.
  ///
  /// Штриховка — поперечные штрихи между контурами: без обрезки по пути,
  /// чтобы одинаково работать и в вебе.
  void _paintSeamBand(Canvas canvas) {
    // У скрина запайки под окантовку нет — есть подворот со швом.
    if (params.isScreen) return;
    final outerPoints = layers.filmEdge;
    final innerPoints = _drawInner;
    if (outerPoints.length < 3 || innerPoints.length != outerPoints.length) {
      return;
    }

    final hatch = Paint()
      ..color = _edgeDark.withValues(alpha: 0.5)
      ..strokeWidth = 1.1;
    final hatchLight = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.1;

    for (var i = 0; i < outerPoints.length; i++) {
      if (layers.isSideWelded(i)) continue;
      final a1 = layout.toPxPoint(outerPoints[i]);
      final b1 = layout.toPxPoint(outerPoints[(i + 1) % outerPoints.length]);
      final a2 = layout.toPxPoint(innerPoints[i]);
      final b2 = layout.toPxPoint(innerPoints[(i + 1) % innerPoints.length]);

      final band = Path()..fillType = PathFillType.evenOdd;
      _addPolygon(band, [
        outerPoints[i],
        outerPoints[(i + 1) % outerPoints.length],
        innerPoints[(i + 1) % innerPoints.length],
        innerPoints[i],
      ]);
      canvas.drawPath(
        band,
        Paint()..color = _edgeColor.withValues(alpha: 0.30),
      );

      final length = (b1 - a1).distance;
      if (length < 4) continue;
      final step = math.max(length / math.max((length / 9).round(), 1), 4.0);
      for (var d = 0.0; d <= length; d += step) {
        final t = d / length;
        final from = Offset.lerp(a1, b1, t)!;
        final to = Offset.lerp(a2, b2, t)!;
        canvas.drawLine(from, to, hatchLight);
        canvas.drawLine(from, to, hatch);
      }
    }
  }

  /// Вырезы: отверстие, окантовка по контуру и зона напайки вокруг.
  /// У скрина окантовки нет — рисуется только контур отверстия.
  void _paintCutouts(Canvas canvas) {
    if (params.isScreen) {
      for (final cutout in layers.cutouts) {
        canvas.drawPath(
          _cutoutPath(cutout, 0),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = _ink,
        );
        _label(
          canvas,
          _cutoutLabel(cutout),
          layout.toPxPoint(cutout.center),
          small: true,
        );
      }
      return;
    }
    for (final cutout in layers.cutouts) {
      final width = _drawWidths[0];
      final seamWidth = math.max(width - params.weldOverlapMm, width * 0.35);
      final outerBounds = _cutoutBounds(cutout, width);

      final band = Path()..fillType = PathFillType.evenOdd;
      _addCutoutShape(band, cutout, width);
      _addCutoutShape(band, cutout, 0);
      canvas.drawPath(
        band,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              _edgeDark,
              _edgeColor,
              Color.lerp(_edgeColor, Colors.white, 0.16)!,
              _edgeColor,
              _edgeDark,
            ],
          ).createShader(outerBounds),
      );

      final seam = Path()..fillType = PathFillType.evenOdd;
      _addCutoutShape(seam, cutout, seamWidth);
      _addCutoutShape(seam, cutout, 0);
      canvas.drawPath(
        seam,
        Paint()..color = _edgeColor.withValues(alpha: 0.30),
      );
      _hatchCutoutRing(canvas, cutout, 0, seamWidth);

      canvas.drawPath(
        _cutoutPath(cutout, 0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..color = _ink,
      );
      canvas.drawPath(
        _cutoutPath(cutout, width),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.3
          ..color = _edgeDark,
      );

      _label(
        canvas,
        _cutoutLabel(cutout),
        layout.toPxPoint(cutout.center),
        small: true,
      );
    }
  }

  String _cutoutLabel(CutoutGeometry cutout) => cutout.isCircle
      ? 'вырез Ø${formatMm(cutout.spec.width)}'
      : 'вырез ${formatMm(cutout.spec.width)}×${formatMm(cutout.spec.height)}';

  Rect _cutoutBounds(CutoutGeometry cutout, double grow) => Rect.fromPoints(
    layout.toPxPoint(
      Offset(cutout.bounds.left - grow, cutout.bounds.top - grow),
    ),
    layout.toPxPoint(
      Offset(cutout.bounds.right + grow, cutout.bounds.bottom + grow),
    ),
  );

  Path _cutoutPath(CutoutGeometry cutout, double grow) {
    final path = Path();
    _addCutoutShape(path, cutout, grow);
    return path;
  }

  void _addCutoutShape(Path path, CutoutGeometry cutout, double grow) {
    if (cutout.isCircle) {
      path.addOval(
        Rect.fromCircle(
          center: layout.toPxPoint(cutout.center),
          radius: layout.px(cutout.radius! + grow),
        ),
      );
      return;
    }
    final rect = cutout.rect!.inflate(grow);
    _addPolygon(path, [
      Offset(rect.left, rect.top),
      Offset(rect.right, rect.top),
      Offset(rect.right, rect.bottom),
      Offset(rect.left, rect.bottom),
    ]);
  }

  /// Поперечные штрихи в кольце напайки вокруг выреза.
  void _hatchCutoutRing(
    Canvas canvas,
    CutoutGeometry cutout,
    double from,
    double to,
  ) {
    final hatch = Paint()
      ..color = _edgeDark.withValues(alpha: 0.45)
      ..strokeWidth = 1;
    if (cutout.isCircle) {
      final center = layout.toPxPoint(cutout.center);
      final inner = layout.px(cutout.radius! + from);
      final outer = layout.px(cutout.radius! + to);
      final segments = math.max(((2 * math.pi * inner) / 9).round(), 8);
      for (var i = 0; i < segments; i++) {
        final angle = 2 * math.pi * i / segments;
        final unit = Offset(math.cos(angle), math.sin(angle));
        canvas.drawLine(center + unit * inner, center + unit * outer, hatch);
      }
      return;
    }
    final rect = cutout.rect!;
    final sides = [
      (Offset(rect.left, rect.top), Offset(rect.right, rect.top)),
      (Offset(rect.right, rect.top), Offset(rect.right, rect.bottom)),
      (Offset(rect.right, rect.bottom), Offset(rect.left, rect.bottom)),
      (Offset(rect.left, rect.bottom), Offset(rect.left, rect.top)),
    ];
    final center = layout.toPxPoint(cutout.center);
    for (final (a, b) in sides) {
      final a1 = layout.toPxPoint(a);
      final b1 = layout.toPxPoint(b);
      final normal = _outwardOffset(a1, b1, center);
      final length = (b1 - a1).distance;
      if (length < 4) continue;
      final step = math.max(length / math.max((length / 9).round(), 1), 4.0);
      for (var d = 0.0; d <= length; d += step) {
        final point = Offset.lerp(a1, b1, d / length)!;
        canvas.drawLine(
          point + normal * layout.px(from),
          point + normal * layout.px(to),
          hatch,
        );
      }
    }
  }

  /// Единичная нормаль от отрезка наружу от центра выреза (экранные координаты).
  Offset _outwardOffset(Offset a, Offset b, Offset center) {
    final direction = b - a;
    final length = direction.distance;
    if (length < 0.01) return const Offset(0, -1);
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    final middle = (a + b) / 2;
    return ((middle - center).dx * normal.dx +
                (middle - center).dy * normal.dy) >=
            0
        ? normal
        : -normal;
  }

  /// Видимая граница плёнки — внутренняя кромка окантовки.
  void _paintVisibleFilmEdge(Canvas canvas) {
    canvas.drawPath(
      _polygonPath(layers.edgeInner),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _filmStrokeColor,
    );
  }

  /// Молния: у ПВХ впаяна в полосу тента, у скрина — в подвёрнутую полосу
  /// (накладную полосу) из того же скрина.
  ///
  /// У ПВХ по краям полосы рисуются зоны напайки [WindowParams.weldOverlapMm],
  /// у скрина той же полосой идёт шов [screenSeamMm] мм серым цветом скрина.
  void _paintZipper(Canvas canvas) {
    for (var i = 0; i < layers.zippers.length; i++) {
      _paintOneZipper(canvas, layers.zippers[i], layers.zipperBands[i], i);
    }
  }

  void _paintOneZipper(
    Canvas canvas,
    ({Offset start, Offset end, double bandWidth}) zipper,
    Rect bandRect,
    int index,
  ) {
    final start = layout.toPxPoint(zipper.start);
    final end = layout.toPxPoint(zipper.end);
    final length = (end - start).distance;
    if (length < 4) return;
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final bandWidth = math.max(layout.px(bandRect.width), 7.0);
    final half = bandWidth / 2;
    final weld = math.max(layout.px(params.weldOverlapMm), 2.5);

    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);

    final rect = Rect.fromLTWH(0, -half, length, bandWidth);
    if (params.isScreen) {
      // Полоса скрина: серая ткань, как подворот, с тем же швом 3 мм по краям
      // (вместо зон напайки 25 мм у тента).
      canvas.drawRect(
        rect,
        Paint()..color = const Color(0xFFB9BEC4).withValues(alpha: 0.85),
      );
      final seam = math.max(layout.px(screenSeamMm), 1.2);
      for (final y in [rect.top, rect.bottom]) {
        canvas.drawLine(
          Offset(rect.left, y),
          Offset(rect.right, y),
          Paint()
            ..color = const Color(0xFF8C9298)
            ..strokeWidth = seam,
        );
        canvas.drawLine(
          Offset(rect.left, y),
          Offset(rect.right, y),
          Paint()
            ..color = Colors.white.withValues(alpha: 0.85)
            ..strokeWidth = math.max(seam * 0.35, 0.6),
        );
      }
      _label(
        canvas,
        'шов ${formatMm(screenSeamMm)} мм по краям полосы',
        Offset(length * 0.5, -half - 13),
        small: true,
        color: const Color(0xFF5B6B80),
      );
    } else {
      // Полоса тента под молнию — с тем же тканевым видом, что окантовка.
      canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _edgeDark,
              _edgeColor,
              Color.lerp(_edgeColor, Colors.white, 0.2)!,
              _edgeColor,
              _edgeDark,
            ],
            stops: const [0, 0.2, 0.45, 0.8, 1],
          ).createShader(rect),
      );
      canvas.save();
      canvas.clipRect(rect);
      final texture = Paint()
        ..color = _edgeDark.withValues(alpha: 0.10)
        ..strokeWidth = 1;
      for (var x = 0.0; x < length; x += 4) {
        canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), texture);
      }
      canvas.restore();

      // Зоны напайки по обоим краям полосы.
      for (final side in [-1.0, 1.0]) {
        final weldRect = side > 0
            ? Rect.fromLTRB(rect.left, half - weld, rect.right, half)
            : Rect.fromLTRB(rect.left, -half, rect.right, -half + weld);
        canvas.save();
        canvas.clipRect(weldRect);
        final hatch = Paint()
          ..color = _edgeDark.withValues(alpha: 0.45)
          ..strokeWidth = 1;
        for (
          var x = weldRect.left - weldRect.height;
          x < weldRect.right + weldRect.height;
          x += 7
        ) {
          canvas.drawLine(
            Offset(x, weldRect.top),
            Offset(x + weldRect.height, weldRect.bottom),
            hatch,
          );
        }
        canvas.restore();
        canvas.drawRect(
          weldRect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = _edgeDark.withValues(alpha: 0.6),
        );
      }
    }

    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = params.isScreen ? const Color(0xFF5B6B80) : _edgeDark,
    );

    // Застёжка: два ряда зубцов и щель между ними.
    final tooth = math.max(bandWidth * 0.22, 2.6);
    final step = math.max(tooth * 1.75, 4.2);
    final teethLeft = Paint()..color = _metal;
    final teethRight = Paint()..color = Color.lerp(_metal, _metalDark, 0.35)!;
    final gap = Paint()
      ..color = _ink.withValues(alpha: 0.55)
      ..strokeWidth = math.max(tooth * 0.22, 0.8);
    canvas.drawLine(Offset(0, 0), Offset(length, 0), gap);
    for (var x = tooth; x < length - tooth; x += step) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, -tooth, tooth * 0.85, tooth * 1.05),
          Radius.circular(tooth * 0.3),
        ),
        teethLeft,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            x + tooth * 0.9,
            -tooth * 0.05,
            tooth * 0.85,
            tooth * 1.05,
          ),
          Radius.circular(tooth * 0.3),
        ),
        teethRight,
      );
    }

    // Ограничители в начале и конце застёжки.
    for (final x in [0.0, length - tooth * 1.1]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, -tooth * 1.25, tooth * 1.1, tooth * 2.5),
          Radius.circular(tooth * 0.3),
        ),
        Paint()..color = _metalDark,
      );
    }

    // Бегунок с язычком.
    final sliderWidth = math.max(tooth * 3.4, 9.0);
    final sliderRect = Rect.fromLTWH(
      math.max(length * 0.08, 4),
      -tooth * 1.6,
      sliderWidth,
      tooth * 3.2,
    );
    _metalShadow(canvas, sliderRect, tooth);
    final sliderRRect = RRect.fromRectAndRadius(
      sliderRect,
      Radius.circular(tooth * 0.55),
    );
    canvas.drawRRect(sliderRRect, Paint()..shader = _metalShader(sliderRect));
    canvas.drawRRect(
      sliderRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(tooth * 0.2, 0.9)
        ..color = _metalDark,
    );
    final pull = RRect.fromRectAndRadius(
      Rect.fromLTWH(
        sliderRect.center.dx - tooth * 0.35,
        sliderRect.bottom,
        tooth * 0.7,
        tooth * 2.6,
      ),
      Radius.circular(tooth * 0.3),
    );
    canvas.drawRRect(pull, Paint()..color = _metal);
    canvas.drawRRect(
      pull,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(tooth * 0.16, 0.8)
        ..color = _metalDark,
    );

    if (layers.zippers.length > 1) {
      _label(
        canvas,
        'молния ${index + 1}',
        Offset(length * 0.5, half + 14),
        small: true,
        color: _special,
      );
    }
    canvas.restore();
  }

  /// Цепочка размеров вокруг молний: слева до полосы, полоса, справа до кромки.
  ///
  /// У каждой следующей молнии цепочка идёт ниже, чтобы подписи не налезали.
  /// У скрина цепочка меряется до кромки подворота (видимого контура).
  void _paintZipperDimensions(Canvas canvas) {
    final all = layers.zipperGapsAll;
    if (all.isEmpty) return;
    final bounds = layers.filmVisibleBounds;
    for (var i = 0; i < all.length; i++) {
      final gaps = all[i];
      final band = layers.zipperBands[i];
      final lineY = bounds.bottom - bounds.height * (0.13 + 0.11 * i);
      final p0 = layout.toPx(bounds.left, lineY);
      final p1 = layout.toPx(band.left, lineY);
      final p2 = layout.toPx(band.right, lineY);
      final p3 = layout.toPx(bounds.right, lineY);

      _dimension(canvas, p0, p1, const Offset(0, -18), formatMm(gaps.left));
      _dimension(canvas, p1, p2, const Offset(0, -18), formatMm(gaps.band));
      _dimension(canvas, p2, p3, const Offset(0, -18), formatMm(gaps.right));
    }
  }

  /// Подъёмные ремни: висят сверху вниз по полотну.
  void _paintLiftStraps(Canvas canvas) {
    final straps = layers.liftStraps;
    if (straps.isEmpty) return;
    for (final rect in straps) {
      final screenRect = Rect.fromPoints(
        layout.toPxPoint(Offset(rect.left, rect.bottom)),
        layout.toPxPoint(Offset(rect.right, rect.top)),
      );
      final rrect = RRect.fromRectAndRadius(
        screenRect,
        const Radius.circular(2),
      );
      canvas.drawRRect(rrect, Paint()..color = const Color(0xFFDCE2EA));
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..color = _metalDark,
      );
      // Прострочка у верхнего края и петля на конце.
      canvas.drawLine(
        Offset(screenRect.left + 3, screenRect.top + 8),
        Offset(screenRect.right - 3, screenRect.top + 8),
        Paint()
          ..color = _metalDark
          ..strokeWidth = 1,
      );
      canvas.drawCircle(
        Offset(screenRect.center.dx, screenRect.bottom - 7),
        math.max(screenRect.width * 0.28, 2.2),
        Paint()..color = _metalDark,
      );
    }

    final first = straps.first;
    final topPoint = layout.toPxPoint(Offset(first.center.dx, first.bottom));
    _label(
      canvas,
      'подъёмные ремни: ${straps.length} шт',
      topPoint + const Offset(0, -12),
      small: true,
      color: _metalDark,
    );
  }

  /// Фартук (бывший карман) — полоса от внутреннего края окантовки (у скрина
  /// от линии подворота) до внешнего края и немного ниже/выше.
  ///
  /// Рисуется только полупрозрачной накладкой с тонкой пунктирной кромкой:
  /// текстовых подписей на самом чертеже нет — они перекрывали подписи
  /// подворота и шва. Что это фартук, сказано в легенде и примечаниях листа.
  void _paintPocket(Canvas canvas) {
    _paintPocketBand(canvas, layers.pocketBand(WindowSide.bottom));
    _paintPocketBand(canvas, layers.pocketBand(WindowSide.top));
  }

  void _paintPocketBand(Canvas canvas, List<Offset> polygon) {
    if (polygon.length < 3) return;
    final path = _polygonPath(polygon);

    // Полупрозрачная накладка: основной чертёж остаётся читаемым.
    canvas.drawPath(
      path,
      Paint()
        ..color = (params.isScreen ? const Color(0xFF8C9298) : _edgeColor)
            .withValues(alpha: params.isScreen ? 0.10 : 0.26),
    );

    // Тонкая пунктирная кромка — фартук не спорит с контуром окантовки.
    final border = Paint()
      ..strokeWidth = 1.1
      ..color = (params.isScreen ? const Color(0xFF5B6B80) : _edgeDark)
          .withValues(alpha: 0.85);
    for (var i = 0; i < polygon.length; i++) {
      _dashedLine(
        canvas,
        layout.toPxPoint(polygon[i]),
        layout.toPxPoint(polygon[(i + 1) % polygon.length]),
        border,
        dash: 5,
        gap: 4,
      );
    }
  }

  /// Центр люверса с поправкой на минимальную ширину канта.
  ///
  /// Если кант на мелком масштабе расширен до [minBandWithEyeletsPx], центр
  /// полосы смещается внутрь. Сдвигаем туда и люверс, иначе кольцо свисало
  /// бы с наружной кромки.
  Offset _eyeletDrawCenter(EyeletPlacement eyelet) {
    final center = layout.toPxPoint(eyelet.center);
    if (params.isScreen) return center;
    final actual = layout.px(layers.finishedWidthFor(eyelet.side));
    final drawn = math.max(actual, _minBandWithEyeletsPx);
    final shift = (drawn - actual) / 2;
    if (shift <= 0.05) return center;
    return center - _outwardNormal(eyelet) * shift;
  }

  void _paintEyelets(Canvas canvas) {
    final eyelets = layers.eyelets;
    if (eyelets.isEmpty) return;

    // Расстояние до ближайшего соседнего люверса на листе: по нему решаем,
    // можно ли рисовать кольца крупно или они уже сливаются в кашу.
    final centers = [
      for (final eyelet in eyelets) _eyeletDrawCenter(eyelet),
    ];
    final spacing = List<double>.filled(centers.length, double.infinity);
    for (var i = 0; i < centers.length; i++) {
      for (var j = i + 1; j < centers.length; j++) {
        final distance = (centers[i] - centers[j]).distance;
        if (distance < spacing[i]) spacing[i] = distance;
        if (distance < spacing[j]) spacing[j] = distance;
      }
    }

    for (var i = 0; i < eyelets.length; i++) {
      final eyelet = eyelets[i];
      // В углах круглый люверс (если тумблер включён): угол тянет по
      // диагонали, овальный там не держит.
      final type = layers.typeFor(eyelet);
      final actualWidth = layout.px(type.outerWidth);
      final actualHeight = layout.px(type.outerHeight);
      // Минимальный символ считается по меньшей стороне: кольцо должно
      // читаться, даже если овальный люверс стоит боком.
      final symbolSize = eyeletDrawSize(
        layout.scale,
        actualDiameterMm: math.min(type.outerWidth, type.outerHeight),
        spacingPx: spacing[i],
      );
      // Овал сохраняет пропорции: меньшая сторона не меньше минимума,
      // большая растягивается во столько же раз.
      final actualMin = math.min(actualWidth, actualHeight);
      final grow = math.max(symbolSize / math.max(actualMin, 0.01), 1.0);
      final outerWidth = actualWidth * grow;
      final outerHeight = actualHeight * grow;
      // Плотная расстановка: кольца почти касаются. Убираем тень и блеск,
      // оставляем только металл, отверстие и тонкий контур — иначе каша.
      final dense =
          spacing[i].isFinite && spacing[i] < 1.6 * minEyeletOuterPx;
      _drawEyelet(
        canvas,
        centers[i],
        -eyelet.angle,
        outerWidth,
        outerHeight,
        _eyeletHolePx(
          type.holeWidth,
          type.outerWidth,
          outerWidth,
        ),
        _eyeletHolePx(
          type.holeHeight,
          type.outerHeight,
          outerHeight,
        ),
        simple: dense || symbolSize <= minEyeletOuterPx + 0.4,
      );
    }
  }

  /// Отверстие люверса на листе: фактическая доля внешнего размера, но не
  /// меньше [minEyeletHolePx] и не больше 45 % — кольцо обязано остаться.
  double _eyeletHolePx(
    double actualHoleMm,
    double actualOuterMm,
    double outerPx,
  ) {
    final pxPerMm = actualOuterMm > 0.01 ? outerPx / actualOuterMm : 0.0;
    return math.min(
      eyeletHoleDrawSize(
        outerPx,
        actualHoleMm: actualHoleMm,
        pxPerMm: pxPerMm,
      ),
      outerPx * 0.45,
    );
  }

  /// Люверс: металлическое кольцо с блеском, фаской и отверстием.
  void _drawEyelet(
    Canvas canvas,
    Offset center,
    double angle,
    double outerWidth,
    double outerHeight,
    double holeWidth,
    double holeHeight, {
    bool simple = false,
  }) {
    // Даже если расчёт дал меньше минимума, рисуем символ по минимуму:
    // на 1:20–1:50 люверс остаётся кольцом, а не точкой.
    final width = math.max(outerWidth, minEyeletOuterPx);
    final height = math.max(outerHeight, minEyeletOuterPx);
    final oval = Rect.fromCenter(
      center: center,
      width: width,
      height: height,
    );
    final radius = math.min(width, height) / 2;

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);

    // Тень под кольцом — только на крупном масштабе: у 7-точечного символа
    // размытие превращается в грязное пятно.
    if (!simple) {
      canvas.drawOval(
        oval.shift(Offset(0, radius * 0.14)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.25)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.35),
      );
    }

    // Само кольцо металла: градиент сохраняется и на мелком масштабе.
    canvas.drawOval(oval, Paint()..shader = _metalShader(oval));
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = simple ? 0.8 : math.max(radius * 0.16, 0.9)
        ..color = _metalDark,
    );

    // Люфт вокруг отверстия — металл утолщается к центру.
    final hole = Rect.fromCenter(
      center: center,
      width: math.min(
        math.max(holeWidth, minEyeletHolePx),
        width * 0.5,
      ),
      height: math.min(
        math.max(holeHeight, minEyeletHolePx),
        height * 0.5,
      ),
    );
    if (!simple) {
      canvas.drawOval(
        hole.inflate(radius * 0.30),
        Paint()..color = Colors.black.withValues(alpha: 0.20),
      );
    }

    // Отверстие: сквозь него видно светлую подложку листа.
    canvas.drawOval(hole, Paint()..color = const Color(0xFFF1F5FA));
    canvas.drawOval(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = simple ? 0.7 : math.max(radius * 0.14, 0.8)
        ..color = _metalDark,
    );
    if (!simple) {
      canvas.drawOval(
        hole.deflate(radius * 0.1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(radius * 0.08, 0.6)
          ..color = Colors.white.withValues(alpha: 0.85),
      );
    }

    // Блик сверху слева: он и делает люверс металлическим кольцом.
    canvas.drawArc(
      oval.deflate(radius * 0.26),
      math.pi * 1.05,
      math.pi * 0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = simple ? 0.7 : math.max(radius * 0.2, 0.8)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: simple ? 0.75 : 0.8),
    );
    canvas.restore();
  }

  void _paintFasteners(Canvas canvas) {
    // Скрин крепится по подвороту так же, как ПВХ по окантовке: тип крепежа
    // действует, по низу и бокам рисуем выбранные скобы/замки/ремни.
    final eyelets = layers.movableSideEyelets;
    if (eyelets.isEmpty) return;
    if (params.fastenerType == FastenerType.eyeletsOnly) return;

    for (final eyelet in eyelets) {
      final normal = _outwardNormal(eyelet);
      // Размер крепежа считается по полосе своей стороны: у ПВХ это готовая
      // окантовка, у скрина — подворот (у скрина finishedWidths нулевые).
      final bandWidth = _fastenerBandWidth(eyelet.side);
      final anchor = layout.toPxPoint(eyelet.center);
      // У ПВХ люверс стоит на середине окантовки, и крепёж лежит на ленте.
      // У скрина люверс — на линии подворота (готовый контур), а полоса
      // подворота нарисована снаружи, поэтому крепёж сдвигаем наружу на
      // половину подворота: он ложится на подворот и не заходит на полотно.
      final center = params.isScreen
          ? anchor + normal * layout.px(bandWidth / 2)
          : anchor;
      switch (params.fastenerType) {
        case FastenerType.turnBuckles:
          _drawTurnBuckle(canvas, center, normal, bandWidth);
        case FastenerType.frenchLocks:
          _drawFrenchLock(canvas, center, normal, bandWidth);
        case FastenerType.straps:
          _drawStrap(canvas, center, normal);
        case FastenerType.eyeletsOnly:
          break;
      }
    }
  }

  /// Ширина полосы, на которой стоит крепёж, мм.
  ///
  /// У ПВХ это готовая (сложенная пополам) окантовка, у скрина — подворот
  /// соответствующей стороны: у скрина `finishedWidths` нулевые, и без этого
  /// скоба/замок получали бы минимальный размер.
  double _fastenerBandWidth(WindowSide side) {
    if (!params.isScreen) {
      return layers.finishedWidths.isEmpty
          ? 50.0
          : layers.finishedWidths.reduce(math.min);
    }
    return switch (side) {
      WindowSide.bottom => params.hemBottomMm,
      WindowSide.right => params.hemRightMm,
      WindowSide.top => params.hemTopMm,
      WindowSide.left => params.hemLeftMm,
    };
  }

  // -------------------------------------- размеры между креплениями

  /// Ширина полосы, в которой рисуются размеры между креплениями, мм.
  ///
  /// Это та же полоса, на которой стоит крепёж: готовая окантовка у ПВХ и
  /// подворот у скрина. У Т-окна кромок больше четырёх, поэтому для «лишних»
  /// кромок берётся самая узкая полоса — размеры всё равно останутся внутри
  /// канта.
  double _spanBandWidth(FastenerSpanLabel label) => fastenerBandWidthMm(
    WindowSpec(params, layout.geometry, layers),
    side: label.side,
    edgeIndex: label.edgeIndex,
  );

  /// Размерные подписи между центрами креплений — в пикселях листа.
  ///
  /// Считаем один раз на отрисовку: список нужен и пейнтеру размеров, и
  /// подписям окантовки (они уступают место размерам, чтобы не налезать).
  List<_SpanPx> _measureSpans() {
    final spec = WindowSpec(params, layout.geometry, layers);
    final labels = fastenerSpanLabels(
      spec,
      pxPerMm: layout.scale,
      minSpanPx: minFastenerSpanPx,
    );
    if (labels.isEmpty) return const [];

    // Контур нужен, чтобы понять, с какой стороны от кромки лежит кант:
    // у ПВХ он внутри контура, у скрина — снаружи (подворот).
    final outline = _polygonPath(layers.outer);
    final spans = <_SpanPx>[];
    for (final label in labels) {
      final bandPx = layout.px(_spanBandWidth(label));
      // В ячейке режима «все окна» полоса уже нескольких пикселей — там
      // размеры не читаются и только засоряют лист.
      if (bandPx < minFastenerSpanBandPx) continue;

      final start = layout.toPxPoint(label.startMm);
      final end = layout.toPxPoint(label.endMm);
      final center = layout.toPxPoint(label.centerMm);
      final direction = end - start;
      final length = direction.distance;
      final unit = length < 0.01 ? const Offset(1, 0) : direction / length;
      final normal = Offset(-unit.dy, unit.dx);
      // Нормаль, которая выводит за контур, — наружная.
      final outward = outline.contains(center + normal * (bandPx * 1.2))
          ? -normal
          : normal;
      // От линии центров креплений идём в полосу: у ПВХ — к плёнке,
      // у скрина — наружу, в подворот.
      final intoBand = params.isScreen ? outward : -outward;
      // Середина полосы занята крепежом и подписью окантовки, поэтому
      // размерную линию сдвигаем к краю полосы, но оставляем внутри канта.
      final offset = math.min(
        bandPx * 0.40,
        math.max(bandPx / 2 - 1, 1.0),
      );
      final fontSize = fastenerSpanFontSizePx(bandPx);
      final painter = _textPainter(
        label.text,
        color: _spanInk,
        fontSize: fontSize,
      );
      spans.add(
        _SpanPx(
          label: label,
          start: start,
          end: end,
          center: center,
          intoBand: intoBand,
          offset: offset,
          fontSize: fontSize,
          halfLength: painter.width / 2,
          angle: math.atan2(unit.dy, unit.dx),
        ),
      );
    }
    return spans;
  }

  /// Размерные подписи между креплениями, посчитанные один раз на отрисовку.
  List<_SpanPx>? _spanCache;

  List<_SpanPx> _spans() => _spanCache ??= _measureSpans();

  /// Свободное место для вспомогательной подписи на стороне [edgeIndex].
  ///
  /// Перебираем доли вдоль стороны и берём первую, которая не попадает на
  /// размеры между креплениями: цифры шага важнее, а ширина окантовки,
  /// подворота и длина кромки есть ещё и в примечаниях.
  Offset? _freeSpotOnEdge({
    required int edgeIndex,
    required Offset a,
    required Offset b,
    required Offset normal,
    required double depth,
    required double halfLength,
  }) {
    for (final fraction in const [0.32, 0.68, 0.5, 0.2, 0.8, 0.12, 0.88]) {
      final point = Offset.lerp(a, b, fraction)! + normal * depth;
      if (!_spanClashesAt(_spans(), edgeIndex, point, halfLength)) {
        return point;
      }
    }
    return null;
  }

  /// Сторона контура занята подписью размера? Тогда подпись окантовки
  /// сдвигается вдоль стороны на свободное место.
  bool _spanClashesAt(
    List<_SpanPx> spans,
    int edgeIndex,
    Offset point,
    double halfLength,
  ) {
    for (final span in spans) {
      if (span.label.edgeIndex != edgeIndex) continue;
      if ((span.center - point).distance <
          span.halfLength + halfLength + 5) {
        return true;
      }
    }
    return false;
  }

  /// Расстояние между центрами креплений: маленькие стрелки и цифра.
  ///
  /// Всё рисуется ВНУТРИ канта (полосы окантовки/подворота): выносные штрихи
  /// идут от центров креплений к размерной линии, линия — тонкая, подпись —
  /// на белой подложке, чтобы читалась поверх штриховки и на печати А4.
  void _paintFastenerSpans(Canvas canvas) {
    final spans = _measureSpans();
    if (spans.isEmpty) return;

    final tickPaint = Paint()
      ..color = _ink.withValues(alpha: 0.45)
      ..strokeWidth = 0.8;
    final linePaint = Paint()
      ..color = _spanInk
      ..strokeWidth = 0.9
      ..strokeCap = StrokeCap.round;

    for (final span in spans) {
      final a = span.start + span.intoBand * span.offset;
      final b = span.end + span.intoBand * span.offset;
      // Выносные штрихи от центров люверсов к размерной линии.
      if (span.offset > 1.5) {
        canvas.drawLine(span.start, a, tickPaint);
        canvas.drawLine(span.end, b, tickPaint);
      }
      canvas.drawLine(a, b, linePaint);

      final direction = b - a;
      final length = direction.distance;
      if (length > 3) {
        final unit = direction / length;
        _spanArrow(canvas, a, -unit, span.fontSize);
        _spanArrow(canvas, b, unit, span.fontSize);
      }
      _spanLabel(
        canvas,
        span.label.text,
        span.center + span.intoBand * span.offset,
        span.angle,
        span.fontSize,
      );
    }
  }

  /// Стрелка размерной линии между креплениями.
  void _spanArrow(Canvas canvas, Offset tip, Offset direction, double fontSize) {
    final length = math.max(fontSize * 0.5, 5.0);
    final halfWidth = math.max(fontSize * 0.17, 1.7);
    final back = tip - direction * length;
    final normal = Offset(-direction.dy, direction.dx) * halfWidth;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
      ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = _spanInk);
  }

  /// Подпись размера между креплениями: компактная, на белой подложке.
  void _spanLabel(
    Canvas canvas,
    String text,
    Offset position,
    double angle,
    double fontSize,
  ) {
    final painter = _textPainter(text, color: _spanInk, fontSize: fontSize);
    var rotation = angle;
    if (rotation > math.pi / 2 + 1e-6 || rotation < -math.pi / 2 - 1e-6) {
      rotation += math.pi;
    }
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: painter.width + 5,
          height: painter.height + 1.5,
        ),
        const Radius.circular(2.5),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.88),
    );
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  /// Нормаль, направленная наружу фигуры, в экранных координатах.
  Offset _outwardNormal(EyeletPlacement eyelet) {
    final center = layout.toPxPoint(eyelet.center);
    final shapeCenter = layout.toPxPoint(boundsOf(layers.outer).center);
    final away = center - shapeCenter;
    final length = away.distance;
    return length < 0.01 ? const Offset(0, 1) : away / length;
  }

  /// Поворотная скоба: пластина на окантовке и проволочная петля,
  /// которая поворачивается и цепляется за ответную часть.
  ///
  /// [bandWidth] — ширина полосы под крепежом (окантовка ПВХ или подворот
  /// скрина), по ней считается размер пластины.
  void _drawTurnBuckle(
    Canvas canvas,
    Offset center,
    Offset normal,
    double bandWidth,
  ) {
    final angle = math.atan2(normal.dy, normal.dx);
    // Наибольшая сторона символа — не меньше 16 точек листа; на крупном
    // масштабе размер честный, прежний.
    final overall = fastenerDrawSize(
      layout.scale,
      bandWidthMm: bandWidth,
      factor: 0.7,
    );
    final size = (overall / 1.6).clamp(5.6, 20.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    // Основание — металлическая пластина с двумя саморезами.
    final plate = Rect.fromCenter(
      center: Offset.zero,
      width: size * 0.95,
      height: size * 1.25,
    );
    _metalShadow(canvas, plate, size * 0.3);
    final plateRRect = RRect.fromRectAndRadius(
      plate,
      Radius.circular(size * 0.22),
    );
    canvas.drawRRect(plateRRect, Paint()..shader = _metalShader(plate));
    canvas.drawRRect(
      plateRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.09, 0.9)
        ..color = _metalDark,
    );
    for (final dy in [-size * 0.36, size * 0.36]) {
      final screw = Offset(0, dy);
      canvas.drawCircle(screw, size * 0.13, Paint()..color = _metalDark);
      canvas.drawCircle(
        screw,
        size * 0.13,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(size * 0.04, 0.6)
          ..color = _metal.withValues(alpha: 0.9),
      );
      canvas.drawLine(
        screw - Offset(size * 0.09, size * 0.09),
        screw + Offset(size * 0.09, size * 0.09),
        Paint()
          ..strokeWidth = math.max(size * 0.05, 0.7)
          ..color = _metalDark,
      );
    }

    // Петля из проволоки — рисуем «трубкой»: контур, металл, блик.
    final loop = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(size * 0.55, 0),
            width: size * 1.05,
            height: size * 0.95,
          ),
          Radius.circular(size * 0.42),
        ),
      );
    canvas.drawPath(
      loop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.3, 1.6)
        ..color = _metalDark,
    );
    canvas.drawPath(
      loop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.2, 1.1)
        ..color = _metal,
    );
    canvas.drawPath(
      loop,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.07, 0.5)
        ..color = Colors.white.withValues(alpha: 0.55),
    );

    // Стрелка поворота: скоба откидывается.
    canvas.drawArc(
      Rect.fromCircle(center: Offset(size * 0.5, 0), radius: size * 0.95),
      -math.pi * 0.35,
      math.pi * 0.7,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.08, 0.8)
        ..color = _special.withValues(alpha: 0.85),
    );
    final tip = Offset(
      size * 0.5 + size * 0.95 * math.cos(-math.pi * 0.35),
      size * 0.95 * math.sin(-math.pi * 0.35),
    );
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - size * 0.2, tip.dy + size * 0.05)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - size * 0.05, tip.dy + size * 0.22),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.08, 0.8)
        ..color = _special.withValues(alpha: 0.85),
    );
    canvas.restore();
  }

  /// Французский замок: металлическая планка с поворотным рычажком и
  /// стрелкой поворота на 90° (замок затягивается поворотом).
  ///
  /// [bandWidth] — ширина полосы под крепежом (окантовка ПВХ или подворот
  /// скрина).
  void _drawFrenchLock(
    Canvas canvas,
    Offset center,
    Offset normal,
    double bandWidth,
  ) {
    final angle = math.atan2(normal.dy, normal.dx);
    // Наибольшая сторона символа — не меньше 16 точек листа. У мелкого
    // масштаба длинную сторону кладём ВДОЛЬ канта: так фото остаётся
    // узнаваемым и не вылезает за полосу.
    final overall = fastenerDrawSize(
      layout.scale,
      bandWidthMm: bandWidth,
      factor: 0.62,
    );
    final size = (overall / 2.1).clamp(5.0, 20.0);
    final bandPx = layout.px(bandWidth);
    final image = fastenerImage;

    // Фото заказчика: металлическая овальная пластина с коричневым
    // ремешком. На крупном масштабе длинная ось идёт ПОПЕРЁК канта, как
    // раньше; на мелком — вдоль, чтобы 16 точек поместились в полосу.
    // Картинка поворачивается вместе со стороной.
    final acrossLimit = math.min(math.max(bandPx * 0.92, 1.0), 20.0);
    final imageAspect = (image != null && image.width > 0)
        ? image.height / image.width
        : 1.47;
    final naturalAcross = acrossLimit;
    final naturalAlong = naturalAcross / imageAspect;
    final double across;
    final double along;
    if (math.max(naturalAlong, naturalAcross) >= minFastenerPx) {
      across = naturalAcross;
      along = naturalAlong;
    } else {
      // Символ дорос до минимума по длине вдоль канта; по ширине полосы
      // он остаётся внутри окантовки.
      along = minFastenerPx;
      across = math.min(acrossLimit, along * imageAspect);
    }
    if (image != null && image.height > 0) {
      final destination = Rect.fromCenter(
        center: Offset.zero,
        width: along,
        height: across,
      );
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);
      // У фото белые углы — обрезаем их по овалу пластины, чтобы на полосе
      // окантовки не появлялся белый прямоугольник.
      canvas.clipPath(Path()..addOval(destination.inflate(0.4)));
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        destination,
        Paint()..filterQuality = FilterQuality.medium,
      );
      canvas.restore();
      return;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final plate = Rect.fromCenter(
      center: Offset.zero,
      width: size * 1.05,
      height: size * 0.95,
    );
    _metalShadow(canvas, plate, size * 0.26);
    final plateRRect = RRect.fromRectAndRadius(
      plate,
      Radius.circular(size * 0.24),
    );
    canvas.drawRRect(plateRRect, Paint()..shader = _metalShader(plate));
    canvas.drawRRect(
      plateRRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.09, 0.9)
        ..color = _metalDark,
    );

    // Два самореза по краям планки.
    for (final dx in [-size * 0.32, size * 0.32]) {
      canvas.drawCircle(Offset(dx, 0), size * 0.1, Paint()..color = _metalDark);
      canvas.drawCircle(
        Offset(dx, 0),
        size * 0.1,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(size * 0.035, 0.5)
          ..color = _metal,
      );
    }

    // Поворотный рычажок под 45° с осью.
    final lever = Path()
      ..moveTo(0, 0)
      ..lineTo(size * 0.52, -size * 0.52);
    canvas.drawPath(
      lever,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.22, 1.4)
        ..strokeCap = StrokeCap.round
        ..color = _metalDark,
    );
    canvas.drawPath(
      lever,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.13, 0.9)
        ..strokeCap = StrokeCap.round
        ..color = _metal,
    );
    canvas.drawCircle(Offset.zero, size * 0.16, Paint()..color = _metalDark);
    canvas.drawCircle(
      Offset.zero,
      size * 0.16,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.05, 0.7)
        ..color = Colors.white.withValues(alpha: 0.7),
    );

    // Стрелка поворота на 90°.
    final arcRect = Rect.fromCircle(center: Offset.zero, radius: size * 1.05);
    canvas.drawArc(
      arcRect,
      -math.pi * 0.5,
      math.pi * 0.5,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.09, 0.9)
        ..color = _special,
    );
    final tip = Offset(0, -size * 1.05);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - size * 0.2, tip.dy + size * 0.05)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx - size * 0.02, tip.dy + size * 0.24),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(size * 0.09, 0.9)
        ..color = _special,
    );
    canvas.restore();
  }

  void _drawStrap(Canvas canvas, Offset center, Offset normal) {
    final angle = math.atan2(normal.dy, normal.dx);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final strap = RRect.fromRectAndRadius(
      const Rect.fromLTWH(-20, -3.5, 40, 7),
      const Radius.circular(3),
    );
    canvas.drawRRect(strap, Paint()..color = const Color(0xFFD8DEE6));
    canvas.drawRRect(
      strap,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = _metalDark,
    );

    // Пряжка.
    final buckle = RRect.fromRectAndRadius(
      const Rect.fromLTWH(8, -6, 12, 12),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(buckle, Paint()..color = _metal);
    canvas.drawRRect(
      buckle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8
        ..color = _metalDark,
    );
    canvas.drawLine(
      const Offset(14, -6),
      const Offset(14, 6),
      Paint()
        ..color = _metalDark
        ..strokeWidth = 2,
    );
    canvas.restore();
  }

  void _paintDrains(Canvas canvas) {
    final holes = layers.drainHoles;
    if (holes.isEmpty) return;
    final radius = math.max(layout.px(3), 2.0);
    for (final hole in holes) {
      final center = layout.toPxPoint(hole);
      canvas.drawCircle(center, radius, Paint()..color = Colors.white);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = _metalDark,
      );
    }
  }

  // -------------------------------------------------------------- размеры

  Paint _extensionPaint() => Paint()
    ..color = _ink.withValues(alpha: 0.45)
    ..strokeWidth = 1;

  void _paintDimensions(Canvas canvas) {
    final geometry = layout.geometry;
    final bottomLeft = layout.toPxPoint(geometry.bottomLeft);
    final bottomRight = layout.toPxPoint(geometry.bottomRight);
    final topLeft = layout.toPxPoint(geometry.topLeft);
    final topRight = layout.toPxPoint(geometry.topRight);
    final leftHeightTop = layout.toPx(0, geometry.leftHeight);
    final rightHeightTop = layout.toPx(
      geometry.bottomWidth,
      geometry.rightHeight,
    );
    // Верхняя кромка горизонтальна только при равных высотах слева/справа.
    // «Ширина верх» — это горизонтальный размер между верхними углами,
    // поэтому при разных высотах его нельзя вести вдоль наклонной кромки:
    // там длина стороны (например 1 265 мм), а не ширина (1 200 мм).
    final topWidthY = math.max(geometry.leftHeight, geometry.rightHeight);
    final topWidthLeft = layout.toPx(geometry.topLeft.dx, topWidthY);
    final topWidthRight = layout.toPx(geometry.topRight.dx, topWidthY);

    _dimension(
      canvas,
      bottomLeft,
      bottomRight,
      const Offset(0, 52),
      'Ширина низ ${formatMm(geometry.bottomWidth)}',
    );
    _dimension(
      canvas,
      topWidthLeft,
      topWidthRight,
      const Offset(0, -52),
      'Ширина верх ${formatMm(geometry.topWidth)}',
    );
    _dimension(
      canvas,
      bottomLeft,
      leftHeightTop,
      const Offset(-62, 0),
      'Высота лево ${formatMm(geometry.leftHeight)}',
    );
    _dimension(
      canvas,
      bottomRight,
      rightHeightTop,
      const Offset(62, 0),
      'Высота право ${formatMm(geometry.rightHeight)}',
    );

    final extension = _extensionPaint();
    // Выносные линии ширины верха — от actual верхних углов к горизонтальной
    // размерной линии (при разных высотах один угол ниже другого).
    canvas.drawLine(topLeft, topWidthLeft, extension);
    canvas.drawLine(topRight, topWidthRight, extension);
    canvas.drawLine(topLeft, leftHeightTop, extension);
    canvas.drawLine(topRight, rightHeightTop, extension);

    // У прямоугольного скрина длина кромки равна высоте стороны — подпись
    // «кромка» дублировала бы размер и засоряла узкое поле. Оставляем её
    // только там, где кромка действительно длиннее/короче (трапеция).
    final screenEdgeEqualsHeight =
        params.isScreen &&
        (geometry.leftEdgeLength - geometry.leftHeight).abs() < 0.5 &&
        (geometry.rightEdgeLength - geometry.rightHeight).abs() < 0.5;
    if (options.showEdgeLengths && !screenEdgeEqualsHeight) {
      _edgeLabel(
        canvas,
        bottomLeft,
        topLeft,
        'кромка ${formatMm(geometry.leftEdgeLength)}',
        edgeIndex: 3,
      );
      _edgeLabel(
        canvas,
        topRight,
        bottomRight,
        'кромка ${formatMm(geometry.rightEdgeLength)}',
        edgeIndex: 1,
      );
    }
  }

  void _dimension(
    Canvas canvas,
    Offset a,
    Offset b,
    Offset offset,
    String text,
  ) {
    final distance = offset.distance;
    if (distance < 1) return;
    final outward = offset / distance;
    final a2 = a + offset;
    final b2 = b + offset;
    final direction = b2 - a2;
    final length = direction.distance;
    if (length < 1) return;
    final unit = direction / length;

    final extension = _extensionPaint();
    canvas.drawLine(a + outward * 3, a2 + outward * 7, extension);
    canvas.drawLine(b + outward * 3, b2 + outward * 7, extension);

    final dimensionPaint = Paint()
      ..color = _ink
      ..strokeWidth = 1.3;
    canvas.drawLine(a2, b2, dimensionPaint);
    _arrowHead(canvas, a2, -unit);
    _arrowHead(canvas, b2, unit);

    final middle = (a2 + b2) / 2;
    _label(
      canvas,
      text,
      middle + outward * 13,
      angle: math.atan2(unit.dy, unit.dx),
    );
  }

  void _arrowHead(Canvas canvas, Offset tip, Offset direction) {
    const length = 11.5;
    const halfWidth = 4.0;
    final back = tip - direction * length;
    final normal = Offset(-direction.dy, direction.dx) * halfWidth;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
      ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = _ink);
  }

  void _edgeLabel(
    Canvas canvas,
    Offset a,
    Offset b,
    String text, {
    int? edgeIndex,
  }) {
    final direction = b - a;
    final length = direction.distance;
    if (length < 1) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    final middle = Offset.lerp(a, b, 0.5)!;
    final center = layout.toPxPoint(boundsOf(layers.outer).center);
    final toCenter = center - middle;
    final inward = (toCenter.dx * normal.dx + toCenter.dy * normal.dy) >= 0
        ? normal
        : -normal;
    // Середину стороны занимает подпись шага между креплениями, а «кромка» —
    // вспомогательная подпись: ищем для неё свободное место вдоль кромки.
    final halfLength = _textPainter(
      text,
      color: _filmEdge,
      small: true,
    ).width / 2;
    final position = edgeIndex == null
        ? middle + inward * 20
        : _freeSpotOnEdge(
            edgeIndex: edgeIndex,
            a: a,
            b: b,
            normal: inward,
            depth: 20,
            halfLength: halfLength,
          );
    if (position == null) return;
    _label(
      canvas,
      text,
      position,
      angle: math.atan2(unit.dy, unit.dx),
      small: true,
      color: _filmEdge,
    );
  }

  // -------------------------------------------------------------- выноски

  void _paintCallouts(Canvas canvas) {
    final outer = layers.outer;
    final edgeInner = layers.edgeInner;
    final filmEdge = layers.filmEdge;
    final widths = layers.finishedWidths;

    // Скрин: подворот подписан по каждой стороне — низ, право, верх, лево.
    // Подпись стоит в ПОЛЕ ЧЕРТЕЖА сразу за краем заготовки, между ним и
    // размерной цепочкой: так она не налезает ни на штриховку подворота, ни на
    // линию сгиба, ни на шов и не спорит с размерами. Слева и справа подпись
    // развёрнута вдоль стороны — в узком поле она занимает меньше места.
    if (params.isScreen) {
      final hemLine = layers.screenHemLine;
      final center = layout.toPxPoint(boundsOf(layers.outer).center);
      const offset = 24.0;
      for (var i = 0; i < hemLine.length; i++) {
        final a = layout.toPxPoint(hemLine[i]);
        final b = layout.toPxPoint(hemLine[(i + 1) % hemLine.length]);
        if ((b - a).distance < 1) continue;
        final outward = _outwardOffset(a, b, center);
        final vertical = outward.dx.abs() > outward.dy.abs();
        // Подпись подворота — не на середине стороны: там стоит сводная
        // подпись «шаг … × N» между креплениями, и две подписи спорили бы
        // за одно место (особенно на вертикальных сторонах).
        final text = 'подворот ${formatMm(params.hemForEdge(i))}';
        final position = _freeSpotOnEdge(
          edgeIndex: i,
          a: a,
          b: b,
          normal: outward,
          depth: offset,
          halfLength: _textPainter(
            text,
            color: const Color(0xFF5B6B80),
            small: true,
          ).width / 2,
        );
        if (position == null) continue;
        _label(
          canvas,
          text,
          position,
          angle: vertical ? _uprightAngle(b - a) : 0,
          small: true,
          color: const Color(0xFF5B6B80),
        );
      }
    }

    // Ширина окантовки — по каждой стороне. Подпись стоит в полосе
    // окантовки, но уступает место размерам между креплениями: если на
    // стороне есть цепочка или сводная подпись «шаг … × N», ищем свободное
    // место вдоль стороны, а если его нет — подпись не рисуем (ширины сторон
    // всё равно перечислены в примечаниях под чертежом).
    for (var i = 0; i < outer.length; i++) {
      final a = outer[i];
      final b = outer[(i + 1) % outer.length];
      final innerA = edgeInner[i];
      final innerB = edgeInner[(i + 1) % edgeInner.length];
      final direction = b - a;
      final length = direction.distance;
      if (length < 1) continue;
      final unit = direction / length;
      final normal = Offset(-unit.dy, unit.dx);
      final middle = Offset.lerp(a, b, 0.3)!;
      final center = boundsOf(outer).center;
      final toCenter = center - middle;
      final inward = (toCenter.dx * normal.dx + toCenter.dy * normal.dy) >= 0
          ? normal
          : -normal;
      final boundary = Offset.lerp(innerA, innerB, 0.3)!;
      final depth = (boundary - middle).distance;
      if (depth < 1) continue;
      final text = 'окантовка ${formatMm(widths[i])}';
      final position = _freeSpotOnEdge(
        edgeIndex: i,
        a: layout.toPxPoint(a),
        b: layout.toPxPoint(b),
        // inward посчитан в модели (ось Y вверх), на листе Y смотрит вниз.
        normal: Offset(inward.dx, -inward.dy),
        depth: layout.px(depth / 2),
        halfLength: _textPainter(
          text,
          color: _ink,
          small: true,
        ).width / 2,
      );
      if (position == null) continue;
      _label(
        canvas,
        text,
        position,
        angle: math.atan2(inward.dy, inward.dx),
        small: true,
      );
    }

    // Запайка на верхней стороне. У скрина шов уже подписан на каждой
    // стороне в _paintScreenHem — второй выноски не нужно.
    if (!params.isScreen) {
      final seamOuter = (edgeInner[3] + edgeInner[2]) / 2;
      final seamInner = (filmEdge[3] + filmEdge[2]) / 2;
      _callout(
        canvas,
        layout.toPxPoint((seamOuter + seamInner) / 2),
        layout.toPxPoint(seamOuter) + const Offset(10, -24),
        'запайка ${formatMm(params.weldOverlapMm)}',
      );
    }
  }

  /// Подпись заготовки: размер полотна в раскрое и вычет полосы молнии.
  ///
  /// Стоит в нижнем поле листа, поэтому не перекрывает ни чертёж, ни
  /// размерные цепочки, ни подписи подворота и шва.
  ///
  /// Если у окна есть молния, ширина заготовки уменьшена на ширину её полосы
  /// (см. [WindowSpec.filmCutWidth]) — и у скрина, и у ПВХ. Об этом прямо
  /// сказано в подписи («ширина 1 910 → 1 860 мм, минус полоса молнии
  /// 50 мм»), сам чертёж при этом не меняется: полотно и молния рисуются как
  /// раньше.
  void _paintBlankNote(Canvas canvas, Size size) {
    final blankWidth = layers.blankWidth + params.allowanceWidthMm;
    final blankHeight = layers.blankHeight + params.effectiveAllowanceHeightMm;
    final zipperBand = layers.zipperBandTotalMm;
    final zipperNote = zipperBand > 0
        ? ' · ширина ${formatMm(layers.filmCutBounds.width)}'
              ' → ${formatMm(layers.blankWidth)} мм, минус полоса молнии '
              '${formatMm(zipperBand)} мм'
        : '';
    final edgeHint = params.isScreen ? ' (пунктир — край заготовки)' : '';
    _label(
      canvas,
      'заготовка ${formatMm(blankWidth)} × ${formatMm(blankHeight)} мм'
      '$edgeHint$zipperNote',
      Offset(size.width / 2, size.height - 10),
      small: true,
      color: const Color(0xFF3E4C60),
    );
  }

  void _callout(
    Canvas canvas,
    Offset anchor,
    Offset textPosition,
    String text,
  ) {
    canvas.drawLine(
      anchor,
      textPosition + const Offset(-6, 5),
      Paint()
        ..color = _ink.withValues(alpha: 0.5)
        ..strokeWidth = 1,
    );
    canvas.drawCircle(anchor, 2, Paint()..color = _ink);
    _label(canvas, text, textPosition, small: true);
  }

  // ------------------------------------------------------------- оформление

  void _paintGrid(Canvas canvas, Size size) {
    final geometry = layout.geometry;
    final step = _gridStep(layout.scale);
    final minorPaint = Paint()
      ..color = _gridMinor
      ..strokeWidth = 1;
    final majorPaint = Paint()
      ..color = _gridMajor
      ..strokeWidth = 1;

    final startX = (geometry.minX / step).floor() * step;
    final endX = geometry.maxX + step;
    var index = (startX / step).round();
    for (var x = startX; x <= endX; x += step, index++) {
      final dx = layout.toPx(x, 0).dx;
      if (dx < 0 || dx > size.width) continue;
      canvas.drawLine(
        Offset(dx, 0),
        Offset(dx, size.height),
        index % 5 == 0 ? majorPaint : minorPaint,
      );
    }

    final startY = (geometry.minY / step).floor() * step;
    final endY = geometry.maxY + step;
    index = (startY / step).round();
    for (var y = startY; y <= endY; y += step, index++) {
      final dy = layout.toPx(0, y).dy;
      if (dy < 0 || dy > size.height) continue;
      canvas.drawLine(
        Offset(0, dy),
        Offset(size.width, dy),
        index % 5 == 0 ? majorPaint : minorPaint,
      );
    }
  }

  double _gridStep(double scale) {
    const candidates = <double>[
      10,
      20,
      25,
      50,
      100,
      200,
      250,
      500,
      1000,
      2000,
      5000,
    ];
    for (final candidate in candidates) {
      if (candidate * scale >= 34) return candidate;
    }
    return 10000;
  }

  /// Масштабная линейка: чередующиеся деления, подписи и штамп масштаба.
  void _paintScaleBar(Canvas canvas, Size size) {
    if (size.width < 240) return;
    final step = _barLength(layout.scale);
    const divisions = 4;
    final segment = layout.px(step) / divisions;
    final total = segment * divisions;
    const left = 26.0;
    // Линейку ставим в верхний левый угол рамки: внизу идёт размер ширины.
    const baseline = 52.0;

    final scaleText = _textPainter(
      layout.scaleLabel,
      color: _ink,
      small: false,
    );
    final caption = _textPainter(
      '0 — ${_barLabel(step)}',
      color: _ink,
      small: true,
    );
    final width =
        math.max(total, math.max(scaleText.width, caption.width)) + 24;

    // Подложка.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left - 12,
          baseline - 44,
          left - 12 + width,
          baseline + 12,
        ),
        const Radius.circular(8),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.94),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left - 12,
          baseline - 44,
          left - 12 + width,
          baseline + 12,
        ),
        const Radius.circular(8),
      ),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _gridMajor,
    );

    scaleText.paint(canvas, Offset(left, baseline - 40));

    // Полоса линейки: чередующиеся залитые и пустые деления.
    final barTop = baseline - 11;
    const barHeight = 8.0;
    for (var i = 0; i < divisions; i++) {
      final rect = Rect.fromLTWH(
        left + segment * i,
        barTop,
        segment,
        barHeight,
      );
      canvas.drawRect(rect, Paint()..color = i.isEven ? _ink : Colors.white);
    }
    canvas.drawRect(
      Rect.fromLTWH(left, barTop, total, barHeight),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _ink,
    );

    // Мелкие деления и подписи по краям.
    final tick = Paint()
      ..color = _ink
      ..strokeWidth = 1;
    for (var i = 0; i <= divisions; i++) {
      final x = left + segment * i;
      canvas.drawLine(
        Offset(x, barTop - (i.isEven ? 4 : 2)),
        Offset(x, barTop),
        tick,
      );
    }
    caption.paint(canvas, Offset(left, baseline - 1));
  }

  /// Подпись длины линейки: мм до метра, дальше — метры.
  String _barLabel(double millimeters) {
    if (millimeters >= 1000) {
      final meters = millimeters / 1000;
      final text = meters == meters.roundToDouble()
          ? meters.toStringAsFixed(0)
          : meters.toStringAsFixed(1).replaceAll('.', ',');
      return '$text м';
    }
    return '${formatMm(millimeters)} мм';
  }

  double _barLength(double scale) {
    const candidates = <double>[100, 200, 250, 500, 1000, 2000, 5000, 10000];
    for (final candidate in candidates) {
      if (candidate * scale >= 140) return candidate;
    }
    return 20000;
  }

  TextPainter _textPainter(
    String text, {
    required Color color,
    bool small = false,
    double? fontSize,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize:
              fontSize ??
              (small ? drawingLabelFontPx : drawingTitleFontPx) * labelScale,
          fontWeight: small ? FontWeight.w500 : FontWeight.w600,
          fontFamily: labelFontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Подпись с подложкой, при необходимости повёрнутая по кромке.
  void _label(
    Canvas canvas,
    String text,
    Offset position, {
    double angle = 0,
    bool small = false,
    Color color = _ink,
  }) {
    final painter = _textPainter(text, color: color, small: small);
    var rotation = angle;
    if (rotation > math.pi / 2 + 1e-6 || rotation < -math.pi / 2 - 1e-6) {
      rotation += math.pi;
    }

    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(rotation);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: painter.width + 10,
      height: painter.height + 5,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(4)),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }
}

/// Размерная подпись между креплениями, пересчитанная в пиксели листа.
class _SpanPx {
  const _SpanPx({
    required this.label,
    required this.start,
    required this.end,
    required this.center,
    required this.intoBand,
    required this.offset,
    required this.fontSize,
    required this.halfLength,
    required this.angle,
  });

  final FastenerSpanLabel label;

  /// Центры первого и последнего крепления, px.
  final Offset start;
  final Offset end;

  /// Середина между ними — там стоит подпись, px.
  final Offset center;

  /// Единичное направление в полосу окантовки/подворота.
  final Offset intoBand;

  /// Сдвиг размерной линии от центров креплений, px.
  final double offset;

  final double fontSize;

  /// Половина длины подписи вдоль кромки, px (для разведения с окантовкой).
  final double halfLength;

  /// Угол кромки на листе.
  final double angle;
}
