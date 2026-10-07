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
    scale = math.min(availableWidth / spanX, availableHeight / spanY);
  }

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

  String get scaleLabel => formatScaleLabel(scale);
}

const List<double> _niceScales = [
  1.0, 2.0, 2.5, 5.0, 10.0, 15.0, 20.0, 25.0, 50.0, 75.0, 100.0, 150.0, 200.0,
  250.0, 500.0, 1000.0,
];

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
  static const Color _filmFill = Color(0x2E5AA7E8);
  static const Color _filmEdge = Color(0xFF4C9BE8);
  static const Color _metal = Color(0xFF9AA3AD);
  static const Color _metalDark = Color(0xFF4C545E);
  static const Color _special = Color(0xFF0B62C4);
  static const Color _gridMinor = Color(0xFFE8ECF3);
  static const Color _gridMajor = Color(0xFFCFD9E8);

  @override
  void paint(Canvas canvas, Size size) {
    if (options.showGrid) _paintGrid(canvas, size);
    _paintFilm(canvas);
    _paintEdgeBand(canvas);
    _paintSeamBand(canvas);
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

  /// Кольцо между двумя контурами (окантовка, зона напайки).
  ///
  /// Строится как один путь из двух подконтуров с правилом evenOdd:
  /// так обходимся без `Path.combine`, который в вебе не работает и раньше
  /// заливал всё окно цветом окантовки.
  Path _ringPath(List<Offset> outerPoints, List<Offset> innerPoints) {
    final path = Path()..fillType = PathFillType.evenOdd;
    _addPolygon(path, outerPoints);
    _addPolygon(path, innerPoints);
    return path;
  }

  void _addPolygon(Path path, List<Offset> points) {
    final px = points.map(layout.toPxPoint).toList();
    if (px.isEmpty) return;
    path.moveTo(px.first.dx, px.first.dy);
    for (final point in px.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    path.close();
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

  /// Цвет заливки плёнки зависит от материала.
  Color get _filmFillColor => switch (params.material) {
        FilmMaterial.clearPvc => _filmFill,
        FilmMaterial.tintedPvc => const Color(0x4A39424F),
        FilmMaterial.mosquitoNet => const Color(0x1F8A939C),
      };

  Color get _filmStrokeColor => switch (params.material) {
        FilmMaterial.clearPvc => _filmEdge,
        FilmMaterial.tintedPvc => const Color(0xFF3D4A5C),
        FilmMaterial.mosquitoNet => const Color(0xFF6B7480),
      };

  /// Плёнка в раскрое: она заходит под окантовку, поэтому рисуется первой,
  /// а окантовка перекрывает её край.
  void _paintFilm(Canvas canvas) {
    final film = _polygonPath(layers.filmEdge);
    canvas.drawPath(film, Paint()..color = _filmFillColor);

    // Москитная сетка — мелкая клетка по всей площади плёнки.
    if (params.material == FilmMaterial.mosquitoNet) {
      canvas.save();
      canvas.clipPath(film);
      final mesh = Paint()
        ..color = const Color(0x33606A76)
        ..strokeWidth = 0.8;
      final bounds = film.getBounds();
      const step = 3.2;
      for (var x = bounds.left; x < bounds.right; x += step) {
        canvas.drawLine(Offset(x, bounds.top), Offset(x, bounds.bottom), mesh);
      }
      for (var y = bounds.top; y < bounds.bottom; y += step) {
        canvas.drawLine(Offset(bounds.left, y), Offset(bounds.right, y), mesh);
      }
      canvas.restore();
    }
  }

  void _paintEdgeBand(Canvas canvas) {
    final outer = _polygonPath(layers.outer);
    final inner = _polygonPath(layers.edgeInner);
    final band = _ringPath(layers.outer, layers.edgeInner);

    canvas.drawPath(band, Paint()..color = _edgeColor.withValues(alpha: 0.88));
    canvas.drawPath(
      outer,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeJoin = StrokeJoin.miter
        ..color = _ink,
    );
    canvas.drawPath(
      inner,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.1
        ..color = _edgeDark,
    );
  }

  /// Зона напайки: кольцо, на которое плёнка заходит под окантовку.
  ///
  /// Штриховка рисуется поперечными штрихами между внешним и внутренним
  /// контуром — без обрезки по пути, чтобы одинаково работать и в вебе.
  void _paintSeamBand(Canvas canvas) {
    final outerPoints = layers.filmEdge;
    final innerPoints = layers.edgeInner;
    if (outerPoints.length < 3 || innerPoints.length != outerPoints.length) {
      return;
    }

    final band = _ringPath(outerPoints, innerPoints);
    canvas.drawPath(
      band,
      Paint()..color = _edgeColor.withValues(alpha: 0.32),
    );

    final hatch = Paint()
      ..color = _edgeDark.withValues(alpha: 0.5)
      ..strokeWidth = 1.1;
    final hatchLight = Paint()
      ..color = Colors.white.withValues(alpha: 0.55)
      ..strokeWidth = 1.1;

    for (var i = 0; i < outerPoints.length; i++) {
      final a1 = layout.toPxPoint(outerPoints[i]);
      final b1 = layout.toPxPoint(outerPoints[(i + 1) % outerPoints.length]);
      final a2 = layout.toPxPoint(innerPoints[i]);
      final b2 = layout.toPxPoint(innerPoints[(i + 1) % innerPoints.length]);
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

    canvas.drawPath(
      _polygonPath(innerPoints),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _edgeDark.withValues(alpha: 0.55),
    );
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

  /// Молния впаяна в полосу тента: полоса цвета окантовки, по её краям —
  /// зоны напайки, а сама молния идёт по середине полосы.
  void _paintZipper(Canvas canvas) {
    final zipper = layers.zipper;
    final band = layers.zipperBand;
    if (zipper == null || band == null) return;
    final start = layout.toPxPoint(zipper.start);
    final end = layout.toPxPoint(zipper.end);
    final length = (end - start).distance;
    if (length < 4) return;
    final angle = math.atan2(end.dy - start.dy, end.dx - start.dx);
    final bandWidth = math.max(layout.px(band.width), 7.0);
    final half = bandWidth / 2;
    final weld = math.max(layout.px(weldOverlap), 2.5);
    const overhang = 7.0;

    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(angle);

    final bandRect = Rect.fromLTRB(-overhang, -half, length + overhang, half);
    canvas.drawRect(
      bandRect,
      Paint()..color = _edgeColor.withValues(alpha: 0.9),
    );

    // Зоны напайки по обоим краям полосы.
    for (final side in [-1.0, 1.0]) {
      final rect = side > 0
          ? Rect.fromLTRB(bandRect.left, half - weld, bandRect.right, half)
          : Rect.fromLTRB(bandRect.left, -half, bandRect.right, -half + weld);
      canvas.save();
      canvas.clipRect(rect);
      final hatch = Paint()
        ..color = _edgeDark.withValues(alpha: 0.45)
        ..strokeWidth = 1;
      for (var x = rect.left - rect.height;
          x < rect.right + rect.height;
          x += 7) {
        canvas.drawLine(
          Offset(x, rect.top),
          Offset(x + rect.height, rect.bottom),
          hatch,
        );
      }
      canvas.restore();
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = _edgeDark.withValues(alpha: 0.6),
      );
    }

    canvas.drawRect(
      bandRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _edgeDark,
    );

    // Сама молния — по середине полосы.
    final teeth = Paint()
      ..color = _special
      ..strokeWidth = 1.6;
    const toothStep = 6.0;
    for (var x = 2.0; x < length; x += toothStep) {
      canvas.drawLine(
        Offset(x, -weld * 0.4),
        Offset(x, weld * 0.4),
        teeth,
      );
    }
    canvas.drawLine(
      Offset(0, 0),
      Offset(length, 0),
      Paint()
        ..color = _special.withValues(alpha: 0.55)
        ..strokeWidth = 1,
    );

    final slider = RRect.fromRectAndRadius(
      Rect.fromLTWH(math.max(length - 16, 0), -weld * 0.8, 14, weld * 1.6),
      const Radius.circular(2.5),
    );
    canvas.drawRRect(slider, Paint()..color = _special);
    canvas.drawRRect(
      slider,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = _ink,
    );
    canvas.restore();
  }

  /// Цепочка размеров вокруг молнии: слева до спайки, спайка, справа до кромки.
  void _paintZipperDimensions(Canvas canvas) {
    final gaps = layers.zipperGaps;
    final band = layers.zipperBand;
    if (gaps == null || band == null) return;
    final bounds = layers.filmVisibleBounds;
    final lineY = bounds.bottom - bounds.height * 0.13;
    final p0 = layout.toPx(bounds.left, lineY);
    final p1 = layout.toPx(band.left, lineY);
    final p2 = layout.toPx(band.right, lineY);
    final p3 = layout.toPx(bounds.right, lineY);

    _dimension(canvas, p0, p1, const Offset(0, -18), formatMm(gaps.left));
    _dimension(canvas, p1, p2, const Offset(0, -18), formatMm(gaps.band));
    _dimension(canvas, p2, p3, const Offset(0, -18), formatMm(gaps.right));
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


  /// Карман — продолжение нижнего тента вниз: полупрозрачная накладка
  /// ниже нижней кромки с подписью «карман».
  void _paintPocket(Canvas canvas) {
    final rect = layers.pocketRect;
    if (rect.isEmpty) return;
    final screenRect = Rect.fromPoints(
      layout.toPxPoint(Offset(rect.left, rect.bottom)),
      layout.toPxPoint(Offset(rect.right, rect.top)),
    );

    canvas.drawRect(
      screenRect,
      Paint()..color = _edgeColor.withValues(alpha: 0.32),
    );
    canvas.drawRect(
      screenRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..color = _edgeDark.withValues(alpha: 0.8),
    );

    _label(
      canvas,
      'карман ${formatMm(params.pocketWidth)} (тент ${formatMm(pocketRollWidth)} ×2)',
      screenRect.center,
      small: true,
    );
  }

  void _paintEyelets(Canvas canvas) {
    final type = layers.eyeletType;
    final outerWidth = layout.px(type.outerWidth);
    final outerHeight = layout.px(type.outerHeight);
    final metalFill = Paint()..color = _metal;
    final metalStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = _metalDark;
    final holeFill = Paint()..color = Colors.white;
    final holeStroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = _metalDark;

    if (outerHeight < 2.4) {
      for (final eyelet in layers.eyelets) {
        canvas.drawCircle(layout.toPxPoint(eyelet.center), 2.0, metalFill);
      }
      return;
    }

    final holeWidth = math.max(layout.px(type.holeWidth), 1.6);
    final holeHeight = math.max(layout.px(type.holeHeight), 1.6);

    for (final eyelet in layers.eyelets) {
      final center = layout.toPxPoint(eyelet.center);
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(-eyelet.angle);

      final outerRect = Rect.fromCenter(
        center: Offset.zero,
        width: outerWidth,
        height: outerHeight,
      );
      final outerRRect = RRect.fromRectAndRadius(
        outerRect,
        Radius.circular(math.min(outerWidth, outerHeight) / 2),
      );
      canvas.drawRRect(outerRRect, metalFill);
      canvas.drawRRect(outerRRect, metalStroke);

      final holeRect = Rect.fromCenter(
        center: Offset.zero,
        width: holeWidth,
        height: holeHeight,
      );
      final holeRRect = RRect.fromRectAndRadius(
        holeRect,
        Radius.circular(math.min(holeWidth, holeHeight) / 2),
      );
      canvas.drawRRect(holeRRect, holeFill);
      canvas.drawRRect(holeRRect, holeStroke);
      canvas.restore();
    }
  }

  void _paintFasteners(Canvas canvas) {
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

  /// Скоба — прямоугольник поперёк окантовки с отверстием под саморез.
  ///
  /// Габарит ограничен шириной окантовки, чтобы скоба оставалась внутри неё.
  void _drawTurnBuckle(Canvas canvas, Offset center, Offset normal) {
    final angle = math.atan2(normal.dy, normal.dx);
    final bandWidth = layers.finishedWidths.isEmpty
        ? 50.0
        : layers.finishedWidths.reduce(math.min);
    final length = math.min(layout.px(bandWidth * 0.8), 16.0).clamp(6.0, 16.0);
    final height = math.max(length * 0.5, 4.0);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final plate = Rect.fromCenter(
      center: Offset.zero,
      width: length,
      height: height,
    );
    canvas.drawRect(plate, Paint()..color = _metal);
    canvas.drawRect(
      plate,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(height * 0.22, 1.2)
        ..color = _metalDark,
    );
    if (length > 9) {
      canvas.drawCircle(
        Offset(-length * 0.28, 0),
        math.max(height * 0.16, 1.2),
        Paint()..color = _metalDark,
      );
    }
    canvas.restore();
  }

  /// Французский замок: квадрат основания и стрелка поворота на 90°.
  void _drawFrenchLock(Canvas canvas, Offset center, Offset normal) {
    final angle = math.atan2(normal.dy, normal.dx);
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);

    final square = Rect.fromCenter(
      center: const Offset(6, 0),
      width: 7,
      height: 7,
    );
    canvas.drawRect(square, Paint()..color = _metal);
    canvas.drawRect(
      square,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..color = _metalDark,
    );

    final arcRect = Rect.fromCenter(
      center: const Offset(6, 0),
      width: 20,
      height: 20,
    );
    final arcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = _special;
    canvas.drawArc(arcRect, -math.pi / 2, math.pi * 0.65, false, arcPaint);

    final tip = Offset(arcRect.center.dx, arcRect.top);
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx - 3.4, tip.dy + 3.4)
        ..lineTo(tip.dx, tip.dy)
        ..lineTo(tip.dx + 3.4, tip.dy + 3.4),
      arcPaint,
    );
    canvas.restore();
  }

  /// Силиконовый ремень: полоса с пряжкой и шпеньком — крупно и чётко.
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
      ..strokeWidth = 1.1;
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
    const length = 10.0;
    const halfWidth = 3.4;
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

    // Напайка — на верхней стороне.
    final seamOuter = (edgeInner[3] + edgeInner[2]) / 2;
    final seamInner = (filmEdge[3] + filmEdge[2]) / 2;
    _callout(
      canvas,
      layout.toPxPoint((seamOuter + seamInner) / 2),
      layout.toPxPoint(seamOuter) + const Offset(10, -24),
      'напайка ${formatMm(weldOverlap)}',
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

  void _paintScaleBar(Canvas canvas, Size size) {
    if (size.width < 260) return;
    final step = _barLength(layout.scale);
    final barWidth = layout.px(step);
    const left = 24.0;
    final y = size.height - 24;
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.4;

    final label = _textPainter(
      '0 — ${formatMm(step)} мм · ${layout.scaleLabel}',
      color: _ink,
      small: true,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(
          left - 8,
          y - 24,
          left + math.max(barWidth, label.width) + 10,
          y + 9,
        ),
        const Radius.circular(6),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );

    canvas.drawLine(Offset(left, y), Offset(left + barWidth, y), paint);
    canvas.drawLine(Offset(left, y - 5), Offset(left, y + 5), paint);
    canvas.drawLine(
      Offset(left + barWidth, y - 5),
      Offset(left + barWidth, y + 5),
      paint,
    );
    label.paint(canvas, Offset(left, y - 21));
  }

  double _barLength(double scale) {
    const candidates = <double>[100, 200, 250, 500, 1000, 2000, 5000, 10000];
    for (final candidate in candidates) {
      if (candidate * scale >= 90) return candidate;
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
          fontSize: (small ? 11 : 12.5) * labelScale,
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
