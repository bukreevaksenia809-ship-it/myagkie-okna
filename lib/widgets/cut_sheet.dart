import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';

/// Лист «Раскрой плёнки» — вырезанные заготовки мягких окон.
///
/// В отличие от листа «Раскладка» (там заготовки уложены на рулон), здесь
/// показаны сами заготовки: каждая — прямоугольник в ОДНОМ общем масштабе,
/// с размерами по бокам, площадью внутри и подписью материала под ним.
/// Заготовки идут в порядке окон, слева направо, с переносом на новый ряд.
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
  static const double _chromeHeight = _captionBarHeight +
      _totalsHeight +
      titleBlockHeight +
      _piecesVerticalPadding * 2;

  /// То же плюс поля вокруг листа — полная высота «обвязки» листа.
  static const double _sheetChrome = _chromeHeight + _outerPadding * 2;

  /// Заготовки заказа: по одной на окно, в порядке окон.
  static List<CutPiece> piecesOf(OrderProject project) => [
        for (final window in project.windows) CutPiece.ofSpec(WindowSpec.of(window)),
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
        final sheetWidth =
            math.max(constraints.maxWidth - _outerPadding * 2, 320.0);
        final sheetHeight =
            math.max(constraints.maxHeight - _outerPadding * 2, 320.0);
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

/// Заготовка плёнки: габариты прямоугольника в миллиметрах.
class CutPiece {
  const CutPiece({required this.widthMm, required this.heightMm});

  /// Габарит заготовки к раскрою: плёнка с напайкой под окантовку, плюс
  /// припуск на раскрой (см. [WindowSpec.filmCutWidthWithAllowance]) и
  /// компенсация усадки ПВХ.
  factory CutPiece.ofSpec(WindowSpec spec) => CutPiece(
        widthMm: _positive(spec.filmCutWidthWithShrinkage),
        heightMm: _positive(spec.filmCutHeightWithShrinkage),
      );

  final double widthMm;
  final double heightMm;

  /// Некорректные размеры не роняют лист: считаем их минимальной заготовкой.
  static double _positive(double value) =>
      (!value.isFinite || value <= 0) ? 1 : value;

  double get areaMm2 => widthMm * heightMm;

  double get minSideMm => math.min(widthMm, heightMm);

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

    final naturalLayout = _wrap(pieces, _naturalScale(pieces, width, height), width);
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
    if (minSideMm.isFinite && minSideMm > 0 && widthLimit.isFinite && widthLimit > 0) {
      final readable = minSmallSidePx / minSideMm;
      if (readable > scale) scale = math.min(readable, widthLimit);
    }
    if (!scale.isFinite || scale <= 0) scale = 0.001;
    return scale;
  }

  /// Укладывает заготовки рядами при заданном масштабе.
  static CutLayout _wrap(List<CutPiece> pieces, double scale, double width) {
    final placements = <CutPlacement>[];
    final row = <({int index, CutPiece piece, double left, double heightPx, int column})>[];
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
        placements.add(CutPlacement(
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
        ));
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
  });

  final List<WindowSpec> specs;
  final CutLayout layout;
  final String? labelFontFamily;

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

    // Полупрозрачная плёнка, как на чертеже.
    canvas.drawRect(rect, Paint()..color = palette.fill);
    if (palette.mesh) _paintMesh(canvas, rect, palette.meshColor);
    canvas.drawRect(
      rect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..color = palette.edge,
    );

    _paintArea(canvas, rect, spec);
    _paintDimensions(canvas, rect, placement);
    _paintCaption(canvas, rect, spec, placement.index);
  }

  /// Мелкая клетка москитной сетки — только линии внутри прямоугольника.
  void _paintMesh(Canvas canvas, Rect rect, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    canvas.save();
    canvas.clipRect(rect);
    for (var x = rect.left + _meshStep; x < rect.right; x += _meshStep) {
      canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    }
    for (var y = rect.top + _meshStep; y < rect.bottom; y += _meshStep) {
      canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    }
    canvas.restore();
  }

  /// Площадь заготовки к раскрою крупно по центру прямоугольника.
  void _paintArea(Canvas canvas, Rect rect, WindowSpec spec) {
    final text = '${formatMeters(spec.filmCutAreaM2)} м²';
    var fontSize = math.min(21.0, rect.height * 0.34);
    if (fontSize < 8) return;
    var painter = _painter(text, fontSize: fontSize, bold: true);
    while (fontSize > 8 && painter.width > rect.width - 12) {
      fontSize -= 1;
      painter = _painter(text, fontSize: fontSize, bold: true);
    }
    if (painter.width > rect.width - 6 || painter.height > rect.height - 6) return;
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
  }

  /// Размеры заготовки: ширина сверху и снизу, высота слева и справа.
  void _paintDimensions(Canvas canvas, Rect rect, CutPlacement placement) {
    _horizontalDimension(
      canvas,
      rect,
      rect.top - 16,
      formatMm(placement.piece.widthMm),
      above: true,
    );
    _horizontalDimension(
      canvas,
      rect,
      rect.bottom + 16,
      formatMm(placement.piece.widthMm),
      above: false,
    );
    _verticalDimension(
      canvas,
      rect,
      rect.left - 16,
      formatMm(placement.piece.heightMm),
      left: true,
    );
    _verticalDimension(
      canvas,
      rect,
      rect.right + 16,
      formatMm(placement.piece.heightMm),
      left: false,
    );
  }

  void _horizontalDimension(
    Canvas canvas,
    Rect rect,
    double y,
    String text, {
    required bool above,
  }) {
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.1;
    canvas.drawLine(Offset(rect.left, y), Offset(rect.right, y), paint);
    _arrow(canvas, Offset(rect.left, y), const Offset(-1, 0));
    _arrow(canvas, Offset(rect.right, y), const Offset(1, 0));
    final edge = above ? rect.top : rect.bottom;
    final tick = above ? -3.0 : 3.0;
    canvas.drawLine(Offset(rect.left, edge), Offset(rect.left, y + tick), paint);
    canvas.drawLine(Offset(rect.right, edge), Offset(rect.right, y + tick), paint);
    _label(
      canvas,
      text,
      Offset(rect.center.dx, y + (above ? -11 : 11)),
      small: true,
      color: _dim,
    );
  }

  void _verticalDimension(
    Canvas canvas,
    Rect rect,
    double x,
    String text, {
    required bool left,
  }) {
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.1;
    canvas.drawLine(Offset(x, rect.top), Offset(x, rect.bottom), paint);
    _arrow(canvas, Offset(x, rect.top), const Offset(0, -1));
    _arrow(canvas, Offset(x, rect.bottom), const Offset(0, 1));
    final edge = left ? rect.left : rect.right;
    final tick = left ? -3.0 : 3.0;
    canvas.drawLine(Offset(edge, rect.top), Offset(x + tick, rect.top), paint);
    canvas.drawLine(Offset(edge, rect.bottom), Offset(x + tick, rect.bottom), paint);
    _label(
      canvas,
      text,
      Offset(x + (left ? -12 : 12), rect.center.dy),
      angle: -math.pi / 2,
      small: true,
      color: _dim,
    );
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
      if (params.hasManualAllowance)
        'припуск ${params.allowanceWidthLabel}/'
            '${params.manualAllowanceHeightLabel} мм',
      if (params.hasAutoHeightAllowance)
        'авто +${formatMm(params.autoHeightAllowanceMm)} мм к высоте (ПВХ)',
      if (params.hasShrinkage)
        'с усадкой ${formatPercent(params.effectiveShrinkagePercent)}: '
            '${formatMm(spec.filmCutWidthWithShrinkage)} × '
            '${formatMm(spec.filmCutHeightWithShrinkage)} мм',
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
      oldDelegate.labelFontFamily != labelFontFamily;
}

/// Итоги раскроя: количество, площади заготовок и материалы.
class _CutTotals {
  _CutTotals(this.specs) {
    for (final spec in specs) {
      // Плёнка в раскрое — заготовка (габарит): припуск уже внутри, усадка
      // компенсируется в габаритах, поэтому в расход идёт площадь с усадкой.
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

  /// Площадь заготовок к раскрою (с припуском), м².
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
              const Text(
                'Масштаб заготовок единый · размеры в мм',
                style: TextStyle(fontSize: 9.5, color: Color(0xFF8A93A0)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _statTile('Заготовок', '${specs.length} шт'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  'Заготовки (габарит) с усадкой',
                  '${formatMeters(totals.filmAreaWithShrinkageM2)} м²',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statTile(
                  'Без усадки (габарит)',
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
            style: TextStyle(fontSize: 9.5, height: 1.2, color: Color(0xFF66748A)),
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
    final date = '${now.day.toString().padLeft(2, '0')}.'
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
            child: _cell('Площадь изделий',
                '${formatMeters(totals.productAreaM2)} м²'),
          ),
          Expanded(
            flex: 3,
            child: _cell('Заготовки (габарит) с усадкой',
                '${formatMeters(totals.filmAreaWithShrinkageM2)} м²'),
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
