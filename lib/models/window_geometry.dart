import 'dart:math' as math;
import 'dart:ui' show Offset, Rect;

import 'window_params.dart';

/// Сторона окна, к которой относится элемент.
enum WindowSide {
  bottom,
  right,
  top,
  left;

  String get label => switch (this) {
        WindowSide.bottom => 'низ',
        WindowSide.right => 'право',
        WindowSide.top => 'верх',
        WindowSide.left => 'лево',
      };
}

/// Вырез в полотне в координатах модели.
class CutoutGeometry {
  const CutoutGeometry._({
    required this.spec,
    required this.center,
    this.rect,
    this.radius,
  });

  factory CutoutGeometry.rect({required Rect rect, required Cutout spec}) =>
      CutoutGeometry._(spec: spec, center: rect.center, rect: rect);

  factory CutoutGeometry.circle({
    required Offset center,
    required double radius,
    required Cutout spec,
  }) =>
      CutoutGeometry._(spec: spec, center: center, radius: radius);

  final Cutout spec;
  final Offset center;

  /// Прямоугольник выреза (для [CutoutShape.rect]).
  final Rect? rect;

  /// Радиус выреза (для [CutoutShape.circle]).
  final double? radius;

  bool get isCircle => spec.shape == CutoutShape.circle;

  double get perimeterMm => spec.perimeterMm;

  double get areaMm2 => spec.areaMm2;

  /// Габарит выреза — по нему считаются подписи.
  Rect get bounds => rect ?? Rect.fromCircle(center: center, radius: radius!);
}

/// Люверс на чертеже.
class EyeletPlacement {
  const EyeletPlacement({
    required this.center,
    required this.side,
    required this.angle,
    required this.isCorner,
    required this.positionInEdge,
  });

  /// Центр люверса, мм.
  final Offset center;

  /// К какой стороне окна относится.
  final WindowSide side;

  /// Направление кромки, радианы (для ориентации овального люверса).
  final double angle;

  /// Совпадает с углом полотна.
  final bool isCorner;

  /// Доля длины стороны от её начала, 0…1.
  final double positionInEdge;
}

/// Чертёж мягкого окна: четырёхугольник, у которого нижняя и верхняя кромки
/// горизонтальны, а высоты слева и справа заданы замерами.
///
/// Координаты — в миллиметрах, начало в левом нижнем углу, ось Y вверх.
class WindowGeometry {
  WindowGeometry({
    required this.bottomWidth,
    required this.topWidth,
    required this.leftHeight,
    required this.rightHeight,
    required this.topOffset,
    this.pocketDrop = 0,
    this.pocketTopRise = 0,
  });

  factory WindowGeometry.of(WindowParams params) {
    // Геометрия строится по ОСНОВНЫМ размерам изделия (замеру). Припуск на
    // раскрой сюда не входит: он добавляется только к заготовке плёнки
    // (см. WindowSpec.filmCutWidthWithAllowance), поэтому чертёж, окантовка,
    // люверсы, площадь изделия и документы считаются по чистому изделию.
    final bottom = _positive(params.bottomWidth);
    final top = _positive(params.topWidth);
    final offset = switch (params.topAlign) {
      TopAlign.center => (bottom - top) / 2,
      TopAlign.left => 0.0,
      TopAlign.right => bottom - top,
      TopAlign.custom => params.topOffsetMm.isFinite ? params.topOffsetMm : 0.0,
    };
    final pocketWidth =
        params.pocketWidth.isFinite && params.pocketWidth > 0
            ? params.pocketWidth
            : 0.0;
    return WindowGeometry(
      bottomWidth: bottom,
      topWidth: top,
      leftHeight: _positive(params.leftHeight),
      rightHeight: _positive(params.rightHeight),
      topOffset: offset,
      pocketDrop: params.pocket ? pocketWidth : 0,
      pocketTopRise: params.pocketTop ? pocketWidth : 0,
    );
  }

  final double bottomWidth;
  final double topWidth;
  final double leftHeight;
  final double rightHeight;

  /// Смещение левого верхнего угла вправо от левого нижнего угла.
  final double topOffset;

  /// Насколько карман опускается ниже нижнего тента, мм.
  final double pocketDrop;

  /// Насколько верхний карман поднимается выше верхней кромки, мм.
  final double pocketTopRise;

  static double _positive(double value) =>
      (!value.isFinite || value <= 0) ? 100 : value;

  Offset get bottomLeft => const Offset(0, 0);
  Offset get bottomRight => Offset(bottomWidth, 0);
  Offset get topLeft => Offset(topOffset, leftHeight);
  Offset get topRight => Offset(topOffset + topWidth, rightHeight);

  /// Углы против часовой стрелки (в координатах с осью Y вверх), начиная
  /// с левого нижнего. Порядок важен для [insetPolygonPerSide].
  List<Offset> get corners => [bottomLeft, bottomRight, topRight, topLeft];

  /// Длины сторон по обходу углов: низ, право, верх, лево.
  List<double> get sideLengths {
    final points = corners;
    return [
      for (var i = 0; i < points.length; i++)
        (points[(i + 1) % points.length] - points[i]).distance,
    ];
  }

  double get leftEdgeLength => sideLengths[3];

  double get rightEdgeLength => sideLengths[1];

  /// Длина окантовки по наружному контуру (без запаса на стыки).
  double get perimeter => sideLengths.reduce((a, b) => a + b);

  double get areaMm2 => polygonArea(corners).abs();

  double get areaM2 => areaMm2 / 1000000;

  double get minX => math.min(0, topOffset);
  double get maxX => math.max(bottomWidth, topOffset + topWidth);
  double get minY => -pocketDrop;
  double get maxY => math.max(leftHeight, rightHeight);

  /// Верхняя граница листа: изделие плюс верхний карман (если он есть).
  ///
  /// [maxY] и [overallHeight] остаются габаритом ИЗДЕЛИЯ — по ним считаются
  /// площадь и подписи, а карман лишь расширяет лист чертежа ([spanY]).
  double get topBound => maxY + pocketTopRise;

  double get spanX => maxX - minX;
  double get spanY => topBound - minY;

  /// Габаритная высота изделия.
  double get overallHeight => maxY;

  /// Насколько верхняя кромка выходит за нижнюю справа (мм).
  double get rightOverhang => topOffset + topWidth - bottomWidth;

  /// Насколько верхняя кромка выходит за нижнюю слева (мм).
  double get leftOverhang => -topOffset;
}

/// Слои окна: окантовка по сторонам, шов (напайка), плёнка и люверсы.
class WindowLayers {
  WindowLayers(this.params, this.geometry);

  final WindowParams params;
  final WindowGeometry geometry;

  /// Скрин — технология без окантовки (см. [WindowParams.isScreen]).
  bool get isScreen => params.isScreen;

  /// Наружная граница (внешний контур окна).
  List<Offset> get outer => geometry.corners;

  /// Ширины рулонов окантовки по сторонам в порядке обхода:
  /// низ, право, верх, лево (мм). У скрина окантовки нет — нули.
  List<double> get rolls =>
      isScreen ? const [0, 0, 0, 0] : [for (var i = 0; i < 4; i++) params.rollForEdge(i)];

  /// Готовые (сложенные пополам) ширины окантовки по сторонам.
  List<double> get finishedWidths => isScreen
      ? const [0, 0, 0, 0]
      : [for (final width in rolls) WindowParams.finishedEdgeWidth(width)];

  /// Подворот скрина по сторонам, мм (у ПВХ — нули).
  List<double> get hemWidths =>
      isScreen ? [for (var i = 0; i < 4; i++) params.hemMm] : const [0, 0, 0, 0];

  /// Внутренняя граница окантовки: видимая граница плёнки.
  ///
  /// У скрина видимый размер — это готовый контур изделия: подворот
  /// загибается на изнанку, наружу ничего не выходит.
  late final List<Offset> edgeInner =
      isScreen ? List.of(outer) : insetPolygonPerSide(outer, finishedWidths);

  /// Граница полотна в раскрое.
  ///
  /// ПВХ заходит под окантовку на [WindowParams.weldOverlapMm], поэтому его
  /// край ближе к наружному контуру, чем внутренняя граница окантовки.
  /// Скрин, наоборот, кроится БОЛЬШЕ готового размера на подворот
  /// [WindowParams.hemMm] с каждой стороны: 2000 × 2000 при подвороте 40 мм
  /// даёт заготовку 2080 × 2080 мм.
  late final List<Offset> filmEdge = isScreen
      ? outsetPolygonPerSide(outer, hemWidths)
      : insetPolygonPerSide(
          outer,
          [
            for (final width in finishedWidths)
              math.max(width - params.weldOverlapMm, 0.0),
          ],
        );

  /// Линия центров люверсов.
  ///
  /// У ПВХ это середина окантовки, у скрина — линия подворота (готовый
  /// контур): люверсы ставятся по подвороту.
  late final List<Offset> eyeletLine = isScreen
      ? List.of(outer)
      : insetPolygonPerSide(
          outer,
          [for (final width in finishedWidths) width / 2],
        );

  /// Линия подворота скрина: на [WindowParams.hemMm] внутрь от края заготовки.
  late final List<Offset> screenHemLine =
      isScreen ? insetPolygonPerSide(filmEdge, hemWidths) : const [];

  /// Линия шва [screenSeamMm] внутри подворота скрина.
  late final List<Offset> screenSeamLine = isScreen
      ? insetPolygonPerSide(screenHemLine, const [
          screenSeamMm,
          screenSeamMm,
          screenSeamMm,
          screenSeamMm,
        ])
      : const [];

  late final _EyeletResult _eyeletResult = _computeEyelets();

  /// Все люверсы по периметру; угловые не дублируются.
  List<EyeletPlacement> get eyelets => _eyeletResult.placements;

  /// Фактический шаг по каждой стороне.
  List<double> get eyeletSteps => _eyeletResult.steps;

  int get eyeletCount => eyelets.length;

  /// Габариты видимой плёнки (по внутренней границе окантовки).
  late final Rect filmVisibleBounds = boundsOf(edgeInner);

  /// Габариты плёнки в раскрое (с напайкой под окантовку).
  late final Rect filmCutBounds = boundsOf(filmEdge);

  /// Площадь полотна изделия в раскрое (с напайкой, без припуска), м².
  double get filmAreaM2 =>
      math.max(polygonArea(filmEdge).abs() - cutoutAreaMm2, 0) / 1000000;

  /// Люверсы, которые закрываются крепежом подвижных сторон:
  /// у подъёмного и комбинированного окна — низ и бока, сверху саморезы.
  /// Люверсы подвижных сторон, на которые ставится поворотный крепёж.
  ///
  /// Углы исключены: в углу всегда простой круглый люверс, иначе на стыке
  /// двух сторон (например, верх-право) вместо круглого люверса оказывается
  /// прямоугольная скоба.
  List<EyeletPlacement> get movableSideEyelets {
    // Скрин крепится только люверсами: скоб, замков и ремней у него нет.
    if (params.windowType == WindowType.fixed || isScreen) return const [];
    return eyelets
        .where((eyelet) => eyelet.side != WindowSide.top && !eyelet.isCorner)
        .toList(growable: false);
  }

  List<EyeletPlacement> get topEyelets =>
      eyelets.where((eyelet) => eyelet.side == WindowSide.top).toList();

  /// Тип люверса в конкретной точке: в углах всегда круглый (угол тянет
  /// по диагонали, овальный там не держит), у глухого окна — тоже круглые.
  EyeletType typeFor(EyeletPlacement eyelet) =>
      eyelet.isCorner ? EyeletType.round10 : params.effectiveEyeletType;

  /// Тип люверса с учётом типа окна: у глухого — только круглые.
  EyeletType get eyeletType => params.effectiveEyeletType;

  /// Подъёмные ремни: висят сверху вниз, ширина [liftStrapWidth] мм.
  List<Rect> get liftStraps {
    final count = params.liftStrapCount;
    if (count <= 0) return const [];
    final bounds = filmVisibleBounds;
    final length = math.min(liftStrapLength, bounds.height * 0.8);
    // У прямоугольников из boundsOf верхняя по экрану кромка — это bounds.bottom
    // (координата Y в модели растёт вверх).
    return [
      for (var i = 1; i <= count; i++)
        Rect.fromLTWH(
          bounds.left + bounds.width * i / (count + 1) - liftStrapWidth / 2,
          bounds.bottom - length,
          liftStrapWidth,
          length,
        ),
    ];
  }

  /// Полосы тента под все молнии.
  List<Rect> get zipperBands => [for (final line in zippers) _bandOf(line)];

  Rect _bandOf(({Offset start, Offset end, double bandWidth}) line) {
    final half = math.max(line.bandWidth, 20) / 2;
    return Rect.fromLTRB(
      line.start.dx - half,
      math.min(line.start.dy, line.end.dy),
      line.start.dx + half,
      math.max(line.start.dy, line.end.dy),
    );
  }

  /// Полоса первой молнии — для подписей и совместимости.
  Rect? get zipperBand => zipperBands.isEmpty ? null : zipperBands.first;

  /// Расход окантовки по ширинам рулонов: ширина рулона (мм) → сумма длин, мм.
  ///
  /// Спаянные с соседним окном стороны окантовки не требуют — там идёт
  /// сварка полотен. Вырезы, наоборот, добавляют расход по своему контуру
  /// (по ширине нижней стороны).
  Map<double, double> get edgeConsumption {
    final result = <double, double>{};
    // Скрин не окантовывается: расход тента нулевой.
    if (isScreen) return result;
    final lengths = geometry.sideLengths;
    for (var i = 0; i < lengths.length; i++) {
      if (isSideWelded(i)) continue;
      final roll = rolls[i];
      result[roll] = (result[roll] ?? 0) + lengths[i];
    }
    for (final cutout in cutouts) {
      final roll = rolls[0];
      result[roll] = (result[roll] ?? 0) + cutout.perimeterMm;
    }
    return result;
  }

  /// Спаяна ли сторона с индексом обхода углов (0 — низ, 1 — право,
  /// 2 — верх, 3 — лево).
  bool isSideWelded(int index) => switch (index % 4) {
        0 => params.isWelded(EdgeSide.bottom),
        1 => params.isWelded(EdgeSide.right),
        2 => params.isWelded(EdgeSide.top),
        _ => params.isWelded(EdgeSide.left),
      };

  /// Длина спаек с соседними окнами, мм.
  double get weldLengthMm {
    var total = 0.0;
    final lengths = geometry.sideLengths;
    for (var i = 0; i < lengths.length; i++) {
      if (isSideWelded(i)) total += lengths[i];
    }
    return total;
  }

  /// Готовые подписи расхода окантовки: «Тент 100 мм — 654 см».
  List<String> get edgeConsumptionLabels {
    final entries = edgeConsumption.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        '${edgeBandLabel(entry.key)} — ${formatCm(entry.value)} см',
    ];
  }

  /// Дренажные отверстия в нижней окантовке.
  List<Offset> get drainHoles {
    final count = params.drainCount.round();
    // У скрина нет нижней окантовки — пробивать дренаж не во что.
    if (!params.drainHoles || count <= 0 || isScreen) return const [];

    final bottomEyelets = eyelets
        .where((eyelet) => eyelet.side == WindowSide.bottom)
        .map((eyelet) => eyelet.center)
        .toList()
      ..sort((a, b) => a.dx.compareTo(b.dx));

    if (bottomEyelets.length >= count + 2) {
      final middles = <Offset>[];
      for (var i = 0; i < bottomEyelets.length - 1; i++) {
        middles.add((bottomEyelets[i] + bottomEyelets[i + 1]) / 2);
      }
      final result = <Offset>[];
      for (var k = 1; k <= count; k++) {
        final index = (k * middles.length / (count + 1))
            .floor()
            .clamp(0, middles.length - 1);
        result.add(middles[index]);
      }
      return result;
    }

    final line = eyeletLine;
    return [
      for (var k = 1; k <= count; k++)
        Offset.lerp(line[0], line[1], k / (count + 1))!,
    ];
  }


  /// Линии всех молний: всегда вертикально, по низу до верха видимой плёнки.
  List<({Offset start, Offset end, double bandWidth})> get zippers => [
        for (final spec in params.zippers) _zipperOf(spec),
      ];

  ({Offset start, Offset end, double bandWidth}) _zipperOf(ZipperSpec spec) {
    final bounds = filmVisibleBounds;
    final half = math.max(spec.bandWidth, 20) / 2;
    final x = spec.centered
        ? bounds.center.dx
        : (bounds.left + spec.offsetMm).clamp(
            bounds.left + half,
            bounds.right - half,
          );
    return (
      start: Offset(x, bounds.top),
      end: Offset(x, bounds.bottom),
      bandWidth: spec.bandWidth,
    );
  }

  /// Первая молния — для подписей и совместимости.
  ({Offset start, Offset end, double bandWidth})? get zipper =>
      zippers.isEmpty ? null : zippers.first;

  /// Вырезы в координатах модели: прямоугольник или окружность.
  List<CutoutGeometry> get cutouts {
    final bounds = filmVisibleBounds;
    final result = <CutoutGeometry>[];
    for (final cutout in params.cutouts) {
      final center = Offset(
        (bounds.left + cutout.centerXMm).clamp(bounds.left, bounds.right),
        (bounds.top + cutout.centerYMm).clamp(bounds.top, bounds.bottom),
      );
      if (cutout.shape == CutoutShape.circle) {
        result.add(
          CutoutGeometry.circle(
            center: center,
            radius: math.max(cutout.width, 1) / 2,
            spec: cutout,
          ),
        );
      } else {
        result.add(
          CutoutGeometry.rect(
            rect: Rect.fromCenter(
              center: center,
              width: math.max(cutout.width, 1),
              height: math.max(cutout.height, 1),
            ),
            spec: cutout,
          ),
        );
      }
    }
    return result;
  }

  /// Суммарная площадь вырезов, мм².
  double get cutoutAreaMm2 =>
      cutouts.fold(0, (sum, cutout) => sum + cutout.areaMm2);

  /// Суммарный контур вырезов, мм.
  double get cutoutPerimeterMm =>
      cutouts.fold(0, (sum, cutout) => sum + cutout.perimeterMm);

  /// Ширина спайки молнии и расстояния от неё до кромок плёнки — по каждой.
  List<({double left, double band, double right})> get zipperGapsAll => [
        for (final band in zipperBands) _gapsOf(band),
      ];

  ({double left, double band, double right}) _gapsOf(Rect band) {
    final bounds = filmVisibleBounds;
    return (
      left: band.left - bounds.left,
      band: band.width,
      right: bounds.right - band.right,
    );
  }

  /// Зазоры первой молнии — для подписей и совместимости.
  ({double left, double band, double right})? get zipperGaps =>
      zipperBands.isEmpty ? null : _gapsOf(zipperBands.first);

  /// Карман — продолжение нижнего тента вниз: полоса тента 200 мм,
  /// сложенная пополам (100 мм), по всей ширине окна.
  ///
  /// У скрина эта же полоса образуется нижним подворотом.
  Rect get pocketRect => params.pocket
      ? Rect.fromLTRB(0, -params.pocketWidth, geometry.bottomWidth, 0)
      : Rect.zero;

  /// Верхний карман — зеркало нижнего: полоса тента/подворота вверх от
  /// верхней кромки.
  Rect get pocketTopRect => params.pocketTop
      ? Rect.fromLTRB(
          geometry.topOffset,
          geometry.maxY,
          geometry.topOffset + geometry.topWidth,
          geometry.maxY + params.pocketWidth,
        )
      : Rect.zero;

  _EyeletResult _computeEyelets() {
    const sides = [
      WindowSide.bottom,
      WindowSide.right,
      WindowSide.top,
      WindowSide.left,
    ];
    final polygon = eyeletLine;
    final placements = <EyeletPlacement>[];
    final steps = <double>[];

    for (var i = 0; i < polygon.length; i++) {
      // Спаянная сторона: там сварка полотен, крепить нечего.
      if (params.removeEyeletsOnWelded && isSideWelded(i)) continue;

      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final direction = b - a;
      final length = direction.distance;
      if (length < 1) continue;
      final unit = direction / length;
      final angle = math.atan2(unit.dy, unit.dx);
      final side = sides[i % sides.length];

      final offset = params.eyeletCornerOffset.clamp(0.0, math.max(length / 2 - 1, 0));
      final usable = length - offset * 2;
      final nominal = params.eyeletStep.clamp(50.0, 1000.0);
      final intervals = math.max(1, (usable / nominal).ceil());
      final actual = usable / intervals;
      steps.add(actual);

      for (var k = 0; k <= intervals; k++) {
        var distance = offset + actual * k;

        // Карман снизу: угловые люверсы внизу не ставим, а боковые поднимаем,
        // чтобы в полость кармана заводился утяжитель. Карман сверху —
        // зеркально: углы сверху убираем, боковые опускаем.
        if (params.pocket) {
          if (side == WindowSide.bottom && (k == 0 || k == intervals)) {
            continue;
          }
          if (side == WindowSide.right && k == 0) {
            distance += pocketCornerOffset;
          }
          if (side == WindowSide.left && k == intervals) {
            distance -= pocketCornerOffset;
          }
        }
        if (params.pocketTop) {
          if (side == WindowSide.top && (k == 0 || k == intervals)) {
            continue;
          }
          if (side == WindowSide.right && k == intervals) {
            distance -= pocketCornerOffset;
          }
          if (side == WindowSide.left && k == 0) {
            distance += pocketCornerOffset;
          }
        }
        if ((params.pocket || params.pocketTop) &&
            (distance < 0 || distance > length)) {
          continue;
        }

        placements.add(EyeletPlacement(
          center: a + unit * distance,
          side: side,
          angle: angle,
          isCorner: k == 0 || k == intervals,
          positionInEdge: distance / length,
        ));
      }
    }

    // Угловые люверсы принадлежат сразу двум сторонам — оставляем по одному.
    final merged = <EyeletPlacement>[];
    for (final eyelet in placements) {
      final isDuplicate = merged.any(
        (existing) => (existing.center - eyelet.center).distance < 1,
      );
      if (!isDuplicate) merged.add(eyelet);
    }

    return _EyeletResult(merged, steps);
  }
}

class _EyeletResult {
  const _EyeletResult(this.placements, this.steps);

  final List<EyeletPlacement> placements;
  final List<double> steps;
}

/// Итоговые расчёты для штампа, раскроя и раскладки.
class WindowSpec {
  WindowSpec(this.params, this.geometry, this.layers);

  factory WindowSpec.of(WindowParams params) {
    final geometry = WindowGeometry.of(params);
    return WindowSpec(params, geometry, WindowLayers(params, geometry));
  }

  final WindowParams params;
  final WindowGeometry geometry;
  final WindowLayers layers;

  double get outerPerimeter => geometry.perimeter;

  double get outerAreaM2 => geometry.areaM2;

  /// Площадь готового изделия по наружному контуру, м².
  ///
  /// Припуск на раскрой сюда не входит: изделие остаётся размером замера.
  double get productAreaM2 => geometry.areaM2;

  /// Площадь полотна изделия в раскрое (с напайкой, без припуска), м².
  ///
  /// Это справочная площадь самого полотна; для закупки и денег берётся
  /// [filmCutAreaM2] — заготовка с припуском на раскрой.
  double get filmAreaM2 => layers.filmAreaM2;

  /// Видимый размер плёнки (по внутренней границе окантовки).
  double get filmVisibleWidth => layers.filmVisibleBounds.width;
  double get filmVisibleHeight => layers.filmVisibleBounds.height;

  /// Раскрой полотна.
  ///
  /// Для ПВХ: видимый размер плюс запайка [WindowParams.weldOverlapMm] с двух
  /// сторон — плёнка заходит под окантовку. Для скрина: готовый размер плюс
  /// подворот [WindowParams.hemMm] с каждой стороны (2000 × 2000 при
  /// подвороте 40 мм → 2080 × 2080 мм). Припуск на раскрой здесь ещё не учтён.
  double get filmCutWidth => layers.filmCutBounds.width;
  double get filmCutHeight => layers.filmCutBounds.height;

  /// Заготовка плёнки к раскрою с припуском, без усадки, мм.
  ///
  /// Припуск на раскрой добавляется ТОЛЬКО к заготовке: изделие, чертёж,
  /// окантовка и люверсы считаются по основным размерам.
  double get filmCutWidthWithAllowance =>
      filmCutWidth + params.allowanceWidthMm;
  double get filmCutHeightWithAllowance =>
      filmCutHeight + params.allowanceHeightMm;

  /// Заготовка полотна с припуском на раскрой и компенсацией усадки, мм.
  ///
  /// Усадка берётся из [WindowParams.effectiveShrinkagePercent]: у скрина её
  /// нет (0 %), у ПВХ — поле окна.
  double get filmCutWidthWithShrinkage =>
      filmCutWidthWithAllowance *
      (1 + params.effectiveShrinkagePercent / 100);
  double get filmCutHeightWithShrinkage =>
      filmCutHeightWithAllowance *
      (1 + params.effectiveShrinkagePercent / 100);

  /// Площадь заготовки плёнки к раскрою (с припуском, минус вырезы), м².
  ///
  /// Именно эта площадь идёт в расход материала, смету и ведомость, потому
  /// что плёнка закупается и кроится по заготовке.
  double get filmCutAreaM2 {
    final blank = filmCutWidthWithAllowance * filmCutHeightWithAllowance;
    return math.max(blank - layers.cutoutAreaMm2, 0) / 1000000;
  }

  /// Площадь заготовки к раскрою с учётом усадки, м².
  double get filmCutAreaWithShrinkageM2 =>
      filmCutAreaM2 * (1 + params.effectiveShrinkagePercent / 100);

  /// Расход окантовки по ширинам рулонов.
  Map<double, double> get edgeConsumption => layers.edgeConsumption;

  List<String> get edgeConsumptionLabels => layers.edgeConsumptionLabels;

  int get eyeletCount => layers.eyeletCount;

  double? get eyeletStepMin =>
      layers.eyeletSteps.isEmpty ? null : layers.eyeletSteps.reduce(math.min);
  double? get eyeletStepMax =>
      layers.eyeletSteps.isEmpty ? null : layers.eyeletSteps.reduce(math.max);

  String get eyeletStepLabel {
    final min = eyeletStepMin;
    final max = eyeletStepMax;
    if (min == null || max == null) return '—';
    if ((max - min).abs() < 1) return '${formatMm(max)} мм';
    return '${formatMm(min)}…${formatMm(max)} мм';
  }

  /// Подпись окантовки по сторонам: «низ 100, верх 100, лево 200, право 200».
  ///
  /// У скрина окантовки нет — вместо неё подворот по периметру.
  String get edgeBySideSummary {
    if (params.isScreen) {
      return 'подворот ${formatMm(params.hemMm)} мм по периметру, '
          'шов ${formatMm(screenSeamMm)} мм';
    }
    final sides = [
      ('низ', params.rollBottom),
      ('право', params.rollRight),
      ('верх', params.rollTop),
      ('лево', params.rollLeft),
    ];
    final groups = <String, List<String>>{};
    for (final (name, width) in sides) {
      groups.putIfAbsent(edgeBandLabel(width, short: true), () => []).add(name);
    }
    return groups.entries
        .map((entry) => '${entry.key}: ${entry.value.join(', ')}')
        .join(' · ');
  }

  String get edgeSummary => params.isScreen
      ? 'без окантовки: подворот ${formatMm(params.hemMm)} мм, '
          'шов ${formatMm(screenSeamMm)} мм'
      : '${params.edgeColor.label.toLowerCase()}, ${params.edgeMaterial.label}';

  String get fastenerSummary {
    // Скрин крепится только люверсами: тип крепежа игнорируется.
    if (params.isScreen) {
      return 'Только люверсы по подвороту (скрин)';
    }
    final movable = switch (params.fastenerType) {
      FastenerType.eyeletsOnly => 'только люверсы',
      FastenerType.turnBuckles => 'поворотные скобы',
      FastenerType.frenchLocks => 'французский замок',
      FastenerType.straps => 'силиконовые ремни',
    };
    return switch (params.windowType) {
      WindowType.fixed => 'Саморезы по окантовке (глухое)',
      WindowType.lifting => 'Сверху саморезы, низ и бока — $movable',
    };
  }

  /// Тип люверса, который реально ставится.
  EyeletType get eyeletType => params.effectiveEyeletType;

  /// Количество подъёмных ремней.
  int get strapCount => params.liftStrapCount;

  /// Заготовка полосы тента под молнию: (ширина, длина), мм.
  (double, double)? get zipperBandPiece {
    final band = layers.zipperBand;
    if (band == null) return null;
    final visible = layers.filmVisibleBounds;
    // Заготовка спайки: полоса по высоте плёнки.
    return (band.width, visible.height);
  }

  /// Подпись всех молний: «2 шт: 33 % и 66 % ширины».
  String get zippersSummary {
    if (params.zippers.isEmpty) return '—';
    if (params.zippers.length == 1) return zipperSummary;
    final parts = <String>[];
    for (final gaps in layers.zipperGapsAll) {
      final band = gaps.band;
      parts.add('спайка ${formatMm(band)} мм (слева ${formatMm(gaps.left)}, '
          'справа ${formatMm(gaps.right)} мм)');
    }
    return '${params.zippers.length} шт — ${parts.join('; ')}';
  }

  /// Вырезы в полотне.
  String get cutoutsSummary {
    if (params.cutouts.isEmpty) return '—';
    final parts = <String>[
      for (final cutout in layers.cutouts)
        cutout.isCircle
            ? 'Ø${formatMm(cutout.spec.width)} мм в точке '
                '${formatMm(cutout.spec.centerXMm)}×'
                '${formatMm(cutout.spec.centerYMm)} мм'
            : '${formatMm(cutout.spec.width)}×${formatMm(cutout.spec.height)} мм '
                'в точке ${formatMm(cutout.spec.centerXMm)}×'
                '${formatMm(cutout.spec.centerYMm)} мм',
    ];
    return '${params.cutouts.length} шт: ${parts.join('; ')}; '
        '${params.isScreen ? 'подворот по контуру' : 'окантовка по контуру'} '
        '${formatMm(layers.cutoutPerimeterMm)} мм';
  }

  /// Спайка с соседними окнами.
  String get weldSummary {
    if (params.weldedSides.isEmpty) return '—';
    final sides = params.weldedSides
        .map((side) => switch (side) {
              EdgeSide.left => 'левая',
              EdgeSide.right => 'правая',
              EdgeSide.bottom => 'нижняя',
              EdgeSide.top => 'верхняя',
            })
        .join(', ');
    return '$sides сторона — полотна свариваются внахлёст '
        '${formatMm(windowWeldWidth)} мм, окантовка не ставится '
        '(всего ${formatMm(layers.weldLengthMm)} мм)';
  }

  String get zipperSummary {
    if (!params.hasZipper) return '—';
    final gaps = layers.zipperGaps;
    final position = params.zipperCentered
        ? 'по центру'
        : '${formatMm(params.zipperOffsetMm)} мм от левого края';
    final around = gaps == null
        ? ''
        : ', слева ${formatMm(gaps.left)} / справа ${formatMm(gaps.right)} мм '
            'до кромок плёнки';
    return 'вертикальная, $position$around';
  }

  /// Подпись молнии с полосой тента.
  String get zipperBandSummary {
    final piece = zipperBandPiece;
    if (piece == null) return '—';
    final bandWidth = piece.$1;
    final bandLength = piece.$2;
    return '$zipperSummary; полоса тента ${formatMm(bandWidth)} × '
        '${formatMm(bandLength)} мм';
  }

  /// Примечания для штампа.
  ///
  /// У скрина своя технология: в примечаниях нет ни тента, ни напайки —
  /// вместо них подворот, шов [screenSeamMm] мм и расход по площади
  /// заготовки скрина.
  List<String> get notes {
    return [
      if (params.isScreen) ...[
        'Скрин: технология без тента и окантовки — материал подворачивается '
            'сам, крепёж только люверсы',
        'Подворот материала ${formatMm(params.hemMm)} мм на сторону, '
            'шов сварки подворота ${formatMm(screenSeamMm)} мм с каждой стороны',
        'Заготовка скрина — готовый размер плюс 2 × подворот: '
            '${formatMm(filmCutWidthWithAllowance)} × '
            '${formatMm(filmCutHeightWithAllowance)} мм '
            '(${formatMm(filmCutWidth)} × ${formatMm(filmCutHeight)} мм '
            'до припуска); усадки нет',
        'Расход скрина — площадь заготовки '
            '${formatMeters(filmCutAreaM2)} м²',
      ] else ...[
        'Окантовка складывается пополам; запайка плёнки под окантовку '
            '${formatMm(params.weldOverlapMm)} мм по всему периметру',
        'Окантовка по сторонам — ${edgeBySideSummary.lowercaseFirst}',
        'Расход окантовки: ${edgeConsumptionLabels.join(', ')}',
      ],
      'Полотно ${params.isScreen ? 'скрина' : 'ПВХ 700 мкм'} в раскрое: '
          'заготовка ${formatMm(filmCutWidthWithAllowance)} × '
          '${formatMm(filmCutHeightWithAllowance)} мм'
          '${params.isScreen ? '' : '; с усадкой '
              '${formatPercent(params.effectiveShrinkagePercent)} — '
              '${formatMm(filmCutWidthWithShrinkage)} × '
              '${formatMm(filmCutHeightWithShrinkage)} мм'}',
      if (params.hasAllowance)
        'Припуск на раскрой: ширина ${params.allowanceWidthLabel} мм, '
            'высота ${params.allowanceHeightLabel} мм — полотно кроится '
            '${formatMm(filmCutWidthWithAllowance)} × '
            '${formatMm(filmCutHeightWithAllowance)} мм',
      'Люверсы ${eyeletType.label.toLowerCase()}, шаг $eyeletStepLabel '
          '(номинал ${formatMm(params.eyeletStep)} мм), от угла '
          '${formatMm(params.eyeletCornerOffset)} мм, всего $eyeletCount шт',
      'Крепёж: ${fastenerSummary.toLowerCase()}',
      if (params.isLifting && !params.isScreen)
        'Подъёмные ремни: $strapCount шт, '
            '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} мм '
            '(2 шт до 2 м ширины, далее +1 на метр)',
      if (params.zippers.length == 1) 'Молния: $zipperBandSummary',
      if (params.zippers.length > 1) 'Молнии: $zippersSummary',
      if (params.hasZipper && layers.zipperGaps != null && params.zippers.length == 1)
        'Спайка молнии ${formatMm(params.zipperBandWidth)} мм; от спайки до '
            'кромок плёнки: слева ${formatMm(layers.zipperGaps!.left)} мм, '
            'справа ${formatMm(layers.zipperGaps!.right)} мм',
      if (params.cutouts.isNotEmpty) 'Вырезы: $cutoutsSummary',
      if (params.weldedSides.isNotEmpty) 'Спайка окон: $weldSummary',
      if (params.drainHoles && !params.isScreen)
        'Дренаж: ${params.drainCount.round()} отв. Ø6 мм в нижней окантовке',
      if (params.pocket || params.pocketTop)
        _pocketNote(),
      'Полотно: ${params.material.thickness}; доступные рулоны '
          '${params.material.rollWidthsLabel} см',
      if (params.isScreen)
        'Скрин сваривается горячим воздухом 400–500 °C, морозостойкость '
            'до −30 °C'
      else
        '${params.edgeMaterial.joining}, морозостойкость до −30 °C',
    ];
  }

  /// Примечание о карманах: снизу, сверху или оба; у скрина — подворотом.
  String _pocketNote() {
    final where = switch ((params.pocket, params.pocketTop)) {
      (true, true) => 'снизу и сверху',
      (true, false) => 'снизу',
      (false, true) => 'сверху',
      (false, false) => '',
    };
    if (params.isScreen) {
      return 'Карман $where: подворот ${formatMm(params.pocketWidth)} мм, '
          'угловой люверс со стороны кармана смещён на '
          '${formatMm(pocketCornerOffset)} мм';
    }
    return 'Карман $where: тент ${formatMm(pocketRollWidth)} мм сложен '
        'пополам → ${formatMm(params.pocketWidth)} мм; угловой люверс со '
        'стороны кармана смещён на ${formatMm(pocketCornerOffset)} мм';
  }
}

extension on String {
  String get lowercaseFirst =>
      isEmpty ? this : '${this[0].toLowerCase()}${substring(1)}';
}

/// Замечание к введённым параметрам.
class ParamIssue {
  const ParamIssue(this.field, this.message, {this.isError = true});

  final ParamField field;
  final String message;
  final bool isError;
}

/// Проверка параметров окна: физически невозможные значения — ошибки,
/// сомнительные сочетания — предупреждения.
List<ParamIssue> validateParams(WindowParams params) {
  final issues = <ParamIssue>[];

  void checkPositive(ParamField field, double value, {double max = 20000}) {
    if (!value.isFinite || value <= 0) {
      issues.add(ParamIssue(field, '${field.label}: укажите значение больше нуля'));
    } else if (value > max) {
      issues.add(ParamIssue(
        field,
        '${field.label}: ${formatMm(value)} — больше ${formatMm(max)}, проверьте замер',
        isError: false,
      ));
    }
  }

  void checkRange(
    ParamField field,
    double value,
    double min,
    double max,
    String hint,
  ) {
    if (!value.isFinite) return;
    if (value < min || value > max) {
      issues.add(ParamIssue(
        field,
        '${field.label}: обычно $hint, у вас ${formatMm(value)}',
        isError: false,
      ));
    }
  }

  checkPositive(ParamField.bottomWidth, params.bottomWidth);
  checkPositive(ParamField.topWidth, params.topWidth);
  checkPositive(ParamField.leftHeight, params.leftHeight);
  checkPositive(ParamField.rightHeight, params.rightHeight);

  checkRange(ParamField.eyeletStep, params.eyeletStep, 250, 400, '250–400 мм');
  checkRange(
    ParamField.eyeletCornerOffset,
    params.eyeletCornerOffset,
    0,
    70,
    '0 мм (в углу) или до 70 мм',
  );
  // У скрина усадки нет — поле не проверяем.
  if (!params.isScreen) {
    checkRange(
      ParamField.shrinkagePercent,
      params.shrinkagePercent,
      1,
      2,
      '1–2 %',
    );
  }

  // Припуск на раскрой: 0…500 мм. Отрицательный припуск — не ошибка ввода,
  // но изделие получится меньше замера, поэтому предупреждаем.
  void checkAllowance(ParamField field, double value, String axis) {
    if (!value.isFinite) {
      issues.add(ParamIssue(
        field,
        'Припуск на раскрой, $axis: укажите число в миллиметрах',
        isError: false,
      ));
      return;
    }
    if (value < 0) {
      issues.add(ParamIssue(
        field,
        'Припуск на раскрой, $axis: ${formatMm(value)} мм — отрицательный, '
        'изделие будет меньше замера',
        isError: false,
      ));
      return;
    }
    if (value > maxAllowanceMm) {
      issues.add(ParamIssue(
        field,
        'Припуск на раскрой, $axis: ${formatMm(value)} мм — больше '
        '${formatMm(maxAllowanceMm)} мм, проверьте значение',
        isError: false,
      ));
    }
  }

  checkAllowance(ParamField.allowanceWidth, params.allowanceWidthMm, 'ширина');
  checkAllowance(ParamField.allowanceHeight, params.allowanceHeightMm, 'высота');

  if (params.topWidth.isFinite &&
      params.bottomWidth.isFinite &&
      params.topWidth > params.bottomWidth) {
    issues.add(const ParamIssue(
      ParamField.topWidth,
      'Верх шире низа — проверьте замеры',
      isError: false,
    ));
  }

  final geometry = WindowGeometry.of(params);
  if (params.topAlign == TopAlign.custom) {
    if (geometry.rightOverhang > 1) {
      issues.add(ParamIssue(
        ParamField.topOffset,
        'Верх выступает вправо на ${formatMm(geometry.rightOverhang)} мм',
        isError: false,
      ));
    }
    if (geometry.leftOverhang > 1) {
      issues.add(ParamIssue(
        ParamField.topOffset,
        'Верх выступает влево на ${formatMm(geometry.leftOverhang)} мм',
        isError: false,
      ));
    }
  }

  final layers = WindowLayers(params, geometry);

  // Запайка плёнки под окантовку: 5…60 мм. От неё напрямую зависит размер
  // заготовки, поэтому значение вводится руками и проверяется.
  if (!params.weldOverlapMm.isFinite ||
      params.weldOverlapMm < minWeldOverlapMm ||
      params.weldOverlapMm > maxWeldOverlapMm) {
    issues.add(ParamIssue(
      ParamField.weldOverlap,
      'Запайка под окантовку: ${formatMm(params.weldOverlapMm)} мм — вне '
      'диапазона ${formatMm(minWeldOverlapMm)}–${formatMm(maxWeldOverlapMm)} мм',
      isError: !params.weldOverlapMm.isFinite,
    ));
  } else if (!params.isScreen) {
    checkRange(
      ParamField.weldOverlap,
      params.weldOverlapMm,
      10,
      40,
      '10–40 мм',
    );
  }

  // Подворот скрина: 10…150 мм на сторону. Готовый размер плюс два подворота
  // даёт заготовку (2000 × 2000 при подвороте 40 мм → 2080 × 2080 мм).
  if (params.isScreen && params.hemMm.isFinite) {
    checkRange(ParamField.hemWidth, params.hemMm, 30, 80, '40–60 мм');
  }

  if (params.isScreen) {
    // У скрина нет окантовки: проверять её ширины и запайку нечего.
    if (params.drainHoles) {
      issues.add(const ParamIssue(
        ParamField.drainCount,
        'Дренаж делается в нижней окантовке — у скрина её нет',
        isError: false,
      ));
    }
  } else {
    final maxFinished =
        layers.finishedWidths.reduce((a, b) => a > b ? a : b);
    final minSpan = math.min(geometry.spanX, geometry.maxY);
    if (maxFinished * 2 + params.weldOverlapMm * 2 >= minSpan) {
      issues.add(const ParamIssue(
        ParamField.bottomWidth,
        'Окантовка со швом не оставляет места полотну — выберите рулон уже',
      ));
    }

    // Окантовка: ширина рулона вводится вручную на каждую сторону. Разумный
    // диапазон — 40…400 мм; своя ширина (не из пресетов) это нормально и
    // отдельного замечания не требует. А вот если готовой полосы (рулон / 2)
    // не хватает на запайку с двух сторон (2 × weldOverlapMm), ленте не за
    // что зацепиться — об этом предупреждаем.
    for (final side in EdgeSide.values) {
      final raw = params.rollForSide(side);
      final name = side.label.toLowerCase();
      if (!raw.isFinite || raw < minEdgeRollWidth || raw > maxEdgeRollWidth) {
        issues.add(ParamIssue(
          ParamField.bottomWidth,
          'Окантовка, $name: ${formatMm(raw)} мм — вне диапазона '
          '${formatMm(minEdgeRollWidth)}–${formatMm(maxEdgeRollWidth)} мм',
          isError: false,
        ));
        continue;
      }
      final finished = WindowParams.finishedEdgeWidth(raw);
      // Полоса складывается пополам: на запайку нужна такая же полоса плюс
      // запас на кромку, поэтому минимум — запайка + 15 мм готовой.
      final minFinishedForWeld = params.weldOverlapMm + 15;
      if (finished < minFinishedForWeld) {
        issues.add(ParamIssue(
          ParamField.bottomWidth,
          'Окантовка, $name: готовая полоса ${formatMm(finished)} мм — уже '
          '${formatMm(minFinishedForWeld)} мм, запайке '
          '${formatMm(params.weldOverlapMm)} мм не хватает ленты',
          isError: false,
        ));
      }
    }
  }

  if (params.drainHoles && !params.isScreen) {
    checkRange(ParamField.drainCount, params.drainCount, 1, 8, '1–5 отверстий');
  }
  if (params.pocket || params.pocketTop) {
    checkRange(ParamField.pocketWidth, params.pocketWidth, 80, 150, '100 мм');
  }
  for (var i = 0; i < params.zippers.length; i++) {
    final spec = params.zippers[i];
    if (spec.bandWidth < 40 || spec.bandWidth > 120) {
      issues.add(const ParamIssue(
        ParamField.bottomWidth,
        'Ширина спайки молнии — 40–120 мм (обычно 50 мм)',
        isError: false,
      ));
    }
    if (!spec.centered) {
      final bounds = layers.filmVisibleBounds;
      final half = math.max(spec.bandWidth, 20) / 2;
      final limit = bounds.width;
      if (spec.offsetMm < half || spec.offsetMm > limit - half) {
        issues.add(ParamIssue(
          ParamField.bottomWidth,
          'Молния №${i + 1} выходит за пределы плёнки '
              '(доступно ${formatMm(limit)} мм)',
        ));
      }
    }
  }

  // Вырезы: должны целиком лежать в полотне и не пересекаться.
  final filmBounds = layers.filmVisibleBounds;
  for (var i = 0; i < layers.cutouts.length; i++) {
    final cutout = layers.cutouts[i];
    final bounds = cutout.bounds;
    if (bounds.left < filmBounds.left - 0.5 ||
        bounds.right > filmBounds.right + 0.5 ||
        bounds.top < filmBounds.top - 0.5 ||
        bounds.bottom > filmBounds.bottom + 0.5) {
      issues.add(ParamIssue(
        ParamField.bottomWidth,
        'Вырез №${i + 1} выходит за пределы полотна',
      ));
    }
    for (var j = i + 1; j < layers.cutouts.length; j++) {
      if (bounds.overlaps(layers.cutouts[j].bounds)) {
        issues.add(ParamIssue(
          ParamField.bottomWidth,
          'Вырезы №${i + 1} и №${j + 1} пересекаются',
          isError: false,
        ));
      }
    }
    for (final band in layers.zipperBands) {
      if (bounds.overlaps(band)) {
        issues.add(ParamIssue(
          ParamField.bottomWidth,
          'Вырез №${i + 1} попадает на полосу молнии',
          isError: false,
        ));
      }
    }
  }

  final heightDiff = (params.leftHeight - params.rightHeight).abs();
  if (heightDiff.isFinite && heightDiff > 0 && heightDiff <= 500) {
    issues.add(const ParamIssue(
      ParamField.rightHeight,
      'Высоты слева и справа отличаются меньше чем на 500 мм — это нормально, но проверьте, не опечатка ли',
      isError: false,
    ));
  }

  return issues;
}

/// Есть ли среди замечаний настоящие ошибки.
bool hasBlockingIssues(List<ParamIssue> issues) =>
    issues.any((issue) => issue.isError);

/// Знаковая площадь многоугольника (положительная при обходе против часовой).
double polygonArea(List<Offset> polygon) {
  var sum = 0.0;
  for (var i = 0; i < polygon.length; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % polygon.length];
    sum += a.dx * b.dy - b.dx * a.dy;
  }
  return sum / 2;
}

/// Габаритный прямоугольник многоугольника.
Rect boundsOf(List<Offset> polygon) {
  var minX = double.infinity;
  var minY = double.infinity;
  var maxX = -double.infinity;
  var maxY = -double.infinity;
  for (final point in polygon) {
    minX = math.min(minX, point.dx);
    minY = math.min(minY, point.dy);
    maxX = math.max(maxX, point.dx);
    maxY = math.max(maxY, point.dy);
  }
  if (minX == double.infinity) return Rect.zero;
  return Rect.fromLTRB(minX, minY, maxX, maxY);
}

/// Смещает выпуклый многоугольник внутрь: своя величина для каждой стороны.
///
/// [distances] задаются в порядке обхода углов (для окна: низ, право, верх,
/// лево). Каждая сторона сдвигается по своей нормали, соседние сдвинутые
/// стороны пересекаются — так получается внутренняя граница окантовки,
/// граница плёнки и линия центров люверсов.
List<Offset> insetPolygonPerSide(List<Offset> polygon, List<double> distances) {
  if (polygon.length < 3) return List.of(polygon);
  final bounds = boundsOf(polygon);
  final limit = 0.45 * math.min(bounds.width, bounds.height);
  final count = polygon.length;
  final shifted = <(Offset, Offset)>[];

  for (var i = 0; i < count; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % count];
    final direction = b - a;
    final length = direction.distance;
    if (length < 1e-9) return List.of(polygon);
    final unit = direction / length;
    final inward = Offset(-unit.dy, unit.dx);
    final raw = i < distances.length ? distances[i] : distances.last;
    final distance = (!raw.isFinite || raw <= 0) ? 0.0 : math.min(raw, limit);
    shifted.add((a + inward * distance, b + inward * distance));
  }

  final result = <Offset>[];
  for (var i = 0; i < count; i++) {
    final previous = shifted[(i - 1 + count) % count];
    final current = shifted[i];
    final point = _lineIntersection(
      previous.$1,
      previous.$2,
      current.$1,
      current.$2,
    );
    result.add(point ?? current.$1);
  }

  // Защита от вырождения: если контур схлопнулся или вывернулся — уменьшаем
  // отступ вдвое и пробуем снова.
  final area = polygonArea(result);
  if (!area.isFinite || area <= 0 || area >= polygonArea(polygon).abs()) {
    final maxDistance = distances.isEmpty
        ? 0.0
        : distances.reduce((a, b) => a > b ? a : b);
    if (!maxDistance.isFinite || maxDistance <= 0.05) return List.of(polygon);
    return insetPolygonPerSide(
      polygon,
      [for (final distance in distances) distance / 2],
    );
  }
  return result;
}

/// Смещает выпуклый многоугольник наружу: своя величина для каждой стороны.
///
/// Нужно скрину: заготовка кроится больше готового размера на подворот, и
/// её контур — это наружный контур изделия, расширенный на [distances].
List<Offset> outsetPolygonPerSide(
  List<Offset> polygon,
  List<double> distances,
) {
  if (polygon.length < 3) return List.of(polygon);
  final count = polygon.length;
  final shifted = <(Offset, Offset)>[];

  for (var i = 0; i < count; i++) {
    final a = polygon[i];
    final b = polygon[(i + 1) % count];
    final direction = b - a;
    final length = direction.distance;
    if (length < 1e-9) return List.of(polygon);
    final unit = direction / length;
    // При обходе против часовой стрелки внутренняя нормаль — (−dy, dx),
    // значит наружная — (dy, −dx).
    final outward = Offset(unit.dy, -unit.dx);
    final raw = i < distances.length ? distances[i] : distances.last;
    final distance = (!raw.isFinite || raw <= 0) ? 0.0 : raw;
    shifted.add((a + outward * distance, b + outward * distance));
  }

  final result = <Offset>[];
  for (var i = 0; i < count; i++) {
    final previous = shifted[(i - 1 + count) % count];
    final current = shifted[i];
    final point = _lineIntersection(
      previous.$1,
      previous.$2,
      current.$1,
      current.$2,
    );
    result.add(point ?? current.$1);
  }
  return result;
}

Offset? _lineIntersection(Offset p1, Offset p2, Offset p3, Offset p4) {
  final d1 = p2 - p1;
  final d2 = p4 - p3;
  final denominator = d1.dx * d2.dy - d1.dy * d2.dx;
  if (denominator.abs() < 1e-9) return null;
  final t = ((p3.dx - p1.dx) * d2.dy - (p3.dy - p1.dy) * d2.dx) / denominator;
  return p1 + d1 * t;
}
