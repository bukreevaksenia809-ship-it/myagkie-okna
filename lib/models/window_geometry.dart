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
  }) => CutoutGeometry._(spec: spec, center: center, radius: radius);

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
    this.forcedType,
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

  /// Жёстко заданный тип (круглый, добавленный из меню на чертеже).
  final EyeletType? forcedType;

  /// Точка добавлена вручную на чертеже.
  bool get isManual => forcedType != null;
}

/// Крепёж, добавленный вручную на чертеже (замок или скоба).
class ManualFastener {
  const ManualFastener({
    required this.center,
    required this.side,
    required this.angle,
    required this.type,
  });

  final Offset center;
  final WindowSide side;
  final double angle;
  final FastenerType type;
}

/// Нижняя левая вершина прямоугольника в координатах модели (ось Y вверх):
/// у [Rect] поле `top` — это МИНИМАЛЬНЫЙ Y, то есть нижняя кромка.
Offset _rectBottomLeft(Rect rect) => Offset(rect.left, rect.top);

/// Нижняя правая вершина прямоугольника в координатах модели.
Offset _rectBottomRight(Rect rect) => Offset(rect.right, rect.top);

/// Верхняя правая вершина прямоугольника в координатах модели.
Offset _rectTopRight(Rect rect) => Offset(rect.right, rect.bottom);

/// Верхняя левая вершина прямоугольника в координатах модели.
Offset _rectTopLeft(Rect rect) => Offset(rect.left, rect.bottom);

/// Эпсилон геометрии объединения прямоугольников, мм.
const double _unionEps = 1e-6;

/// Внешний контур объединения осевых прямоугольников.
///
/// Используется для Т-окна: контур — объединение основного полотна и всех
/// включённых пристроек. Внутренние (общие) стороны прямоугольников в контур
/// не попадают: по ним идёт шов, а не внешняя кромка. Порядок вершин — против
/// часовой стрелки; вершины стоят на всех границах прямоугольников, поэтому
/// контур повторяет фактическую форму (без скруглений и «склейки» углов).
///
/// [start] — желаемая первая вершина (обычно левый нижний угол основного
/// полотна). Если из неё нет выходящего ребра, обход начнётся с крайней левой
/// нижней вершины контура.
List<Offset> unionOutlineOfRects(List<Rect> rects, {Offset? start}) {
  final parts = [
    for (final rect in rects)
      if (rect.width > _unionEps && rect.height > _unionEps) rect,
  ];
  if (parts.isEmpty) return const [];

  final xs = <double>{
    for (final rect in parts) ...[rect.left, rect.right],
  }.toList()..sort();
  final ys = <double>{
    for (final rect in parts) ...[rect.top, rect.bottom],
  }.toList()..sort();
  bool covered(double x, double y) => parts.any(
    (rect) =>
        x > rect.left + _unionEps &&
        x < rect.right - _unionEps &&
        y > rect.top + _unionEps &&
        y < rect.bottom - _unionEps,
  );

  final nx = xs.length - 1;
  final ny = ys.length - 1;
  if (nx < 1 || ny < 1) return const [];
  final inside = List.generate(nx, (_) => List<bool>.filled(ny, false));
  for (var i = 0; i < nx; i++) {
    for (var j = 0; j < ny; j++) {
      inside[i][j] = covered((xs[i] + xs[i + 1]) / 2, (ys[j] + ys[j + 1]) / 2);
    }
  }

  // Направленные рёбра контура: внутренность всегда слева от направления.
  final edges = <Offset, List<Offset>>{};
  void add(Offset a, Offset b) => edges.putIfAbsent(a, () => []).add(b);
  for (var i = 0; i < nx; i++) {
    for (var j = 0; j < ny; j++) {
      if (!inside[i][j]) continue;
      if (j == 0 || !inside[i][j - 1]) {
        add(Offset(xs[i], ys[j]), Offset(xs[i + 1], ys[j]));
      }
      if (j == ny - 1 || !inside[i][j + 1]) {
        add(Offset(xs[i + 1], ys[j + 1]), Offset(xs[i], ys[j + 1]));
      }
      if (i == 0 || !inside[i - 1][j]) {
        add(Offset(xs[i], ys[j + 1]), Offset(xs[i], ys[j]));
      }
      if (i == nx - 1 || !inside[i + 1][j]) {
        add(Offset(xs[i + 1], ys[j]), Offset(xs[i + 1], ys[j + 1]));
      }
    }
  }
  if (edges.isEmpty) return const [];

  Offset nextOf(Offset current, Offset? previous) {
    final options = edges[current];
    if (options == null || options.isEmpty) return current;
    if (options.length == 1) return options.first;
    Offset? straight;
    Offset? left;
    Offset? right;
    Offset? down;
    if (previous == null) {
      for (final option in options) {
        final delta = option - current;
        if (delta.dx > _unionEps && delta.dy.abs() <= _unionEps) right = option;
        if (delta.dy < -_unionEps && delta.dx.abs() <= _unionEps) down = option;
      }
      return right ?? down ?? options.first;
    }
    final unitX = (current - previous).dx.sign;
    final unitY = (current - previous).dy.sign;
    for (final option in options) {
      final delta = option - current;
      final x = delta.dx.sign;
      final y = delta.dy.sign;
      if (x == unitX && y == unitY) straight = option;
      // Поворот влево (против часовой) — внутренность остаётся слева.
      if (x == -unitY && y == unitX) left = option;
      if (x == unitY && y == -unitX) right = option;
    }
    return straight ?? left ?? right ?? options.first;
  }

  Offset startPoint;
  if (start != null && edges.containsKey(start) && edges[start]!.isNotEmpty) {
    startPoint = start;
  } else {
    final candidates = edges.keys.toList()
      ..sort((a, b) {
        final byY = a.dy.compareTo(b.dy);
        return byY != 0 ? byY : a.dx.compareTo(b.dx);
      });
    startPoint = candidates.first;
  }

  final outline = <Offset>[];
  var current = startPoint;
  Offset? previous;
  var guard = 0;
  do {
    outline.add(current);
    final next = nextOf(current, previous);
    previous = current;
    current = next;
    if (++guard > 100000) break;
  } while ((current - startPoint).distance > _unionEps);
  if (outline.length > 1 &&
      (outline.first - outline.last).distance <= _unionEps) {
    outline.removeLast();
  }
  return _dropCollinear(outline);
}

/// Убирает из ортогонального контура вершины, лежащие на прямой.
///
/// Сетка объединения даёт лишние вершины на продолжениях сторон соседних
/// прямоугольников; в контуре они не нужны. Совпадающие подряд вершины и
/// «нулевые» углы тоже уходят.
List<Offset> _dropCollinear(List<Offset> polygon) {
  if (polygon.length < 3) return polygon;
  final points = List<Offset>.of(polygon);
  var changed = true;
  while (changed && points.length > 3) {
    changed = false;
    for (var i = 0; i < points.length; i++) {
      final previous = points[(i - 1 + points.length) % points.length];
      final current = points[i];
      final next = points[(i + 1) % points.length];
      final sameX =
          (previous.dx - current.dx).abs() <= _unionEps &&
          (next.dx - current.dx).abs() <= _unionEps;
      final sameY =
          (previous.dy - current.dy).abs() <= _unionEps &&
          (next.dy - current.dy).abs() <= _unionEps;
      if (sameX || sameY) {
        points.removeAt(i);
        changed = true;
        break;
      }
    }
  }
  return points;
}

/// Пристройка в построенной геометрии: прямоугольник, сторона и общая сторона.
class TShapeAnnexLayout {
  const TShapeAnnexLayout({
    required this.number,
    required this.side,
    required this.rect,
    required this.offset,
    required this.welded,
    required this.clamped,
  });

  /// Номер пристройки: 1 или 2.
  final int number;

  final TShapeSide side;

  /// Прямоугольник пристройки в координатах модели.
  final Rect rect;

  /// Фактическое смещение вдоль общей стороны (после подрезки), мм.
  final double offset;

  /// Спайка по общей стороне.
  final bool welded;

  /// Пристройка не помещалась в общую сторону и была подрезана — об этом
  /// предупреждает проверка параметров.
  final bool clamped;

  /// Подпись блока: «Пристройка 1».
  String get label => 'Пристройка $number';

  /// Начало общей стороны (шва).
  Offset get sharedStart => switch (side) {
    TShapeSide.right => Offset(rect.left, rect.top),
    TShapeSide.left => Offset(rect.right, rect.top),
    TShapeSide.top => Offset(rect.left, rect.top),
    TShapeSide.bottom => Offset(rect.left, rect.bottom),
  };

  /// Конец общей стороны (шва).
  Offset get sharedEnd => switch (side) {
    TShapeSide.right => Offset(rect.left, rect.bottom),
    TShapeSide.left => Offset(rect.right, rect.bottom),
    TShapeSide.top => Offset(rect.right, rect.top),
    TShapeSide.bottom => Offset(rect.right, rect.bottom),
  };

  double get sharedLength => (sharedEnd - sharedStart).distance;

  /// Контур пристройки против часовой стрелки.
  List<Offset> get polygon => [
    _rectBottomLeft(rect),
    _rectBottomRight(rect),
    _rectTopRight(rect),
    _rectTopLeft(rect),
  ];
}

/// Геометрия Т-образного окна: основное полотно плюс до двух пристроек.
///
/// Основное полотно для Т-окна считается прямоугольником
/// `bottomWidth × leftHeight`; пристройка — прямоугольник, приваренный к
/// стороне [TShapeAnnexLayout.side]. Смещение вдоль общей стороны задаётся
/// параметрами и зажимается так, чтобы пристройка не выходила за общую
/// сторону: об этом предупреждает проверка параметров, а не молчаливая ошибка.
///
/// [outline] — фактический внешний контур (объединение основного полотна и
/// всех включённых пристроек), обход против часовой стрелки. [annexes] —
/// построенные пристройки; [groups] — контуры для расчёта окантовки и
/// люверсов: сваренные пристройки объединены с основным полотном, отдельные
/// (без спайки) идут самостоятельными контурами.
class TShapeLayout {
  const TShapeLayout._({
    required this.mainRect,
    required this.annexes,
    required this.outline,
    required this.groups,
    required this.ignoredSecondAnnex,
    required this.ignoredOverlap,
  });

  factory TShapeLayout.build(WindowParams params) {
    // Для Т-окна основное полотно — прямоугольник: ширины верха и низа и
    // высоты сторон должны совпадать. Панель при переводе в Т выравнивает их,
    // а проверка параметров предупреждает, если пользователь поменял размер.
    final width = WindowGeometry._positive(params.bottomWidth);
    final height = WindowGeometry._positive(params.leftHeight);
    final main = Rect.fromLTWH(0, 0, width, height);

    final annexes = <TShapeAnnexLayout>[];
    var ignoredSecondAnnex = false;
    var ignoredOverlap = false;
    final specs = params.tAnnexes;
    for (final spec in specs) {
      // Две пристройки на одной стороне запрещены: вторая не строится, чтобы
      // расчёт не ломался и чертёж не показывал наложение. Панель и проверка
      // параметров объясняют причину.
      if (spec.number == 2 && params.tAnnexSideConflict) {
        ignoredSecondAnnex = true;
        continue;
      }
      var annexWidth = WindowGeometry._positive(spec.width);
      var annexHeight = WindowGeometry._positive(spec.height);
      var offset = spec.offset.isFinite ? spec.offset : 0.0;
      var clamped = false;

      // Пристройка вдоль общей стороны не может быть длиннее самой стороны.
      if (spec.side == TShapeSide.left || spec.side == TShapeSide.right) {
        if (annexHeight > height) {
          annexHeight = height;
          clamped = true;
        }
        final maxOffset = math.max(height - annexHeight, 0.0);
        if (offset < 0) {
          offset = 0;
          clamped = true;
        } else if (offset > maxOffset) {
          offset = maxOffset;
          clamped = true;
        }
      } else {
        if (annexWidth > width) {
          annexWidth = width;
          clamped = true;
        }
        final maxOffset = math.max(width - annexWidth, 0.0);
        if (offset < 0) {
          offset = 0;
          clamped = true;
        } else if (offset > maxOffset) {
          offset = maxOffset;
          clamped = true;
        }
      }

      final rect = switch (spec.side) {
        TShapeSide.right => Rect.fromLTWH(
          width,
          offset,
          annexWidth,
          annexHeight,
        ),
        TShapeSide.left => Rect.fromLTWH(
          -annexWidth,
          offset,
          annexWidth,
          annexHeight,
        ),
        TShapeSide.top => Rect.fromLTWH(
          offset,
          height,
          annexWidth,
          annexHeight,
        ),
        TShapeSide.bottom => Rect.fromLTWH(
          offset,
          -annexHeight,
          annexWidth,
          annexHeight,
        ),
      };
      // Пересечение пристроек запрещено: наложение двух прямоугольников
      // дало бы несуществующую деталь. Вторая пристройка в этом случае не
      // строится, расчёт не ломается, а панель показывает предупреждение.
      final overlaps = annexes.any(
        (annex) =>
            rect.intersect(annex.rect).width > 0.5 &&
            rect.intersect(annex.rect).height > 0.5,
      );
      if (overlaps) {
        ignoredOverlap = true;
        continue;
      }
      annexes.add(
        TShapeAnnexLayout(
          number: spec.number,
          side: spec.side,
          rect: rect,
          offset: offset,
          welded: spec.welded,
          clamped: clamped,
        ),
      );
    }

    // Контур — объединение основного полотна и всех пристроек. Обход
    // начинается с левого нижнего угла основного полотна, чтобы подписи и
    // прежние чертежи не «прыгали».
    final outline = annexes.isEmpty
        ? <Offset>[
            _rectBottomLeft(main),
            _rectBottomRight(main),
            _rectTopRight(main),
            _rectTopLeft(main),
          ]
        : unionOutlineOfRects([
            main,
            for (final annex in annexes) annex.rect,
          ], start: _rectBottomLeft(main));

    // Группы контуров: сваренные пристройки — часть общего контура, отдельные
    // (без спайки) — самостоятельные окна со своим периметром.
    final groups = <List<Offset>>[];
    final welded = annexes.where((annex) => annex.welded).toList();
    if (welded.isEmpty) {
      groups.add([
        _rectBottomLeft(main),
        _rectBottomRight(main),
        _rectTopRight(main),
        _rectTopLeft(main),
      ]);
    } else {
      final merged = unionOutlineOfRects([
        main,
        for (final annex in welded) annex.rect,
      ], start: _rectBottomLeft(main));
      groups.add(merged);
    }
    for (final annex in annexes.where((annex) => !annex.welded)) {
      groups.add(annex.polygon);
    }

    return TShapeLayout._(
      mainRect: main,
      annexes: annexes,
      outline: outline,
      groups: groups,
      ignoredSecondAnnex: ignoredSecondAnnex || ignoredOverlap,
      ignoredOverlap: ignoredOverlap,
    );
  }

  /// Основное полотно (прямоугольник).
  final Rect mainRect;

  /// Построенные пристройки в порядке номеров.
  final List<TShapeAnnexLayout> annexes;

  /// Фактический внешний контур окна.
  final List<Offset> outline;

  /// Контуры для окантовки, люверсов и подворота: сваренные части объединены,
  /// отдельные окна — раздельно.
  final List<List<Offset>> groups;

  /// Вторая пристройка не построена (та же сторона или пересечение).
  final bool ignoredSecondAnnex;

  /// Вторая пристройка не построена из-за пересечения с первой.
  final bool ignoredOverlap;

  /// Первая пристройка (для обратной совместимости и подписей).
  TShapeAnnexLayout? get firstAnnex => annexes.isEmpty ? null : annexes.first;

  bool get hasAnnexes => annexes.isNotEmpty;

  /// Есть ли хоть одна спайка с основным полотном.
  bool get anyWelded => annexes.any((annex) => annex.welded);

  /// Все пристройки спаяны с основным полотном (или пристроек нет).
  bool get allWelded => annexes.every((annex) => annex.welded);

  /// Сваренные пристройки.
  List<TShapeAnnexLayout> get weldedAnnexes =>
      annexes.where((annex) => annex.welded).toList(growable: false);

  /// Отдельные (несваренные) пристройки.
  List<TShapeAnnexLayout> get separateAnnexes =>
      annexes.where((annex) => !annex.welded).toList(growable: false);

  /// Суммарная длина швов по всем пристройкам, мм.
  double get allSeamsLength =>
      annexes.fold(0.0, (sum, annex) => sum + annex.sharedLength);

  /// Суммарная длина ШВОВ спайки (только сваренные пристройки), мм.
  double get weldedSeamLength =>
      weldedAnnexes.fold(0.0, (sum, annex) => sum + annex.sharedLength);

  // --- Прежние имена для одной пристройки -------------------------------

  /// Сторона первой пристройки (null — пристроек нет).
  TShapeSide? get side => firstAnnex?.side;

  /// Прямоугольник первой пристройки (null — пристроек нет).
  Rect? get annexRect => firstAnnex?.rect;

  /// Начало шва первой пристройки.
  Offset get sharedStart => firstAnnex?.sharedStart ?? Offset.zero;

  /// Конец шва первой пристройки.
  Offset get sharedEnd => firstAnnex?.sharedEnd ?? Offset.zero;

  /// Суммарная длина общих сторон всех пристроек, мм.
  double get sharedLength => allSeamsLength;

  /// Спайка по общей стороне у первой пристройки (прежнее поле).
  bool get welded => firstAnnex?.welded ?? false;

  /// Контур основного полотна (для расчёта отдельных окон).
  List<Offset> get mainPolygon => [
    _rectBottomLeft(mainRect),
    _rectBottomRight(mainRect),
    _rectTopRight(mainRect),
    _rectTopLeft(mainRect),
  ];

  /// Контуры пристроек.
  List<List<Offset>> get annexPolygons => [
    for (final annex in annexes) annex.polygon,
  ];

  /// Контур первой пристройки (прежнее поле).
  List<Offset> get annexPolygon =>
      annexes.isEmpty ? const [] : annexes.first.polygon;
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
    this.levelEdge = LevelEdge.bottom,
    this.tLayout,
    this.compositeSpec,
    this.shapePolygon,
    double? bottomLeftY,
    double? bottomRightY,
    double? topLeftY,
    double? topRightY,
  }) : bottomLeftY = bottomLeftY ?? 0,
       bottomRightY = bottomRightY ?? 0,
       topLeftY = topLeftY ?? leftHeight,
       topRightY = topRightY ?? rightHeight;

  factory WindowGeometry.of(WindowParams params) {
    if (params.isSpecialShape) {
      final width = _positive(params.bottomWidth);
      final height = _positive(params.leftHeight);
      final apexX = (width / 2 + params.apexOffsetMm)
          .clamp(5.0, math.max(width - 5, 6))
          .toDouble();
      final List<Offset> polygon;
      if (params.isTriangle) {
        polygon = [Offset(0, 0), Offset(width, 0), Offset(apexX, height)];
      } else {
        final roof = params.roofHeightMm
            .clamp(10.0, math.max(height - 10, 11))
            .toDouble();
        final wall = params.wallHeightMm > 0
            ? params.wallHeightMm.clamp(10.0, 20000.0).toDouble()
            : height - roof;
        final overhang = params.roofOverhangMm
            .clamp(0.0, width * 0.25)
            .toDouble();
        polygon = overhang <= 0.5
            ? [
                Offset(0, 0),
                Offset(width, 0),
                Offset(width, wall),
                Offset(apexX, wall + roof),
                Offset(0, wall),
              ]
            : [
                Offset(0, 0),
                Offset(width, 0),
                Offset(width, wall),
                Offset(width + overhang, wall),
                Offset(apexX, wall + roof),
                Offset(-overhang, wall),
                Offset(0, wall),
              ];
      }
      return WindowGeometry(
        bottomWidth: width,
        topWidth: width,
        leftHeight: height,
        rightHeight: height,
        topOffset: 0,
        shapePolygon: polygon,
      );
    }
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
    final pocketWidth = params.pocketWidth.isFinite && params.pocketWidth > 0
        ? params.pocketWidth
        : 0.0;
    final leftHeight = _positive(params.leftHeight);
    final rightHeight = _positive(params.rightHeight);
    // «Ровно»: какая кромка остаётся горизонтальной. Прежняя геометрия —
    // низ ровно (bottom): низ горизонтален, верх наклонён. Для top верх
    // фиксируется на максимальной высоте, нижние углы смещаются. Для none
    // перепад делится поровну: правую сторону сдвигаем вниз на половину
    // разницы, тогда низ и верх наклонены в разные стороны одинаково.
    var bottomLeftY = 0.0;
    var bottomRightY = 0.0;
    var topLeftY = leftHeight;
    var topRightY = rightHeight;
    switch (params.levelEdge) {
      case LevelEdge.bottom:
        break;
      case LevelEdge.top:
        final maxHeight = math.max(leftHeight, rightHeight);
        topLeftY = maxHeight;
        topRightY = maxHeight;
        bottomLeftY = maxHeight - leftHeight;
        bottomRightY = maxHeight - rightHeight;
      case LevelEdge.none:
        final delta = rightHeight - leftHeight;
        bottomRightY = -delta / 2;
        topRightY = rightHeight - delta / 2;
    }
    return WindowGeometry(
      bottomWidth: bottom,
      topWidth: top,
      leftHeight: leftHeight,
      rightHeight: rightHeight,
      topOffset: offset,
      levelEdge: params.levelEdge,
      bottomLeftY: bottomLeftY,
      bottomRightY: bottomRightY,
      topLeftY: topLeftY,
      topRightY: topRightY,
      pocketDrop: params.pocket && !params.isScreen ? pocketWidth : 0,
      pocketTopRise: params.pocketTop && !params.isScreen ? pocketWidth : 0,
      // Т-образное окно: контур строится объединением основного полотна и
      // приставки (см. [TShapeLayout]). Остальные размеры остаются в полях,
      // чтобы чертёж и подписи могли показать обе части.
      tLayout: params.isTShape ? TShapeLayout.build(params) : null,
      compositeSpec: params.isComposite ? params.composite : null,
    );
  }

  final double bottomWidth;
  final double topWidth;
  final double leftHeight;
  final double rightHeight;

  /// Смещение левого верхнего угла вправо от левого нижнего угла.
  final double topOffset;

  /// Насколько фартук (бывший карман) опускается ниже нижнего тента, мм.
  final double pocketDrop;

  /// Насколько верхний фартук (бывший карман) поднимается выше верхней
  /// кромки, мм.
  final double pocketTopRise;

  /// Какая кромка горизонтальна (см. [LevelEdge]).
  final LevelEdge levelEdge;

  /// Вертикальные координаты углов: низ может быть смещён при levelEdge.top,
  /// а верх/низ наклонены при levelEdge.none.
  final double bottomLeftY;
  final double bottomRightY;
  final double topLeftY;
  final double topRightY;

  /// Геометрия Т-образного окна (null у обычного окна).
  final TShapeLayout? tLayout;

  /// Второй сегмент составного окна (null у остальных типов).
  final CompositeSpec? compositeSpec;

  /// Особый контур (треугольник/домик), null у обычных окон.
  final List<Offset>? shapePolygon;

  /// Т-образное окно — контур не четырёхугольный.
  bool get isTShape => tLayout != null;

  /// Составное окно: ПВХ-полотно плюс второй материал по общему шву.
  bool get isComposite => compositeSpec != null;

  /// Построенная геометрия составного окна (null у остальных типов).
  late final CompositeLayout? compositeLayout = compositeSpec == null
      ? null
      : CompositeLayout.build(compositeSpec!, _mainQuad);

  /// Четырёхугольник основного полотна по габаритам окна.
  List<Offset> get _mainQuad => [bottomLeft, bottomRight, topRight, topLeft];

  static double _positive(double value) =>
      (!value.isFinite || value <= 0) ? 100 : value.clamp(100, 20000);

  Offset get bottomLeft => Offset(0, bottomLeftY);
  Offset get bottomRight => Offset(bottomWidth, bottomRightY);
  Offset get topLeft => Offset(topOffset, topLeftY);
  Offset get topRight => Offset(topOffset + topWidth, topRightY);

  /// Углы против часовой стрелки (в координатах с осью Y вверх), начиная
  /// с левого нижнего. Порядок важен для [insetPolygonPerSide].
  ///
  /// У Т-образного окна вершин 6–8: это фактический контур объединения
  /// основного полотна и приставки.
  List<Offset> get corners =>
      shapePolygon ??
      compositeLayout?.outline ??
      tLayout?.outline ??
      [bottomLeft, bottomRight, topRight, topLeft];

  /// Габарит фактического контура изделия (без фартука).
  Rect get productBounds => boundsOf(corners);

  /// Длины сторон по обходу углов: низ, право, верх, лево.
  List<double> get sideLengths {
    final points = corners;
    return [
      for (var i = 0; i < points.length; i++)
        (points[(i + 1) % points.length] - points[i]).distance,
    ];
  }

  /// Длина левой кромки. У Т-окна это сумма всех левых отрезков контура.
  double get leftEdgeLength {
    if (shapePolygon == null && !isTShape && !isComposite) {
      return sideLengths[3];
    }
    return _edgeLengthOnSide(WindowSide.left);
  }

  /// Длина правой кромки. У Т-окна — сумма правых отрезков контура.
  double get rightEdgeLength {
    if (shapePolygon == null && !isTShape && !isComposite) {
      return sideLengths[1];
    }
    return _edgeLengthOnSide(WindowSide.right);
  }

  double _edgeLengthOnSide(WindowSide side) {
    var total = 0.0;
    final points = corners;
    for (var i = 0; i < points.length; i++) {
      final a = points[i];
      final b = points[(i + 1) % points.length];
      if (sideOfPolygonEdge(points, i) == side) total += (b - a).distance;
    }
    return total;
  }

  /// Длина окантовки по наружному контуру (без запаса на стыки).
  double get perimeter => sideLengths.reduce((a, b) => a + b);

  double get areaMm2 => polygonArea(corners).abs();

  double get areaM2 => areaMm2 / 1000000;

  double get minX => productBounds.left;
  double get maxX => productBounds.right;
  double get minY => productBounds.top - pocketDrop;
  double get maxY => productBounds.bottom;

  /// Верхняя граница листа: изделие плюс верхний фартук (если он есть).
  ///
  /// [maxY] и [overallHeight] остаются габаритом ИЗДЕЛИЯ — по ним считаются
  /// площадь и подписи, а фартук лишь расширяет лист чертежа ([spanY]).
  double get topBound => maxY + pocketTopRise;

  double get spanX => maxX - minX;
  double get spanY => topBound - minY;

  /// Габаритная высота изделия (у Т-окна — вместе с приставкой).
  ///
  /// Считается по фактическому контуру: при режиме «Нет» низ и верх наклонены
  /// в разные стороны, и высота — это расстояние между крайними кромками, а не
  /// только верхняя координата.
  double get overallHeight => productBounds.height;

  /// Насколько верхняя кромка выходит за нижнюю справа (мм).
  double get rightOverhang => (shapePolygon != null || isTShape || isComposite)
      ? 0
      : topOffset + topWidth - bottomWidth;

  /// Насколько верхняя кромка выходит за нижнюю слева (мм).
  double get leftOverhang =>
      (shapePolygon != null || isTShape || isComposite) ? 0 : -topOffset;
}

/// Геометрия составного окна: основное полотно ПВХ и второй сегмент,
/// спаянные по общей линии шва.
///
/// Основное полотно — четырёхугольник по габаритам окна (может быть
/// трапецией). Второй сегмент пристраивается с любой стороны [CompositeSpec.side]:
///
/// * прямой шов — прямоугольник снаружи стороны, шов совпадает с участком
///   кромки; окантовка/подворот идут по трём свободным сторонам;
/// * диагональный шов — линия шва проходит через точку на стороне под углом
///   к ней; основное полотно подрезается этой линией (честный многоугольник),
///   второй сегмент встаёт к шву встык.
///
/// [outline] — единый внешний контур (обе зоны вместе, без внутренней линии
/// шва); [seamStart]/[seamEnd] — линия шва внутри контура. Площади частей
/// считаются по формуле Гаусса, чтобы смета и раскрой не двоили материал.
class CompositeLayout {
  const CompositeLayout._({
    required this.side,
    required this.material,
    required this.diagonal,
    required this.mainPolygon,
    required this.secondPolygon,
    required this.outline,
    required this.seamStart,
    required this.seamEnd,
    required this.depth,
    required this.clamped,
  });

  factory CompositeLayout.build(CompositeSpec spec, List<Offset> mainQuad) {
    if (mainQuad.length < 3) {
      return CompositeLayout._(
        side: spec.side,
        material: spec.material,
        diagonal: false,
        mainPolygon: const [],
        secondPolygon: const [],
        outline: const [],
        seamStart: Offset.zero,
        seamEnd: Offset.zero,
        depth: 0,
        clamped: true,
      );
    }

    final (a, b) = _edgeOf(mainQuad, spec.side);
    final length = (b - a).distance;
    final u = length > 1e-9 ? (b - a) / length : const Offset(1, 0);
    final centroid = _centroid(mainQuad);
    var normal = Offset(u.dy, -u.dx);
    final middle = (a + b) / 2;
    if ((middle - centroid).dx * normal.dx +
            (middle - centroid).dy * normal.dy <
        0) {
      normal = -normal;
    }
    final inward = -normal;

    if (!spec.isDiagonal) {
      // Шов параллелен стороне и смещён внутрь на вынос: второй сегмент —
      // полоса ВНУТРИ введённых габаритов, поэтому размер окна не меняется.
      final room = math.max((centroid - middle).dx * inward.dx +
          (centroid - middle).dy * inward.dy, 1.0);
      final rawDepth = spec.depth.isFinite ? spec.depth : 0.0;
      final depth = rawDepth.clamp(1.0, room * 1.8);
      final clamped = (rawDepth - depth).abs() > 1e-6;
      final origin = a + inward * depth;
      final dir = u;
      final keepLeft = _cross(dir, centroid - origin) >= 0;
      final inner = _clipHalfPlane(mainQuad, origin, dir, keepLeft);
      final outer = _clipHalfPlane(mainQuad, origin, dir, !keepLeft);
      final seam = _seamEdge(inner, origin, dir);
      if (inner.length < 3 || outer.length < 3 || seam == null) {
        return CompositeLayout._(
          side: spec.side,
          material: spec.material,
          diagonal: false,
          mainPolygon: List<Offset>.of(mainQuad),
          secondPolygon: const [],
          outline: List<Offset>.of(mainQuad),
          seamStart: a,
          seamEnd: b,
          depth: 0,
          clamped: true,
        );
      }
      return CompositeLayout._(
        side: spec.side,
        material: spec.material,
        diagonal: false,
        mainPolygon: inner,
        secondPolygon: outer,
        outline: List<Offset>.of(mainQuad),
        seamStart: seam.$1,
        seamEnd: seam.$2,
        depth: depth,
        clamped: clamped,
      );
    }

    // Диагональный шов: хорда от точки на стороне внутрь полотна; второй
    // сегмент — отрезанный угол ВНУТРИ общего контура.
    final fraction = spec.seamOffset.isFinite
        ? spec.seamOffset.clamp(0.05, 0.95)
        : 0.5;
    final pivot = a + u * (length * fraction);
    final angle = (spec.seamAngleDeg.isFinite ? spec.seamAngleDeg.abs() : 25.0)
        .clamp(5.0, 80.0) *
        math.pi /
        180;
    final dir = u * math.cos(angle) + inward * math.sin(angle);
    final hits = _lineHits(mainQuad, pivot, dir);
    final forward = hits.where((t) => t > 1e-6).toList();
    if (forward.isEmpty) {
      return CompositeLayout.build(
        spec.copyWith(seam: CompositeSeam.straight),
        mainQuad,
      );
    }
    final s1 = pivot + dir * forward.reduce(math.min);
    if ((s1 - pivot).distance < 1.0) {
      return CompositeLayout.build(
        spec.copyWith(seam: CompositeSeam.straight),
        mainQuad,
      );
    }
    final keepLeft = _cross(dir, centroid - pivot) >= 0;
    final inner = _clipHalfPlane(mainQuad, pivot, dir, keepLeft);
    final outer = _clipHalfPlane(mainQuad, pivot, dir, !keepLeft);
    if (inner.length < 3 || outer.length < 3) {
      return CompositeLayout.build(
        spec.copyWith(seam: CompositeSeam.straight),
        mainQuad,
      );
    }

    // «Вынос» диагонального сегмента — наибольшее удаление его вершин от шва.
    final depth = outer.fold<double>(
      0,
      (value, point) => math.max(value, _cross(dir, point - pivot).abs()),
    );
    return CompositeLayout._(
      side: spec.side,
      material: spec.material,
      diagonal: true,
      mainPolygon: inner,
      secondPolygon: outer,
      outline: List<Offset>.of(mainQuad),
      seamStart: pivot,
      seamEnd: s1,
      depth: depth,
      clamped: false,
    );
  }

  /// Ребро контура, лежащее на прямой [origin] + [dir] * t.
  static (Offset, Offset)? _seamEdge(
    List<Offset> polygon,
    Offset origin,
    Offset dir,
  ) {
    final onLine = <Offset>[
      for (final point in polygon)
        if (_cross(dir, point - origin).abs() < 1e-3) point,
    ];
    if (onLine.length < 2) return null;
    var best = (onLine[0], onLine[1]);
    var bestLength = (best.$2 - best.$1).distance;
    for (var i = 0; i < onLine.length; i++) {
      for (var j = i + 1; j < onLine.length; j++) {
        final distance = (onLine[j] - onLine[i]).distance;
        if (distance > bestLength) {
          bestLength = distance;
          best = (onLine[i], onLine[j]);
        }
      }
    }
    return bestLength > 1e-6 ? best : null;
  }

  final EdgeSide side;
  final FilmMaterial material;
  final bool diagonal;

  /// Основное полотно (у диагонального шва — подрезанный многоугольник).
  final List<Offset> mainPolygon;

  /// Второй сегмент (спайка встык по линии шва).
  final List<Offset> secondPolygon;

  /// Единый внешний контур окна без внутреннего шва.
  final List<Offset> outline;

  /// Начало и конец линии шва.
  final Offset seamStart;
  final Offset seamEnd;

  /// Вынос второго сегмента от шва наружу, мм.
  final double depth;

  /// Размеры второго сегмента пришлось подрезать под сторону.
  final bool clamped;

  bool get isScreen => material == FilmMaterial.screen;

  /// Линия шва: две точки для чертежа и сметы.
  List<Offset> get seam => [seamStart, seamEnd];

  /// Длина шва, мм.
  double get seamLength => (seamEnd - seamStart).distance;

  /// Площадь основного полотна, мм².
  double get mainAreaMm2 => polygonArea(mainPolygon).abs();

  /// Площадь второго сегмента, мм².
  double get secondAreaMm2 => polygonArea(secondPolygon).abs();

  /// Площадь всего окна, мм².
  double get totalAreaMm2 => mainAreaMm2 + secondAreaMm2;

  /// Контуры частей: основное полотно и второй сегмент.
  List<List<Offset>> get partPolygons => [mainPolygon, secondPolygon];

  /// Подпись второго сегмента для документов.
  String get secondLabel =>
      '${material.label}, ${side.label.toLowerCase()}, '
      '${diagonal ? 'диагональный шов' : 'прямой шов'}';

  /// Середина шва — для подписи на чертеже.
  Offset get seamMid => (seamStart + seamEnd) / 2;

  static (Offset, Offset) _edgeOf(List<Offset> quad, EdgeSide side) {
    // Порядок углов окна: низ, право, верх, лево (обход против часовой).
    return switch (side) {
      EdgeSide.bottom => (quad[0], quad[1 % quad.length]),
      EdgeSide.right => (quad[1 % quad.length], quad[2 % quad.length]),
      EdgeSide.top => (quad[2 % quad.length], quad[3 % quad.length]),
      EdgeSide.left => (quad[3 % quad.length], quad[0]),
    };
  }

  static Offset _centroid(List<Offset> polygon) {
    var x = 0.0;
    var y = 0.0;
    for (final point in polygon) {
      x += point.dx;
      y += point.dy;
    }
    return Offset(x / polygon.length, y / polygon.length);
  }

  static double _cross(Offset a, Offset b) => a.dx * b.dy - a.dy * b.dx;


  /// Параметры t пересечения прямой `origin + dir * t` с рёбрами контура.
  static List<double> _lineHits(
    List<Offset> polygon,
    Offset origin,
    Offset dir,
  ) {
    final hits = <double>[];
    for (var i = 0; i < polygon.length; i++) {
      final p = polygon[i];
      final q = polygon[(i + 1) % polygon.length];
      final segment = q - p;
      final denominator = _cross(dir, segment);
      if (denominator.abs() < 1e-9) continue;
      final diff = p - origin;
      final t = _cross(diff, segment) / denominator;
      final u = _cross(diff, dir) / denominator;
      if (u >= -1e-9 && u <= 1 + 1e-9 && t.isFinite) hits.add(t);
    }
    hits.sort();
    return hits;
  }

  /// Оставляет часть многоугольника по одну сторону прямой (Сазерленд—Ходжман).
  static List<Offset> _clipHalfPlane(
    List<Offset> polygon,
    Offset origin,
    Offset dir,
    bool keepLeft,
  ) {
    double sideOf(Offset point) {
      final value = _cross(dir, point - origin);
      return keepLeft ? value : -value;
    }

    final result = <Offset>[];
    for (var i = 0; i < polygon.length; i++) {
      final current = polygon[i];
      final next = polygon[(i + 1) % polygon.length];
      final sideCurrent = sideOf(current);
      final sideNext = sideOf(next);
      if (sideCurrent >= -1e-9) result.add(current);
      final crosses =
          (sideCurrent > 1e-9 && sideNext < -1e-9) ||
          (sideCurrent < -1e-9 && sideNext > 1e-9);
      if (crosses) {
        final t = sideCurrent / (sideCurrent - sideNext);
        result.add(current + (next - current) * t);
      }
    }
    return result;
  }
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
  List<double> get rolls => isScreen
      ? const [0, 0, 0, 0]
      : [for (var i = 0; i < 4; i++) params.rollForEdge(i)];

  /// Готовые (сложенные пополам) ширины окантовки по сторонам.
  List<double> get finishedWidths => isScreen
      ? const [0, 0, 0, 0]
      : [for (final width in rolls) WindowParams.finishedEdgeWidth(width)];

  /// Подворот скрина по сторонам, мм (у ПВХ — нули).
  ///
  /// Это ФАКТИЧЕСКИЕ подвороты, которыми подписаны стороны и по которым
  /// строится линия подворота. Для габарита заготовки они не суммируются:
  /// там работает [hemOutsetWidths].
  List<double> get hemWidths =>
      isScreen ? List.of(params.hemWidths) : const [0, 0, 0, 0];

  /// Расширение контура заготовки скрина по сторонам в порядке обхода
  /// (низ, право, верх, лево), мм.
  ///
  /// В заготовку идёт ПОЛОВИНА введённого подворота каждой стороны: 80 → 40,
  /// 120 → 60. К высоте добавляется ещё 20 мм на шов и запас — их делим
  /// поровну между нижней и верхней кромкой (по 10 мм), поэтому высота
  /// заготовки растёт ровно на `низ / 2 + верх / 2 + 20`. Ширина — только
  /// `лево / 2 + право / 2`, без добавки. Пример заказчика: скрин 1000 × 1000,
  /// подвороты 80/80/120/80 → заготовка 1080 × 1120 мм.
  List<double> get hemOutsetWidths {
    if (!isScreen) return const [0, 0, 0, 0];
    const halfExtra = screenHemAxisExtraMm / 2;
    // Порядок обхода: низ, право, верх, лево.
    return [
      params.hemBottomHalfMm + halfExtra,
      params.hemRightHalfMm,
      params.hemTopHalfMm + halfExtra,
      params.hemLeftHalfMm,
    ];
  }

  /// Т-образное окно: контур из нескольких вершин.
  bool get isTShape => geometry.isTShape;

  /// Составное окно: две зоны материалов с общим швом.
  bool get isComposite => geometry.isComposite;

  /// Геометрия составного окна (null у остальных типов).
  CompositeLayout? get compositeLayout => geometry.compositeLayout;

  /// Геометрия Т-образного окна (null у обычного окна).
  TShapeLayout? get tLayout => geometry.tLayout;

  /// Спайка по общей стороне у Т-окна (хотя бы у одной пристройки).
  bool get tWelded => tLayout?.anyWelded ?? false;

  /// Все пристройки Т-окна спаяны с основным полотном.
  bool get tAllWelded => tLayout?.allWelded ?? false;

  /// Есть ли пристройка без спайки: тогда это отдельное окно.
  bool get tAnySeparate => tLayout?.separateAnnexes.isNotEmpty ?? false;

  /// Части Т-окна: основное полотно и каждая пристройка. У обычного окна —
  /// один контур. Нужно для раскроя, чертежа и «отдельных окон».
  List<List<Offset>> get partPolygons {
    final composite = compositeLayout;
    if (composite != null) return composite.partPolygons;
    final t = tLayout;
    if (t == null) return [outer];
    return [t.mainPolygon, ...t.annexPolygons];
  }

  /// Контуры для окантовки и люверсов: у Т-окна сваренные пристройки
  /// объединены с основным полотном, отдельные (без спайки) идут сами по
  /// себе. У обычного окна — внешний контур.
  List<List<Offset>> get groupPolygons {
    // У составного окна обе зоны спаяны: окантовка, люверсы и подворот идут
    // по единому внешнему контуру, шов внутри окантовки не имеет.
    if (isComposite) return [outer];
    return tLayout?.groups ?? [outer];
  }

  /// Пристройки Т-окна (пусто у обычного окна).
  List<TShapeAnnexLayout> get tAnnexes =>
      tLayout?.annexes ?? const <TShapeAnnexLayout>[];

  /// Сторона окна для ребра многоугольника. Для четырёхугольника порядок
  /// прежний (низ, право, верх, лево), для Т-контура сторона выводится из
  /// направления наружной нормали ребра.
  WindowSide sideOfEdge(List<Offset> polygon, int index) =>
      sideOfPolygonEdge(polygon, index);

  static EdgeSide edgeSideOf(WindowSide side) => switch (side) {
    WindowSide.bottom => EdgeSide.bottom,
    WindowSide.right => EdgeSide.right,
    WindowSide.top => EdgeSide.top,
    WindowSide.left => EdgeSide.left,
  };

  static WindowSide windowSideOf(EdgeSide side) => switch (side) {
    EdgeSide.bottom => WindowSide.bottom,
    EdgeSide.right => WindowSide.right,
    EdgeSide.top => WindowSide.top,
    EdgeSide.left => WindowSide.left,
  };

  /// Готовая ширина окантовки для стороны окна, мм.
  double finishedWidthFor(WindowSide side) => isScreen
      ? 0.0
      : WindowParams.finishedEdgeWidth(params.rollForSide(edgeSideOf(side)));

  /// Подворот скрина для стороны окна, мм.
  double hemWidthFor(WindowSide side) => switch (side) {
    WindowSide.bottom => params.hemBottomMm,
    WindowSide.right => params.hemRightMm,
    WindowSide.top => params.hemTopMm,
    WindowSide.left => params.hemLeftMm,
  };

  /// Прибавка к заготовке скрина по стороне, мм.
  ///
  /// Ровно половина подворота этой стороны ([WindowParams.hemLeftHalfMm] и
  /// т. п.); к нижней и верхней кромке добавлено ещё по 10 мм — половина
  /// постоянной добавки +20 мм к высоте.
  double hemOutsetFor(WindowSide side) => switch (side) {
    WindowSide.bottom => params.hemBottomHalfMm + screenHemAxisExtraMm / 2,
    WindowSide.top => params.hemTopHalfMm + screenHemAxisExtraMm / 2,
    WindowSide.left => params.hemLeftHalfMm,
    WindowSide.right => params.hemRightHalfMm,
  };

  /// Ребро контура лежит на линии шва составного окна.
  ///
  /// Проверяем по прямой, а не по концам: контуры частей могут быть
  /// подрезаны под окантовку, и концы ребра уже не совпадают с концами шва.
  bool isCompositeSeamEdge(Offset a, Offset b) {
    final composite = compositeLayout;
    if (composite == null) return false;
    final direction = composite.seamEnd - composite.seamStart;
    final length = direction.distance;
    if (length < 1e-6) return false;
    final unit = direction / length;
    bool onLine(Offset point) =>
        (unit.dx * (point.dy - composite.seamStart.dy) -
                unit.dy * (point.dx - composite.seamStart.dx))
            .abs() <
        1e-3;
    return onLine(a) && onLine(b);
  }

  /// Точка лежит на линии шва составного окна.
  bool isOnCompositeSeam(Offset point) {
    final composite = compositeLayout;
    if (composite == null) return false;
    final direction = composite.seamEnd - composite.seamStart;
    final length = direction.distance;
    if (length < 1e-6) return false;
    final unit = direction / length;
    return (unit.dx * (point.dy - composite.seamStart.dy) -
                unit.dy * (point.dx - composite.seamStart.dx))
            .abs() <
        0.5;
  }

  /// Ширины по рёбрам многоугольника — по стороне каждого ребра.
  List<double> perEdge(
    List<Offset> polygon,
    double Function(WindowSide side) width,
  ) => [
    for (var i = 0; i < polygon.length; i++)
      width(sideOfPolygonEdge(polygon, i)),
  ];

  static List<Offset> _rectPolygon(Rect rect) => [
    Offset(rect.left, rect.top),
    Offset(rect.right, rect.top),
    Offset(rect.right, rect.bottom),
    Offset(rect.left, rect.bottom),
  ];

  /// Припуск под окантовку (ПВХ) или прибавка подворота (скрин) по стороне.
  ///
  /// Положительное значение — внутрь (плёнка подрезается под окантовку),
  /// отрицательное — наружу (заготовка скрина больше готового изделия).
  double _blankAmount(WindowSide side) => isScreen
      ? -hemOutsetFor(side)
      : math.max(finishedWidthFor(side) - params.weldOverlapMm, 0.0);

  /// Вычет с кромки для заготовки полотна, мм.
  ///
  /// Это и есть заказчиково `d = готовая полоса − запайка`: у ПВХ
  /// [WindowParams.finishedEdgeWidth] минус [WindowParams.weldOverlapMm].
  /// У скрина вычет отрицательный — заготовка БОЛЬШЕ готового изделия на
  /// половину подворота этой стороны ([hemOutsetFor]).
  double blankSideDeduction(WindowSide side) => _blankAmount(side);

  /// Геометрия заготовки полотна: та же форма, что у изделия, но каждая
  /// сторона уменьшена на свой вычет.
  ///
  /// Заказчик: «каждая сторона заготовки = сторона изделия − 2 × (готовая
  /// полоса) + 2 × запайка», причём считается по длине КАЖДОЙ стороны
  /// отдельно. Поэтому у трапеции и окна с разными высотами заготовка —
  /// не прямоугольник по габариту, а такой же косой четырёхугольник:
  /// низ 2 990, право 2 740, верх 2 990, лево 2 080 при изделии
  /// 3 050/3 050 × 2 140/2 800, полосе 50 и запайке 20 мм.
  ///
  /// Ширины уменьшаются на вычеты левой и правой сторон, высоты — на вычеты
  /// нижней и верхней. При одинаковой полосе по всем сторонам это ровно
  /// «сторона − 2d» из примера заказчика.
  late final WindowGeometry blankGeometry = _buildBlankGeometry();

  WindowGeometry _buildBlankGeometry() {
    // У Т-окна заготовка строится по прямоугольникам частей
    // ([partBlankRects]); отдельная косоугольная геометрия там не нужна.
    // У составного окна каждая часть кроится своим контуром
    // ([filmPolygons]), поэтому общая «одна» геометрия тоже не нужна.
    if (isTShape || isComposite) return geometry;
    final widthDeduction =
        blankSideDeduction(WindowSide.left) +
        blankSideDeduction(WindowSide.right);
    final heightDeduction =
        blankSideDeduction(WindowSide.bottom) +
        blankSideDeduction(WindowSide.top);
    double side(double value, double deduction) {
      final result = value - deduction;
      return result.isFinite && result > 1 ? result : 1.0;
    }

    // Каждая кромка сдвигается на СВОЙ вычет: низ — вверх (у скрина вниз),
    // верх — вниз (у скрина вверх), бока — внутрь/наружу. Иначе при «Ровно:
    // верх» и «Ровно: нет» заготовка снова получала бы горизонтальный низ:
    // конструктор WindowGeometry сам режим «Ровно» не применяет — он лишь
    // хранит координаты углов, которые сюда надо передать явно.
    final bottomDeduction = blankSideDeduction(WindowSide.bottom);
    final topDeduction = blankSideDeduction(WindowSide.top);

    return WindowGeometry(
      bottomWidth: side(geometry.bottomWidth, widthDeduction),
      topWidth: side(geometry.topWidth, widthDeduction),
      leftHeight: side(geometry.leftHeight, heightDeduction),
      rightHeight: side(geometry.rightHeight, heightDeduction),
      // Наклон и выравнивание кромок сохраняются: заготовка — та же косая
      // форма, только меньше по каждой стороне.
      topOffset: geometry.topOffset,
      levelEdge: geometry.levelEdge,
      // Координаты углов повторяют изделие с поправкой на вычет кромки.
      bottomLeftY: geometry.bottomLeftY + bottomDeduction,
      bottomRightY: geometry.bottomRightY + bottomDeduction,
      topLeftY: geometry.topLeftY - topDeduction,
      topRightY: geometry.topRightY - topDeduction,
    );
  }

  /// Длины сторон заготовки по обходу: низ, право, верх, лево (мм).
  ///
  /// Это НОМИНАЛЬНЫЕ стороны заготовки — ровно те числа, которые заказчик
  /// называет в примере (2 990 / 2 740 / 2 990 / 2 080). У наклонной верхней
  /// кромки фактическая длина отрезка на чертеже чуть больше (как и у самого
  /// изделия, где «верх 3 050» — это ширина, а не длина наклонной кромки),
  /// поэтому подписи и документы берут именно эти значения.
  List<double> get blankSideLengths => geometry.shapePolygon != null
      ? const <double>[]
      : [
          blankGeometry.bottomWidth,
          blankGeometry.rightHeight,
          blankGeometry.topWidth,
          blankGeometry.leftHeight,
        ];

  /// Вершины заготовки: контур изделия расширен на половину подворота
  /// каждой стороны.
  ///
  /// Размеры сторон — из [blankGeometry]. У ПВХ контур сдвинут так, чтобы его
  /// габарит был вписан в изделие симметрично (вычет по каждой кромке). У
  /// скрина, наоборот, каждая кромка отодвигается на СВОЮ половину подворота:
  /// низ — на `низ / 2 + 10`, верх — на `верх / 2 + 10`, лево/право — на
  /// `лево / 2` и `право / 2`. Так полоса подворота на чертеже равна половине
  /// введённого значения даже при разных подворотах по сторонам.
  late final List<Offset> blankCorners = _buildBlankCorners();

  List<Offset> _buildBlankCorners() {
    if (isComposite) {
      // У составного окна заготовок две; «первый контур» — основное полотно
      // (см. [filmPolygons]).
      final polygons = _buildCompositeFilmPolygons();
      return polygons.isEmpty ? const [] : polygons.first;
    }
    final shape = geometry.shapePolygon;
    if (shape != null) {
      return insetPolygonPerSide(
        shape,
        perEdge(shape, (side) => _blankAmount(side)),
      );
    }
    final corners = blankGeometry.corners;
    if (corners.isEmpty) return const [];
    final bounds = boundsOf(corners);
    if (isScreen) {
      final product = geometry.productBounds;
      final shift = Offset(
        // Левая кромка — на лево / 2 наружу, правая — на право / 2.
        product.left - hemOutsetFor(WindowSide.left) - bounds.left,
        // В модели ось Y вверх: top Rect — нижняя кромка изделия.
        product.top - hemOutsetFor(WindowSide.bottom) - bounds.top,
      );
      return [for (final point in corners) point + shift];
    }
    final shift = geometry.productBounds.center - bounds.center;
    return [for (final point in corners) point + shift];
  }

  /// Площадь заготовки по формуле Гаусса (по контуру косой формы), мм².
  double get blankAreaMm2 => isComposite
      ? filmPolygons.fold<double>(
          0,
          (sum, polygon) => sum + polygonArea(polygon).abs(),
        )
      : polygonArea(blankCorners).abs();

  /// Прямоугольник заготовки с подрезкой по сторонам.
  ///
  /// [shared] — стороны, по которым припуска нет: там шов спайки.
  Rect _blankRect(Rect rect, Set<EdgeSide> shared) {
    double value(EdgeSide side) =>
        shared.contains(side) ? 0.0 : _blankAmount(windowSideOf(side));
    return Rect.fromLTRB(
      rect.left + value(EdgeSide.left),
      rect.top + value(EdgeSide.bottom),
      rect.right - value(EdgeSide.right),
      rect.bottom - value(EdgeSide.top),
    );
  }

  /// Габарит заготовки всего окна.
  ///
  /// Для прямоугольного окна это ровно прежняя формула «габарит минус
  /// окантовка (плюс запайка) по сторонам»; для трапеции и окна с разными
  /// высотами сторон — габарит косой заготовки ([blankGeometry]), а площадь
  /// считается по её контуру, а не по этому прямоугольнику.
  Rect get blankRect {
    if (isComposite) return boundsOfAll(filmPolygons);
    if (!isTShape) return boundsOf(blankCorners);
    final bounds = geometry.productBounds;
    return _blankRect(bounds, const <EdgeSide>{});
  }

  /// Заготовки по частям: у обычного окна один прямоугольник, у Т-окна —
  /// основное полотно и каждая пристройка (свой прямоугольник).
  late final List<Rect> partBlankRects = _buildPartBlankRects();

  List<Rect> _buildPartBlankRects() {
    if (isComposite) {
      return [for (final polygon in filmPolygons) boundsOf(polygon)];
    }
    final t = tLayout;
    if (t == null) return [blankRect];
    final mainShared = <EdgeSide>{
      for (final annex in t.weldedAnnexes) annex.side.sharedEdge,
    };
    return [
      _blankRect(t.mainRect, mainShared),
      for (final annex in t.annexes)
        _blankRect(
          annex.rect,
          annex.welded
              ? <EdgeSide>{annex.side.sharedEdge.opposite}
              : const <EdgeSide>{},
        ),
    ];
  }

  /// Контуры заготовки полотна.
  ///
  /// У обычного окна — контур фактической формы: прямоугольник у
  /// прямоугольного окна и косой четырёхугольник у трапеции или окна с
  /// разными высотами сторон. У Т-окна сваренные пристройки объединены
  /// с основным полотном в общий контур, а пристройки без спайки — отдельные
  /// прямоугольники.
  late final List<List<Offset>> filmPolygons = _buildFilmPolygons();

  List<List<Offset>> _buildFilmPolygons() {
    if (isComposite) return _buildCompositeFilmPolygons();
    final t = tLayout;
    if (t == null) return [List<Offset>.of(blankCorners)];
    final welded = t.weldedAnnexes;
    final polygons = <List<Offset>>[];
    final mainBlank = partBlankRects.first;
    if (welded.isEmpty) {
      polygons.add(_rectPolygon(mainBlank));
    } else {
      final merged = unionOutlineOfRects([
        mainBlank,
        for (final annex in welded) partBlankRects[annex.number],
      ], start: Offset(mainBlank.left, mainBlank.top));
      polygons.add(merged.length >= 3 ? merged : _rectPolygon(mainBlank));
    }
    for (final annex in t.separateAnnexes) {
      polygons.add(_rectPolygon(partBlankRects[annex.number]));
    }
    return polygons;
  }

  /// Заготовки частей составного окна: у каждой свой контур, шов — общая
  /// кромка без окантовки/подворота.
  List<List<Offset>> _buildCompositeFilmPolygons() {
    final composite = compositeLayout;
    if (composite == null) return const [];
    return [
      _compositeBlankOf(composite, composite.mainPolygon),
      _compositeBlankOf(composite, composite.secondPolygon),
    ];
  }

  /// Вычет кромки для конкретного материала части: у второго сегмента
  /// материал может отличаться от основного полотна.
  double _blankAmountForMaterial(WindowSide side, FilmMaterial material) {
    if (material == FilmMaterial.screen) return -hemOutsetFor(side);
    return _blankAmount(side);
  }

  List<Offset> _compositeBlankOf(
    CompositeLayout composite,
    List<Offset> polygon,
  ) {
    if (polygon.length < 3) return const [];
    final amounts = <double>[];
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      // Сторона шва: припуск/подворот там не нужен — это стык двух деталей.
      final seam = ((a - composite.seamStart).distance < 1e-6 &&
              (b - composite.seamEnd).distance < 1e-6) ||
          ((a - composite.seamEnd).distance < 1e-6 &&
              (b - composite.seamStart).distance < 1e-6);
      amounts.add(
        seam
            ? 0.0
            : _blankAmountForMaterial(
                sideOfPolygonEdge(polygon, i),
                composite.material,
              ),
      );
    }
    return insetPolygonPerSide(polygon, amounts);
  }

  /// Габариты заготовок по частям: основное полотно и каждая пристройка
  /// (у обычного окна — один габарит). По ним в техкарте печатаются размеры
  /// каждой части, а не только общий габарит.
  late final List<Rect> filmPartBounds = partBlankRects;

  /// Внутренняя граница окантовки: видимая граница плёнки.
  ///
  /// У скрина видимый размер — это готовый контур изделия: подворот
  /// загибается на изнанку, наружу ничего не выходит. У Т-окна контуров
  /// столько же, сколько групп частей (см. [groupPolygons]).
  late final List<List<Offset>> edgeInnerPolygons = _buildEdgeInnerPolygons();

  List<List<Offset>> _buildEdgeInnerPolygons() {
    final composite = compositeLayout;
    if (composite != null) {
      return [
        _edgeInnerForPart(composite.mainPolygon, params.material),
        _edgeInnerForPart(composite.secondPolygon, composite.material),
      ];
    }
    if (isScreen) return groupPolygons;
    return [
      for (final polygon in groupPolygons)
        insetPolygonPerSide(polygon, perEdge(polygon, finishedWidthFor)),
    ];
  }

  List<Offset> _edgeInnerForPart(
    List<Offset> polygon,
    FilmMaterial material,
  ) {
    if (material == FilmMaterial.screen) return polygon;
    return insetPolygonPerSide(polygon, _partEdgeAmounts(polygon, material, 1));
  }

  /// Внутренняя граница окантовки (первый контур — для подписей и старых
  /// вызовов; у Т-окна без спайки контуров два, см. [edgeInnerPolygons]).
  List<Offset> get edgeInner => edgeInnerPolygons.first;

  /// Граница полотна в раскрое (первый контур). Полный список контуров —
  /// [filmPolygons]: у Т-окна без спайки их два.
  List<Offset> get filmEdge => filmPolygons.first;

  /// Линия центров люверсов (первый контур).
  List<Offset> get eyeletLine => eyeletPolygons.first;

  /// Контуры, по которым ставятся люверсы: у обычного окна один, у Т-окна
  /// при спайке — общий внешний контур, без спайки — периметры двух частей.
  late final List<List<Offset>> eyeletPolygons = _buildEyeletPolygons();

  List<List<Offset>> _buildEyeletPolygons() {
    final composite = compositeLayout;
    if (composite != null) {
      return [
        _eyeletPolygonForPart(composite.mainPolygon, params.material),
        _eyeletPolygonForPart(composite.secondPolygon, composite.material),
      ];
    }
    if (isScreen) return groupPolygons;
    return [
      for (final polygon in groupPolygons)
        insetPolygonPerSide(
          polygon,
          perEdge(polygon, (side) => finishedWidthFor(side) / 2),
        ),
    ];
  }

  /// Линия люверсов одной части составного окна: у ПВХ — середина окантовки,
  /// у скрина — сам контур (люверсы по подвороту).
  List<Offset> _eyeletPolygonForPart(
    List<Offset> polygon,
    FilmMaterial material,
  ) {
    if (material == FilmMaterial.screen) return polygon;
    return insetPolygonPerSide(polygon, _partEdgeAmounts(polygon, material, 0.5));
  }

  /// Отступы по рёбрам части составного окна: на шве — 0, на свободных
  /// кромках — окантовка/подворот в долях [factor] от готовой ширины.
  List<double> _partEdgeAmounts(
    List<Offset> polygon,
    FilmMaterial material,
    double factor,
  ) => [
    for (var i = 0; i < polygon.length; i++)
      isCompositeSeamEdge(polygon[i], polygon[(i + 1) % polygon.length])
          ? 0.0
          : (material == FilmMaterial.screen
                ? 0.0
                : finishedWidthFor(sideOfPolygonEdge(polygon, i)) * factor),
  ];

  /// Линия подворота (сгиба) скрина: готовый контур изделия.
  ///
  /// У ПВХ подворота нет — список пуст. У Т-окна — по группам частей.
  late final List<List<Offset>> screenHemPolygons = isScreen
      ? groupPolygons
      : (isComposite && compositeLayout!.material == FilmMaterial.screen
            ? [compositeLayout!.secondPolygon]
            : const []);

  /// Линия шва [screenSeamMm] внутри подворота скрина.
  late final List<List<Offset>> screenSeamPolygons = [
    for (final hem in screenHemPolygons)
      insetPolygonPerSide(hem, const [
        screenSeamMm,
        screenSeamMm,
        screenSeamMm,
        screenSeamMm,
      ]),
  ];

  /// Линия подворота (первый контур — для подписей и старых вызовов).
  List<Offset> get screenHemLine =>
      screenHemPolygons.isEmpty ? const [] : screenHemPolygons.first;

  /// Линия шва подворота (первый контур).
  List<Offset> get screenSeamLine =>
      screenSeamPolygons.isEmpty ? const [] : screenSeamPolygons.first;

  late final _EyeletResult _eyeletResult = _computeEyelets();

  /// Все люверсы по периметру; угловые не дублируются.
  List<EyeletPlacement> get eyelets => _eyeletResult.placements;

  /// Фактический интервал по каждой стороне, мм (не больше заданного).
  List<double> get eyeletSteps => _eyeletResult.steps;

  int get eyeletCount => eyelets.length;

  /// Габариты видимой плёнки (по внутренней границе окантовки).
  late final Rect filmVisibleBounds = boundsOfAll(edgeInnerPolygons);

  /// Габариты плёнки в раскрое (с напайкой под окантовку).
  late final Rect filmCutBounds = boundsOfAll(filmPolygons);

  /// Суммарная ширина полос всех молний окна, мм.
  ///
  /// Это ровно та величина, на которую заказчик уменьшает ширину заготовки:
  /// полоса молнии (у скрина — подвёрнутая полоса, у ПВХ — спайка тента)
  /// кроится из того же полотна, поэтому из ширины полотна на вкладке
  /// «Раскрой» она вычитается у ВСЕХ материалов. Заготовка 2 530 мм с молнией
  /// и полосой 50 мм кроится 2 480 мм; две молнии по 50 мм дают 2 430 мм.
  /// Для ПВХ 2 000 мм с окантовкой 100 и запайкой 5 мм: 1 910 мм без молнии,
  /// 1 860 мм с полосой 50 мм и 1 810 мм с двумя полосами по 50 мм.
  ///
  /// Ширина берётся из параметров как есть (в панели допустимо 40…120 мм),
  /// без «минимальных 20 мм», которые нужны только для читаемости чертежа:
  /// вычитаться должно ровно то число, которое человек ввёл.
  /// Фактическая ширина полосы молнии: у края учитывает окантовку, в
  /// середине — два тента и две напайки.
  double zipperWidthFor(ZipperSpec zipper) {
    if (!zipper.atEdge) return zipper.bandWidth;
    final visible = filmVisibleBounds;
    final onLeft = zipper.atEdge
        ? !zipper.edgeRight
        : (zipper.centered
                  ? visible.center.dx
                  : visible.left + zipper.offsetMm) <
              visible.center.dx;
    final edgeFinished = onLeft ? finishedWidths[3] : finishedWidths[1];
    return zipper.bandWidthFor(edgeFinished);
  }

  double get zipperBandTotalMm {
    // Раскрой всегда делится на сегменты: из ширины вычитаются только
    // молнии впритык к канту — остальные дают зазор и отдельные заготовки.
    final segments = !isComposite;
    final visible = filmVisibleBounds;
    var total = 0.0;
    for (final zipper in params.zippers) {
      final width = zipperWidthFor(zipper);
      if (!width.isFinite || width <= 0) continue;
      if (segments) {
        final x = zipper.centered
            ? visible.center.dx
            : (visible.left + zipper.offsetMm).clamp(
                visible.left + width / 2,
                visible.right - width / 2,
              );
        final edge = x - width / 2 <= visible.left + 0.5 ||
            x + width / 2 >= visible.right - 0.5;
        if (!edge) continue;
        // Полоса у края целиком вычитается из ширины заготовки: её размер
        // уже посчитан из окантовки, молнии, тента и напайки.
        total += width;
      } else {
        total += width;
      }
    }
    return total;
  }

  /// Раскладка молний для режима сегментов: центр, полоса, впритык ли к
  /// канту и границы зазора 7 см (по 2 см тента напаивается на сегменты).
  List<
    ({
      double center,
      double bandWidth,
      bool edge,
      double gapStart,
      double gapEnd,
    })
  >
  get zipperSegmentLayout {
    if (isComposite) return const [];
    final visible = filmVisibleBounds;
    return [
      for (final line in zippers)
        () {
          final half = line.bandWidth / 2;
          final x = line.start.dx;
          final edge = x - half <= visible.left + 0.5 ||
              x + half >= visible.right - 0.5;
          final gap = line.bandWidth;
          return (
            center: x,
            bandWidth: line.bandWidth,
            edge: edge,
            gapStart: x - gap / 2,
            gapEnd: x + gap / 2,
          );
        }(),
    ];
  }

  /// Ширина заготовки без припуска на раскрой, уже с вычетом полос молний, мм.
  ///
  /// Ширина не может стать отрицательной: заготовка 100 мм с полосой 120 мм
  /// (такое бывает только на вырожденных размерах) остаётся хотя бы 1 мм,
  /// чтобы раскрой и раскладка не делили на ноль.
  double get blankWidth =>
      math.max(filmCutBounds.width - zipperBandTotalMm, 1.0);

  /// Высота заготовки без припуска на раскрой, мм (полоса её не меняет).
  double get blankHeight => filmCutBounds.height;

  /// Площадь полотна изделия в раскрое (с напайкой, без припуска), м².
  ///
  /// У Т-окна без спайки это сумма площадей двух заготовок: они не
  /// пересекаются и считаются раздельно.
  double get filmAreaM2 {
    var area = 0.0;
    for (final polygon in filmPolygons) {
      area += polygonArea(polygon).abs();
    }
    return math.max(area - cutoutAreaMm2, 0) / 1000000;
  }

  /// Люверсы, которые закрываются крепежом подвижных сторон:
  /// низ и бока, сверху саморезы или люверсы.
  ///
  /// Скрин — съёмное полотно: крепёж на нём ставится по тому же правилу, что
  /// у подъёмного ПВХ-окна, и не зависит от типа окна. Поэтому глухой скрин
  /// (WindowType.fixed) тоже получает скобы, замки или ремни по низу и бокам —
  /// иначе выбранный в панели крепёж молча пропадал бы с чертежа.
  ///
  /// Углы исключены: в углу всегда простой круглый люверс, иначе на стыке
  /// двух сторон (например, верх-право) вместо круглого люверса оказывается
  /// прямоугольная скоба. Если тумблер «Круглые люверсы в углах» выключен,
  /// угловых точек в [eyelets] нет вовсе, и список крепежа не меняется.
  List<EyeletPlacement> get movableSideEyelets {
    // Т-образное окно глухое: подвижного крепежа у него нет (у скрина есть —
    // он снимается).
    if (!isScreen && !params.isLifting) return const [];
    return eyelets
        .where((eyelet) => eyelet.side != WindowSide.top && !eyelet.isCorner)
        .toList(growable: false);
  }

  List<EyeletPlacement> get topEyelets =>
      eyelets.where((eyelet) => eyelet.side == WindowSide.top).toList();

  /// Угловые (круглые) люверсы — по одному на угол, если тумблер включён.
  List<EyeletPlacement> get cornerEyelets =>
      eyelets.where((eyelet) => eyelet.isCorner).toList(growable: false);

  /// Сколько круглых люверсов реально ставится (углы).
  ///
  /// Число берётся из фактических точек, а не из «4 угла»: при выключенном
  /// тумблере, спайке стороны или сторонах без люверсов углов может не быть.
  int get roundEyeletCount =>
      eyelets.where((eyelet) => typeFor(eyelet).isRound).length;

  /// Включён ли тумблер «Круглые люверсы в углах».
  bool get roundEyeletsEnabled => params.roundEyeletsEnabled;

  /// Стороны, на которых люверсы не ставятся (кнопки «не ставить сверху/снизу»).
  ///
  /// Порядок — по обходу углов: низ, право, верх, лево.
  List<WindowSide> get eyeletlessSides => [
    if (params.noEyeletsBottom) WindowSide.bottom,
    if (params.noEyeletsTop) WindowSide.top,
  ];

  /// Подпись сторон без люверсов для документов: «верх», «низ», «низ и верх».
  String get eyeletlessSidesLabel {
    final labels = [for (final side in eyeletlessSides) side.label];
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels.first;
    return '${labels.sublist(0, labels.length - 1).join(', ')} и ${labels.last}';
  }

  /// Ставятся ли на этой стороне люверсы (кнопки «не ставить сверху/снизу»).
  bool sideHasEyelets(WindowSide side) => switch (side) {
    WindowSide.bottom => !params.noEyeletsBottom,
    WindowSide.top => !params.noEyeletsTop,
    WindowSide.left || WindowSide.right => true,
  };

  /// Тип люверса в конкретной точке: в углах круглый (угол тянет
  /// по диагонали, овальный там не держит), по сторонам — выбранный
  /// пользователем тип. Глухое окно больше не заменяет тип принудительно.
  ///
  /// Если тумблер «Круглые люверсы в углах» выключен, угловых точек в
  /// [eyelets] нет, и круглый тип не подставляется нигде.
  EyeletType typeFor(EyeletPlacement eyelet) =>
      eyelet.forcedType ??
      (eyelet.isCorner && params.roundEyeletsEnabled
          ? EyeletType.round10
          : params.effectiveEyeletType);

  /// Крепёж, добавленный вручную на чертеже.
  List<ManualFastener> get manualFasteners => _eyeletResult.manualFasteners;

  /// Люверсы, которые стоят сами по себе — без замка/скобы/ремня в той же
  /// точке. Именно они идут строкой «Люверс» в расходе и смете: замок на
  /// чертеже заменяет люверс, а не добавляется к нему.
  List<EyeletPlacement> get standaloneEyelets {
    if (params.fastenerType == FastenerType.eyeletsOnly) return eyelets;
    final fasteners = movableSideEyelets;
    return [
      for (final eyelet in eyelets)
        if (!fasteners.any(
          (fastener) => (fastener.center - eyelet.center).distance < 1.0,
        ))
          eyelet,
    ];
  }

  /// Все точки крепежа: автомат по типу окна + добавленные вручную.
  int get fastenerPointsCount =>
      (params.fastenerType == FastenerType.eyeletsOnly
          ? 0
          : movableSideEyelets.length) +
      manualFasteners.length;

  /// Тип люверса, который ставится по сторонам окна.
  EyeletType get eyeletType => params.effectiveEyeletType;

  /// Подъёмные ремни: висят сверху вниз, ширина [liftStrapWidth] мм.
  ///
  /// Каждый ремень привязан к ЛИНИИ ТЕНТА на своей высоте: на косом окне
  /// верхняя кромка наклонена, и ремень начинается ровно на ней, а не висит
  /// за окантовкой. Если положения заданы вручную ([WindowParams
  /// .liftStrapOffsets]) — берём их, иначе прежняя автоматическая расстановка.
  List<Rect> get liftStraps {
    if (!params.isLifting && !params.isScreen) return const [];
    final autoCount = params.liftStrapCount;
    final manual = params.liftStrapOffsets;
    if (manual.isEmpty && autoCount <= 0) return const [];
    final bounds = filmVisibleBounds;
    final length = math.min(liftStrapLength, bounds.height * 0.8);
    final minCenter = bounds.left + liftStrapWidth / 2;
    final maxCenter = math.max(bounds.right - liftStrapWidth / 2, minCenter);
    final centers = manual.isNotEmpty
        ? [
            for (final offset in manual)
              (bounds.left + offset).clamp(minCenter, maxCenter).toDouble(),
          ]
        : [
            for (var i = 1; i <= autoCount; i++)
              bounds.left + bounds.width * i / (autoCount + 1),
          ];
    return [
      for (final center in centers)
        Rect.fromLTWH(
          center - liftStrapWidth / 2,
          _tentLineYAt(center) - length,
          liftStrapWidth,
          length,
        ),
    ];
  }

  /// Высота линии тента (внутренней кромки окантовки) при данном x.
  ///
  /// У косого окна линия наклонена: берём верхнее ребро контура окантовки и
  /// интерполируем по нему. Если ребра нет (вырожденный контур) — верх
  /// видимой плёнки.
  double _tentLineYAt(double x) {
    final bounds = filmVisibleBounds;
    final polygons = edgeInnerPolygons;
    if (polygons.isEmpty) return bounds.bottom;
    final polygon = polygons.first;
    double? best;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final minX = math.min(a.dx, b.dx);
      final maxX = math.max(a.dx, b.dx);
      if (x < minX - 1e-6 || x > maxX + 1e-6) continue;
      final dx = b.dx - a.dx;
      final t = dx.abs() < 1e-9 ? 0.0 : (x - a.dx) / dx;
      final y = a.dy + (b.dy - a.dy) * t;
      if (best == null || y > best) best = y;
    }
    return best ?? bounds.bottom;
  }

  /// Нижняя линия плёнки (внутренней кромки) при данном x: для косого окна
  /// низ тоже может быть наклонён.
  double _filmBottomLineYAt(double x) {
    final bounds = filmVisibleBounds;
    final polygons = edgeInnerPolygons;
    if (polygons.isEmpty) return bounds.top;
    final polygon = polygons.first;
    double? best;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final minX = math.min(a.dx, b.dx);
      final maxX = math.max(a.dx, b.dx);
      if (x < minX - 1e-6 || x > maxX + 1e-6) continue;
      final dx = b.dx - a.dx;
      final t = dx.abs() < 1e-9 ? 0.0 : (x - a.dx) / dx;
      final y = a.dy + (b.dy - a.dy) * t;
      if (best == null || y < best) best = y;
    }
    return best ?? bounds.top;
  }

  /// Диапазон x контура на высоте y — чтобы полоса молнии не вылезала за
  /// наклонную боковую кромку.
  ({double left, double right})? _filmXRangeAtY(double y) {
    final polygons = edgeInnerPolygons;
    if (polygons.isEmpty) return null;
    final polygon = polygons.first;
    final xs = <double>[];
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      final minY = math.min(a.dy, b.dy);
      final maxY = math.max(a.dy, b.dy);
      if (y < minY - 1e-6 || y > maxY + 1e-6) continue;
      final dy = b.dy - a.dy;
      final t = dy.abs() < 1e-9 ? 0.0 : (y - a.dy) / dy;
      final x = a.dx + (b.dx - a.dx) * t;
      xs.add(x);
    }
    if (xs.length < 2) return null;
    var left = xs.first;
    var right = xs.first;
    for (final x in xs) {
      if (x < left) left = x;
      if (x > right) right = x;
    }
    return (left: left, right: right);
  }

  /// Полосы тента под все молнии.
  List<Rect> get zipperBands => [for (final line in zippers) _bandOf(line)];

  Rect _bandOf(({Offset start, Offset end, double bandWidth}) line) {
    final half = math.max(line.bandWidth, 20) / 2;
    var left = line.start.dx - half;
    var right = line.start.dx + half;
    var lowY = math.min(line.start.dy, line.end.dy);
    var highY = math.max(line.start.dy, line.end.dy);

    // Косое окно: полоса вертикальная, а тент сверху/снизу наклонён. Подрезаем
    // полосу по внутреннему контуру и при необходимости сдвигаем её внутрь,
    // иначе её углы вылезают за тент.
    final simpleQuad = !isTShape && compositeLayout == null;
    if (simpleQuad && edgeInnerPolygons.isNotEmpty) {
      final bounds = filmVisibleBounds;
      final topRange0 = _filmXRangeAtY(bounds.bottom);
      final bottomRange0 = _filmXRangeAtY(bounds.top);
      if (topRange0 != null && bottomRange0 != null) {
        final minLeft = math.max(topRange0.left, bottomRange0.left);
        final maxRight = math.min(topRange0.right, bottomRange0.right);
        if (maxRight - minLeft > 20) {
          final width = math.min(right - left, maxRight - minLeft);
          var center = (left + right) / 2;
          center = center.clamp(minLeft + width / 2, maxRight - width / 2);
          left = center - width / 2;
          right = center + width / 2;
        }
      }

      final lowEdge = math.max(
        _filmBottomLineYAt(left),
        _filmBottomLineYAt(right),
      );
      final highEdge = math.min(_tentLineYAt(left), _tentLineYAt(right));
      if (highEdge - lowEdge > 10) {
        lowY = math.max(lowY, lowEdge);
        highY = math.min(highY, highEdge);
      }

      final topRange = _filmXRangeAtY(highY);
      final bottomRange = _filmXRangeAtY(lowY);
      if (topRange != null && bottomRange != null) {
        final minLeft = math.max(topRange.left, bottomRange.left);
        final maxRight = math.min(topRange.right, bottomRange.right);
        if (maxRight - minLeft > 10) {
          final width = math.min(right - left, maxRight - minLeft);
          var center = (left + right) / 2;
          center = center.clamp(minLeft + width / 2, maxRight - width / 2);
          left = center - width / 2;
          right = center + width / 2;
        }
      }
    }
    return Rect.fromLTRB(left, lowY, right, highY);
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

    // Составное окно: у каждой части свой материал и свои свободные кромки,
    // шов не окантовывается. У скрин-части — подворот, тента нет.
    final composite = compositeLayout;
    if (composite != null) {
      void addPart(List<Offset> polygon, FilmMaterial material) {
        if (material == FilmMaterial.screen) return;
        for (var i = 0; i < polygon.length; i++) {
          final a = polygon[i];
          final b = polygon[(i + 1) % polygon.length];
          if (isCompositeSeamEdge(a, b)) continue;
          final edgeSide = edgeSideOf(sideOfPolygonEdge(polygon, i));
          final roll = params.rollForSide(edgeSide);
          result[roll] = (result[roll] ?? 0) + (b - a).distance;
        }
      }

      addPart(composite.mainPolygon, params.material);
      addPart(composite.secondPolygon, composite.material);
      for (final cutout in cutouts) {
        final roll = rolls[0];
        result[roll] = (result[roll] ?? 0) + cutout.perimeterMm;
      }
      return result;
    }

    void addPolygon(List<Offset> polygon) {
      for (var i = 0; i < polygon.length; i++) {
        final side = sideOfPolygonEdge(polygon, i);
        final edgeSide = edgeSideOf(side);
        final length =
            (polygon[(i + 1) % polygon.length] - polygon[i]).distance;
        final roll = params.rollForSide(edgeSide);
        result[roll] = (result[roll] ?? 0) + length;
      }
    }

    // У Т-окна окантовка считается по группам частей: сваренные пристройки
    // входят в общий контур (общая сторона — шов, окантовки там нет),
    // а пристройки без спайки — отдельные окна со своим периметром,
    // включая общую линию.
    for (final polygon in groupPolygons) {
      addPolygon(polygon);
    }

    for (final cutout in cutouts) {
      // Осознанное упрощение: контуры вырезов всегда относятся к нижнему
      // рулону (rolls[0]), даже если низ спаян с соседним окном. Вырез
      // обрабатывается той же лентой, что лежит по низу окна; отдельного
      // рулона «под вырезы» в заказе не бывает, а дробить ленту по сторонам
      // из-за вырезов — лишняя путаница в раскрое.
      final roll = rolls[0];
      result[roll] = (result[roll] ?? 0) + cutout.perimeterMm;
    }
    return result;
  }

  /// Длины внешних кромок по сторонам окна, мм.
  ///
  /// У Т-окна на одной стороне может быть несколько отрезков (низ основного
  /// полотна плюс низ приставки) — они суммируются. Это длины ИЗДЕЛИЯ: без
  /// вычета спаек.
  Map<EdgeSide, double> get edgeLengthsBySide {
    final result = <EdgeSide, double>{
      for (final side in EdgeSide.values) side: 0.0,
    };
    void addPolygon(List<Offset> polygon) {
      for (var i = 0; i < polygon.length; i++) {
        final edgeSide = edgeSideOf(sideOfPolygonEdge(polygon, i));
        final length =
            (polygon[(i + 1) % polygon.length] - polygon[i]).distance;
        result[edgeSide] = (result[edgeSide] ?? 0) + length;
      }
    }

    for (final polygon in groupPolygons) {
      addPolygon(polygon);
    }
    return result;
  }

  /// Спаяна ли кромка внешнего контура с индексом обхода.
  ///
  /// Спайка с соседним окном удалена — всегда false. Метод оставлен ради
  /// старых вызовов в документах и тестах.
  bool isSideWelded(int index) => false;

  /// Длина швов, мм: только общие стороны пристроек Т-окна.
  ///
  /// Спайка с соседним окном удалена; шов составного окна считается отдельно
  /// ([WindowSpec.compositeSeamLength]).
  double get weldLengthMm =>
      isTShape ? tLayout!.weldedSeamLength : 0;

  /// Готовые подписи расхода окантовки: «Тент 100 мм — 654 см».
  List<String> get edgeConsumptionLabels {
    final entries = edgeConsumption.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        '${edgeBandLabel(entry.key)} — ${formatMm(entry.value)} ${unitSuffix()}',
    ];
  }

  /// Дренажные отверстия в нижней окантовке.
  List<Offset> get drainHoles {
    final count = params.drainCount.round();
    // У скрина нет нижней окантовки — пробивать дренаж не во что.
    if (!params.drainHoles || count <= 0 || isScreen) return const [];

    final bottomEyelets =
        eyelets
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
        final index = (k * middles.length / (count + 1)).floor().clamp(
          0,
          middles.length - 1,
        );
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
  ///
  /// У скрина видимый контур — готовое изделие (кромка подворота), поэтому
  /// полоса молнии целиком лежит внутри заготовки: заготовка больше готового
  /// размера на прибавку по каждой оси ([hemOutsetWidths]).
  /// Положение зажато в границах видимого контура (см. [_zipperOf]).
  List<({Offset start, Offset end, double bandWidth})> get zippers => [
    for (final spec in params.zippers) _zipperOf(spec),
  ];

  ({Offset start, Offset end, double bandWidth}) _zipperOf(ZipperSpec spec) {
    // Для скрина это кромка подворота: полоса не выходит за заготовку и не
    // заходит на сам подворот.
    final bounds = filmVisibleBounds;
    // У края сторона задаётся явно: так две молнии могут стоять и слева,
    // и справа, не перекрывая друг друга.
    final onLeft = spec.atEdge ? !spec.edgeRight : () {
      final requested = spec.centered
          ? bounds.center.dx
          : bounds.left + spec.offsetMm;
      return requested < bounds.center.dx;
    }();
    // У края в полосу входит готовая окантовка этой стороны.
    final edgeFinished = onLeft ? finishedWidths[3] : finishedWidths[1];
    final band = spec.bandWidthFor(edgeFinished);
    final half = math.max(band, 20) / 2;
    final x = spec.atEdge
        ? (onLeft ? bounds.left + half : bounds.right - half)
        : (spec.centered
              ? bounds.center.dx
              : bounds.left + spec.offsetMm)
              .clamp(bounds.left + half, bounds.right - half);
    return (
      start: Offset(x, bounds.top),
      end: Offset(x, bounds.bottom),
      bandWidth: band,
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

  /// Ширина полосы фартука (бывшего кармана) для стороны, мм.
  ///
  /// У ПВХ это готовая ширина фартука [WindowParams.pocketWidth]
  /// (рулон 200 мм, сложенный пополам). У скрина отдельного тента нет:
  /// фартук образуется подворотом, поэтому его полоса равна подвороту
  /// соответствующей стороны.
  double pocketBandWidth(WindowSide side) => params.isScreen
      ? switch (side) {
          WindowSide.bottom => params.hemBottomMm,
          WindowSide.right => params.hemRightMm,
          WindowSide.top => params.hemTopMm,
          WindowSide.left => params.hemLeftMm,
        }
      : params.pocketWidth;

  /// Полоса фартука (бывшего кармана) по стороне — четырёхугольник по контуру.
  ///
  /// По описанию заказчика полоса идёт **от внутреннего края окантовки до
  /// внешнего края и немного ниже (выше)**: то есть начинается на линии
  /// внутреннего края тента (`edgeInner`, у скрина — на линии подворота
  /// `screenHemLine`), закрывает всю полосу окантовки и уходит за внешний
  /// край ещё на [WindowParams.pocketWidth].
  ///
  /// Четырёхугольник (а не прямоугольник) нужен для косого окна: верхняя
  /// кромка трапеции наклонена, и полоса должна лежать параллельно ей.
  /// Углы возвращаются в порядке обхода углов окна (низ, право, верх, лево).
  List<Offset> pocketBand(WindowSide side) {
    final enabled = switch (side) {
      WindowSide.bottom => params.pocket,
      WindowSide.top => params.pocketTop,
      WindowSide.right || WindowSide.left => false,
    };
    if (!enabled) return const [];
    // У Т-окна без спайки хотя бы одной пристройки фартук не поддерживается:
    // полосы частей пересекаются на общей стороне и полоса рвётся.
    if (isTShape && !tAllWelded) return const [];
    // Пристройка на той же стороне перекрывает кромку основного полотна —
    // фартук по этой стороне не строится (см. проверку параметров).
    final t = tLayout;
    if (t != null) {
      final blocked = t.annexes.any(
        (annex) => switch (side) {
          WindowSide.bottom => annex.side == TShapeSide.bottom,
          WindowSide.top => annex.side == TShapeSide.top,
          WindowSide.left => annex.side == TShapeSide.left,
          WindowSide.right => annex.side == TShapeSide.right,
        },
      );
      if (blocked) return const [];
    }

    final index = switch (side) {
      WindowSide.bottom => 0,
      WindowSide.right => 1,
      WindowSide.top => 2,
      WindowSide.left => 3,
    };
    final a = outer[index];
    final b = outer[(index + 1) % outer.length];

    // Внутренняя граница полосы: у ПВХ — внутренний край окантовки,
    // у скрина — линия подворота (готовый контур изделия).
    final innerA = isScreen ? screenHemLine[index] : edgeInner[index];
    final innerB = isScreen
        ? screenHemLine[(index + 1) % screenHemLine.length]
        : edgeInner[(index + 1) % edgeInner.length];

    // Наружная граница: у ПВХ внешний край тента плюс ширина фартука,
    // у скрина — край заготовки (полоса подворота уже лежит снаружи контура).
    late final Offset outerA;
    late final Offset outerB;
    if (isScreen) {
      outerA = filmEdge[index];
      outerB = filmEdge[(index + 1) % filmEdge.length];
    } else {
      final direction = b - a;
      final length = direction.distance;
      if (length < 1e-9) return const [];
      final unit = direction / length;
      // Наружная нормаль при обходе против часовой стрелки — (dy, −dx).
      final outward = Offset(unit.dy, -unit.dx);
      final width = params.pocketWidth.isFinite && params.pocketWidth > 0
          ? params.pocketWidth
          : 0.0;
      outerA = a + outward * width;
      outerB = b + outward * width;
    }

    return [innerA, innerB, outerB, outerA];
  }

  /// Габарит нижнего фартука (для подписей и старых тестов).
  ///
  /// Полоса идёт от внутреннего края нижней окантовки (`finishedWidths[0]`)
  /// до внешнего края и ниже на ширину фартука.
  Rect get pocketRect =>
      params.pocket ? boundsOf(pocketBand(WindowSide.bottom)) : Rect.zero;

  /// Габарит верхнего фартука — зеркало нижнего.
  Rect get pocketTopRect =>
      params.pocketTop ? boundsOf(pocketBand(WindowSide.top)) : Rect.zero;

  /// Угол касается стороны, которая расставлена вручную.
  bool _cornerTouchesManualSide(Offset vertex) {
    if (params.manualEyeletSides.isEmpty) return false;
    final polygons = eyeletPolygons;
    if (polygons.isEmpty) return false;
    final polygon = polygons.first;
    for (var i = 0; i < polygon.length; i++) {
      final edgeSide = edgeSideOf(sideOfPolygonEdge(polygon, i));
      if (!params.manualEyeletSides.contains(edgeSide)) continue;
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if ((vertex - a).distance < 1e-6 || (vertex - b).distance < 1e-6) {
        return true;
      }
    }
    return false;
  }

  _EyeletResult _computeEyelets() {
    final placements = <EyeletPlacement>[];
    final steps = <double>[];
    final manualFasteners = <ManualFastener>[];

    // Люверсы ставятся по каждому контуру: у обычного окна он один, у Т-окна
    // со спайкой — общий внешний, без спайки — по периметру каждой части.
    for (final polygon in eyeletPolygons) {
      for (var i = 0; i < polygon.length; i++) {
        final a = polygon[i];
        final b = polygon[(i + 1) % polygon.length];
        // Шов составного окна — не кромка: крепёж по нему не ставится,
        // иначе люверсы/замки задваивались бы с обеих сторон стыка.
        if (isCompositeSeamEdge(a, b)) continue;
        final side = sideOfPolygonEdge(polygon, i);

        final direction = b - a;
        final length = direction.distance;
        if (length < 1) continue;
        final unit = direction / length;
        final angle = math.atan2(unit.dy, unit.dx);

        // Ручные точки: если сторону правили на чертеже, ставим ровно их
        // (включая пустой список — «на этой стороне люверсов нет»).
        final manualSide = params.hasManualEyelets(edgeSideOf(side));
        if (manualSide && !isTShape && !isComposite) {
          final points = params.eyeletPositions
              .where((position) => position.side == edgeSideOf(side))
              .toList()
            ..sort((left, right) => left.fraction.compareTo(right.fraction));
          for (final point in points) {
            final fraction = point.fraction.clamp(0.0, 1.0);
            final center = a + unit * (length * fraction);
            if (isOnCompositeSeam(center)) continue;
            final isCornerPoint = fraction < 0.005 || fraction > 0.995;
            // Замок/скоба ЗАМЕНЯЮТ люверс в этой точке, а не добавляются к
            // нему: иначе в смете остаётся строка круглых люверсов, которых
            // на изделии нет.
            if (point.kind == MarkerKind.frenchLock ||
                point.kind == MarkerKind.turnBuckle) {
              manualFasteners.add(
                ManualFastener(
                  center: center,
                  side: side,
                  angle: angle,
                  type: point.kind == MarkerKind.frenchLock
                      ? FastenerType.frenchLocks
                      : FastenerType.turnBuckles,
                ),
              );
              continue;
            }
            placements.add(
              EyeletPlacement(
                center: center,
                side: side,
                angle: angle,
                isCorner: isCornerPoint,
                positionInEdge: fraction,
                forcedType: point.kind == MarkerKind.roundEyelet
                    ? EyeletType.round10
                    : null,
              ),
            );
          }
          continue;
        }

        final offset = params.eyeletCornerOffset.clamp(
          0.0,
          math.max(length / 2 - 1, 0),
        );
        final usable = length - offset * 2;
        // Интервал задаёт пользователь ([WindowParams.eyeletStep], 50…2000 мм).
        // Жёсткого «рекомендованного» коридора здесь нет: берём ровно введённое
        // число. Защищаемся только от нуля/NaN/отрицательного значения — иначе
        // деление даст бесконечность, и минимум 50 мм.
        final requested = params.eyeletStep;
        final nominal = requested.isFinite && requested >= minEyeletStepMm
            ? requested
            : minEyeletStepMm;
        // Число интервалов округляем ВВЕРХ: тогда фактический интервал
        // usable / intervals получается НЕ БОЛЬШЕ заданного, и «хвоста» в углу
        // нет. Именно поэтому это «примерный интервал»: задан 300 мм — фактически
        // 269…291 мм по сторонам.
        // Если заданный интервал больше стороны (1500 мм на стороне 800 мм),
        // получается ровно один интервал: по люверсу в каждом углу стороны.
        final intervals = math.max(1, (usable / nominal).ceil());
        final actual = usable / intervals;
        // Сторона без люверсов (кнопка «не ставить сверху/снизу») в подпись
        // фактического интервала не попадает: крепежа там нет.
        if (sideHasEyelets(side)) steps.add(actual);

        // Аварийный предел: при ошибочном размере (например, лишние нули)
        // миллионы люверсов кладут браузер. Рабочие окна далеки от предела.
        if (placements.length > 6000) break;
        for (var k = 0; k <= intervals; k++) {
          // Точки стороны идут строго с равным шагом [actual] от отступа
          // [offset]: k = 0 — начало стороны, k = intervals — её конец. Никаких
          // дополнительных «угловых» точек сверх этой последовательности нет,
          // поэтому расстановка детерминирована: при одном и том же отступе
          // люверсы всегда в одних и тех же координатах.
          var distance = offset + actual * k;
          // Угол — это точка, стоящая в самом углу полотна. При отступе
          // [eyeletCornerOffset] > 0 концы стороны сдвинуты внутрь и углами уже
          // не являются: иначе при отступе 50 мм на чертеже появлялись бы
          // «лишние» круглые люверсы у каждого угла (по два на угол).
          final isCornerIndex = offset < 0.5 && (k == 0 || k == intervals);
          // Соседняя сторона правится вручную — не ставим自動 угловую точку
          // на общем углу, иначе после перетаскивания в углу будет два люверса.
          if (isCornerIndex &&
              _cornerTouchesManualSide(
                k == 0 ? polygon[i] : polygon[(i + 1) % polygon.length],
              )) {
            continue;
          }

          // Тумблер «Круглые люверсы в углах» выключен: угловая точка не
          // ставится вовсе — ни на чертеже, ни в расходе, ни в смете.
          // Точки, сдвинутые от угла на [offset] > 0, — обычные точки стороны,
          // их выключение не трогает: там уже не угол.
          if (!params.roundEyeletsEnabled && isCornerIndex && offset < 0.5) {
            continue;
          }

          // Фартук (бывший карман) снизу: угловые люверсы внизу не ставим, а
          // боковые поднимаем, чтобы в полость фартука заводился утяжитель.
          // Фартук сверху — зеркально: углы сверху убираем, боковые опускаем.
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

          final center = a + unit * distance;
          // Точка ровно на шве составного окна — это стык, а не кромка:
          // люверс там не ставится (иначе он задваивался бы).
          if (isOnCompositeSeam(center)) continue;
          placements.add(
            EyeletPlacement(
              center: center,
              side: side,
              angle: angle,
              isCorner: isCornerIndex,
              positionInEdge: distance / length,
            ),
          );
        }
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

    // Стороны без люверсов: сторона и её угловые точки исключаются.
    //
    // Угол принадлежит стороне, которая идёт первой в обходе
    // (низ → право → верх → лево): у низа это оба нижних угла, у права —
    // правый верхний, у верха — левый верхний. Поэтому у выключенной стороны
    // пропадают её крепления вместе с её углами, а соседние стороны свои углы
    // сохраняют. Крепёж считается уменьшенным предсказуемо — см. тесты.
    final visible = [
      for (final eyelet in merged)
        if (sideHasEyelets(eyelet.side)) eyelet,
    ];

    return _EyeletResult(visible, steps, manualFasteners);
  }
}

class _EyeletResult {
  const _EyeletResult(this.placements, this.steps, this.manualFasteners);

  final List<EyeletPlacement> placements;
  final List<double> steps;
  final List<ManualFastener> manualFasteners;
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

  /// Т-образное окно.
  bool get isTShape => params.isTShape;

  /// Составное окно: ПВХ-полотно плюс второй материал по общему шву.
  bool get isComposite => params.isComposite;

  /// Геометрия составного окна (null у остальных типов).
  CompositeLayout? get compositeLayout => geometry.compositeLayout;

  /// Линия шва составного окна (две точки).
  List<Offset> get compositeSeam => compositeLayout?.seam ?? const [];

  /// Длина шва составного окна, мм.
  double get compositeSeamLength => compositeLayout?.seamLength ?? 0;

  /// Площадь второго сегмента, м².
  double get compositeSecondAreaM2 =>
      (compositeLayout?.secondAreaMm2 ?? 0) / 1000000;

  /// Периметр свободных кромок второго сегмента, мм (без шва).
  double get compositeSecondFreePerimeterMm {
    final composite = compositeLayout;
    if (composite == null) return 0;
    final polygon = composite.secondPolygon;
    var total = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if (layers.isCompositeSeamEdge(a, b)) continue;
      total += (b - a).distance;
    }
    return total;
  }

  /// Периметр свободных кромок основного полотна, мм (без шва).
  double get compositeMainFreePerimeterMm {
    final composite = compositeLayout;
    if (composite == null) return 0;
    final polygon = composite.mainPolygon;
    var total = 0.0;
    for (var i = 0; i < polygon.length; i++) {
      final a = polygon[i];
      final b = polygon[(i + 1) % polygon.length];
      if (layers.isCompositeSeamEdge(a, b)) continue;
      total += (b - a).distance;
    }
    return total;
  }

  /// Площади заготовок к раскрою с усадкой по частям: [основное, второе].
  ///
  /// Порядок совпадает с [WindowLayers.filmPolygons]; вырезы вычитаются из
  /// основного полотна.
  List<double> get compositeFilmPartAreasM2 {
    final polygons = filmCutPolygonsWithShrinkage;
    if (polygons.length < 2) return const [];
    final cutouts = layers.cutoutAreaMm2 / 1000000;
    final main = polygonArea(polygons[0]).abs() / 1000000 - cutouts;
    return [
      main < 0 ? 0 : main,
      polygonArea(polygons[1]).abs() / 1000000,
    ];
  }

  /// Геометрия Т-окна (null у обычного).
  TShapeLayout? get tLayout => geometry.tLayout;

  /// Длина общей стороны (шва) первой пристройки, мм.
  double get tSharedLength => tLayout?.firstAnnex?.sharedLength ?? 0;

  /// Суммарная длина швов по всем пристройкам, мм.
  double get tSeamsLength => tLayout?.allSeamsLength ?? 0;

  /// Длина только сваренных швов по пристройкам, мм.
  double get tWeldedSeamLength => tLayout?.weldedSeamLength ?? 0;

  /// Пристройки Т-окна (пусто у обычного окна).
  List<TShapeAnnexLayout> get tAnnexes =>
      tLayout?.annexes ?? const <TShapeAnnexLayout>[];

  /// Предупреждение о конфликте пристроек; null — всё в порядке.
  ///
  /// Две пристройки на одной стороне запрещены: в расчёте остаётся только
  /// первая, а панель и проверка параметров объясняют, что поменять.
  String? get tAnnexConflict {
    if (!params.isTShape) return null;
    if (params.tAnnexSideConflict) {
      return 'Пристройки 1 и 2 стоят на одной стороне — так нельзя. '
          'В расчёте оставлена только пристройка 1: выберите для второй '
          'другую сторону.';
    }
    if (tLayout?.ignoredOverlap ?? false) {
      return 'Пристройки пересекаются — так нельзя. В расчёте оставлена '
          'только первая: сдвиньте вторую вдоль её стороны.';
    }
    if (tLayout?.ignoredSecondAnnex ?? false) {
      return 'Вторая пристройка не построена: она стоит на одной стороне '
          'с первой.';
    }
    return null;
  }

  /// Габариты заготовок по частям: [основное, пристройка 1, пристройка 2]
  /// или [общий] у обычного окна.
  List<Rect> get filmPartBounds => layers.filmPartBounds;

  /// Периметр, по которому идёт окантовка/подворот: у Т-окна без спайки —
  /// сумма периметров каждой части, со спайкой — внешний контур.
  double get edgePerimeterMm =>
      layers.edgeLengthsBySide.values.fold(0.0, (sum, value) => sum + value);

  /// Подпись Т-окна для панели, чертежа и документов.
  String get tShapeSummary {
    final t = tLayout;
    if (t == null) return '—';
    final parts = <String>[
      'основное ${formatMm(params.bottomWidth)} × '
          '${formatMm(params.leftHeight)} ${unitSuffix()}',
      for (final annex in t.annexes)
        '${annex.number == 1 ? 'пристройка 1' : 'пристройка 2'} '
            '${formatMm(annex.rect.width)} × ${formatMm(annex.rect.height)} ${unitSuffix()} '
            '${annex.side.label.toLowerCase()}, смещение '
            '${formatMm(annex.offset)} ${unitSuffix()}',
    ];
    final welded = t.weldedAnnexes;
    final separate = t.separateAnnexes;
    final details = <String>[];
    if (welded.isNotEmpty) {
      details.add(
        'швы по общей стороне: '
        '${welded.map((annex) => '${formatMm(annex.sharedLength)} ${unitSuffix()}').join(' и ')}',
      );
    }
    if (separate.isNotEmpty) {
      details.add(
        'без спайки — отдельные окна: '
        '${separate.map((annex) => annex.label.toLowerCase()).join(', ')}',
      );
    }
    final conflict = tAnnexConflict;
    return 'Т-образное: ${parts.join(' + ')}; '
        '${details.isEmpty ? 'пристроек нет' : details.join('; ')}'
        '${conflict == null ? '' : '; $conflict'}';
  }

  /// Площадь ЗАГОТОВКИ ПОЛОТНА (с напайкой/подворотом, без припуска), м².
  ///
  /// Считается по формуле Гаусса для фактического контура заготовки
  /// ([WindowLayers.blankGeometry]): у косого окна это трапеция, а не
  /// прямоугольник по габариту. Для денег берётся заготовка
  /// ([filmCutAreaWithShrinkageM2]) — она же плюс припуск и усадка.
  double get filmAreaM2 => layers.filmAreaM2;

  /// Стороны заготовки по обходу: низ, право, верх, лево (мм).
  ///
  /// Номинальные значения по формуле заказчика:
  /// `сторона изделия − 2 × (готовая полоса) + 2 × запайка`.
  List<double> get blankSideLengths => layers.blankSideLengths;

  /// Стороны заготовки К РАСКРОЮ с припуском и усадкой, мм.
  ///
  /// Порядок прежний: низ, право, верх, лево. Ширины (низ/верх) растянуты на
  /// припуск по ширине, высоты (право/лево) — на припуск по высоте; усадка
  /// умножает обе оси. Для прямоугольного окна это ровно прежние
  /// `[ширина, высота, ширина, высота]`.
  List<double> get filmCutSideLengths {
    final blank = layers.blankGeometry;
    final bounds = layers.filmCutBounds;
    final targetWidth = filmCutWidth + params.allowanceWidthMm;
    final targetHeight = bounds.height + params.effectiveAllowanceHeightMm;
    final sx = bounds.width > 1e-9 ? targetWidth / bounds.width : 1.0;
    final sy = bounds.height > 1e-9 ? targetHeight / bounds.height : 1.0;
    final shrink = 1 + params.effectiveShrinkagePercent / 100;
    final fx = sx.isFinite && sx > 0.05 ? sx : 1.0;
    final fy = sy.isFinite && sy > 0.05 ? sy : 1.0;
    return [
      blank.bottomWidth * fx * shrink,
      blank.rightHeight * fy * shrink,
      blank.topWidth * fx * shrink,
      blank.leftHeight * fy * shrink,
    ];
  }

  /// Заготовка косой формы: стороны низа/верха или высоты слева/справа
  /// отличаются. Прямоугольное окно по-прежнему кроится прямоугольником.
  bool get isObliqueBlank =>
      !isTShape &&
      !isComposite &&
      ((params.bottomWidth - params.topWidth).abs() > 0.5 ||
          (params.leftHeight - params.rightHeight).abs() > 0.5);

  /// Подпись сторон заготовки: «низ 2 990, право 2 740, верх 2 990,
  /// лево 2 080 мм».
  String get blankSidesLabel {
    final sides = blankSideLengths;
    return 'низ ${formatMm(sides[0])}, право ${formatMm(sides[1])}, '
        'верх ${formatMm(sides[2])}, лево ${formatMm(sides[3])} '
        '${unitSuffix()}';
  }

  /// Подпись сторон заготовки К РАСКРОЮ (с припуском и усадкой).
  String get filmCutSidesLabel {
    final sides = filmCutSideLengths;
    return 'низ ${formatMm(sides[0])}, право ${formatMm(sides[1])}, '
        'верх ${formatMm(sides[2])}, лево ${formatMm(sides[3])} '
        '${unitSuffix()}';
  }

  /// Видимый размер плёнки (по внутренней границе окантовки).
  double get filmVisibleWidth => layers.filmVisibleBounds.width;
  double get filmVisibleHeight => layers.filmVisibleBounds.height;

  /// Раскрой полотна.
  ///
  /// Для ПВХ: видимый размер плюс запайка [WindowParams.weldOverlapMm] с двух
  /// сторон — плёнка заходит под окантовку.
  ///
  /// Для скрина: готовый размер плюс ПОЛОВИНА подворота каждой стороны
  /// ([WindowParams.hemAxisBottomTopIncrease] /
  /// [WindowParams.hemAxisLeftRightIncrease]); к высоте добавляется ещё
  /// 20 мм. Скрин 1000 × 1000 при подворотах 80/80/120/80 даёт
  /// 1080 × 1120 мм; на изделии 2000 × 2000 подвороты 80 на все стороны —
  /// 2080 × 2100 мм, 120 на все стороны — 2120 × 2140 мм.
  ///
  /// Если есть молнии, из ширины ВЫЧИТАЕТСЯ суммарная ширина их полос
  /// ([zipperBandTotalMm]): заказчик кроит полотно уже на полосу, потому что
  /// полоса молнии выкраивается из того же полотна. Это правило общее для
  /// всех материалов: 2080 мм с полосой 50 мм дают 2030 мм, две полосы по
  /// 50 мм — 1980 мм. У ПВХ 2000 мм с окантовкой 100 и запайкой 5 мм дают
  /// 1910 мм без молнии, 1860 мм с полосой 50 мм и 1810 мм с двумя полосами.
  /// Высота не меняется: полоса идёт по всей высоте полотна.
  ///
  /// Припуск на раскрой здесь ещё не учтён.
  double get filmCutWidth => layers.blankWidth;
  double get filmCutHeight => layers.blankHeight;

  /// Ширина заготовки ДО вычета полос молний, мм (без припуска).
  ///
  /// Нужна для честной формулы в панели: «2000 + 2 × 40 − полоса 50».
  double get filmCutWidthBeforeZipper => layers.filmCutBounds.width;

  /// Готовая подпись вычета полосы молнии из ширины кроя:
  /// «ширина 1 910 → 1 860 мм, минус полоса молнии 50 мм».
  ///
  /// Одна формулировка на все листы (панель, «Раскрой», чертёж, техкарта),
  /// чтобы у ПВХ и скрина вычет читался одинаково. Показаны ширины ДО
  /// припуска на раскрой: вычет полосы идёт первым, припуск — отдельным
  /// слагаемым. null — молний нет.
  String? get zipperWidthReductionLabel {
    final total = zipperBandTotalMm;
    if (!(total > 0)) return null;
    return 'ширина ${formatMm(filmCutWidthBeforeZipper)}'
        ' → ${formatMm(filmCutWidth)} ${unitSuffix()}, минус полоса молнии '
        '${formatMm(total)} ${unitSuffix()}';
  }

  /// Заготовка плёнки к раскрою с припуском, без усадки, мм.
  ///
  /// Припуск на раскрой добавляется ТОЛЬКО к заготовке: изделие, чертёж,
  /// окантовка и люверсы считаются по основным размерам. По высоте берётся
  /// фактический припуск [WindowParams.effectiveAllowanceHeightMm]: ручной
  /// плюс авто +10 мм для ПВХ ([pvcHeightAllowanceMm]); у скрина авто-части
  /// нет, поэтому его высота считается как раньше.
  double get filmCutWidthWithAllowance =>
      filmCutWidth + params.allowanceWidthMm;
  double get filmCutHeightWithAllowance =>
      filmCutHeight + params.effectiveAllowanceHeightMm;

  /// Добавка к габариту заготовки скрина от наклона сторон, мм.
  ///
  /// У прямоугольника её нет: габарит заготовки = готовый размер + прибавка по
  /// оси. У трапеции и у окна с разными высотами вычисленные стороны
  /// заготовки могут дать по габариту чуть больше, чем «готовый габарит плюс
  /// половины подворотов». Эти «лишние» миллиметры показываем отдельным
  /// слагаемым, чтобы формула не выдавала необъяснимое число.
  double get _widthSlopeExtra =>
      filmCutWidthBeforeZipper -
      geometry.spanX -
      params.hemAxisLeftRightIncrease;

  double get _heightSlopeExtra =>
      filmCutHeight - geometry.spanY - params.hemAxisBottomTopIncrease;

  /// Добавка к ширине габарита заготовки от наклона боковых сторон, мм.
  ///
  /// Ноль у прямоугольника; у трапеции положительная — по ней видно, почему
  /// габарит заготовки больше «готовый размер + половины подворотов».
  double get widthSlopeExtraMm => _widthSlopeExtra;

  /// Добавка к высоте габарита заготовки от наклона верхней стороны, мм.
  double get heightSlopeExtraMm => _heightSlopeExtra;

  String _slopeExtraLabel(double extra, String sides) =>
      extra.abs() < 0.5 ? '' : ' + ${formatMm(extra)} (наклон $sides)';

  /// Человеческий расчёт высоты заготовки скрина для панели:
  /// «Высота: 1 000 + 40 + 60 + 20 = 1 120 мм».
  ///
  /// В заготовку идёт половина подворота каждой стороны, к высоте добавляется
  /// постоянные +20 мм на шов и запас ([screenHemAxisExtraMm]). Припуск на
  /// раскрой, если он задан, идёт отдельным слагаемым. У окна с разными
  /// высотами слева/справа наклон верхней стороны даёт добавочное слагаемое.
  String get screenBlankHeightFormulaLabel {
    final allow = params.hasAllowance
        ? ' + припуск ${formatMm(params.allowanceHeightMm)}'
        : '';
    final slope = _slopeExtraLabel(_heightSlopeExtra, 'верхней стороны');
    return 'Высота: ${formatMm(geometry.spanY)} + '
        '${formatMmTrimmed(params.hemBottomHalfMm)} + '
        '${formatMmTrimmed(params.hemTopHalfMm)} + '
        '${formatMm(screenHemAxisExtraMm)}$slope$allow = '
        '${formatMm(filmCutHeightWithAllowance)} ${unitSuffix()}';
  }

  /// Человеческий расчёт ширины заготовки скрина для панели:
  /// «Ширина: 1 000 + 40 + 40 = 1 080 мм».
  ///
  /// Смысл тот же, что у [screenBlankHeightFormulaLabel], только по ширине
  /// добавки +20 мм нет. Если у скрина есть молнии, из ширины вычитается
  /// суммарная ширина их полос — это видно прямо в формуле:
  /// «Ширина: 2 000 + 40 + 40 − полоса молнии 50 = 2 030 мм».
  /// У трапеции наклон боковых сторон добавляет к габариту отдельное
  /// слагаемое.
  String get screenBlankWidthFormulaLabel {
    final allow = params.hasAllowance
        ? ' + припуск ${formatMm(params.allowanceWidthMm)}'
        : '';
    final zipper = zipperBandTotalMm > 0
        ? ' − полоса молнии ${formatMm(zipperBandTotalMm)}'
        : '';
    final slope = _slopeExtraLabel(_widthSlopeExtra, 'боковых сторон');
    return 'Ширина: ${formatMm(geometry.spanX)} + '
        '${formatMmTrimmed(params.hemLeftHalfMm)} + '
        '${formatMmTrimmed(params.hemRightHalfMm)}$slope$zipper$allow = '
        '${formatMm(filmCutWidthWithAllowance)} ${unitSuffix()}';
  }

  /// Суммарная ширина полос всех молний окна, мм.
  ///
  /// См. [WindowLayers.zipperBandTotalMm]: именно на эту величину сужена
  /// заготовка — и у скрина, и у ПВХ.
  double get zipperBandTotalMm => layers.zipperBandTotalMm;

  /// Заготовка полотна с припуском на раскрой и компенсацией усадки, мм.
  ///
  /// Усадка берётся из [WindowParams.effectiveShrinkagePercent]: у скрина её
  /// нет (0 %), у ПВХ — поле окна.
  double get filmCutWidthWithShrinkage =>
      filmCutWidthWithAllowance * (1 + params.effectiveShrinkagePercent / 100);
  double get filmCutHeightWithShrinkage =>
      filmCutHeightWithAllowance * (1 + params.effectiveShrinkagePercent / 100);

  /// Контур заготовки к раскрою: [WindowLayers.filmEdge], растянутый на
  /// припуск на раскрой.
  ///
  /// Форма сохраняется: у прямоугольного окна это прямоугольник, у трапеции
  /// и окна с разными высотами — косой четырёхугольник, у Т-окна —
  /// прямоугольники частей (сваренные объединены в общий контур). Припуск по
  /// ширине и высоте — прибавка к габариту, поэтому контур растягивается
  /// относительно центра своего габарита: ширина становится
  /// `filmCutWidth + allowanceWidthMm`, высота —
  /// `filmCutHeight + effectiveAllowanceHeightMm`.
  ///
  /// Полоса молнии уже учтена в [filmCutWidth]: до припуска контур сжимается
  /// по ширине на [zipperBandTotalMm] (у ПВХ и у скрина одинаково).
  List<List<Offset>> get filmCutPolygons {
    final polygons = layers.filmPolygons;
    if (polygons.isEmpty) return const [];
    final bounds = layers.filmCutBounds;
    final width = bounds.width;
    final height = bounds.height;
    // Целевая ширина без полос молний: полосы у края срезаются по краям
    // (см. ниже), а не растягивают/сжимают всё полотно пропорционально.
    final targetWidth = filmCutWidthBeforeZipper + params.allowanceWidthMm;
    final sx = width > 1e-9 ? targetWidth / width : 1.0;
    final sy = height > 1e-9
        ? (height + params.effectiveAllowanceHeightMm) / height
        : 1.0;
    final fx = sx.isFinite && sx > 0.05 ? sx : 1.0;
    final fy = sy.isFinite && sy > 0.05 ? sy : 1.0;
    final center = bounds.center;
    // Контуры растягиваются вокруг ОБЩЕГО центра габарита: так у Т-окна без
    // спайки обе части сохраняют взаимное положение, а не «разъезжаются».
    final scaled = [
      for (final polygon in polygons)
        [
          for (final point in polygon)
            Offset(
              center.dx + (point.dx - center.dx) * fx,
              center.dy + (point.dy - center.dy) * fy,
            ),
        ],
    ];

    // Молнии вплотную к окантовке срезают полотно у краёв на свою полосу.
    var leftTrim = 0.0;
    var rightTrim = 0.0;
    for (final gap in layers.zipperSegmentLayout) {
      if (!gap.edge) continue;
      if (gap.center < layers.filmVisibleBounds.center.dx) {
        leftTrim += gap.bandWidth;
      } else {
        rightTrim += gap.bandWidth;
      }
    }
    var pieces = scaled;
    if (leftTrim > 0 || rightTrim > 0) {
      final scaledBounds = boundsOfAll(scaled);
      pieces = [
        for (final polygon in scaled)
          _trimPolygon(
            polygon,
            scaledBounds.left + leftTrim,
            scaledBounds.right - rightTrim,
          ),
      ];
    }

    // Раскрой всегда режется на сегменты по зазорам молний.
    if (isComposite || params.zippers.isEmpty) {
      return pieces;
    }
    final gaps = layers.zipperSegmentLayout
        .where((gap) => !gap.edge)
        .toList()
      ..sort((a, b) => a.center.compareTo(b.center));
    if (gaps.isEmpty) return pieces;

    // Зазор — это абсолютная координата полосы: он не должен сжиматься
    // вместе с общим габаритом (иначе теряются миллиметры между сегментами).
    double mapX(double x) => center.dx + (x - center.dx) * fx;

    final result = <List<Offset>>[];
    for (final polygon in pieces) {
      var remaining = <List<Offset>>[polygon];
      for (final gap in gaps) {
        final leftEdge = mapX(gap.gapStart);
        final rightEdge = mapX(gap.gapEnd);
        final next = <List<Offset>>[];
        for (final piece in remaining) {
          final left = _clipVertical(piece, leftEdge, keepLeft: true);
          final right = _clipVertical(piece, rightEdge, keepLeft: false);
          if (left.length >= 3 && polygonArea(left).abs() > 1) {
            result.add(left);
          }
          if (right.length >= 3) next.add(right);
        }
        remaining = next;
      }
      for (final piece in remaining) {
        if (piece.length >= 3 && polygonArea(piece).abs() > 1) {
          result.add(piece);
        }
      }
    }
    return result;
  }

  /// Срезает контур слева и справа до [leftX]..[rightX].
  List<Offset> _trimPolygon(List<Offset> polygon, double leftX, double rightX) {
    var result = _clipVertical(polygon, leftX, keepLeft: false);
    if (result.length >= 3) {
      result = _clipVertical(result, rightX, keepLeft: true);
    }
    return result;
  }

  /// Отрезает часть контура по вертикальной прямой x = [x].
  List<Offset> _clipVertical(
    List<Offset> polygon,
    double x, {
    required bool keepLeft,
  }) {
    double side(Offset point) => keepLeft ? (x - point.dx) : (point.dx - x);
    final result = <Offset>[];
    for (var i = 0; i < polygon.length; i++) {
      final current = polygon[i];
      final next = polygon[(i + 1) % polygon.length];
      final sideCurrent = side(current);
      final sideNext = side(next);
      if (sideCurrent >= -1e-9) result.add(current);
      final crosses =
          (sideCurrent > 1e-9 && sideNext < -1e-9) ||
          (sideCurrent < -1e-9 && sideNext > 1e-9);
      if (crosses) {
        final t = sideCurrent / (sideCurrent - sideNext);
        result.add(current + (next - current) * t);
      }
    }
    return result;
  }

  /// Контур заготовки к раскрою (первый; у Т-окна без спайки их два —
  /// см. [filmCutPolygons]).
  List<Offset> get filmCutPolygon => filmCutPolygons.first;

  /// Контуры заготовки к раскрою с компенсацией усадки ПВХ.
  ///
  /// Усадка компенсируется по обеим осям, поэтому контуры равномерно
  /// растягиваются в `1 + s/100` раз относительно центра габарита.
  List<List<Offset>> get filmCutPolygonsWithShrinkage {
    final factor = 1 + params.effectiveShrinkagePercent / 100;
    if (factor == 1) return filmCutPolygons;
    final center = layers.filmCutBounds.center;
    return [
      for (final polygon in filmCutPolygons)
        [
          for (final point in polygon)
            Offset(
              center.dx + (point.dx - center.dx) * factor,
              center.dy + (point.dy - center.dy) * factor,
            ),
        ],
    ];
  }

  /// Контур заготовки к раскрою с компенсацией усадки (первый).
  List<Offset> get filmCutPolygonWithShrinkage =>
      filmCutPolygonsWithShrinkage.first;

  /// Ширины сегментов кроя при включённой «доп. настройке молнии», мм.
  List<double> get zipperSegmentWidths => [
    for (final polygon in filmCutPolygons) boundsOf(polygon).width,
  ];

  /// Подпись сегментов для раскроя и техкарты: «сегментов 3: 700 + 700 + 700».
  String get zipperSegmentsLabel {
    final widths = zipperSegmentWidths;
    if (widths.length < 2) return '';
    final total = boundsOfAll(filmCutPolygons).width;
    return 'сегментов ${widths.length}: '
        '${widths.map(formatMm).join(' + ')} ${unitSuffix()} · '
        'общая ширина ${formatMm(total)} ${unitSuffix()}';
  }

  /// Площадь ЗАГОТОВКИ к раскрою: припуск, без усадки, минус вырезы, м².
  ///
  /// Считается по формуле Гаусса для контуров [filmCutPolygons]: у косого
  /// окна площадь трапеции, а не габаритного прямоугольника. У Т-окна
  /// складываются площади заготовок частей.
  double get filmCutAreaM2 {
    var area = 0.0;
    for (final polygon in filmCutPolygons) {
      area += polygonArea(polygon).abs();
    }
    return math.max(area - layers.cutoutAreaMm2, 0) / 1000000;
  }

  /// Площадь заготовки к раскрою С учётом усадки, м².
  ///
  /// Контуры заготовки растягиваются в `1 + s/100` раз по обеим осям, поэтому
  /// площадь растёт в `(1 + s/100)²`, а форма остаётся косой. Для Т-окна без
  /// спайки складываются площади двух растянутых заготовок. Именно эта
  /// площадь идёт в расход, смету и ведомость.
  double get filmCutAreaWithShrinkageM2 {
    var area = 0.0;
    for (final polygon in filmCutPolygonsWithShrinkage) {
      area += polygonArea(polygon).abs();
    }
    return math.max(area - layers.cutoutAreaMm2, 0) / 1000000;
  }

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
    if ((max - min).abs() < 1) return '${formatMm(max)} ${unitSuffix()}';
    return '${formatMm(min)}…${formatMm(max)} ${unitSuffix()}';
  }

  /// Подпись окантовки по сторонам: «низ 100, верх 100, лево 200, право 200».
  ///
  /// У скрина окантовки нет — вместо неё подворот по сторонам.
  String get edgeBySideSummary {
    if (params.isScreen) {
      return 'подворот ${params.hemBySideLabel}, '
          'шов ${formatMm(screenSeamMm)} ${unitSuffix()}';
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
      ? 'без окантовки: подворот ${params.hemBySideShortLabel} '
            '(низ/право/верх/лево), шов ${formatMm(screenSeamMm)} ${unitSuffix()}'
      : '${params.edgeColor.label.toLowerCase()}, ${params.edgeMaterial.label}';

  /// Название выбранного крепежа подвижных сторон строчными: «поворотные
  /// скобы». У скрина крепёж ставится по подвороту, у ПВХ — по окантовке.
  String get movableFastenerLabel => switch (params.fastenerType) {
    FastenerType.eyeletsOnly => 'только люверсы',
    FastenerType.turnBuckles => 'поворотные скобы',
    FastenerType.frenchLocks => 'французский замок',
    FastenerType.straps => 'силиконовые ремни',
  };

  /// Подпись крепежа окна.
  ///
  /// У скрина выбранный тип крепежа действует так же, как у подъёмного
  /// ПВХ-окна: скобы, замки и ремни ставятся по низу и бокам, сверху —
  /// саморезы. Раньше у скрина всё это молча игнорировалось, теперь работает.
  String get fastenerSummary {
    if (params.isScreen) {
      if (params.fastenerType == FastenerType.eyeletsOnly) {
        return 'Только люверсы по подвороту, сверху саморезы (скрин)';
      }
      return 'Сверху саморезы, низ и бока — $movableFastenerLabel '
          'по подвороту (скрин)';
    }
    return switch (params.windowType) {
      // Составное окно — тоже глухое: крепёж по окантовке обеих частей.
      WindowType.fixed ||
      WindowType.tShape ||
      WindowType.composite ||
      WindowType.triangle ||
      WindowType.house => 'Саморезы по окантовке (глухое)',
      WindowType.lifting =>
        'Сверху саморезы, низ и бока — $movableFastenerLabel',
    };
  }

  /// Тип люверса, который реально ставится.
  EyeletType get eyeletType => params.effectiveEyeletType;

  /// Количество подъёмных ремней.
  int get strapCount => params.liftStrapOffsets.isNotEmpty
      ? params.liftStrapOffsets.length
      : params.liftStrapCount;

  /// Заготовка полосы под молнию: (ширина, длина), мм.
  ///
  /// У ПВХ это полоса тента, у скрина — полоса (подворот) из самого скрина.
  (double, double)? get zipperBandPiece {
    final band = layers.zipperBand;
    if (band == null) return null;
    final visible = layers.filmVisibleBounds;
    // Заготовка полосы: по всей высоте полотна.
    return (band.width, visible.height);
  }

  /// Площадь полос молний у скрина, м² (0 у ПВХ: там полоса из тента).
  ///
  /// Справочное число для подписей: ширина полосы × высота полотна на каждую
  /// молнию. В расход и смету отдельным слагаемым она НЕ входит: по правилу
  /// заказчика ширина кроя заранее уменьшена на полосу
  /// ([zipperBandTotalMm], см. [filmCutWidth]), поэтому расход идёт по площади
  /// суженной заготовки. Иначе площадь полосы посчиталась бы дважды.
  double get screenZipperBandAreaM2 {
    if (!params.isScreen) return 0;
    final height = layers.filmVisibleBounds.height;
    var area = 0.0;
    for (final band in layers.zipperBands) {
      area += band.width * height;
    }
    return area / 1000000;
  }

  /// Длина полос молний у скрина, мм (0 у ПВХ).
  ///
  /// По ней считается работа подворота/шва полосы: шов идёт по длине полосы.
  double get screenZipperBandLengthMm {
    if (!params.isScreen) return 0;
    final height = layers.filmVisibleBounds.height;
    return height * layers.zipperBands.length;
  }

  /// Подпись всех молний: «2 шт: 33 % и 66 % ширины».
  String get zippersSummary {
    if (params.zippers.isEmpty) return '—';
    if (params.zippers.length == 1) return zipperSummary;
    final parts = <String>[];
    for (final gaps in layers.zipperGapsAll) {
      final band = gaps.band;
      parts.add(
        '${params.isScreen ? 'полоса скрина' : 'спайка'} '
        '${formatMm(band)} ${unitSuffix()} (слева ${formatMm(gaps.left)}, '
        'справа ${formatMm(gaps.right)} ${unitSuffix()})',
      );
    }
    return '${params.zippers.length} шт — ${parts.join('; ')}';
  }

  /// Вырезы в полотне.
  String get cutoutsSummary {
    if (params.cutouts.isEmpty) return '—';
    final parts = <String>[
      for (final cutout in layers.cutouts)
        cutout.isCircle
            ? 'Ø${formatMm(cutout.spec.width)} ${unitSuffix()} в точке '
                  '${formatMm(cutout.spec.centerXMm)}×'
                  '${formatMm(cutout.spec.centerYMm)} ${unitSuffix()}'
            : '${formatMm(cutout.spec.width)}×${formatMm(cutout.spec.height)} ${unitSuffix()} '
                  'в точке ${formatMm(cutout.spec.centerXMm)}×'
                  '${formatMm(cutout.spec.centerYMm)} ${unitSuffix()}',
    ];
    return '${params.cutouts.length} шт: ${parts.join('; ')}; '
        '${params.isScreen ? 'подворот по контуру' : 'окантовка по контуру'} '
        '${formatMm(layers.cutoutPerimeterMm)} ${unitSuffix()}';
  }

  /// Спайка с соседними окнами.
  String get weldSummary {
    final parts = <String>[];
    // Швы по пристройкам — каждый отдельной операцией.
    for (final annex in tAnnexes.where((annex) => annex.welded)) {
      parts.add(
        'шов по общей стороне пристройки ${annex.number} '
        '(${annex.side.label.toLowerCase()}, ${formatMm(annex.sharedLength)} ${unitSuffix()}) '
        '— полотна свариваются внахлёст ${formatMm(windowWeldWidth)} ${unitSuffix()}, '
        'окантовка по ней не ставится',
      );
    }
    if (params.isTShape && tAnnexes.isNotEmpty && !tLayout!.anyWelded) {
      parts.add('пристройки не спаяны — отдельные окна');
    }
    if (parts.isEmpty) return '—';
    return '${parts.join('; ')} (всего ${formatMm(layers.weldLengthMm)} ${unitSuffix()})';
  }

  String get zipperSummary {
    if (!params.hasZipper) return '—';
    final gaps = layers.zipperGaps;
    final position = params.zipperCentered
        ? 'по центру'
        : '${formatMm(params.zipperOffsetMm)} ${unitSuffix()} от левого края';
    // У скрина видимая кромка — линия подворота, у ПВХ — кромка плёнки.
    final edge = params.isScreen ? 'кромки подворота' : 'кромок плёнки';
    final around = gaps == null
        ? ''
        : ', слева ${formatMm(gaps.left)} / справа ${formatMm(gaps.right)} ${unitSuffix()} '
              'до $edge';
    return 'вертикальная, $position$around';
  }

  /// Подпись молнии с полосой: у ПВХ — тента, у скрина — скрина.
  String get zipperBandSummary {
    final piece = zipperBandPiece;
    if (piece == null) return '—';
    final bandWidth = piece.$1;
    final bandLength = piece.$2;
    if (params.isScreen) {
      return '$zipperSummary; полоса скрина ${formatMm(bandWidth)} × '
          '${formatMm(bandLength)} ${unitSuffix()}, шов ${formatMm(screenSeamMm)} ${unitSuffix()} '
          'по краям полосы';
    }
    final reduction = zipperBandTotalMm > 0
        ? ', ширина кроя −${formatMm(zipperBandTotalMm)} ${unitSuffix()}'
        : '';
    return '$zipperSummary; полоса тента ${formatMm(bandWidth)} × '
        '${formatMm(bandLength)} ${unitSuffix()}$reduction';
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
            'сам; молния ставится в полосу из скрина '
            '(подворот или накладная полоса), шов '
            '${formatMm(screenSeamMm)} ${unitSuffix()} по краям полосы',
        'Подворот материала по сторонам — ${params.hemBySideLabel} '
            '(низ/право/верх/лево); шов сварки подворота '
            '${formatMm(screenSeamMm)} ${unitSuffix()} с каждой стороны',
        'Заготовка скрина — готовый габарит плюс ПОЛОВИНА подворота с каждой '
            'стороны; к высоте добавляется ${formatMm(screenHemAxisExtraMm)} '
            '${unitSuffix()} на шов и запас. По ширине лево '
            '${formatMmTrimmed(params.hemLeftHalfMm)} + право '
            '${formatMmTrimmed(params.hemRightHalfMm)} = '
            '${formatMm(params.hemAxisLeftRightIncrease)} ${unitSuffix()}, по высоте низ '
            '${formatMmTrimmed(params.hemBottomHalfMm)} + верх '
            '${formatMmTrimmed(params.hemTopHalfMm)} + '
            '${formatMm(screenHemAxisExtraMm)} = '
            '${formatMm(params.hemAxisBottomTopIncrease)} ${unitSuffix()}'
            '${widthSlopeExtraMm.abs() >= 0.5 || heightSlopeExtraMm.abs() >= 0.5 ? '; у трапеции/окна с разными высотами наклон сторон добавляет к габариту по ширине '
                      '${formatSignedMm(widthSlopeExtraMm)}, по высоте '
                      '${formatSignedMm(heightSlopeExtraMm)} ${unitSuffix()}' : ''}',
        'Заготовка скрина: ${formatMm(filmCutWidthWithAllowance)} × '
            '${formatMm(filmCutHeightWithAllowance)} ${unitSuffix()} '
            '(${formatMm(filmCutWidth)} × ${formatMm(filmCutHeight)} ${unitSuffix()} '
            'до припуска); усадки нет',
        'Расход скрина — площадь заготовки по фактическому контуру '
            '${formatMeters(filmCutAreaWithShrinkageM2)} м²'
            '${zipperBandTotalMm > 0 ? ' (ширина уже без полосы молнии '
                      '${formatMm(zipperBandTotalMm)} ${unitSuffix()})' : ''}',
      ] else ...[
        'Окантовка складывается пополам; запайка плёнки под окантовку '
            '${formatMm(params.weldOverlapMm)} ${unitSuffix()} по всему периметру',
        'Окантовка по сторонам — ${edgeBySideSummary.lowercaseFirst}',
        'Расход окантовки: ${edgeConsumptionLabels.join(', ')}',
      ],
      if (params.isTShape) tShapeSummary,
      if (params.isTShape && tLayout!.weldedAnnexes.isNotEmpty)
        'Спайка по общей стороне пристроек: ${formatMm(tWeldedSeamLength)} ${unitSuffix()}, '
            'шов ${formatMm(windowWeldWidth)} ${unitSuffix()} внахлёст; окантовка идёт '
            'только по внешнему периметру (${formatMm(edgePerimeterMm)} ${unitSuffix()}), '
            'на общей стороне её нет',
      if (params.isTShape && tLayout!.separateAnnexes.isNotEmpty)
        'Пристройки без спайки (${tLayout!.separateAnnexes.map((annex) => annex.number).join(', ')}) '
            '— отдельные окна: окантовка считается по периметру каждой части '
            '(${formatMm(edgePerimeterMm)} ${unitSuffix()})',
      if (params.isTShape)
        'Заготовка Т-окна — прямоугольник по каждой части: '
            '${filmPartBounds.map((rect) => '${formatMm(rect.width)} × ${formatMm(rect.height)}').join(', ')} ${unitSuffix()}',
      ?tAnnexConflict,
      'Полотно ${params.isScreen ? 'скрина' : 'ПВХ 700 мкм'} в раскрое: '
          'заготовка ${formatMm(filmCutWidthWithAllowance)} × '
          '${formatMm(filmCutHeightWithAllowance)} ${unitSuffix()}'
          '${params.isScreen
              ? ''
              : params.hasShrinkage
              ? '; с усадкой '
                    '${formatPercent(params.effectiveShrinkagePercent)} — '
                    '${formatMm(filmCutWidthWithShrinkage)} × '
                    '${formatMm(filmCutHeightWithShrinkage)} ${unitSuffix()}'
              : '; усадка не учитывается'}',
      if (params.hasAllowance)
        'Припуск на раскрой: ширина ${params.allowanceWidthLabel} ${unitSuffix()}, '
            'высота ${params.allowanceHeightLabel} ${unitSuffix()}'
            '${params.hasAutoHeightAllowance ? ' (в том числе авто '
                      '${formatMm(params.autoHeightAllowanceMm)} ${unitSuffix()} к высоте для ПВХ)' : ''} — '
            '${params.isScreen ? 'скрин кроится' : 'плёнка кроится'} '
            '${formatMm(filmCutWidthWithAllowance)} × '
            '${formatMm(filmCutHeightWithAllowance)} ${unitSuffix()}',
      'Люверсы ${eyeletType.displayLabel.toLowerCase()}: интервал задан '
          '${formatMm(params.eyeletStep)} ${unitSuffix()}, факт $eyeletStepLabel по '
          'сторонам, от угла ${formatMm(params.eyeletCornerOffset)} ${unitSuffix()}, '
          'всего $eyeletCount шт'
          '${params.roundEyeletsEnabled ? '' : '; круглые люверсы в углах '
                    'отключены — угловых точек нет'}'
          '${params.hasEyeletlessSides ? '; без люверсов: '
                    '${layers.eyeletlessSidesLabel} (сторона остаётся без крепежа)' : ''}',
      'Крепёж: ${fastenerSummary.toLowerCase()}',
      if (params.isLifting && !params.isScreen)
        'Подъёмные ремни: $strapCount шт, '
            '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} ${unitSuffix()} '
            '(2 шт до 2 м ширины, далее +1 на метр)',
      if (params.zippers.length == 1) 'Молния: $zipperBandSummary',
      if (params.zippers.length > 1) 'Молнии: $zippersSummary',
      if (params.hasZipper &&
          layers.zipperGaps != null &&
          params.zippers.length == 1)
        params.isScreen
            ? 'Полоса молнии из скрина ${formatMm(params.zipperBandWidth)} ${unitSuffix()}; '
                  'от полосы до кромки подворота: слева '
                  '${formatMm(layers.zipperGaps!.left)} ${unitSuffix()}, справа '
                  '${formatMm(layers.zipperGaps!.right)} ${unitSuffix()} (не меньше '
                  '${formatMm(minScreenZipperHemMm)} ${unitSuffix()})'
            : 'Спайка молнии ${formatMm(params.zipperBandWidth)} ${unitSuffix()}; от спайки '
                  'до кромок плёнки: слева ${formatMm(layers.zipperGaps!.left)} ${unitSuffix()}, '
                  'справа ${formatMm(layers.zipperGaps!.right)} ${unitSuffix()}',
      if (zipperWidthReductionLabel != null)
        params.isScreen
            ? 'Ширина кроя скрина уменьшена на полосу молнии '
                  '${formatMm(zipperBandTotalMm)} ${unitSuffix()}: '
                  '${formatMm(filmCutWidthBeforeZipper)} → '
                  '${formatMm(filmCutWidth)} ${unitSuffix()} до припуска (площадь полосы '
                  '${formatMeters(screenZipperBandAreaM2)} м² отдельно не '
                  'считается)'
            : 'Ширина кроя плёнки уменьшена на полосу (спайку) молнии '
                  '${formatMm(zipperBandTotalMm)} ${unitSuffix()}: '
                  '${formatMm(filmCutWidthBeforeZipper)} → '
                  '${formatMm(filmCutWidth)} ${unitSuffix()} до припуска; полоса тента '
                  'идёт в расход окантовки',
      if (params.cutouts.isNotEmpty) 'Вырезы: $cutoutsSummary',
      if (params.isComposite)
        'Составное окно: ${params.composite.material.label}, '
            '${params.composite.isDiagonal ? 'диагональный' : 'прямой'} шов '
            '${formatMm(layers.compositeLayout?.seamLength ?? 0)} ${unitSuffix()}',
      if (params.drainHoles && !params.isScreen)
        'Дренаж: ${params.drainCount.round()} отв. Ø6 мм в нижней окантовке',
      if (params.pocket || params.pocketTop) _pocketNote(),
      'Полотно: ${params.material.thickness}; доступные рулоны '
          '${params.material.rollWidthsLabel} ${unitSuffix()}',
      if (params.isScreen)
        'Скрин сваривается горячим воздухом 400–500 °C, морозостойкость '
            'до −30 °C'
      else
        '${params.edgeMaterial.joining}, морозостойкость до −30 °C',
    ];
  }

  /// Примечание о фартуках (бывших карманах): снизу, сверху или оба;
  /// у скрина — подворотом.
  String _pocketNote() {
    final where = switch ((params.pocket, params.pocketTop)) {
      (true, true) => 'снизу и сверху',
      (true, false) => 'снизу',
      (false, true) => 'сверху',
      (false, false) => '',
    };
    if (params.isScreen) {
      return 'Фартук $where: подворот ${formatMm(params.pocketWidth)} ${unitSuffix()}, '
          'угловой люверс со стороны фартука смещён на '
          '${formatMm(pocketCornerOffset)} ${unitSuffix()}';
    }
    return 'Фартук $where: тент ${formatMm(pocketRollWidth)} ${unitSuffix()} сложен '
        'пополам → ${formatMm(params.pocketWidth)} ${unitSuffix()}; угловой люверс со '
        'стороны фартука смещён на ${formatMm(pocketCornerOffset)} ${unitSuffix()}';
  }
}

extension on String {
  String get lowercaseFirst =>
      isEmpty ? this : '${this[0].toLowerCase()}${substring(1)}';
}

/// Важность замечания к параметрам: подсказка, предупреждение или ошибка.
///
/// Ошибка блокирует производство ([ParamIssue.isError]), предупреждение —
/// риск брака, подсказка — «так тоже можно, но обычно делают иначе».
enum ParamIssueSeverity {
  info,
  warning,
  error;

  String get label => switch (this) {
    ParamIssueSeverity.info => 'Подсказка',
    ParamIssueSeverity.warning => 'Предупреждение',
    ParamIssueSeverity.error => 'Ошибка',
  };
}

/// Замечание к введённым параметрам.
class ParamIssue {
  const ParamIssue(
    this.field,
    this.message, {
    bool isError = true,
    ParamIssueSeverity? severity,
  }) : severity =
           severity ??
           (isError ? ParamIssueSeverity.error : ParamIssueSeverity.info);

  final ParamField field;
  final String message;

  /// Важность замечания. Старый флаг [isError] выводится из неё, поэтому
  /// прежние вызовы `isError: false` продолжают работать как «подсказка».
  final ParamIssueSeverity severity;

  bool get isError => severity == ParamIssueSeverity.error;

  /// Предупреждение — не ошибка, но и не безобидная подсказка.
  bool get isWarning => severity == ParamIssueSeverity.warning;
}

/// Проверка интервала люверсов.
///
/// Пользователь задаёт интервал сам ([WindowParams.eyeletStep]), поэтому
/// «шага 250–400» тут больше нет. Ошибки — только выход за рамки ввода
/// [minEyeletStepMm]…[maxEyeletStepMm]. Внутри рамок значение принимается:
/// 250–450 мм — рекомендация (подсказка), свыше [looseEyeletStepMm] — риск
/// парусности, ниже [denseEyeletStepMm] — перерасход люверсов.
void _checkEyeletStep(WindowParams params, List<ParamIssue> issues) {
  final step = params.eyeletStep;
  if (!step.isFinite) {
    issues.add(
      const ParamIssue(
        ParamField.eyeletStep,
        'Интервал люверсов: укажите число в миллиметрах',
      ),
    );
    return;
  }
  if (step < minEyeletStepMm) {
    issues.add(
      ParamIssue(
        ParamField.eyeletStep,
        'Интервал люверсов: ${formatMm(step)} ${unitSuffix()} — меньше минимума '
        '${formatMm(minEyeletStepMm)} ${unitSuffix()}',
      ),
    );
    return;
  }
  if (step > maxEyeletStepMm) {
    issues.add(
      ParamIssue(
        ParamField.eyeletStep,
        'Интервал люверсов: ${formatMm(step)} ${unitSuffix()} — больше максимума '
        '${formatMm(maxEyeletStepMm)} ${unitSuffix()}',
      ),
    );
    return;
  }
  if (step > looseEyeletStepMm) {
    issues.add(
      ParamIssue(
        ParamField.eyeletStep,
        'Интервал люверсов: ${formatMm(step)} ${unitSuffix()} — полотно будет парусить '
        'между креплениями',
        severity: ParamIssueSeverity.warning,
      ),
    );
    return;
  }
  if (step < denseEyeletStepMm) {
    issues.add(
      ParamIssue(
        ParamField.eyeletStep,
        'Интервал люверсов: ${formatMm(step)} ${unitSuffix()} — перерасход люверсов и узкая '
        'перемычка',
        severity: ParamIssueSeverity.warning,
      ),
    );
    return;
  }
  // Рекомендуемый диапазон: вне него — только подсказка, ввод не запрещён.
  if (step < recommendedEyeletStepMinMm || step > recommendedEyeletStepMaxMm) {
    issues.add(
      ParamIssue(
        ParamField.eyeletStep,
        'Интервал люверсов: ${formatMm(step)} ${unitSuffix()} — вне рекомендуемых '
        '${formatMm(recommendedEyeletStepMinMm)}–'
        '${formatMm(recommendedEyeletStepMaxMm)} ${unitSuffix()}, но так тоже делают',
        severity: ParamIssueSeverity.info,
      ),
    );
  }
}

/// Проверка параметров окна: физически невозможные значения — ошибки,
/// сомнительные сочетания — предупреждения.
List<ParamIssue> validateParams(WindowParams params) {
  final issues = <ParamIssue>[];

  void checkPositive(ParamField field, double value, {double max = 20000}) {
    if (!value.isFinite || value <= 0) {
      issues.add(
        ParamIssue(field, '${field.label}: укажите значение больше нуля'),
      );
    } else if (value > max) {
      issues.add(
        ParamIssue(
          field,
          '${field.label}: ${formatMm(value)} — больше ${formatMm(max)}, проверьте замер',
          isError: false,
        ),
      );
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
      issues.add(
        ParamIssue(
          field,
          '${field.label}: обычно $hint, у вас ${formatMm(value)}',
          isError: false,
        ),
      );
    }
  }

  checkPositive(ParamField.bottomWidth, params.bottomWidth);
  checkPositive(ParamField.topWidth, params.topWidth);
  checkPositive(ParamField.leftHeight, params.leftHeight);
  checkPositive(ParamField.rightHeight, params.rightHeight);

  // --- Т-образное окно -----------------------------------------------------
  if (params.isTShape) {
    final annexes = params.tAnnexes;
    for (var index = 0; index < annexes.length; index++) {
      final annex = annexes[index];
      final widthField = index == 0 ? ParamField.tWidth : ParamField.t2Width;
      final heightField = index == 0 ? ParamField.tHeight : ParamField.t2Height;
      final offsetField = index == 0 ? ParamField.tOffset : ParamField.t2Offset;
      checkPositive(widthField, annex.width);
      checkPositive(heightField, annex.height);
      if (!annex.offset.isFinite || annex.offset < 0) {
        issues.add(
          ParamIssue(
            offsetField,
            '${annex.label}: смещение — 0 или больше, пристройка не может '
            'выступать за начало общей стороны',
            isError: false,
          ),
        );
      }
      final vertical =
          annex.side == TShapeSide.left || annex.side == TShapeSide.right;
      final along = vertical ? params.leftHeight : params.bottomWidth;
      final annexAlong = vertical ? annex.height : annex.width;
      if (annexAlong.isFinite && along.isFinite && annexAlong > along + 0.5) {
        issues.add(
          ParamIssue(
            heightField,
            '${annex.label} длиннее общей стороны на '
            '${formatMm(annexAlong - along)} ${unitSuffix()} — в чертеже она подрезана по '
            'стороне ${formatMm(along)} ${unitSuffix()}',
            isError: false,
          ),
        );
      }
    }
    // Две пристройки на одной стороне запрещены: в расчёте остаётся только
    // первая, а здесь — понятное предупреждение, что поменять.
    if (params.tAnnexSideConflict) {
      issues.add(
        const ParamIssue(
          ParamField.t2Width,
          'Пристройки 1 и 2 стоят на одной стороне — так нельзя. В расчёте '
          'оставлена только пристройка 1. Выберите для второй другую сторону',
          severity: ParamIssueSeverity.warning,
        ),
      );
    }
    // Основное полотно Т-окна — прямоугольник: контур строится по низу и
    // левой высоте. Если верх/право отличаются, честно предупреждаем, что
    // в чертеже используется прямоугольник, а не трапеция.
    if ((params.topWidth - params.bottomWidth).abs() > 0.5 ||
        (params.rightHeight - params.leftHeight).abs() > 0.5) {
      issues.add(
        const ParamIssue(
          ParamField.topWidth,
          'Т-образное окно: основное полотно считается прямоугольником по низу '
          'и левой высоте. Выровняйте ширины верха/низа и высоты сторон',
          isError: false,
        ),
      );
    }
    for (final annex in params.tAnnexes.where((annex) => !annex.welded)) {
      issues.add(
        ParamIssue(
          annex.number == 1 ? ParamField.tWidth : ParamField.t2Width,
          '${annex.label}: спайка по общей стороне выключена — это отдельное '
          'окно, окантовка и площадь считаются по каждой части раздельно',
          isError: false,
        ),
      );
    }
    final separate = params.tAnnexes.any((annex) => !annex.welded);
    final bottomAnnex = params.tAnnexes.any(
      (annex) => annex.side == TShapeSide.bottom,
    );
    final topAnnex = params.tAnnexes.any(
      (annex) => annex.side == TShapeSide.top,
    );
    if ((params.pocket && (separate || bottomAnnex)) ||
        (params.pocketTop && (separate || topAnnex))) {
      issues.add(
        const ParamIssue(
          ParamField.pocketWidth,
          'Фартук в Т-окне не поддерживается без спайки и со стороны '
          'пристройки: полоса фартука разрывается на общей стороне',
          isError: false,
        ),
      );
    }
  }

  // Интервал люверсов задаёт пользователь: 50…2000 мм — рамки ввода.
  // Внутри них значение принимается всегда (это не «шаг 250–400» из старой
  // версии). Выход за рекомендуемые 250–450 мм — подсказка, парусность
  // (свыше 800 мм) и перерасход (ниже 150 мм) — предупреждения.
  _checkEyeletStep(params, issues);
  checkRange(
    ParamField.eyeletCornerOffset,
    params.eyeletCornerOffset,
    0,
    70,
    '0 мм (в углу) или до 70 мм',
  );
  // Усадка: у скрина её нет, а при выключенном тумблере значение не
  // применяется к раскрою — замечаний по нему не выдаём. При включённом
  // тумблере подсказываем типовой диапазон 1–2 %; саму рамку ввода 0…5 %
  // держит панель.
  if (params.isPvcFilm &&
      params.shrinkageEnabled &&
      params.shrinkagePercent != 0) {
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
      issues.add(
        ParamIssue(
          field,
          'Припуск на раскрой, $axis: укажите число в миллиметрах',
          isError: false,
        ),
      );
      return;
    }
    if (value < 0) {
      issues.add(
        ParamIssue(
          field,
          'Припуск на раскрой, $axis: ${formatMm(value)} ${unitSuffix()} — отрицательный, '
          'изделие будет меньше замера',
          isError: false,
        ),
      );
      return;
    }
    if (value > maxAllowanceMm) {
      issues.add(
        ParamIssue(
          field,
          'Припуск на раскрой, $axis: ${formatMm(value)} ${unitSuffix()} — больше '
          '${formatMm(maxAllowanceMm)} ${unitSuffix()}, проверьте значение',
          isError: false,
        ),
      );
    }
  }

  checkAllowance(ParamField.allowanceWidth, params.allowanceWidthMm, 'ширина');
  checkAllowance(
    ParamField.allowanceHeight,
    params.allowanceHeightMm,
    'высота',
  );

  if (params.topWidth.isFinite &&
      params.bottomWidth.isFinite &&
      params.topWidth > params.bottomWidth) {
    issues.add(
      const ParamIssue(
        ParamField.topWidth,
        'Верх шире низа — проверьте замеры',
        isError: false,
      ),
    );
  }

  if (params.isComposite) {
    final composite = params.composite;
    if (params.isScreen) {
      issues.add(
        const ParamIssue(
          ParamField.bottomWidth,
          'Основное полотно составного окна — ПВХ: второй материал выбирается '
          'отдельно (скрин или ПВХ)',
          isError: true,
        ),
      );
    }
    checkRange(
      ParamField.compositeWidth,
      composite.width,
      100,
      6000,
      '100…6000 мм',
    );
    checkRange(
      ParamField.compositeDepth,
      composite.depth,
      100,
      3000,
      '100…3000 мм',
    );
    if (composite.isDiagonal) {
      checkRange(
        ParamField.compositeAngle,
        composite.seamAngleDeg,
        5,
        80,
        '5…80°',
      );
    }
    final layout = WindowGeometry.of(params).compositeLayout;
    if (layout != null && layout.clamped) {
      issues.add(
        const ParamIssue(
          ParamField.compositeOffset,
          'Второй сегмент не помещается на стороне окна: размеры подрезаны',
          isError: false,
        ),
      );
    }
  }

  final geometry = WindowGeometry.of(params);
  if (params.topAlign == TopAlign.custom) {
    if (geometry.rightOverhang > 1) {
      issues.add(
        ParamIssue(
          ParamField.topOffset,
          'Верх выступает вправо на ${formatMm(geometry.rightOverhang)} ${unitSuffix()}',
          isError: false,
        ),
      );
    }
    if (geometry.leftOverhang > 1) {
      issues.add(
        ParamIssue(
          ParamField.topOffset,
          'Верх выступает влево на ${formatMm(geometry.leftOverhang)} ${unitSuffix()}',
          isError: false,
        ),
      );
    }
  }

  final layers = WindowLayers(params, geometry);

  // Запайка плёнки под окантовку: 5…60 мм. От неё напрямую зависит размер
  // заготовки, поэтому значение вводится руками и проверяется.
  if (!params.weldOverlapMm.isFinite ||
      params.weldOverlapMm < minWeldOverlapMm ||
      params.weldOverlapMm > maxWeldOverlapMm) {
    issues.add(
      ParamIssue(
        ParamField.weldOverlap,
        'Запайка под окантовку: ${formatMm(params.weldOverlapMm)} ${unitSuffix()} — вне '
        'диапазона ${formatMm(minWeldOverlapMm)}–${formatMm(maxWeldOverlapMm)} ${unitSuffix()}',
        isError: !params.weldOverlapMm.isFinite,
      ),
    );
  } else if (!params.isScreen) {
    checkRange(
      ParamField.weldOverlap,
      params.weldOverlapMm,
      10,
      40,
      '10–40 мм',
    );
  }

  // Подворот скрина: 10…200 мм на каждую сторону, обычный диапазон 40–80 мм.
  // В заготовку идёт половина подворота каждой стороны, к высоте +20 мм:
  // 2000 × 2000 при подвороте 40 мм на все стороны → 2040 × 2060 мм,
  // при (низ 40, верх 60) → 2040 × 2070 мм.
  if (params.isScreen) {
    for (final side in EdgeSide.values) {
      final hem = params.hemForSide(side);
      final field = hemFieldForSide(side);
      final name = side.label.toLowerCase();
      if (!hem.isFinite || hem <= 0) {
        issues.add(
          ParamIssue(field, 'Подворот, $name: укажите значение больше нуля'),
        );
        continue;
      }
      if (hem < minScreenHemMm || hem > maxScreenHemMm) {
        issues.add(
          ParamIssue(
            field,
            'Подворот, $name: ${formatMm(hem)} ${unitSuffix()} — вне диапазона '
            '${formatMm(minScreenHemMm)}–${formatMm(maxScreenHemMm)} ${unitSuffix()}',
            isError: false,
          ),
        );
        continue;
      }
      checkRange(field, hem, 30, 80, '40–60 мм');
    }
  }

  if (params.isScreen) {
    // У скрина нет окантовки: проверять её ширины и запайку нечего.
    if (params.drainHoles) {
      issues.add(
        const ParamIssue(
          ParamField.drainCount,
          'Дренаж делается в нижней окантовке — у скрина её нет',
          isError: false,
        ),
      );
    }
  } else {
    final maxFinished = layers.finishedWidths.reduce((a, b) => a > b ? a : b);
    final minSpan = math.min(geometry.spanX, geometry.maxY);
    if (maxFinished * 2 + params.weldOverlapMm * 2 >= minSpan) {
      issues.add(
        const ParamIssue(
          ParamField.bottomWidth,
          'Окантовка со швом не оставляет места полотну — выберите рулон уже',
        ),
      );
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
        issues.add(
          ParamIssue(
            ParamField.bottomWidth,
            'Окантовка, $name: ${formatMm(raw)} ${unitSuffix()} — вне диапазона '
            '${formatMm(minEdgeRollWidth)}–${formatMm(maxEdgeRollWidth)} ${unitSuffix()}',
            isError: false,
          ),
        );
        continue;
      }
      final finished = WindowParams.finishedEdgeWidth(raw);
      // Полоса складывается пополам: на запайку нужна такая же полоса плюс
      // запас на кромку, поэтому минимум — запайка + 15 мм готовой.
      final minFinishedForWeld = params.weldOverlapMm + 15;
      if (finished < minFinishedForWeld) {
        issues.add(
          ParamIssue(
            ParamField.bottomWidth,
            'Окантовка, $name: готовая полоса ${formatMm(finished)} ${unitSuffix()} — уже '
            '${formatMm(minFinishedForWeld)} ${unitSuffix()}, запайке '
            '${formatMm(params.weldOverlapMm)} ${unitSuffix()} не хватает ленты',
            isError: false,
          ),
        );
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
    if (spec.zipWidthMm < 1 || spec.zipWidthMm > 100) {
      issues.add(
        const ParamIssue(
          ParamField.bottomWidth,
          'Ширина молнии — 1–100 мм (обычно 15 мм)',
          isError: false,
        ),
      );
    }
    if (spec.tentWidthMm < 5 || spec.tentWidthMm > 300) {
      issues.add(
        const ParamIssue(
          ParamField.bottomWidth,
          'Ширина тента у молнии — 5–300 мм (обычно 50 мм)',
          isError: false,
        ),
      );
    }
    if (spec.weldMm < 0 || spec.weldMm > 100) {
      issues.add(
        const ParamIssue(
          ParamField.bottomWidth,
          'Напайка тента — 0–100 мм (обычно 20 мм)',
          isError: false,
        ),
      );
    }
    if (!spec.centered) {
      final bounds = layers.filmVisibleBounds;
      final half = math.max(spec.bandWidth, 20) / 2;
      final limit = bounds.width;
      if (spec.offsetMm < half || spec.offsetMm > limit - half) {
        issues.add(
          ParamIssue(
            ParamField.bottomWidth,
            params.isScreen
                ? 'Молния №${i + 1} выходит за пределы заготовки '
                      '(ширина по кромке подворота ${formatMm(limit)} ${unitSuffix()})'
                : 'Молния №${i + 1} выходит за пределы плёнки '
                      '(доступно ${formatMm(limit)} ${unitSuffix()})',
          ),
        );
      }
    }
    // Скрин: полоса молнии не подходит к кромке подворота ближе 100 мм —
    // иначе шов полосы сливается со швом подворота и кромка рвётся.
    if (params.isScreen) {
      final gaps = layers.zipperGapsAll;
      if (i < gaps.length) {
        final near = math.min(gaps[i].left, gaps[i].right);
        if (near < minScreenZipperHemMm) {
          issues.add(
            ParamIssue(
              ParamField.bottomWidth,
              'Молния №${i + 1} на скрине: до кромки подворота '
              '${formatMm(near)} ${unitSuffix()} — меньше '
              '${formatMm(minScreenZipperHemMm)} ${unitSuffix()}',
              isError: false,
            ),
          );
        }
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
      issues.add(
        ParamIssue(
          ParamField.bottomWidth,
          'Вырез №${i + 1} выходит за пределы полотна',
        ),
      );
    }
    for (var j = i + 1; j < layers.cutouts.length; j++) {
      if (bounds.overlaps(layers.cutouts[j].bounds)) {
        issues.add(
          ParamIssue(
            ParamField.bottomWidth,
            'Вырезы №${i + 1} и №${j + 1} пересекаются',
            isError: false,
          ),
        );
      }
    }
    for (final band in layers.zipperBands) {
      if (bounds.overlaps(band)) {
        issues.add(
          ParamIssue(
            ParamField.bottomWidth,
            'Вырез №${i + 1} попадает на полосу молнии',
            isError: false,
          ),
        );
      }
    }
  }

  final heightDiff = (params.leftHeight - params.rightHeight).abs();
  if (heightDiff.isFinite && heightDiff > 0 && heightDiff <= 500) {
    issues.add(
      const ParamIssue(
        ParamField.rightHeight,
        'Высоты слева и справа отличаются меньше чем на 500 мм — это нормально, но проверьте, не опечатка ли',
        isError: false,
      ),
    );
  }

  return issues;
}

/// Есть ли среди замечаний настоящие ошибки.
bool hasBlockingIssues(List<ParamIssue> issues) =>
    issues.any((issue) => issue.isError);

/// Сторона окна для ребра многоугольника.
///
/// Для четырёхугольника сохраняется прежний порядок обхода (низ, право, верх,
/// лево), поэтому трапеции и старые чертежи считаются ровно как раньше. Для
/// Т-контура (6–8 вершин) сторона выводится из наружной нормали ребра: какая
/// компонента больше — та сторона и есть.
WindowSide sideOfPolygonEdge(List<Offset> polygon, int index) {
  final count = polygon.length;
  if (count == 4) {
    return switch (index % 4) {
      0 => WindowSide.bottom,
      1 => WindowSide.right,
      2 => WindowSide.top,
      _ => WindowSide.left,
    };
  }
  final a = polygon[index % count];
  final b = polygon[(index + 1) % count];
  final direction = b - a;
  final length = direction.distance;
  if (length < 1e-9) return WindowSide.bottom;
  final unit = direction / length;
  // Обход против часовой стрелки: наружная нормаль — (dy, −dx).
  final outward = Offset(unit.dy, -unit.dx);
  if (outward.dx.abs() >= outward.dy.abs()) {
    return outward.dx >= 0 ? WindowSide.right : WindowSide.left;
  }
  return outward.dy >= 0 ? WindowSide.top : WindowSide.bottom;
}

/// Габарит нескольких контуров (например, двух заготовок Т-окна без спайки).
Rect boundsOfAll(List<List<Offset>> polygons) {
  final points = <Offset>[];
  for (final polygon in polygons) {
    points.addAll(polygon);
  }
  return boundsOf(points);
}

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

/// Растягивает многоугольник относительно центра его габарита.
///
/// Так припуск на раскрой и усадка применяются к фактической форме: габарит
/// растёт ровно на заданные миллиметры, а трапеция остаётся трапецией.
List<Offset> scalePolygonAroundCenter(
  List<Offset> polygon,
  double scaleX,
  double scaleY,
) {
  if (polygon.isEmpty) return const [];
  final center = boundsOf(polygon).center;
  return [
    for (final point in polygon)
      Offset(
        center.dx + (point.dx - center.dx) * scaleX,
        center.dy + (point.dy - center.dy) * scaleY,
      ),
  ];
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
    // Отрицательное расстояние — расширение контура наружу (заготовка скрина
    // с подворотом). Ограничиваем и его, чтобы контур не вывернулся.
    final distance = !raw.isFinite
        ? 0.0
        : raw.clamp(-limit * 0.9, limit);
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
  final grows = distances.any((value) => value.isFinite && value < 0);
  if (!area.isFinite ||
      area <= 0 ||
      (!grows && area >= polygonArea(polygon).abs())) {
    final maxDistance = distances.isEmpty
        ? 0.0
        : distances.reduce((a, b) => a > b ? a : b);
    if (!maxDistance.isFinite || maxDistance <= 0.05) return List.of(polygon);
    return insetPolygonPerSide(polygon, [
      for (final distance in distances) distance / 2,
    ]);
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
