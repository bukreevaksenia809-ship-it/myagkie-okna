import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';

/// Лист «Раскрой плёнки» — вырезанные заготовки мягких окон.
///
/// В отличие от листа «Раскладка» (там заготовки уложены на рулон), здесь
/// показаны сами заготовки: каждая — фактический контур (прямоугольник или
/// трапеция) в ОДНОМ общем масштабе, с длинами всех четырёх сторон, площадью
/// внутри и подписью материала под ним. Заготовки идут в порядке окон, слева
/// направо, с переносом на новый ряд.
///
/// Раскладка на рулоне по-прежнему пакует заготовки по габаритному
/// прямоугольнику — это упаковка. А в ведомости, смете и на этом листе идёт
/// фактическая площадь по контуру: для косого окна она меньше габарита.
class CutSheet extends StatelessWidget {
  const CutSheet({
    super.key,
    required this.project,
    this.captureKey,
    this.labelFontFamily,
  });

  final OrderProject project;
  final GlobalKey? captureKey;
  final String? labelFontFamily;

  /// Высота штампа снизу — как на остальных листах.
  static const double titleBlockHeight = 118;

  static const double _outerPadding = 20;
  static const double _innerPadding = 20;
  static const double _captionBarHeight = 42;
  static const double _totalsHeight = 132;
  static const double _piecesVerticalPadding = 10;

  /// Всё, что на листе занимает место кроме самих заготовок.
  static const double _chromeHeight =
      _captionBarHeight +
      _totalsHeight +
      titleBlockHeight +
      _piecesVerticalPadding * 2;

  /// То же плюс поля вокруг листа — полная высота «обвязки» листа.
  static const double _sheetChrome = _chromeHeight + _outerPadding * 2;

  /// Заготовки заказа: по одной на окно, в порядке окон.
  static List<CutPiece> piecesOf(OrderProject project) => [
    for (final window in project.windows)
      CutPiece.ofSpec(WindowSpec.of(window)),
  ];

  /// Размер листа раскроя. null — заготовки влезают, лист заполняет окно.
  static Size? sheetSize(OrderProject project, Size viewport) {
    final paperWidth = math.max(viewport.width - _outerPadding * 2, 1320.0);
    final contentWidth = math.max(paperWidth - _innerPadding * 2, 240.0);
    // Раскладку считаем по «естественной» полосе ряда: масштаб задаётся шириной
    // листа, поэтому высота листа не зависит от высоты окна и не «разъезжается».
    final layout = CutLayout.natural(piecesOf(project), contentWidth);
    final needed = layout.contentHeight + _sheetChrome;
    if (needed <= viewport.height) return null;
    return Size(paperWidth + _outerPadding * 2, needed);
  }

  @override
  Widget build(BuildContext context) {
    final specs = [for (final window in project.windows) WindowSpec.of(window)];
    final pieces = [for (final spec in specs) CutPiece.ofSpec(spec)];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Если родитель дал бесконечные ограничения, не строим лист
        // бесконечного размера: берём разумную ширину листа. Иначе
        // Container с width: Infinity просто не рисует заготовку.
        final viewportWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 1360.0;
        final viewportHeight = constraints.maxHeight.isFinite
            ? constraints.maxHeight
            : 900.0;
        final sheetWidth = math.max(
          viewportWidth - _outerPadding * 2,
          320.0,
        );
        final sheetHeight = math.max(
          viewportHeight - _outerPadding * 2,
          320.0,
        );
        final contentWidth = math.max(sheetWidth - _innerPadding * 2, 160.0);
        final area = Size(
          contentWidth,
          math.max(sheetHeight - _chromeHeight, 40.0),
        );
        final layout = CutLayout.place(pieces, area);
        final paint = CustomPaint(
          painter: CutSheetPainter(
            specs: specs,
            layout: layout,
            labelFontFamily: labelFontFamily,
          ),
          size: Size(contentWidth, layout.contentHeight),
        );

        return Container(
          color: const Color(0xFFE7EBF2),
          padding: const EdgeInsets.all(_outerPadding),
          child: Center(
            child: RepaintBoundary(
              key: captureKey,
              child: Container(
                width: sheetWidth,
                height: sheetHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFC3CCDA)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Container(
                      height: _captionBarHeight,
                      width: double.infinity,
                      color: const Color(0xFF0B62C4),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Text(
                            'Раскрой плёнки',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Заготовок: ${pieces.length} шт',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ClipRect(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _innerPadding,
                            vertical: _piecesVerticalPadding,
                          ),
                          child: pieces.isEmpty
                              ? const Center(
                                  child: Text(
                                    'В заказе нет окон — кроить нечего',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Color(0xFF66748A),
                                    ),
                                  ),
                                )
                              : layout.contentHeight <= area.height
                              ? Center(child: paint)
                              : SingleChildScrollView(child: paint),
                        ),
                      ),
                    ),
                    _CutTotalsBlock(specs: specs),
                    SizedBox(
                      height: titleBlockHeight,
                      child: _CutTitleBlock(project: project, specs: specs),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Заготовка плёнки: фактический контур в миллиметрах.
///
/// [widthMm] и [heightMm] — габарит контура (по нему упаковывается лист),
/// [outline] — сам контур в миллиметрах с началом в левом нижнем углу
/// габарита и осью Y вверх. Для прямоугольного окна контур не хранится
/// (`outline` пуст) — это экономит память и сохраняет прежнее поведение.
class CutPiece {
  const CutPiece({
    required this.widthMm,
    required this.heightMm,
    this.outline = const [],
    this.contours = const [],
    this.areaM2 = 0,
  });

  /// Заготовка к раскрою: плёнка с напайкой под окантовку, припуском на
  /// раскрой и компенсацией усадки ПВХ (см.
  /// [WindowSpec.filmCutPolygonWithShrinkage]).
  factory CutPiece.ofSpec(WindowSpec spec) {
    final areaM2 = spec.filmCutAreaWithShrinkageM2;
    // Заготовка обычного окна (в том числе трапеции и окна с разными
    // высотами) — ВСЕГДА прямоугольник ширина × высота. Размеры берём из
    // filmCut*WithShrinkage, а не из габарита полигона: даже если контур
    // почему-то окажется пустым или схлопнутым, лист «Раскрой» не останется
    // без заготовки.
    final width = _positive(spec.filmCutWidthWithShrinkage);
    final height = _positive(spec.filmCutHeightWithShrinkage);
    if (!spec.params.isTShape) {
      return CutPiece(
        widthMm: width,
        heightMm: height,
        outline: [
          Offset.zero,
          Offset(width, 0),
          Offset(width, height),
          Offset(0, height),
        ],
        areaM2: areaM2,
      );
    }

    // У Т-окна без спайки заготовок две: каждая нормализуется к общему
    // габариту, чтобы лист «Раскрой» показал обе части.
    final polygons = spec.filmCutPolygonsWithShrinkage;
    if (polygons.isEmpty) {
      return CutPiece(
        widthMm: width,
        heightMm: height,
        areaM2: areaM2,
      );
    }
    final bounds = boundsOfAll(polygons);
    if (bounds.width <= 0 || bounds.height <= 0) {
      return CutPiece(
        widthMm: width,
        heightMm: height,
        areaM2: areaM2,
      );
    }
    final contours = [
      for (final polygon in polygons)
        [
          for (final point in polygon)
            Offset(point.dx - bounds.left, point.dy - bounds.top),
        ],
    ];
    return CutPiece(
      widthMm: bounds.width,
      heightMm: bounds.height,
      outline: contours.first,
      contours: contours,
      areaM2: areaM2,
    );
  }
  final double widthMm;
  final double heightMm;

  /// Контур заготовки, мм: начало в левом нижнем углу габарита, ось Y вверх.
  /// Пустой список — заготовка прямоугольная. У Т-окна без спайки здесь
  /// первый контур, полный список — [contours].
  final List<Offset> outline;

  /// Все контуры заготовки: у обычного окна один, у Т-окна без спайки два.
  final List<List<Offset>> contours;

  /// Площадь к раскрою по фактическому контуру, м² (с усадкой, минус вырезы).
  /// Ноль — посчитать по габариту (для заготовок, созданных вручную).
  final double areaM2;

  /// Некорректные размеры не роняют лист: считаем их минимальной заготовкой.
  static double _positive(double value) =>
      (!value.isFinite || value <= 0) ? 1 : value;

  bool get hasContour => allContours.isNotEmpty;

  /// Все контуры: явный список [contours] или одиночный [outline].
  List<List<Offset>> get allContours => contours.isNotEmpty
      ? contours
      : (outline.length >= 3 ? [outline] : const []);

  /// Площадь фактических контуров, мм² (без вычетов вырезов).
  double get areaMm2 {
    if (!hasContour) return widthMm * heightMm;
    var area = 0.0;
    for (final contour in allContours) {
      area += polygonArea(contour).abs();
    }
    return area;
  }

  /// Длины сторон по обходу всех контуров (мм).
  ///
  /// У обычного окна порядок прежний: низ, право, верх, лево. У Т-окна без
  /// спайки сначала идут четыре стороны основного полотна, затем приставки.
  List<double> get sideLengths {
    if (!hasContour) return [widthMm, heightMm, widthMm, heightMm];
    return [
      for (final contour in allContours)
        for (var i = 0; i < contour.length; i++)
          (contour[(i + 1) % contour.length] - contour[i]).distance,
    ];
  }

  double get minSideMm => sideLengths.isEmpty
      ? math.min(widthMm, heightMm)
      : sideLengths.reduce(math.min);

  /// Отношение сторон заготовки (ширина / высота).
  double get aspect => heightMm <= 0 ? 1 : widthMm / heightMm;
}

/// Место заготовки на листе: прямоугольник в точках листа.
class CutPlacement {
  const CutPlacement({
    required this.index,
    required this.piece,
    required this.rect,
    required this.row,
    required this.column,
  });

  /// Номер окна в заказе (с нуля) — порядок заготовок сохраняется.
  final int index;

  final CutPiece piece;

  /// Прямоугольник заготовки в координатах области заготовок.
  final Rect rect;

  final int row;
  final int column;

  /// Габариты заготовки, мм — для подписей и проверок.
  double get widthMm => piece.widthMm;
  double get heightMm => piece.heightMm;
}

/// Раскладка заготовок по листу: один масштаб на все заготовки.
///
/// Считается только по ширине листа и «естественной» полосе ряда, поэтому
/// результат устойчив: лист растёт по числу рядов, а не по высоте окна.
class CutLayout {
  const CutLayout._({
    required this.placements,
    required this.scale,
    required this.rows,
    required this.contentWidth,
    required this.contentHeight,
    required this.smallestSidePx,
  });

  /// Заготовки в порядке окон.
  final List<CutPlacement> placements;

  /// Общий масштаб: сколько точек листа приходится на один миллиметр.
  final double scale;

  final int rows;

  /// Габариты всей раскладки, точки.
  final double contentWidth;
  final double contentHeight;

  /// Меньшая сторона самой мелкой заготовки на листе, точки.
  final double smallestSidePx;

  /// Зазор между заготовками по горизонтали, точки.
  static const double columnGap = 26;

  /// Зазор между рядами, точки.
  static const double rowGap = 16;

  /// Поля под размерные линии: слева и справа, сверху и снизу.
  static const double sideMargin = 42;
  static const double topMargin = 34;
  static const double bottomMargin = 36;

  /// Место под подписи «№1 · материал» и «с усадкой …» под заготовкой.
  static const double captionHeight = 44;

  /// Естественная высота полосы ряда: одна строка занимает ~420–460 точек.
  static const double preferredRowHeight = 460;

  /// Самая крупная заготовка занимает около 75 % полосы ряда.
  static const double pieceHeightFraction = 0.75;

  /// Меньшая сторона заготовки не должна быть неразличимой.
  static const double minSmallSidePx = 60;

  /// Раскладывает заготовки по области [area]: в ряд слева направо, с
  /// переносом на новый ряд, когда не хватает ширины.
  ///
  /// Масштаб один для всех заготовок: самая крупная заготовка занимает около
  /// 75 % высоты доступной области, а если заготовок много — масштаб
  /// уменьшается так, чтобы вся раскладка поместилась в [area].
  static CutLayout place(List<CutPiece> pieces, Size area) {
    if (pieces.isEmpty) return _empty;

    final width = (area.width.isFinite && area.width > 0) ? area.width : 900.0;
    final height = (area.height.isFinite && area.height > 0)
        ? area.height
        : preferredRowHeight;

    final naturalLayout = _wrap(
      pieces,
      _naturalScale(pieces, width, height),
      width,
    );
    if (naturalLayout.contentHeight <= height) return naturalLayout;

    // Не влезло по высоте: уменьшаем ОБЩИЙ масштаб, пока всё не поместится.
    // Так заготовки остаются одного масштаба и не обрезаются.
    var low = naturalLayout.scale * 0.001;
    var high = naturalLayout.scale;
    var best = _wrap(pieces, low, width);
    if (best.contentHeight > height) return best;
    for (var i = 0; i < 30; i++) {
      final middle = (low + high) / 2;
      final candidate = _wrap(pieces, middle, width);
      if (candidate.contentHeight <= height) {
        best = candidate;
        low = middle;
      } else {
        high = middle;
      }
    }
    return best;
  }

  /// Раскладка «естественного» масштаба без подгонки по высоте: по ней
  /// считается нужная высота листа, когда заготовок много.
  static CutLayout natural(List<CutPiece> pieces, double width) {
    if (pieces.isEmpty) return _empty;
    final safeWidth = (width.isFinite && width > 0) ? width : 900.0;
    return _wrap(
      pieces,
      _naturalScale(pieces, safeWidth, preferredRowHeight),
      safeWidth,
    );
  }

  static const CutLayout _empty = CutLayout._(
    placements: [],
    scale: 1,
    rows: 0,
    contentWidth: 0,
    contentHeight: 0,
    smallestSidePx: 0,
  );

  /// «Естественный» масштаб: самая крупная заготовка — около 75 % высоты
  /// полосы ряда, мелкие не различимы не остаются, всё влезает в ширину листа.
  static double _naturalScale(
    List<CutPiece> pieces,
    double width,
    double height,
  ) {
    var maxWidthMm = 0.0;
    var maxHeightMm = 0.0;
    var minSideMm = double.infinity;
    for (final piece in pieces) {
      maxWidthMm = math.max(maxWidthMm, piece.widthMm);
      maxHeightMm = math.max(maxHeightMm, piece.heightMm);
      minSideMm = math.min(minSideMm, piece.minSideMm);
    }

    var scale = pieceHeightFraction * height / maxHeightMm;
    // Одна заготовка вместе с размерными линиями обязана влезать в ширину.
    final widthLimit = (width - 2 * sideMargin) / maxWidthMm;
    if (widthLimit.isFinite && widthLimit > 0) {
      scale = math.min(scale, widthLimit);
    }
    // Мелкие заготовки не должны стать неразличимыми.
    if (minSideMm.isFinite &&
        minSideMm > 0 &&
        widthLimit.isFinite &&
        widthLimit > 0) {
      final readable = minSmallSidePx / minSideMm;
      if (readable > scale) scale = math.min(readable, widthLimit);
    }
    if (!scale.isFinite || scale <= 0) scale = 0.001;
    return scale;
  }

  /// Укладывает заготовки рядами при заданном масштабе.
  static CutLayout _wrap(List<CutPiece> pieces, double scale, double width) {
    final placements = <CutPlacement>[];
    final row =
        <
          ({
            int index,
            CutPiece piece,
            double left,
            double heightPx,
            int column,
          })
        >[];
    var x = 0.0;
    var top = 0.0;
    var rowIndex = 0;
    var rowHeightPx = 0.0;
    var contentWidth = 0.0;
    var column = 0;

    void flushRow() {
      if (row.isEmpty) return;
      final cellHeight = topMargin + rowHeightPx + bottomMargin + captionHeight;
      for (final item in row) {
        placements.add(
          CutPlacement(
            index: item.index,
            piece: item.piece,
            // Заготовки ряда выравниваем по нижней кромке: подписи под ними
            // оказываются на одной линии.
            rect: Rect.fromLTWH(
              item.left + sideMargin,
              top + topMargin + (rowHeightPx - item.heightPx),
              item.piece.widthMm * scale,
              item.heightPx,
            ),
            row: rowIndex,
            column: item.column,
          ),
        );
      }
      top += cellHeight + rowGap;
      rowIndex += 1;
      row.clear();
      rowHeightPx = 0;
      x = 0;
      column = 0;
    }

    var smallestSidePx = double.infinity;
    for (var i = 0; i < pieces.length; i++) {
      final piece = pieces[i];
      final widthPx = piece.widthMm * scale;
      final heightPx = piece.heightMm * scale;
      final cellWidth = widthPx + 2 * sideMargin;
      // Перенос на новый ряд, когда заготовка не влезает по ширине.
      if (row.isNotEmpty && x + cellWidth > width + 0.5) flushRow();
      row.add((
        index: i,
        piece: piece,
        left: x,
        heightPx: heightPx,
        column: column,
      ));
      x += cellWidth + columnGap;
      column += 1;
      contentWidth = math.max(contentWidth, x - columnGap);
      rowHeightPx = math.max(rowHeightPx, heightPx);
      smallestSidePx = math.min(smallestSidePx, piece.minSideMm * scale);
    }
    flushRow();

    return CutLayout._(
      placements: placements,
      scale: scale,
      rows: rowIndex,
      contentWidth: contentWidth,
      contentHeight: math.max(top - rowGap, 0),
      smallestSidePx: smallestSidePx.isFinite ? smallestSidePx : 0,
    );
  }
}

/// Палитра заготовки: полупрозрачная заливка, кромка и признак клетки.
class CutPalette {
  const CutPalette({
    required this.fill,
    required this.edge,
    this.mesh = false,
    this.meshColor = const Color(0x33707B8A),
  });

  final Color fill;
  final Color edge;

  /// Москитная сетка рисуется мелкой клеткой.
  final bool mesh;
  final Color meshColor;

  static CutPalette of(FilmMaterial material) => switch (material) {
    FilmMaterial.clearPvc => const CutPalette(
      fill: Color(0x335AA7E8),
      edge: Color(0xFF4C9BE8),
    ),
    FilmMaterial.tintedPvc => const CutPalette(
      fill: Color(0x40546886),
      edge: Color(0xFF54688A),
    ),
    FilmMaterial.mosquitoNet => const CutPalette(
      fill: Color(0x2E8A93A0),
      edge: Color(0xFF7C8798),
      mesh: true,
    ),
    // Скрин — простая серая заливка, без клетки.
    FilmMaterial.screen => const CutPalette(
      fill: Color(0x33B9BEC4),
      edge: Color(0xFF8C9298),
    ),
  };
}

/// Отрисовка листа раскроя: прямоугольники заготовок, размеры, площади, подписи.
///
/// Только прямоугольники, линии и текст: ни Path.combine, ни прочей геометрии,
/// которая не работает в вебе.
class CutSheetPainter extends CustomPainter {
  CutSheetPainter({
    required this.specs,
    required this.layout,
    this.labelFontFamily,
    LengthUnit? unit,
  }) : unit = unit ?? DisplayUnits.unit;

  final List<WindowSpec> specs;
  final CutLayout layout;
  final String? labelFontFamily;

  /// Единица подписей: при переключении мм/см лист перерисовывается.
  final LengthUnit unit;

  static const Color _ink = Color(0xFF1B1F27);
  static const Color _dim = Color(0xFF41506A);
  static const double _meshStep = 7;

  @override
  void paint(Canvas canvas, Size size) {
    if (layout.placements.isEmpty) return;
    final dx = math.max((size.width - layout.contentWidth) / 2, 0.0);
    for (final placement in layout.placements) {
      if (placement.index < 0 || placement.index >= specs.length) continue;
      _paintPiece(
        canvas,
        placement.rect.shift(Offset(dx, 0)),
        specs[placement.index],
        placement,
      );
    }
  }

  void _paintPiece(
    Canvas canvas,
    Rect rect,
    WindowSpec spec,
    CutPlacement placement,
  ) {
    final palette = CutPalette.of(spec.params.material);
    final path = _piecePath(rect, placement.piece);

    // Полупрозрачная плёнка, как на чертеже. Форма — фактический контур:
    // прямоугольник, трапеция или четырёхугольник с разными высотами.
    canvas.drawPath(path, Paint()..color = palette.fill);
    if (palette.mesh) _paintMesh(canvas, path, rect, palette.meshColor);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = palette.edge,
    );

    _paintArea(canvas, rect, placement.piece, spec);
    _paintDimensions(canvas, rect, placement);
    _paintCaption(canvas, rect, spec, placement.index);
  }

  /// Путь заготовки на листе: контур в мм переводится в точки листа.
  ///
  /// Ось Y модели направлена вверх, ось Y листа — вниз, поэтому Y зеркалится.
  Path _piecePath(Rect rect, CutPiece piece) {
    final path = Path();
    if (!piece.hasContour) {
      path.addRect(rect);
      return path;
    }
    final contours = _screenContours(rect, piece);
    if (contours.isEmpty) {
      path.addRect(rect);
      return path;
    }
    for (final points in contours) {
      if (points.isEmpty) continue;
      path.moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      path.close();
    }
    return path;
  }

  /// Все контуры в координатах листа (у Т-окна без спайки их два).
  List<List<Offset>> _screenContours(Rect rect, CutPiece piece) {
    final contours = piece.allContours;
    if (contours.isEmpty) return const [];
    return [
      for (final contour in contours)
        [
          for (final point in contour)
            Offset(
              rect.left + point.dx / piece.widthMm * rect.width,
              rect.bottom - point.dy / piece.heightMm * rect.height,
            ),
        ],
    ];
  }

  /// Мелкая клетка москитной сетки — только линии внутри контура.
  void _paintMesh(Canvas canvas, Path path, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipPath(path);
    for (var x = rect.left + _meshStep; x < rect.right; x += _meshStep) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
    for (var y = rect.top + _meshStep; y < rect.bottom; y += _meshStep) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
    canvas.restore();
  }

  /// Площадь заготовки к раскрою крупно по центру контура.
  ///
  /// Площадь берётся фактическая (по контуру, с усадкой и без вырезов), а не
  /// габаритная: для трапеции это то же число, что в ведомости и смете.
  ///
  /// У окна с молнией под площадью стоит строка «− полоса молнии 50 мм»:
  /// заготовка уже сужена на полосу (у ПВХ и у скрина одинаково), и человек
  /// должен видеть, почему ширина меньше готового размера с подворотами или
  /// видимого размера плёнки с запайкой.
  void _paintArea(Canvas canvas, Rect rect, CutPiece piece, WindowSpec spec) {
    final areaM2 = piece.areaM2 > 0 ? piece.areaM2 : piece.areaMm2 / 1000000;
    final text = '${formatMeters(areaM2)} м²';
    var fontSize = math.min(21.0, rect.height * 0.34);
    if (fontSize < 8) return;
    var painter = _painter(text, fontSize: fontSize, bold: true);
    while (fontSize > 8 && painter.width > rect.width - 12) {
      fontSize -= 1;
      painter = _painter(text, fontSize: fontSize, bold: true);
    }
    if (painter.width > rect.width - 6 || painter.height > rect.height - 6) {
      return;
    }
    // Светлая подложка: поверх клетки сетки цифры иначе теряются.
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: rect.center,
          width: painter.width + 12,
          height: painter.height + 6,
        ),
        const Radius.circular(4),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.62),
    );
    painter.paint(
      canvas,
      rect.center - Offset(painter.width / 2, painter.height / 2),
    );

    final zipperBand = spec.zipperBandTotalMm;
    if (zipperBand <= 0) return;
    final note = '− полоса молнии ${formatMm(zipperBand)} ${unitSuffix()}';
    final notePainter = _painter(note, color: _dim, small: true);
    // Строка не должна вылезать за заготовку: на мелких заготовках она
    // останется только в подписи под ними.
    if (notePainter.width > rect.width - 12) return;
    final noteTop = rect.center.dy + painter.height / 2 + 4;
    if (noteTop + notePainter.height > rect.bottom - 4) return;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(rect.center.dx, noteTop + notePainter.height / 2),
          width: notePainter.width + 10,
          height: notePainter.height + 4,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.88),
    );
    notePainter.paint(
      canvas,
      Offset(rect.center.dx - notePainter.width / 2, noteTop),
    );
  }

  /// Размеры заготовки по всем четырём сторонам фактического контура.
  ///
  /// Для прямоугольника это прежние «ширина сверху/снизу» и «высота
  /// слева/справа». Для трапеции каждая сторона получает свою длину, а
  /// наклонные стороны — наклонную размерную линию.
  void _paintDimensions(Canvas canvas, Rect rect, CutPlacement placement) {
    final piece = placement.piece;
    final contours = _screenContours(rect, piece);
    if (contours.isEmpty) return;

    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.1;
    final center = rect.center;

    for (var c = 0; c < contours.length; c++) {
      final points = contours[c];
      if (points.length < 3) continue;
      final contour = piece.allContours[c];
      final lengths = [
        for (var i = 0; i < contour.length; i++)
          (contour[(i + 1) % contour.length] - contour[i]).distance,
      ];
      for (var i = 0; i < points.length; i++) {
        final a = points[i];
        final b = points[(i + 1) % points.length];
        final direction = b - a;
        final lengthPx = direction.distance;
        if (lengthPx < 1) continue;
        final unit = direction / lengthPx;
        var normal = Offset(-unit.dy, unit.dx);
        final middle = (a + b) / 2;
        // Нормаль наружу: от центра заготовки.
        if ((middle + normal - center).distance <
            (middle - normal - center).distance) {
          normal = -normal;
        }
        final offset = normal * 16;
        final a2 = a + offset;
        final b2 = b + offset;

        // Выносные линии и размерная линия со стрелками.
        canvas.drawLine(a + normal * 3, a2 + normal * 6, paint);
        canvas.drawLine(b + normal * 3, b2 + normal * 6, paint);
        canvas.drawLine(a2, b2, paint);
        _arrow(canvas, a2, -unit);
        _arrow(canvas, b2, unit);

        _label(
          canvas,
          formatMm(lengths[i]),
          (a2 + b2) / 2 + normal * 11,
          angle: _uprightAngle(direction),
          small: true,
          color: _dim,
        );
      }
    }
  }

  /// Угол подписи вдоль отрезка, повёрнутый так, чтобы текст читался слева
  /// направо.
  double _uprightAngle(Offset direction) {
    var angle = math.atan2(direction.dy, direction.dx);
    if (angle > math.pi / 2) angle -= math.pi;
    if (angle < -math.pi / 2) angle += math.pi;
    return angle;
  }

  void _arrow(Canvas canvas, Offset tip, Offset direction) {
    const length = 9.0;
    const halfWidth = 3.0;
    final back = tip - direction * length;
    final normal = Offset(-direction.dy, direction.dx) * halfWidth;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
        ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
        ..close(),
      Paint()..color = _ink,
    );
  }

  /// Подпись под заготовкой: номер и материал, припуск и усадка.
  void _paintCaption(Canvas canvas, Rect rect, WindowSpec spec, int index) {
    final params = spec.params;
    final material = params.material.label;
    _label(
      canvas,
      // «Обычный ПВХ» → «обычный ПВХ», аббревиатуру не трогаем.
      '№${index + 1} · ${material[0].toLowerCase()}${material.substring(1)}',
      Offset(rect.center.dx, rect.bottom + 48),
      color: _ink,
    );
    final parts = <String>[
      // Окно с молнией кроится уже: ширина заготовки уменьшена на полосу
      // молнии у всех материалов. Показываем оба числа, чтобы подпись не
      // расходилась с готовым размером и подворотами/запайкой
      // (2 530 → 2 480 мм при полосе 50 мм).
      if (spec.zipperBandTotalMm > 0)
        'ширина заготовки '
            '${formatMm(spec.filmCutWidthBeforeZipper)}'
            ' → ${formatMm(spec.filmCutWidth)} ${unitSuffix()}, '
            'минус полоса молнии ${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()}',
      if (params.hasManualAllowance)
        'припуск ${params.allowanceWidthLabel}/'
            '${params.manualAllowanceHeightLabel} ${unitSuffix()}',
      if (params.hasAutoHeightAllowance)
        'авто +${formatMm(params.autoHeightAllowanceMm)} ${unitSuffix()} к высоте (ПВХ)',
      if (params.hasShrinkage)
        'с усадкой ${formatPercent(params.effectiveShrinkagePercent)}: '
            '${formatMm(spec.filmCutWidthWithShrinkage)} × '
            '${formatMm(spec.filmCutHeightWithShrinkage)} ${unitSuffix()}',
    ];
    if (parts.isNotEmpty) {
      _label(
        canvas,
        parts.join(' · '),
        Offset(rect.center.dx, rect.bottom + 64),
        small: true,
        color: _dim,
      );
    }
  }

  TextPainter _painter(
    String text, {
    Color color = _ink,
    double fontSize = 12.5,
    bool small = false,
    bool bold = false,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: small ? 10.5 : fontSize,
          fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          fontFamily: labelFontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  /// Подпись с белой подложкой по центру точки.
  void _label(
    Canvas canvas,
    String text,
    Offset position, {
    double angle = 0,
    bool small = false,
    Color color = _ink,
  }) {
    final painter = _painter(text, color: color, small: small);
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(angle);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset.zero,
          width: painter.width + 8,
          height: painter.height + 4,
        ),
        const Radius.circular(3),
      ),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CutSheetPainter oldDelegate) =>
      oldDelegate.layout != layout ||
      oldDelegate.specs != specs ||
      oldDelegate.labelFontFamily != labelFontFamily ||
      oldDelegate.unit != unit;
}

/// Итоги раскроя: количество, площади заготовок и материалы.
class _CutTotals {
  _CutTotals(this.specs) {
    for (final spec in specs) {
      // Плёнка в раскрое — заготовка по фактическому контуру: припуск и
      // усадка уже внутри, вырезы вычтены. Для косого окна это меньше
      // габаритного прямоугольника, по которому идёт только упаковка.
      filmAreaM2 += spec.filmCutAreaM2;
      filmAreaWithShrinkageM2 += spec.filmCutAreaWithShrinkageM2;
      productAreaM2 += spec.productAreaM2;
      areaByMaterial.update(
        spec.params.material,
        (value) => value + spec.filmCutAreaWithShrinkageM2,
        ifAbsent: () => spec.filmCutAreaWithShrinkageM2,
      );
    }
  }

  final List<WindowSpec> specs;

  /// Площадь заготовок к раскрою по фактическому контуру (с припуском), м².
  double filmAreaM2 = 0;
  double filmAreaWithShrinkageM2 = 0;
  double productAreaM2 = 0;

  /// Площадь заготовок по материалам.
  final Map<FilmMaterial, double> areaByMaterial = {};

  /// Подписи по материалам: «Обычный ПВХ — 8,57 м²».
  List<String> get materialLabels {
    final entries = areaByMaterial.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries)
        '${entry.key.label} — ${formatMeters(entry.value)} м²',
    ];
  }
}

/// Блок итогов перед штампом.
class _CutTotalsBlock extends StatelessWidget {
  const _CutTotalsBlock({required this.specs});

  final List<WindowSpec> specs;

  @override
  Widget build(BuildContext context) {
    final totals = _CutTotals(specs);
    final materials = totals.materialLabels;

    return Container(
      height: CutSheet._totalsHeight,
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFD9E0EA))),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'ИТОГИ ПО РАСКРОЮ',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.8,
                  color: Color(0xFF66748A),
                ),
              ),
              const Spacer(),
              Text(
                'Масштаб заготовок единый · размеры в ${unitSuffix()}',
                style: const TextStyle(
                  fontSize: 9.5,
                  color: Color(0xFF8A93A0),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _statTile('Заготовок', '${specs.length} шт')),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  'Площадь заготовок с усадкой',
                  '${formatMeters(totals.filmAreaWithShrinkageM2)} м²',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  'Без усадки (прямоугольник)',
                  '${formatMeters(totals.filmAreaM2)} м²',
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Материалы: ${materials.isEmpty ? '—' : materials.join(' · ')}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF2B3440)),
          ),
          const SizedBox(height: 4),
          const Text(
            'Это размеры готовых заготовок к раскрою; раскладка на рулоне — '
            'на отдельном листе.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              height: 1.2,
              color: Color(0xFF66748A),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        border: Border.all(color: const Color(0xFFD9E0EA)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8.5,
              height: 1.15,
              letterSpacing: 0.4,
              fontWeight: FontWeight.w700,
              color: Color(0xFF5B6B80),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16324F),
            ),
          ),
        ],
      ),
    );
  }
}

/// Штамп снизу — в стиле остальных листов.
class _CutTitleBlock extends StatelessWidget {
  const _CutTitleBlock({required this.project, required this.specs});

  final OrderProject project;
  final List<WindowSpec> specs;

  @override
  Widget build(BuildContext context) {
    final totals = _CutTotals(specs);
    final first = project.windows.isEmpty ? null : project.windows.first;
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}.${now.year}';

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1B1F27), width: 1.4)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _cell('Изделие', first?.projectName ?? '')),
          Expanded(flex: 2, child: _cell('Заказчик', first?.customer ?? '')),
          Expanded(
            flex: 2,
            child: _cell('Окон в заказе', '${project.windowCount} шт'),
          ),
          Expanded(flex: 2, child: _cell('Дата', date)),
          Expanded(
            flex: 3,
            child: _cell(
              'Площадь изделий',
              '${formatMeters(totals.productAreaM2)} м²',
            ),
          ),
          Expanded(
            flex: 3,
            child: _cell(
              'Площадь заготовок с усадкой',
              '${formatMeters(totals.filmAreaWithShrinkageM2)} м²',
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFC3CCDA))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8.5,
              height: 1.15,
              letterSpacing: 0.4,
              color: Color(0xFF7C8798),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF1B1F27),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
