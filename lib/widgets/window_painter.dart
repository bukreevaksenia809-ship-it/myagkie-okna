import 'dart:math' as math;

import 'package:flutter/material.dart';

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

const List<double> _niceScales = [
  1.0, 2.0, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0, 50.0, 75.0, 100.0, 150.0, 200.0,
  250.0, 500.0, 1000.0,
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


  // Цвета по ТЗ: размеры чёрные, плёнка голубая полупрозрачная,
  // окантовка — цвет материала, люверсы — серый металл.
  static const Color _ink = Color(0xFF1B1F27);
  static const Color _filmEdge = Color(0xFF4C9BE8);
  static const Color _metal = Color(0xFF9AA3AD);
  static const Color _metalDark = Color(0xFF4C545E);
  static const Color _special = Color(0xFF0B62C4);
  static const Color _gridMinor = Color(0xFFE8ECF3);
  static const Color _gridMajor = Color(0xFFCFD9E8);

  /// Минимальная видимая толщина окантовки, пиксели. На мелком масштабе
  /// (несколько окон на листе) настоящая ширина превращается в пару точек,
  /// поэтому слегка утрируем — чертёж должен читаться без лупы.
  static const double _minBandPx = 5.0;

  /// Минимальный радиус люверса, пиксели.
  static const double _minEyeletPx = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    if (options.showGrid) _paintGrid(canvas, size);
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
    _paintDrains(canvas);
    if (options.showDimensions) _paintDimensions(canvas);
    if (options.showCallouts) _paintCallouts(canvas);
    if (showScaleBar) _paintScaleBar(canvas, size);
  }

  @override
  bool shouldRepaint(covariant WindowDrawingPainter oldDelegate) =>
      oldDelegate.params.signature != params.signature ||
      oldDelegate.options.signature != options.signature ||
      oldDelegate.layout.size != layout.size ||
      oldDelegate.layout.scale != layout.scale ||
      oldDelegate.labelFontFamily != labelFontFamily ||
      oldDelegate.showScaleBar != showScaleBar ||
      oldDelegate.labelScale != labelScale;

  // ---------------------------------------------------------------- геометрия

  Color get _edgeColor => Color(params.edgeColor.value);

  Color get _edgeDark =>
      Color.lerp(_edgeColor, const Color(0xFF15181C), 0.55)!;

  void _addPolygon(Path path, List<Offset> points) {
    final px = points.map(layout.toPxPoint).toList();
    if (px.isEmpty) return;
    path.moveTo(px.first.dx, px.first.dy);
    for (final point in px.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
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
          canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), mesh);
        }
        for (var y = bounds.top; y < bounds.bottom; y += step) {
          canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), mesh);
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
      FilmMaterial.clearPvc =>
        (const Color(0x66DCEBFB), const Color(0x4A7FB8E8)),
      FilmMaterial.tintedPvc =>
        (const Color(0x6639424F), const Color(0x5A22282F)),
      FilmMaterial.mosquitoNet =>
        (const Color(0x33858E99), const Color(0x22858E99)),
      // Скрин — простая серая полупрозрачная заливка.
      FilmMaterial.screen =>
        (const Color(0x66B9BEC4), const Color(0x4AB9BEC4)),
    };
    return LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [light, deep],
    ).createShader(bounds);
  }

  /// Толщина окантовки для рисования: настоящая, но не тоньше пары точек.
  List<double> get _drawWidths => [
        for (final width in layers.finishedWidths)
          math.max(width, _minBandPx / layout.scale),
      ];

  /// Внутренний контур окантовки для рисования.
  List<Offset> get _drawInner => insetPolygonPerSide(layers.outer, _drawWidths);

  /// Окантовка — коричневый тент: по стороне с градиентом, тканевой фактурой
  /// и строчкой по сгибу. Спаянные стороны вместо окантовки получают спайку.
  ///
  /// У скрина окантовки нет: рисуется только наружный контур, а подворот и
  /// шов добавляет [_paintScreenHem].
  void _paintEdgeBand(Canvas canvas) {
    final outer = layers.outer;
    final inner = _drawInner;
    final widths = _drawWidths;

    if (!params.isScreen) {
      for (var i = 0; i < outer.length; i++) {
        if (layers.isSideWelded(i)) {
          _paintWeldSeam(canvas, i, widths);
          continue;
        }
        _paintTentBand(canvas, i, outer, inner, widths);
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

  /// Скрин: линия подворота по периметру и тонкий шов [screenSeamMm] внутри
  /// неё. Коричневого тента нет — материал подворачивается сам.
  void _paintScreenHem(Canvas canvas) {
    final hem = layers.screenHemLine;
    final seam = layers.screenSeamLine;
    if (hem.length < 3 || seam.length < 3) return;

    // Линия подворота — сплошная, чуть жирнее шва.
    canvas.drawPath(
      _polygonPath(hem),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = const Color(0xFF5B6B80),
    );

    // Шов 3 мм — две параллельные линии: широкий серый штрих и светлая
    // середина между ним, то есть видно обе кромки шва.
    final seamWidth = math.max(layout.px(screenSeamMm), 1.6);
    canvas.drawPath(
      _polygonPath(seam),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = seamWidth
        ..color = const Color(0xFF8C9298),
    );
    canvas.drawPath(
      _polygonPath(seam),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(seamWidth * 0.35, 0.6)
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Подпись шва — на верхней стороне, у середины.
    final middle = Offset.lerp(seam[2], seam[3], 0.5)!;
    _label(
      canvas,
      'шов ${formatMm(screenSeamMm)} мм',
      layout.toPxPoint(middle) + const Offset(0, -8),
      small: true,
      color: const Color(0xFF5B6B80),
    );
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
      RRect.fromRectAndRadius(rect.shift(Offset(0, radius * 0.16)), Radius.circular(radius)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.22)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(radius * 0.28, 0.8)),
    );
  }

  /// Одна сторона окантовки: полоса тента со сгибом пополам.
  ///
  /// Полоса строится в локальной системе стороны: по X — длина кромки,
  /// по Y — толщина окантовки. Все точки сначала переводятся в экранные,
  /// иначе модельные координаты дают растянутые полосы.
  void _paintTentBand(
    Canvas canvas,
    int index,
    List<Offset> outer,
    List<Offset> inner,
    List<double> widths,
  ) {
    final start = layout.toPxPoint(outer[index]);
    final finish = layout.toPxPoint(outer[(index + 1) % outer.length]);
    final innerStart = layout.toPxPoint(inner[index]);
    final innerFinish = layout.toPxPoint(inner[(index + 1) % inner.length]);

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
      canvas.drawLine(Offset(x + 1.6, yMin), Offset(x + 1.6, yMax), textureLight);
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
    final quad = Path()
      ..addRect(Rect.fromLTWH(0, 0, length, thickness));
    canvas.drawPath(
      quad,
      Paint()..color = _filmEdge.withValues(alpha: 0.18),
    );
    canvas.save();
    canvas.clipPath(quad);
    final hatch = Paint()
      ..color = _filmEdge.withValues(alpha: 0.75)
      ..strokeWidth = 1.1;
    for (var x = -thickness; x < length + thickness; x += 7) {
      canvas.drawLine(
        Offset(x, thickness),
        Offset(x + thickness, 0),
        hatch,
      );
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
    return ((center - middle).dx * normal.dx + (center - middle).dy * normal.dy) >= 0
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
      canvas.drawPath(band, Paint()..color = _edgeColor.withValues(alpha: 0.30));

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
      final seamWidth = math.max(
        width - params.weldOverlapMm,
        width * 0.35,
      );
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
      canvas.drawPath(seam, Paint()..color = _edgeColor.withValues(alpha: 0.30));
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
        canvas.drawLine(
          center + unit * inner,
          center + unit * outer,
          hatch,
        );
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
        for (var x = weldRect.left - weldRect.height;
            x < weldRect.right + weldRect.height;
            x += 7) {
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
    canvas.drawLine(
      Offset(0, 0),
      Offset(length, 0),
      gap,
    );
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
          Rect.fromLTWH(x + tooth * 0.9, -tooth * 0.05, tooth * 0.85, tooth * 1.05),
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
      final lineY = bounds.bottom -
          bounds.height * (0.13 + 0.11 * i);
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
      final rrect = RRect.fromRectAndRadius(screenRect, const Radius.circular(2));
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


  /// Карман — продолжение полосы тента (у скрина — подворота) за кромкой:
  /// полупрозрачная накладка с подписью «карман снизу» / «карман сверху».
  void _paintPocket(Canvas canvas) {
    _paintPocketBand(canvas, layers.pocketRect, 'карман снизу');
    _paintPocketBand(canvas, layers.pocketTopRect, 'карман сверху');
  }

  void _paintPocketBand(Canvas canvas, Rect rect, String label) {
    if (rect.isEmpty) return;
    final screenRect = Rect.fromPoints(
      layout.toPxPoint(Offset(rect.left, rect.bottom)),
      layout.toPxPoint(Offset(rect.right, rect.top)),
    );

    canvas.drawRect(
      screenRect,
      Paint()
        ..color = params.isScreen
            ? const Color(0xFFB9BEC4).withValues(alpha: 0.45)
            : _edgeColor.withValues(alpha: 0.32),
    );
    canvas.drawRect(
      screenRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = params.isScreen
            ? const Color(0xFF5B6B80).withValues(alpha: 0.8)
            : _edgeDark.withValues(alpha: 0.8),
    );

    final hint = params.isScreen
        ? 'подворот ${formatMm(params.pocketWidth)}'
        : 'тент ${formatMm(pocketRollWidth)} ×2';
    _label(
      canvas,
      '$label ${formatMm(params.pocketWidth)} ($hint)',
      screenRect.center,
      small: true,
    );
  }

  void _paintEyelets(Canvas canvas) {
    for (final eyelet in layers.eyelets) {
      // В углах всегда круглый люверс: угол тянет по диагонали.
      final type = layers.typeFor(eyelet);
      _drawEyelet(
        canvas,
        layout.toPxPoint(eyelet.center),
        -eyelet.angle,
        layout.px(type.outerWidth),
        layout.px(type.outerHeight),
        layout.px(type.holeWidth),
        layout.px(type.holeHeight),
      );
    }
  }

  /// Люверс: металлическое кольцо с блеском, фаской и отверстием.
  void _drawEyelet(
    Canvas canvas,
    Offset center,
    double angle,
    double outerWidth,
    double outerHeight,
    double holeWidth,
    double holeHeight,
  ) {
    final radius = math.max(math.min(outerWidth, outerHeight) / 2, _minEyeletPx);
    if (radius <= _minEyeletPx + 0.01) {
      // На мелком масштабе люверс — просто плотная точка металла.
      canvas.drawCircle(center, radius, Paint()..color = _metal);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = _metalDark,
      );
      return;
    }

    final oval = Rect.fromCenter(
      center: center,
      width: math.max(outerWidth, _minEyeletPx * 2),
      height: math.max(outerHeight, _minEyeletPx * 2),
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    canvas.translate(-center.dx, -center.dy);

    // Тень под кольцом.
    canvas.drawOval(
      oval.shift(Offset(0, radius * 0.14)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, radius * 0.35),
    );

    // Само кольцо металла.
    canvas.drawOval(oval, Paint()..shader = _metalShader(oval));
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(radius * 0.16, 0.9)
        ..color = _metalDark,
    );

    // Люфт вокруг отверстия — металл утолщается к центру.
    final hole = Rect.fromCenter(
      center: center,
      width: math.max(holeWidth, radius * 0.7),
      height: math.max(holeHeight, radius * 0.7),
    );
    canvas.drawOval(
      hole.inflate(radius * 0.34),
      Paint()..color = Colors.black.withValues(alpha: 0.22),
    );

    // Отверстие: сквозь него видно светлую подложку листа.
    canvas.drawOval(hole, Paint()..color = const Color(0xFFF1F5FA));
    canvas.drawOval(
      hole,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(radius * 0.14, 0.8)
        ..color = _metalDark,
    );
    canvas.drawOval(
      hole.deflate(radius * 0.1),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(radius * 0.08, 0.6)
        ..color = Colors.white.withValues(alpha: 0.85),
    );

    // Блик сверху слева.
    canvas.drawArc(
      oval.deflate(radius * 0.26),
      math.pi * 1.05,
      math.pi * 0.55,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(radius * 0.2, 0.8)
        ..strokeCap = StrokeCap.round
        ..color = Colors.white.withValues(alpha: 0.8),
    );
    canvas.restore();
  }

  void _paintFasteners(Canvas canvas) {
    // Скрин крепится только люверсами: скобы, замки и ремни не рисуем.
    if (params.isScreen) return;
    final eyelets = layers.movableSideEyelets;
    if (eyelets.isEmpty) return;
    if (params.fastenerType == FastenerType.eyeletsOnly) return;

    for (final eyelet in eyelets) {
      final center = layout.toPxPoint(eyelet.center);
      final normal = _outwardNormal(eyelet);
      switch (params.fastenerType) {
        case FastenerType.turnBuckles:
          _drawTurnBuckle(canvas, center, normal);
        case FastenerType.frenchLocks:
          _drawFrenchLock(canvas, center, normal);
        case FastenerType.straps:
          _drawStrap(canvas, center, normal);
        case FastenerType.eyeletsOnly:
          break;
      }
    }
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
  void _drawTurnBuckle(Canvas canvas, Offset center, Offset normal) {
    final angle = math.atan2(normal.dy, normal.dx);
    final bandWidth = layers.finishedWidths.isEmpty
        ? 50.0
        : layers.finishedWidths.reduce(math.min);
    final size = (layout.px(bandWidth * 0.7)).clamp(9.0, 20.0);

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
  void _drawFrenchLock(Canvas canvas, Offset center, Offset normal) {
    final angle = math.atan2(normal.dy, normal.dx);
    final bandWidth = layers.finishedWidths.isEmpty
        ? 50.0
        : layers.finishedWidths.reduce(math.min);
    final size = layout.px(bandWidth * 0.62).clamp(10.0, 20.0);

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
    final rightHeightTop =
        layout.toPx(geometry.bottomWidth, geometry.rightHeight);

    _dimension(
      canvas,
      bottomLeft,
      bottomRight,
      const Offset(0, 52),
      'Ширина низ ${formatMm(geometry.bottomWidth)}',
    );
    _dimension(
      canvas,
      topLeft,
      topRight,
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
    canvas.drawLine(topLeft, leftHeightTop, extension);
    canvas.drawLine(topRight, rightHeightTop, extension);

    if (options.showEdgeLengths) {
      _edgeLabel(
        canvas,
        bottomLeft,
        topLeft,
        'кромка ${formatMm(geometry.leftEdgeLength)}',
      );
      _edgeLabel(
        canvas,
        topRight,
        bottomRight,
        'кромка ${formatMm(geometry.rightEdgeLength)}',
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

  void _edgeLabel(Canvas canvas, Offset a, Offset b, String text) {
    final direction = b - a;
    final length = direction.distance;
    if (length < 1) return;
    final unit = direction / length;
    final normal = Offset(-unit.dy, unit.dx);
    final middle = (a + b) / 2;
    final center = layout.toPxPoint(boundsOf(layers.outer).center);
    final toCenter = center - middle;
    final inward = (toCenter.dx * normal.dx + toCenter.dy * normal.dy) >= 0
        ? normal
        : -normal;
    _label(
      canvas,
      text,
      middle + inward * 20,
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
    // Полоса подворота лежит между готовым контуром (outer) и краем заготовки
    // (filmEdge), поэтому подпись ставим в середине этой полосы.
    if (params.isScreen) {
      for (var i = 0; i < outer.length; i++) {
        final a = outer[i];
        final b = outer[(i + 1) % outer.length];
        final cutA = filmEdge[i];
        final cutB = filmEdge[(i + 1) % filmEdge.length];
        final middle =
            (Offset.lerp(a, b, 0.5)! + Offset.lerp(cutA, cutB, 0.5)!) / 2;
        _label(
          canvas,
          'подворот ${formatMm(params.hemForEdge(i))}',
          layout.toPxPoint(middle),
          small: true,
          color: const Color(0xFF5B6B80),
        );
      }
    }

    // Ширина окантовки — по каждой стороне, у середины стороны.
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
      _label(
        canvas,
        'окантовка ${formatMm(widths[i])}',
        layout.toPxPoint(middle + inward * (depth / 2)),
        angle: math.atan2(inward.dy, inward.dx),
        small: true,
      );
    }

    // Запайка (у скрина — шов подворота) на верхней стороне.
    final seamOuter = (edgeInner[3] + edgeInner[2]) / 2;
    final seamInner = (filmEdge[3] + filmEdge[2]) / 2;
    _callout(
      canvas,
      layout.toPxPoint((seamOuter + seamInner) / 2),
      layout.toPxPoint(seamOuter) + const Offset(10, -24),
      params.isScreen
          ? 'шов ${formatMm(screenSeamMm)} мм'
          : 'запайка ${formatMm(params.weldOverlapMm)}',
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
      10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000, 5000,
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
    final width = math.max(total, math.max(scaleText.width, caption.width)) + 24;

    // Подложка.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left - 12, baseline - 44, left - 12 + width, baseline + 12),
        const Radius.circular(8),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.94),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left - 12, baseline - 44, left - 12 + width, baseline + 12),
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
      canvas.drawRect(
        rect,
        Paint()
          ..color = i.isEven ? _ink : Colors.white,
      );
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
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: (small ? 11 : 13.5) * labelScale,
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
