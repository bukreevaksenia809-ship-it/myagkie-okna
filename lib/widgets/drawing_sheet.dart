import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';
import '../models/fastener_spans.dart';
import '../services/fastener_artwork.dart';
import '../services/company_branding.dart';
import '../services/label_settings.dart';
import 'window_painter.dart';

/// Лист чертежа: одно окно подробно или несколько окон заказа с нумерацией.
class DrawingSheet extends StatelessWidget {
  const DrawingSheet({
    super.key,
    required this.project,
    this.captureKey,
    this.labelFontFamily,
    this.company,
    this.onParamsChanged,
  });

  final OrderProject project;

  /// Ключ области, которую снимаем для экспорта.
  final GlobalKey? captureKey;

  /// Шрифт подписей на чертеже; null — системный шрифт.
  final String? labelFontFamily;

  /// Компания для штампа: логотип и реквизиты (если включено).
  final CompanyBrandingState? company;

  /// Правка параметров прямо на чертеже (перетаскивание люверсов).
  final ValueChanged<WindowParams>? onParamsChanged;

  /// Ширина листа A4 в логических точках: 210 мм при 150 dpi.
  static const double a4Width = 1240;

  /// Высота листа A4: 297 мм при 150 dpi.
  static const double a4Height = 1754;

  /// Отношение сторон A4 — 1 : 1,4142 (высота к ширине).
  static const double a4Aspect = a4Height / a4Width;

  /// Плотность листа: 1240 точек на 210 мм (150 dpi).
  static const double a4PxPerMm = a4Width / 210;

  /// Чертёж рисуется в «экранных» точках 96 dpi — в них стандартный масштаб
  /// (1:10, 1:15, 1:20 …) совпадает с масштабной линейкой, — а затем
  /// растягивается до плотности листа. Поэтому напечатанный чертёж измеряется
  /// линейкой без поправок: 1000 мм модели при 1:20 дают ровно 50 мм на бумаге.
  static const double _paintScale = a4PxPerMm / (96 / 25.4);

  static const double titleBlockHeight = 44;

  /// Ширина боковой панели: компактно под A4 (≈36 мм).
  static const double sidePanelWidth = 210;

  static const double _outerPadding = 20;
  static const double _captionHeight = 42;

  /// Высота компактной легенды внизу листа (точек).
  static const double compactLegendHeight = 58;

  /// Внутренний отступ ячейки раскладки 2–3 окон.
  static const double _cellMargin = 2;

  /// Размер листа в рабочей области: сам лист A4 плюс поля рабочей области.
  ///
  /// Лист не подстраивается под окно программы — у него всегда пропорции A4
  /// (210 × 297 мм). Одно окно — одна страница, режим «Все окна» — по
  /// странице на ряд окон, страницы стыкуются вертикально.
  ///
  /// [viewport] больше не влияет на размер листа: он оставлен в подписи,
  /// потому что листы раскладки и раскроя считают свой размер от окна.
  static Size? detailedSheetSize(OrderProject project, Size viewport) => Size(
    a4Width + _outerPadding * 2,
    a4Height * a4PageCount(project) + _outerPadding * 2,
  );

  /// Сколько страниц A4 занимает лист чертежа.
  ///
  /// Одно окно (и режим «Одно окно») — одна страница. В режиме «Все окна» —
  /// по странице на ряд окон: ряд не разрезается между страницами.
  static int a4PageCount(OrderProject project) {
    if (!project.isMultiWindow || project.sheetMode != SheetMode.grid) return 1;
    final columns = project.gridColumns == 0
        ? _columnsFor(project.windowCount)
        : project.gridColumns;
    return (project.windowCount / math.max(columns, 1)).ceil();
  }

  /// Показывать сетку всех окон или подробно одно выбранное.
  bool get _showGrid =>
      project.sheetMode == SheetMode.grid && project.isMultiWindow;

  /// Свободное поле страницы A4 под оптимизированную раскладку 2–3 окон.
  ///
  /// Формула повторяет колонку страницы в [build]: страница A4 минус
  /// компактная легенда, при необходимости фартук и штамп. Отдельный метод
  /// нужен тестам и превью: они проверяют ту же геометрию, что и виджет.
  static Size optimizedGridArea({double apronHeight = 0}) => Size(
    a4Width,
    a4Height - titleBlockHeight - compactLegendHeight - apronHeight,
  );

  /// Включать ли автоматический перебор раскладки для 2–3 окон.
  ///
  /// Только режим «Авто, окон в ряду» ([OrderProject.gridColumns] == 0):
  /// явные 1–4 колонки остаются осмысленными и работают как раньше.
  bool get _useOptimizedGrid =>
      _showGrid &&
      project.gridColumns == 0 &&
      project.windowCount >= 2 &&
      project.windowCount <= 3;

  /// Высота плашки «фартук» на странице, точек.
  double get _apronHeight =>
      project.windows.any((window) => window.pocket || window.pocketTop)
      ? 32
      : 0;

  /// Доли высоты листа, по которым PDF режется ровно по границам A4.
  ///
  /// Лист собран из страниц A4 одинаковой высоты, поэтому резать можно только
  /// между страницами: окно никогда не окажется разрезанным. Одна страница —
  /// резать нечего.
  static List<double>? safeBreakFractions(OrderProject project, Size viewport) {
    final pages = a4PageCount(project);
    if (pages < 2) return null;
    return [for (var page = 1; page < pages; page++) page / pages];
  }

  /// Метрики листа: рамка чертежа, поле листа, масштаб и габарит изделия.
  ///
  /// Считаются ровно так же, как при отрисовке ([_drawingFrame] и
  /// [_drawingLayout]), поэтому тесты и превью проверяют фактический лист, а
  /// не приблизительную формулу. По ним видно, какую долю листа занимает
  /// чертёж: у обычного окна, у Т-окна с одной и с двумя пристройками она
  /// должна быть сопоставимой.
  static DrawingSheetMetrics metricsFor(OrderProject project) {
    final spec = WindowSpec.of(project.selected);
    final area = Size(
      math.max(a4Width - sidePanelWidth - 1, 160.0),
      math.max(a4Height - titleBlockHeight - _captionHeight, 120.0),
    );
    final frame = _drawingFrame(area, spec);
    final layout = _drawingLayout(frame, spec);
    return DrawingSheetMetrics(
      frame: frame,
      area: area,
      scaleDenominator: layout.scaleDenominator,
      productSize: Size(
        spec.geometry.spanX * layout.scale * _paintScale,
        spec.geometry.spanY * layout.scale * _paintScale,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Фото пластиковой скобы догружается один раз. Как только оно готово,
    // ValueListenableBuilder перерисует лист — и в снимок для печати/PDF
    // замок попадёт уже картинкой.
    FastenerArtwork.ensureFrenchLock();
    FastenerArtwork.ensurePlasticClip();
    return ValueListenableBuilder<LabelSettings>(
      valueListenable: LabelSettings.current,
      builder: (context, labelSettings, _) => ListenableBuilder(
        listenable: Listenable.merge([
          FastenerArtwork.frenchLock,
          FastenerArtwork.plasticClip,
        ]),
        builder: (context, _) {
          final isClip =
              project.selected.fastenerType == FastenerType.frenchLocks;
          final image = isClip
              ? FastenerArtwork.plasticClip.value
              : FastenerArtwork.frenchLock.value;
          return _buildSheet(image);
        },
      ),
    );
  }

  /// Лист чертежа с уже загруженной (или ещё нет) картинкой крепежа.
  Widget _buildSheet(ui.Image? fastenerImage) {
    final pages = a4PageCount(project);
    final paper = RepaintBoundary(
      key: captureKey,
      child: Container(
        // Лист всегда одного размера — A4, независимо от окна программы.
        width: a4Width,
        height: a4Height * pages,
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        // Рамку рисуем поверх содержимого: она не отнимает место у страниц,
        // поэтому границы A4 внутри листа остаются точными.
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFC3CCDA)),
        ),
        child: _showGrid
            ? _buildGridPages(pages, fastenerImage)
            : _buildSingle(fastenerImage),
      ),
    );

    return Container(
      color: const Color(0xFFE7EBF2),
      padding: const EdgeInsets.all(_outerPadding),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Лист не сжимаем под окно программы: если места мало, он просто
          // выходит за поля и листается прокруткой.
          if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
            return paper;
          }
          return OverflowBox(
            alignment: Alignment.center,
            minWidth: 0,
            minHeight: 0,
            maxWidth: double.infinity,
            maxHeight: double.infinity,
            child: paper,
          );
        },
      ),
    );
  }

  /// Поля подробного чертежа — под размеры и выноски (в точках листа).
  static const double _detailPadLeft = 104;
  static const double _detailPadRight = 104;
  static const double _detailPadTop = 86;
  static const double _detailPadBottom = 96;

  /// Меньшие поля для ячейки режима «Все окна»: там чертёж мельче.
  ///
  /// Меньше 80 ставить нельзя: размерные линии и подписи выносятся от контура
  /// окна на 52–75 точек, и при меньшем поле их обрежет рамка.
  static const double _cellPad = 88;

  /// Поля автоматической раскладки 2–3 окон.
  ///
  /// 100 точек — как у прежних «2 в ряд»: размерная подпись встаёт в 62
  /// точки от контура плюс запас на крупный кегль из настроек (до 85 точек),
  /// поэтому после поворота на 90° она не упирается в рамку ячейки.
  static const double _optimizedGridPad = 100;

  /// Запас к размеру рамки: страхует пересчёт масштаба от погрешности.
  static const double _frameSlack = 2;

  /// Раскладка чертежа для свободного поля [area] (в точках листа).
  ///
  /// Чертёж всегда считается в «экранных» точках 96 dpi — в них стандартный
  /// масштаб (1:10, 1:15, 1:20 …) совпадает с масштабной линейкой. Поэтому
  /// поле переводим в эти точки делением на [paintScale], а поля оставляем
  /// как есть: их размеры заданы в тех же точках, что и выноски чертежа.
  static DrawingLayout _drawingLayout(
    Size area,
    WindowSpec spec, {
    double paintScale = _paintScale,
    double padLeft = _detailPadLeft,
    double padRight = _detailPadRight,
    double padTop = _detailPadTop,
    double padBottom = _detailPadBottom,
    bool fitExactly = false,
  }) => DrawingLayout(
    size: area / paintScale,
    geometry: spec.geometry,
    padLeft: padLeft,
    padRight: padRight,
    padTop: padTop,
    padBottom: padBottom,
    fitExactly: fitExactly,
  );

  /// Рамка чертежа: масштаб выбираем по свободному полю, затем строим рамку
  /// ровно под сам чертёж плюс поля под размеры и выноски.
  ///
  /// К размеру рамки добавлен небольшой запас: тогда масштаб, пересчитанный
  /// от рамки, не «прыгнет» на следующий стандартный из-за погрешности
  /// округления, и чертёж гарантированно влезает в рамку.
  static Size _drawingFrame(
    Size area,
    WindowSpec spec, {
    double paintScale = _paintScale,
    double padLeft = _detailPadLeft,
    double padRight = _detailPadRight,
    double padTop = _detailPadTop,
    double padBottom = _detailPadBottom,
    bool fitExactly = false,
  }) {
    final layout = _drawingLayout(
      area,
      spec,
      paintScale: paintScale,
      padLeft: padLeft,
      padRight: padRight,
      padTop: padTop,
      padBottom: padBottom,
      fitExactly: fitExactly,
    );
    return Size(
      (spec.geometry.spanX * layout.scale + padLeft + padRight) * paintScale +
          _frameSlack,
      (spec.geometry.spanY * layout.scale + padTop + padBottom) * paintScale +
          _frameSlack,
    );
  }

  /// Отрисовка чертежа в рамке [frame].
  ///
  /// У листа одного окна чертёж рисуется в точках 96 dpi и растягивается до
  /// плотности листа A4 ([paintScale]): так масштаб на бумаге остаётся
  /// честным, а линии и подписи — резкими. В режиме «Все окна» чертежи мелкие
  /// и масштаб у каждого свой — их рисуем как есть.
  Widget _drawingBox({
    required Size frame,
    required DrawingLayout layout,
    required WindowParams params,
    required WindowSpec spec,
    double paintScale = _paintScale,
    double labelScale = 1,
    ui.Image? fastenerImage,
    ValueChanged<WindowParams>? onParamsChanged,
  }) {
    final paintSize = frame / paintScale;
    return SizedBox(
      width: frame.width,
      height: frame.height,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.center,
          minWidth: 0,
          minHeight: 0,
          maxWidth: paintSize.width,
          maxHeight: paintSize.height,
          child: Transform.scale(
            scale: paintScale,
            child: SizedBox(
              width: paintSize.width,
              height: paintSize.height,
              child: Builder(
                builder: (context) {
                  final drawing = DecoratedBox(
                    decoration: BoxDecoration(
                      border: Border.all(color: const Color(0xFF9FB0C6)),
                    ),
                    child: CustomPaint(
                      key: const Key('drawing-canvas'),
                      painter: WindowDrawingPainter(
                        params: params,
                        layout: layout,
                        layers: spec.layers,
                        options: project.options,
                        labelFontFamily: labelFontFamily,
                        showScaleBar: false,
                        labelScale: labelScale,
                        fastenerImage: fastenerImage,
                      ),
                      size: Size.infinite,
                    ),
                  );
                  if (onParamsChanged == null) return drawing;
                  return _EyeletDragLayer(
                    key: const Key('drawing-eyelet-layer'),
                    params: params,
                    spec: spec,
                    layout: layout,
                    onChanged: onParamsChanged,
                    child: drawing,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Крупная плашка «ФАРТУК СНИЗУ / СВЕРХУ» в нижней части чертежа.
  Widget _apronBanner({required bool bottom, required bool top}) {
    if (!bottom && !top) return const SizedBox.shrink();
    final label = bottom && top
        ? 'ФАРТУК СНИЗУ И СВЕРХУ'
        : bottom
        ? 'ФАРТУК СНИЗУ'
        : 'ФАРТУК СВЕРХУ';
    return Container(
      key: const Key('apron-banner'),
      height: 32,
      width: double.infinity,
      alignment: Alignment.center,
      color: const Color(0xFFFFF4E0),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w900,
          letterSpacing: 1.2,
          color: Color(0xFF8A4B00),
        ),
      ),
    );
  }

  /// Лист одного окна (или одного выбранного окна заказа): одна страница A4.
  Widget _buildSingle(ui.Image? fastenerImage) {
    final params = project.selected;
    final spec = WindowSpec.of(params);
    final apronHeight = (params.pocket || params.pocketTop) ? 32.0 : 0.0;
    final area = Size(
      math.max(a4Width - sidePanelWidth - 1, 160.0),
      math.max(
        a4Height - titleBlockHeight - _captionHeight - apronHeight,
        120.0,
      ),
    );
    final frame = _drawingFrame(area, spec);
    // Раскладку считаем уже от рамки: в ней и рисуется чертёж.
    final layout = _drawingLayout(frame, spec);

    return Column(
      children: [
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Column(
                  children: [
                    SizedBox(
                      height: _captionHeight,
                      child: _Caption(
                        number: project.selectedIndex + 1,
                        params: params,
                        spec: spec,
                        highlighted: true,
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _drawingBox(
                          frame: frame,
                          layout: layout,
                          params: params,
                          spec: spec,
                          fastenerImage: fastenerImage,
                          onParamsChanged: onParamsChanged,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const VerticalDivider(
                width: 1,
                thickness: 1,
                color: Color(0xFFC3CCDA),
              ),
              SizedBox(
                width: sidePanelWidth,
                child: _SidePanel(
                  project: project,
                  labelFontFamily: labelFontFamily,
                  scaleLabel: layout.scaleLabel,
                  scaleDenominator: layout.scaleDenominator,
                ),
              ),
            ],
          ),
        ),
        _apronBanner(bottom: params.pocket, top: params.pocketTop),
        SizedBox(
          height: titleBlockHeight,
          child: _TitleBlock(
            project: project,
            scaleLabel: layout.scaleLabel,
            company: company,
          ),
        ),
      ],
    );
  }

  /// Режим «Все окна»: страница A4 на ряд окон, страницы стыкуются сверху вниз.
  ///
  /// Каждая страница самодостаточна — со своей рамкой, легендой и штампом,
  /// поэтому её можно напечатать отдельно, а PDF режется ровно по границам
  /// страниц ([safeBreakFractions]).
  Widget _buildGridPages(int pages, ui.Image? fastenerImage) {
    final columns = project.gridColumns == 0
        ? _columnsFor(project.windowCount)
        : project.gridColumns;

    // 2–3 окна в режиме «Авто»: раскладку и повороты выбирает перебор
    // ([optimizedGridPlan]), а не фиксированное число колонок. Лист из 2–3
    // окон всегда занимает ровно одну страницу A4.
    final plan = _useOptimizedGrid && pages == 1
        ? optimizedGridPlan(
            project,
            optimizedGridArea(apronHeight: _apronHeight),
          )
        : null;
    final optimized = plan != null;
    // 2–3 окна на листе отдают площадь чертежам: боковой панели нет, её
    // заменяет компактная легенда внизу. У прежних «2 в ряд» (в том числе
    // для 4+ окон) панели не было изначально — сохраняем это. Исключение —
    // явное «1 в ряд (подробно)»: подробному листу одного окна панель нужна.
    final compactPage =
        optimized || columns == 2 || (columns >= 2 && project.windowCount <= 3);

    // Для двух окон на листе отдаём максимум ширины чертежам: боковая
    // панель уже, поля ячеек меньше. Иначе окна стоят узкими столбиками.
    final gridSideWidth = columns == 2 ? 160.0 : sidePanelWidth;
    return Column(
      children: [
        for (var page = 0; page < pages; page++)
          SizedBox(
            height: a4Height,
            child: Column(
              children: [
                Expanded(
                  child: optimized && page == 0
                      ? _buildOptimizedPage(plan, fastenerImage)
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _buildGridRow(
                                page,
                                columns,
                                fastenerImage,
                              ),
                            ),
                            // В автоматической раскладке и для 2–3 окон
                            // боковой панели нет: всё поле страницы отдано
                            // чертежам, обозначения — полосой внизу.
                            if (!compactPage && columns != 2) ...[
                              const VerticalDivider(
                                width: 1,
                                thickness: 1,
                                color: Color(0xFFC3CCDA),
                              ),
                              SizedBox(
                                width: gridSideWidth,
                                child: _SidePanel(
                                  project: project,
                                  labelFontFamily: labelFontFamily,
                                  scaleLabel: 'по окнам',
                                  // У набора окон масштаб у каждого свой —
                                  // линейку показывает только лист одного
                                  // окна.
                                  scaleDenominator: 0,
                                ),
                              ),
                            ],
                          ],
                        ),
                ),
                if (compactPage) const _CompactLegend(),
                _apronBanner(
                  bottom: project.windows.any((window) => window.pocket),
                  top: project.windows.any((window) => window.pocketTop),
                ),
                SizedBox(
                  height: titleBlockHeight,
                  child: _TitleBlock(
                    project: project,
                    scaleLabel: 'по окнам',
                    company: company,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Страница с автоматически выбранной раскладкой и поворотами.
  ///
  /// Ячейки ставим абсолютно по координатам плана: тогда геометрия, которую
  /// проверили тесты, совпадает с тем, что нарисовано на листе.
  Widget _buildOptimizedPage(DrawingGridPlan plan, ui.Image? fastenerImage) {
    return SizedBox.expand(
      child: Stack(
        children: [
          for (final cell in plan.cells)
            Positioned.fromRect(
              rect: cell.rect,
              child: _buildPlanCell(cell, fastenerImage),
            ),
        ],
      ),
    );
  }

  /// Ячейка автоматической раскладки: чертёж (при необходимости повёрнутый)
  /// и горизонтальная подпись окна под ним.
  Widget _buildPlanCell(DrawingGridCellPlan cell, ui.Image? fastenerImage) {
    final params = project.windows[cell.windowIndex];
    final spec = WindowSpec.of(params);
    final isSelected = cell.windowIndex == project.selectedIndex;
    final drawing = _drawingBox(
      frame: cell.frame,
      layout: cell.layout,
      params: params,
      spec: spec,
      paintScale: 1,
      labelScale: cell.labelScale,
      fastenerImage: fastenerImage,
    );
    return Container(
      margin: const EdgeInsets.all(_cellMargin),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0x0F0B62C4) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              // Поворачиваем весь чертёж целиком: RotatedBox меняет местами
              // оси, поэтому размерные линии и подписи поворачиваются вместе
              // с контуром и остаются в системе самого painter.
              child: cell.quarterTurns == 0
                  ? drawing
                  : RotatedBox(quarterTurns: cell.quarterTurns, child: drawing),
            ),
          ),
          SizedBox(
            height: _captionHeight,
            child: _Caption(
              number: cell.windowIndex + 1,
              params: params,
              spec: spec,
              highlighted: isSelected,
              scaleLabel: formatExactScaleLabel(cell.scale),
              quarterTurns: cell.quarterTurns,
            ),
          ),
        ],
      ),
    );
  }

  /// Ряд окон одной страницы A4.
  Widget _buildGridRow(int page, int columns, ui.Image? fastenerImage) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 2, 2),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final cellWidth = constraints.maxWidth / columns;
          final cellHeight = constraints.maxHeight;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var column = 0; column < columns; column++)
                Expanded(
                  child: _buildCell(
                    page * columns + column,
                    Size(cellWidth, cellHeight),
                    fastenerImage,
                    pad: columns == 2 ? 100 : _cellPad,
                    labelScale: columns == 2 ? 0.9 : 0.66,
                    fitExactly: columns == 2,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Число колонок: до трёх окон — в ряд, четыре — 2×2, далее по три.
  static int _columnsFor(int count) {
    if (count <= 3) return math.max(count, 1);
    if (count == 4) return 2;
    if (count <= 9) return 3;
    return 4;
  }

  // ------------------------------------------- автоматическая раскладка
  //
  // Задача: для 2–3 окон на одном A4 выбрать самую крупную раскладку.
  // Перебор явный и конечный:
  //
  //  2 окна: «2 в ряд», «2 в столбец»                — 2 раскладки;
  //  3 окна: «3 в ряд», «3 в столбец», «2+1», «1+2»  — 4 раскладки,
  //          причём в «2+1»/«1+2» одиночным перебираем каждое из трёх окон
  //          (3 варианта), потому что окна разного размера;
  //  повороты: каждое окно независимо — 0° или 90° (2² = 4 и 2³ = 8);
  //  пропорции строк: 29 вариантов для двух строк (15…85 %, шаг 2,5 %) и
  //          с шагом 5 % для трёх строк (обе границы 10…80 %, сумма ≤ 90 %).
  //
  // Для каждого варианта масштаб окна считается точным ([DrawingLayout] с
  // fitExactly), затем вариант оценивается метрикой:
  //   1) максимум минимального масштаба по окнам — чтобы самое мелкое окно
  //      было как можно крупнее;
  //   2) при равенстве — максимум суммарной площади чертежей;
  //   3) при равенстве — меньше поворотов (привычнее читать);
  //   4) при равенстве — ровнее строки.
  // Так «магии» нет: видно, какие варианты перебраны и по какому правилу
  // выбран победитель.

  /// Перебирает раскладки 2–3 окон и возвращает самую крупную.
  ///
  /// [pageArea] — поле страницы A4 под чертежи (без легенды, фартука и
  /// штампа). Для 2–3 окон авто-режима это [optimizedGridArea].
  static DrawingGridPlan? optimizedGridPlan(
    OrderProject project,
    Size pageArea, {
    double pad = _optimizedGridPad,
  }) {
    final count = project.windowCount;
    if (count < 2 || count > 3) return null;
    if (pageArea.width <= 0 || pageArea.height <= 0) return null;
    final area = Rect.fromLTWH(0, 0, pageArea.width, pageArea.height);
    final specs = [for (final params in project.windows) WindowSpec.of(params)];

    DrawingGridPlan? best;
    for (final arrangement in DrawingGridArrangement.values) {
      for (final rows in _rowAssignments(arrangement, count)) {
        for (final heights in _rowSplits(rows.length)) {
          for (var rotations = 0; rotations < (1 << count); rotations++) {
            final candidate = _evaluateLayout(
              arrangement: arrangement,
              specs: specs,
              area: area,
              rows: rows,
              heights: heights,
              rotations: rotations,
              pad: pad,
            );
            if (candidate == null) continue;
            if (best == null || candidate.isBetterThan(best)) {
              best = candidate;
            }
          }
        }
      }
    }
    return best;
  }

  /// Какие окна в каких строках для каждой раскладки.
  static List<List<List<int>>> _rowAssignments(
    DrawingGridArrangement arrangement,
    int count,
  ) {
    if (count == 2) {
      return switch (arrangement) {
        DrawingGridArrangement.twoInRow => const [
          [
            [0, 1],
          ],
        ],
        DrawingGridArrangement.twoInColumn => const [
          [
            [0],
            [1],
          ],
        ],
        _ => const [],
      };
    }
    const all = [0, 1, 2];
    return switch (arrangement) {
      DrawingGridArrangement.threeInRow => const [
        [
          [0, 1, 2],
        ],
      ],
      DrawingGridArrangement.threeInColumn => const [
        [
          [0],
          [1],
          [2],
        ],
      ],
      // «2+1»: два окна сверху, одно снизу. Одиночным может быть любое окно.
      DrawingGridArrangement.twoPlusOne => [
        for (final single in all)
          [
            [
              for (final index in all)
                if (index != single) index,
            ],
            [single],
          ],
      ],
      // «1+2»: одно окно сверху на всю ширину, два снизу.
      DrawingGridArrangement.onePlusTwo => [
        for (final single in all)
          [
            [single],
            [
              for (final index in all)
                if (index != single) index,
            ],
          ],
      ],
      _ => const [],
    };
  }

  /// Доли высоты строк. Перебираем конечный набор, а не решаем «на глаз».
  static List<List<double>> _rowSplits(int rows) {
    if (rows <= 1) {
      return const [
        [1],
      ];
    }
    if (rows == 2) {
      // Верхняя строка — от 15 до 85 %: слишком узкие строки отсеет проверка
      // читаемости ниже, зато не пропустим выгодную неравную раскладку.
      return [
        for (var step = 0; step <= 28; step++)
          [0.15 + step * 0.025, 0.85 - step * 0.025],
      ];
    }
    final result = <List<double>>[];
    for (var first = 10; first <= 80; first += 5) {
      for (var second = 10; second <= 80; second += 5) {
        if (first + second > 90) continue;
        result.add([first / 100, second / 100, (100 - first - second) / 100]);
      }
    }
    return result;
  }

  /// Один вариант раскладки: считает масштаб каждого окна и метрику.
  ///
  /// Возвращает null, если вариант физически не влезает или подписи станут
  /// нечитаемыми — такие варианты не участвуют в сравнении.
  static DrawingGridPlan? _evaluateLayout({
    required DrawingGridArrangement arrangement,
    required List<WindowSpec> specs,
    required Rect area,
    required List<List<int>> rows,
    required List<double> heights,
    required int rotations,
    required double pad,
  }) {
    final cells = <DrawingGridCellPlan>[];
    var top = area.top;
    var minScale = double.infinity;
    var totalArea = 0.0;
    var rotatedCount = 0;

    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final rowWindows = rows[rowIndex];
      final rowHeight = area.height * heights[rowIndex];
      final cellWidth = area.width / rowWindows.length;
      for (var column = 0; column < rowWindows.length; column++) {
        final windowIndex = rowWindows[column];
        final rect = Rect.fromLTWH(
          area.left + column * cellWidth,
          top,
          cellWidth,
          rowHeight,
        );
        // Поле под чертёж: без подписи окна и внутреннего отступа ячейки.
        final available = Size(
          rect.width - _cellMargin * 2,
          rect.height - _cellMargin * 2 - _captionHeight,
        );
        // Ниже 120 точек размерные линии и подписи сливаются — вариант
        // нечитаем и в переборе не участвует.
        if (available.width < 120 || available.height < 120) {
          return null;
        }

        final rotated = (rotations & (1 << windowIndex)) != 0;
        // Оставляем место под запас рамки (_frameSlack), чтобы готовый
        // чертёж вошёл в поле ячейки без обрезки.
        final fitArea = rotated
            ? Size(
                available.height - _frameSlack,
                available.width - _frameSlack,
              )
            : Size(
                available.width - _frameSlack,
                available.height - _frameSlack,
              );
        final frame = _drawingFrame(
          fitArea,
          specs[windowIndex],
          paintScale: 1,
          padLeft: pad,
          padRight: pad,
          padTop: pad,
          padBottom: pad,
          fitExactly: true,
        );
        final layout = _drawingLayout(
          frame,
          specs[windowIndex],
          paintScale: 1,
          padLeft: pad,
          padRight: pad,
          padTop: pad,
          padBottom: pad,
          fitExactly: true,
        );
        final scale = layout.scale;
        if (!scale.isFinite || scale <= 0) return null;
        final footprint = rotated ? Size(frame.height, frame.width) : frame;
        if (footprint.width > available.width + 0.001 ||
            footprint.height > available.height + 0.001) {
          return null;
        }
        final drawingRect = Rect.fromCenter(
          center: Offset(
            rect.center.dx,
            rect.top + _cellMargin + available.height / 2,
          ),
          width: footprint.width,
          height: footprint.height,
        );
        cells.add(
          DrawingGridCellPlan(
            windowIndex: windowIndex,
            rect: rect,
            drawingRect: drawingRect,
            available: available,
            frame: frame,
            scale: scale,
            quarterTurns: rotated ? 1 : 0,
            layout: layout,
            // Крупная ячейка — подписи как на подробном листе (1,0);
            // в тесной ячейке чуть мельче, но не ниже 0,8 — иначе при
            // печати цифры размеров не прочитать.
            labelScale: available.shortestSide >= 560
                ? 1.0
                : available.shortestSide >= 420
                ? 0.9
                : 0.8,
          ),
        );
        minScale = math.min(minScale, scale);
        totalArea +=
            specs[windowIndex].geometry.spanX *
            specs[windowIndex].geometry.spanY *
            scale *
            scale;
        if (rotated) rotatedCount++;
      }
      top += rowHeight;
    }
    cells.sort((a, b) => a.windowIndex.compareTo(b.windowIndex));
    return DrawingGridPlan(
      arrangement: arrangement,
      area: area,
      cells: cells,
      minScale: minScale,
      totalArea: totalArea,
      pad: pad,
      rotatedCount: rotatedCount,
      rowBalance: _rowBalance(heights),
    );
  }

  /// Насколько строки далеки от равных: 0 — одинаковые.
  static double _rowBalance(List<double> heights) {
    final even = 1 / heights.length;
    var sum = 0.0;
    for (final height in heights) {
      final delta = height - even;
      sum += delta * delta;
    }
    return sum;
  }

  Widget _buildCell(
    int index,
    Size cellSize,
    ui.Image? fastenerImage, {
    double pad = _cellPad,
    double labelScale = 0.9,
    bool fitExactly = false,
  }) {
    if (index >= project.windows.length) return const SizedBox.shrink();
    final params = project.windows[index];
    final spec = WindowSpec.of(params);
    final isSelected = index == project.selectedIndex;
    final area = Size(
      math.max(cellSize.width - 4, 80.0),
      math.max(cellSize.height - 4 - _captionHeight, 60.0),
    );
    final frame = _drawingFrame(
      area,
      spec,
      paintScale: 1,
      padLeft: pad,
      padRight: pad,
      padTop: pad,
      padBottom: pad,
      fitExactly: fitExactly,
    );
    final layout = _drawingLayout(
      frame,
      spec,
      paintScale: 1,
      padLeft: pad,
      padRight: pad,
      padTop: pad,
      padBottom: pad,
      fitExactly: fitExactly,
    );

    return Container(
      margin: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: isSelected ? const Color(0x0F0B62C4) : null,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        children: [
          Expanded(
            child: Center(
              child: _drawingBox(
                frame: frame,
                layout: layout,
                params: params,
                spec: spec,
                paintScale: 1,
                // Подробный режим: подписи крупные, в ячейке они чуть мельче.
                labelScale: labelScale,
                fastenerImage: fastenerImage,
              ),
            ),
          ),
          SizedBox(
            height: _captionHeight,
            child: _Caption(
              number: index + 1,
              params: params,
              spec: spec,
              highlighted: isSelected,
            ),
          ),
        ],
      ),
    );
  }
}

/// Взаимное расположение 2–3 окон на одном A4.
enum DrawingGridArrangement {
  twoInRow('2 в ряд'),
  twoInColumn('2 в столбец'),
  threeInRow('3 в ряд'),
  threeInColumn('3 в столбец'),
  twoPlusOne('2 + 1'),
  onePlusTwo('1 + 2');

  const DrawingGridArrangement(this.label);

  /// Человеческая подпись варианта — для отчётов, тестов и отладки.
  final String label;
}

/// Одна ячейка выбранной автоматической раскладки.
///
/// Хранит готовую геометрию, поэтому лист рисует ровно то, что проверил
/// перебор: ничего не пересчитывается второй раз «примерно так же».
class DrawingGridCellPlan {
  const DrawingGridCellPlan({
    required this.windowIndex,
    required this.rect,
    required this.drawingRect,
    required this.available,
    required this.frame,
    required this.scale,
    required this.quarterTurns,
    required this.layout,
    required this.labelScale,
  });

  /// Номер окна в заказе, с нуля.
  final int windowIndex;

  /// Внешняя ячейка: чертёж и подпись окна.
  final Rect rect;

  /// Рамка чертежа на листе, уже с учётом поворота.
  final Rect drawingRect;

  /// Поле под чертёж внутри ячейки: без подписи и внутреннего отступа.
  final Size available;

  /// Размер рамки в системе painter (до поворота).
  final Size frame;

  /// Точек листа на миллиметр модели. Точный, без округления до стандартного.
  final double scale;

  /// 0 — окно как нарисовано, 1 — повёрнуто на 90° по часовой.
  final int quarterTurns;

  /// Раскладка painter для этой ячейки — её же получает [WindowDrawingPainter].
  final DrawingLayout layout;

  /// Кегль подписей в ячейке (1 — как в подробном листе).
  final double labelScale;

  /// Повёрнуто ли окно (подписи и размерные линии повёрнуты вместе с ним).
  bool get isRotated => quarterTurns.isOdd;

  /// Габарит рамки на листе с учётом поворота.
  Size get footprint => isRotated ? Size(frame.height, frame.width) : frame;

  /// Габарит изделия на листе с учётом поворота, точки.
  Size get productSize => isRotated
      ? Size(layout.geometry.spanY * scale, layout.geometry.spanX * scale)
      : Size(layout.geometry.spanX * scale, layout.geometry.spanY * scale);
}

/// Результат перебора: выбранная раскладка, повороты и масштабы окон.
class DrawingGridPlan {
  const DrawingGridPlan({
    required this.arrangement,
    required this.area,
    required this.cells,
    required this.minScale,
    required this.totalArea,
    required this.pad,
    required this.rotatedCount,
    required this.rowBalance,
  });

  /// Какая раскладка победила.
  final DrawingGridArrangement arrangement;

  /// Поле страницы, на котором построен план.
  final Rect area;

  /// Ячейки в порядке номеров окон.
  final List<DrawingGridCellPlan> cells;

  /// Минимальный масштаб по окнам, точек листа на миллиметр модели.
  final double minScale;

  /// Суммарная площадь чертежей изделий, точек² — вторая метрика.
  final double totalArea;

  /// Поле под размерные линии в каждой ячейке, точек.
  final double pad;

  /// Сколько окон повёрнуто на 90°.
  final int rotatedCount;

  /// Насколько строки далеки от равных: 0 — одинаковые.
  final double rowBalance;

  /// Есть ли повёрнутые окна.
  bool get hasRotations => rotatedCount > 0;

  /// Точные масштабы окон одной строкой — для подписи и отчёта.
  String get scaleSummary {
    final labels = <String>[];
    for (final cell in cells) {
      final label = formatExactScaleLabel(cell.scale);
      if (!labels.contains(label)) labels.add(label);
    }
    return labels.join(' · ');
  }

  /// Лучше ли этот план, чем [other], по метрике из задачи.
  bool isBetterThan(DrawingGridPlan other) {
    // 1. Максимальный минимальный масштаб: самое мелкое окно — крупнее.
    final scaleDelta = minScale - other.minScale;
    final scaleTolerance = math.max(1e-12, other.minScale.abs() * 1e-9);
    if (scaleDelta.abs() > scaleTolerance) return scaleDelta > 0;

    // 2. При равном минимуме — максимальная суммарная площадь чертежей.
    final areaTolerance = math.max(1e-6, other.totalArea.abs() * 1e-9);
    if ((totalArea - other.totalArea).abs() > areaTolerance) {
      return totalArea > other.totalArea;
    }

    // 3. Меньше поворотов — чертёж привычнее читать.
    if (rotatedCount != other.rotatedCount) {
      return rotatedCount < other.rotatedCount;
    }

    // 4. Ровнее строки — лист выглядит аккуратнее.
    return rowBalance < other.rowBalance - 1e-12;
  }

  @override
  String toString() =>
      'DrawingGridPlan(${arrangement.label}, '
      'min 1:${((96 / 25.4) / minScale).toStringAsFixed(1)}, '
      'rotated=$rotatedCount, cells=${cells.length})';
}

/// Точный масштаб чертежа без округления до стандартного ряда.
///
/// [formatScaleLabel] подбирает ближайший «красивый» знаменатель (1:20), а в
/// автоматической раскладке масштаб точный: подпись должна быть точной, иначе
/// по ней нельзя измерить чертёж. Например, «М 1:18,4».
String formatExactScaleLabel(double pxPerMm) {
  if (pxPerMm <= 0 || !pxPerMm.isFinite) return 'М 1:—';
  final denominator = (96 / 25.4) / pxPerMm;
  final rounded = denominator >= 100
      ? denominator.toStringAsFixed(0)
      : denominator.toStringAsFixed(1);
  return 'М 1:${rounded.replaceAll('.', ',')}';
}

/// Компактная легенда листа «2 в ряд» — горизонтальная полоса внизу.
class _CompactLegend extends StatelessWidget {
  const _CompactLegend();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: DrawingSheet.compactLegendHeight,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: const BoxDecoration(
        color: Color(0xFFF7F9FC),
        border: Border(top: BorderSide(color: Color(0xFFD9E0EA))),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 104,
            child: Text(
              'ОБОЗНАЧЕНИЯ',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.7,
                color: Color(0xFF66748A),
              ),
            ),
          ),
          for (final item in const [
            ('Окантовка', _LegendMarkKind.edge),
            ('Запайка', _LegendMarkKind.seam),
            ('Люверс Ø10', _LegendMarkKind.eyelet),
            ('Крепёж', _LegendMarkKind.fastener),
            ('Молния', _LegendMarkKind.zipper),
            ('Фартук', _LegendMarkKind.pocket),
          ])
            Expanded(
              child: Row(
                children: [
                  _LegendMark(item.$2),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      item.$1,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 8.5,
                        color: Color(0xFF2B3440),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(
            width: 112,
            child: Text(
              'масштаб по окнам',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 8, color: Color(0xFF7C8798)),
            ),
          ),
        ],
      ),
    );
  }
}

enum _LegendMarkKind { edge, seam, eyelet, fastener, zipper, pocket }

class _LegendMark extends StatelessWidget {
  const _LegendMark(this.kind);

  final _LegendMarkKind kind;

  @override
  Widget build(BuildContext context) {
    final (color, shape, border) = switch (kind) {
      _LegendMarkKind.edge => (
        const Color(0xFF8B5A2B),
        BoxShape.rectangle,
        null,
      ),
      _LegendMarkKind.seam => (
        Colors.white,
        BoxShape.rectangle,
        const Color(0xFF8B5A2B),
      ),
      _LegendMarkKind.eyelet => (
        Colors.white,
        BoxShape.circle,
        const Color(0xFF1B1F27),
      ),
      _LegendMarkKind.fastener => (
        const Color(0xFF7C8798),
        BoxShape.rectangle,
        null,
      ),
      _LegendMarkKind.zipper => (
        const Color(0xFF1B1F27),
        BoxShape.rectangle,
        null,
      ),
      _LegendMarkKind.pocket => (
        const Color(0xFFC8A46B),
        BoxShape.rectangle,
        null,
      ),
    };
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: shape,
        border: border == null ? null : Border.all(color: border, width: 1),
      ),
    );
  }
}

/// Подпись окна под ячейкой: номер обязателен.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.number,
    required this.params,
    required this.spec,
    required this.highlighted,
    this.scaleLabel,
    this.quarterTurns = 0,
  });

  final int number;
  final WindowParams params;
  final WindowSpec spec;
  final bool highlighted;

  /// Точный масштаб окна для автоматической раскладки: «М 1:18,4».
  final String? scaleLabel;

  /// Поворот чертежа: в подписи показываем «поворот 90°», если окно
  /// повёрнуто вместе с размерами и надписями.
  final int quarterTurns;

  @override
  Widget build(BuildContext context) {
    final extra = params.drawingNumber.trim().isEmpty
        ? ''
        : ' · ${params.drawingNumber.trim()}';
    final badge = [
      if (quarterTurns.isOdd) 'поворот 90°',
      if (scaleLabel != null && scaleLabel!.isNotEmpty) scaleLabel!,
    ].join(' · ');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      color: highlighted ? const Color(0xFF0B62C4) : const Color(0xFFEEF2F8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'Окно №$number$extra',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5,
              height: 1.15,
              fontWeight: FontWeight.w700,
              color: highlighted ? Colors.white : const Color(0xFF1B1F27),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${formatMm(spec.geometry.spanX)}×${formatMm(spec.geometry.overallHeight)} ${unitSuffix()} · '
                  '${formatMeters(spec.productAreaM2)} м² · '
                  '${params.windowType.label.toLowerCase()} · люверсов ${spec.eyeletCount}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.15,
                    color: highlighted
                        ? Colors.white70
                        : const Color(0xFF66748A),
                  ),
                ),
              ),
              if (badge.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(
                  badge,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.15,
                    fontWeight: FontWeight.w700,
                    color: highlighted ? Colors.white : const Color(0xFF0B62C4),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ штамп

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({
    required this.project,
    required this.scaleLabel,
    this.company,
  });

  final CompanyBrandingState? company;
  final String scaleLabel;
  final OrderProject project;

  @override
  Widget build(BuildContext context) {
    final first = project.windows.first;
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}.${now.year}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1B1F27), width: 1.2)),
      ),
      child: Row(
        children: [
          Text(
            'Заказчик: ${first.customer.trim().isEmpty ? '—' : first.customer}',
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF2B3440),
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Text(
            date,
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF66748A)),
          ),
        ],
      ),
    );
  }
}

class _SidePanel extends StatelessWidget {
  const _SidePanel({
    required this.project,
    required this.labelFontFamily,
    required this.scaleLabel,
    required this.scaleDenominator,
  });

  final OrderProject project;

  /// Семейство шрифта подписей (в тестах подставляется системный).
  final String? labelFontFamily;

  /// Подпись масштаба листа, например «М 1:15».
  final String scaleLabel;

  /// Знаменатель масштаба: 15 для «М 1:15».
  final double scaleDenominator;

  /// Название люверса в текущей единице: «Круглый Ø10 мм» / «Круглый Ø1,0 см».
  String _eyeletLabel(WindowParams params) => params.eyeletType.displayLabel;

  @override
  Widget build(BuildContext context) {
    final labelSettings = LabelSettings.value;
    final windows = project.windows;
    final params = windows.first;
    final anyLifting = windows.any((window) => window.isLifting);
    // Подвижный крепёж (скобы, замки, ремни) есть и у скрина — он ставится по
    // подвороту независимо от типа окна.
    final anyMovable = windows.any(
      (window) => window.isScreen || window.isLifting,
    );
    final anyZipper = windows.any((window) => window.hasZipper);
    final anyCutout = windows.any((window) => window.cutouts.isNotEmpty);
    final anyWeld = windows.any(
      (window) => window.isTShape && window.tAnyWelded,
    );
    final anyPocket = windows.any((window) => window.pocket);
    final anyDrain = windows.any((window) => window.drainHoles);
    final materials = <FilmMaterial>{
      for (final window in windows) window.material,
    };

    final entries = <(LegendKind, String)>[
      if (params.isScreen)
        (
          LegendKind.seam,
          'Подворот ${params.hemBySideShortLabel} (низ/право/верх/лево), шов '
              '${formatMm(screenSeamMm)} ${unitSuffix()}',
        )
      else ...[
        (
          LegendKind.edge,
          'Окантовка по сторонам: ${_widthList(windows)} ${unitSuffix()}',
        ),
        (
          LegendKind.seam,
          'Запайка ${formatMm(params.weldOverlapMm)} ${unitSuffix()}',
        ),
      ],
      if (windows.any((window) => window.isTShape))
        (
          LegendKind.seam,
          params.isTShape
              ? params.tAnyWelded
                    ? 'Т-образное: пристроек ${params.tAnnexes.length}, '
                          'спайка по общим сторонам'
                          '${params.tAnnexes.any((annex) => annex.offset > 0) ? ', со смещением' : ''}'
                    : 'Т-образное: пристройки без спайки — отдельные окна'
              : 'Т-образные окна: см. чертежи',
        ),
      (
        LegendKind.film,
        'Полотно: ${materials.map((material) => material.label.toLowerCase()).join(', ')}',
      ),
      (
        LegendKind.eyelet,
        params.isScreen
            ? 'Люверс ${_eyeletLabel(params)} по подвороту'
            : 'Люверс ${_eyeletLabel(params)}',
      ),
      if (anyMovable)
        switch (params.fastenerType) {
          FastenerType.turnBuckles => (
            LegendKind.buckle,
            params.isScreen
                ? 'Поворотная скоба по подвороту'
                : 'Поворотная скоба',
          ),
          FastenerType.frenchLocks => (
            LegendKind.lock,
            params.isScreen
                ? 'Пластиковая скоба по подвороту'
                : 'Пластиковая скоба',
          ),
          FastenerType.metalFrenchLock => (
            LegendKind.lock,
            params.isScreen
                ? 'Французский замок по подвороту'
                : 'Французский замок',
          ),
          FastenerType.straps => (
            LegendKind.strap,
            params.isScreen
                ? 'Силиконовый ремень по подвороту'
                : 'Силиконовый ремень',
          ),
          FastenerType.eyeletsOnly => (
            LegendKind.eyelet,
            params.isScreen
                ? 'Саморезы по верхней кромке'
                : 'Крепление саморезами',
          ),
        },
      if (anyLifting)
        (
          LegendKind.liftStrap,
          'Подъёмный ремень ${formatMm(liftStrapWidth)}×'
              '${formatMm(liftStrapLength)} ${unitSuffix()}',
        ),
      if (anyZipper)
        (
          LegendKind.zipperBand,
          // У скрина полоса под молнию — из скрина, со швом 3 мм по краям;
          // у ПВХ — спайка тента шириной 50 мм.
          params.isScreen
              ? 'Полоса скрина ${formatMm(params.zipperBandWidth)} ${unitSuffix()} с молнией '
                    '(шов ${formatMm(screenSeamMm)} ${unitSuffix()})'
              : 'Спайка ${formatMm(params.zipperBandWidth)} ${unitSuffix()} с молнией по центру',
        ),
      if (anyCutout)
        (LegendKind.cutout, 'Вырез в полотне с окантовкой по контуру'),
      if (anyWeld)
        (
          LegendKind.weld,
          'Спайка с соседним окном ${formatMm(windowWeldWidth)} ${unitSuffix()}',
        ),
      if (anyPocket)
        (
          LegendKind.pocket,
          params.isScreen
              ? 'Фартук ${formatMm(params.pocketWidth)} ${unitSuffix()} (подворот)'
              : 'Фартук ${formatMm(params.pocketWidth)} ${unitSuffix()} (тент 200 мм ×2)',
        ),
      if (anyDrain)
        (LegendKind.drain, 'Дренаж Ø${formatMm(6)} ${unitSuffix()}'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SideTitle('Условные обозначения'),
          const SizedBox(height: 8),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 32,
                    height: 20,
                    child: CustomPaint(
                      painter: _LegendPainter(
                        kind: entry.$1,
                        // У скрина тента нет — знаки рисуем серым, а не цветом
                        // тента.
                        edgeColor: Color(
                          params.isScreen ? 0xFF8C9298 : params.edgeColor.value,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.$2,
                      style: TextStyle(
                        fontSize: math.min(
                          labelSettings.pxFor(LabelKind.legend),
                          16.0,
                        ),
                        color: const Color(0xFF2B3440),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (!project.isMultiWindow) ...[
            const SizedBox(height: 10),
            const _SideTitle('Расстояния между креплениями'),
            const SizedBox(height: 6),
            _FastenerSpacingList(
              spec: WindowSpec.of(project.windows.first),
            ),
          ],
          const SizedBox(height: 10),
          const _SideTitle('Масштаб листа'),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFD9E0EA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scaleLabel,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B3440),
                  ),
                ),
                // Линейка имеет смысл только у листа одного окна: у набора
                // окон масштаб у каждого свой.
                if (scaleDenominator > 0) ...[
                  const SizedBox(height: 6),
                  SizedBox(
                    height: 36,
                    child: CustomPaint(
                      painter: _RulerPainter(
                        scaleDenominator: scaleDenominator,
                        labelStyle: TextStyle(
                          fontSize: 10.5,
                          fontFamily: labelFontFamily,
                          color: const Color(0xFF66748A),
                        ),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 4),
                Text(
                  scaleDenominator > 0
                      ? 'Лист A4 (210 × 297 мм): печатайте в масштабе 100 %, '
                            'без «по размеру страницы». Чертёж построен ровно '
                            'в этом масштабе — приложите линейку, размеры сойдутся.'
                      : 'Лист A4 (210 × 297 мм): печатайте в масштабе 100 %, '
                            'без «по размеру страницы». Чертежи окон здесь '
                            'обзорные — точный масштаб смотрите на листе '
                            'одного окна.',
                  style: const TextStyle(
                    fontSize: 10.5,
                    height: 1.25,
                    color: Color(0xFF66748A),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const _SideTitle('Примечания'),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final note in _notes())
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1.5),
                            child: Text(
                              '•',
                              style: TextStyle(
                                fontSize: math.min(
                                  labelSettings.pxFor(LabelKind.notes),
                                  13.0,
                                ),
                                color: const Color(0xFF7C8798),
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              note,
                              style: TextStyle(
                                fontSize: math.min(
                                  labelSettings.pxFor(LabelKind.notes),
                                  13.0,
                                ),
                                height: 1.25,
                                color: const Color(0xFF4A5563),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _widthList(List<WindowParams> windows) {
    final widths = <double>{};
    for (final window in windows) {
      for (final raw in [
        window.rollBottom,
        window.rollTop,
        window.rollLeft,
        window.rollRight,
      ]) {
        widths.add(WindowParams.finishedEdgeWidth(raw));
      }
    }
    final sorted = widths.toList()..sort();
    return sorted.map((value) => formatMm(value)).join('/');
  }

  /// Для одного окна — полные примечания, для заказа — сводные.
  List<String> _notes() {
    if (!project.isMultiWindow) {
      return WindowSpec.of(project.windows.first).notes;
    }
    final specs = [for (final window in project.windows) WindowSpec.of(window)];
    final consumption = <double, double>{};
    for (final spec in specs) {
      spec.edgeConsumption.forEach((roll, length) {
        consumption[roll] = (consumption[roll] ?? 0) + length;
      });
    }
    final labels = consumption.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final totalEyelets = specs.fold<int>(
      0,
      (sum, spec) => sum + spec.eyeletCount,
    );
    final first = project.windows.first;
    final materials = <FilmMaterial>{
      for (final window in project.windows) window.material,
    };
    final rollSummary = materials
        .map(
          (material) =>
              '${material.label.toLowerCase()} — рулон '
              '${formatMm(project.rollWidthFor(material))} ${unitSuffix()}',
        )
        .join('; ');
    // Вычет полосы молнии из ширины кроя у ПВХ: та же формула, что у скрина,
    // поэтому в примечаниях заказа показываем её по каждому окну.
    final pvcZipperNotes = [
      for (var i = 0; i < specs.length; i++)
        if (!specs[i].params.isScreen &&
            specs[i].zipperWidthReductionLabel != null)
          '№${i + 1}: ${specs[i].zipperWidthReductionLabel}',
    ];

    return [
      'Окон в заказе: ${project.windows.length}; номера окон указаны под каждым чертежом',
      if (first.isScreen)
        'Скрин: подворот по сторонам ${first.hemBySideLabel} '
            '(низ/право/верх/лево), шов '
            '${formatMm(screenSeamMm)} ${unitSuffix()}; заготовка = готовый размер плюс '
            'ПОЛОВИНА подворота каждой стороны, к высоте +'
            '${formatMm(screenHemAxisExtraMm)} ${unitSuffix()}'
            '${specs.first.zipperBandTotalMm > 0 ? ' минус полоса молнии '
                      '${formatMm(specs.first.zipperBandTotalMm)} ${unitSuffix()}' : ''} — '
            '${formatMm(specs.first.filmCutWidthWithAllowance)} × '
            '${formatMm(specs.first.filmCutHeightWithAllowance)} ${unitSuffix()}; '
            'тента и окантовки нет'
      else
        'Окантовка складывается пополам, запайка плёнки под окантовку '
            '${formatMm(first.weldOverlapMm)} ${unitSuffix()} по всему периметру',
      if (pvcZipperNotes.isNotEmpty)
        'Молния: ширина кроя плёнки уменьшена на полосу (спайку) — '
            '${pvcZipperNotes.join('; ')}',
      if (!first.isScreen)
        'Расход окантовки: '
            '${labels.map((entry) => '${edgeBandLabel(entry.key)} — ${formatMm(entry.value)} ${unitSuffix()}').join(', ')}',
      'Люверсы: всего $totalEyelets шт, шаг ${specs.first.eyeletStepLabel}',
      'Крепёж: ${specs.first.fastenerSummary.toLowerCase()}',
      first.hasShrinkage
          ? 'Полотно: усадка '
                '${formatPercent(first.effectiveShrinkagePercent)} учтена в раскрое'
          : 'Полотно: усадка не учитывается',
      'Раскладка полотна на рулоне ($rollSummary) — на отдельном листе',
      'Полотно: ${materials.map((material) => '${material.label} (${material.thickness})').join('; ')}',
      'Доступные рулоны: '
          '${materials.map((material) => '${material.label.toLowerCase()} — '
              '${material.rollWidthsLabel} ${unitSuffix()}').join('; ')}',
      if (first.isScreen)
        'Скрин сваривается горячим воздухом 400–500 °C, морозостойкость '
            'до −30 °C'
      else
        '${first.edgeMaterial.joining}, морозостойкость до −30 °C',
    ];
  }
}

/// Явная сводка расстояний между центрами креплений по сторонам.
///
/// Дублирует мелкие размерные цепочки на чертеже: на печати А4 и при
/// масштабировании цифры у люверсов бывают плохо читаемы, а в боковой панели
/// всегда видно шаг и количество промежутков.
class _FastenerSpacingList extends StatelessWidget {
  const _FastenerSpacingList({required this.spec});

  final WindowSpec spec;

  List<(WindowSide, String)> _rows() {
    final eyelets = spec.layers.eyelets;
    final rows = <(WindowSide, String)>[];
    for (final side in WindowSide.values) {
      final sideEyelets = eyelets.where((eyelet) => eyelet.side == side).toList()
        ..sort((a, b) => a.positionInEdge.compareTo(b.positionInEdge));
      if (sideEyelets.length < 2) continue;
      final gaps = <double>[
        for (var i = 1; i < sideEyelets.length; i++)
          (sideEyelets[i].center - sideEyelets[i - 1].center).distance,
      ];
      final first = gaps.first;
      final equal = gaps.every(
        (gap) => (gap - first).abs() <= fastenerSpanEqualToleranceMm,
      );
      final text = equal
          ? 'шаг ${formatFastenerSpanMm(first)} ${unitSuffix()} × ${gaps.length}'
          : '${gaps.length} промежутков: '
                '${gaps.map(formatFastenerSpanMm).join(' / ')} ${unitSuffix()}';
      rows.add((side, text));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    if (rows.isEmpty) {
      return const Text(
        'Крепёж не расставлен — добавьте люверсы или включите сторону.',
        style: TextStyle(fontSize: 10.5, color: Color(0xFF7C8798)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              '${row.$1.label}: ${row.$2}',
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.25,
                color: Color(0xFF2B3440),
              ),
            ),
          ),
      ],
    );
  }
}

class _SideTitle extends StatelessWidget {
  const _SideTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 10.5,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: Color(0xFF66748A),
      ),
    );
  }
}

/// Что за условный знак рисуем в легенде.
enum LegendKind {
  edge,
  seam,
  film,
  eyelet,
  buckle,
  lock,
  strap,
  liftStrap,
  zipper,
  zipperBand,
  cutout,
  weld,
  pocket,
  drain,
}

/// Линейка для боковой панели: показывает длину в масштабе листа.
class _RulerPainter extends CustomPainter {
  _RulerPainter({
    required this.scaleDenominator,
    required this.labelStyle,
    LengthUnit? unit,
  }) : unit = unit ?? DisplayUnits.unit;

  final double scaleDenominator;
  final TextStyle labelStyle;

  /// Единица подписи линейки: при переключении мм/см перерисовывается.
  final LengthUnit unit;

  /// Точек листа на миллиметр бумаги: 1240 точек на 210 мм.
  static const double _pxPerPaperMm = DrawingSheet.a4PxPerMm;
  static const List<double> _steps = [100, 200, 250, 500, 1000, 2000, 5000];

  @override
  void paint(Canvas canvas, Size size) {
    // Ширина боковой панели минус её отступы — линейка не выходит за панель.
    const maxWidth = DrawingSheet.sidePanelWidth - 48.0;
    final step = _steps.lastWhere(
      (candidate) => candidate / scaleDenominator * _pxPerPaperMm <= maxWidth,
      orElse: () => _steps.first,
    );
    final barWidth = math.min(
      step / scaleDenominator * _pxPerPaperMm,
      maxWidth,
    );
    const divisions = 4;
    final segment = barWidth / divisions;
    const top = 8.0;
    const barHeight = 8.0;

    for (var i = 0; i < divisions; i++) {
      canvas.drawRect(
        Rect.fromLTWH(segment * i, top, segment, barHeight),
        Paint()..color = i.isEven ? const Color(0xFF1B1F27) : Colors.white,
      );
    }
    canvas.drawRect(
      Rect.fromLTWH(0, top, barWidth, barHeight),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = const Color(0xFF1B1F27),
    );
    for (var i = 0; i <= divisions; i++) {
      final x = segment * i;
      canvas.drawLine(
        Offset(x, top - (i.isEven ? 3 : 1.5)),
        Offset(x, top),
        Paint()
          ..strokeWidth = 1
          ..color = const Color(0xFF1B1F27),
      );
    }

    final label = TextPainter(
      text: TextSpan(
        text: step >= 1000
            ? '0 — ${(step / 1000).toStringAsFixed(step % 1000 == 0 ? 0 : 1).replaceAll('.', ',')} м'
            : '0 — ${formatMm(step)} ${unitSuffix()}',
        style: labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(0, top + barHeight + 2));
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.scaleDenominator != scaleDenominator ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.unit != unit;
}

class _LegendPainter extends CustomPainter {
  _LegendPainter({required this.kind, required this.edgeColor});

  final LegendKind kind;
  final Color edgeColor;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final metal = const Color(0xFF9AA3AD);
    final metalDark = const Color(0xFF4C545E);
    final accent = const Color(0xFF0B62C4);
    final ink = const Color(0xFF1B1F27);
    final filmEdge = const Color(0xFF4C9BE8);

    switch (kind) {
      case LegendKind.edge:
        final rect = Rect.fromLTWH(2, 3, size.width - 4, size.height - 6);
        canvas.drawRect(
          rect,
          Paint()..color = edgeColor.withValues(alpha: 0.88),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = const Color(0xFF1B1F27),
        );
      case LegendKind.seam:
        final rect = Rect.fromLTWH(2, 3, size.width - 4, size.height - 6);
        canvas.drawRect(rect, Paint()..color = Colors.white);
        canvas.save();
        canvas.clipRect(rect);
        final hatch = Paint()
          ..color = metalDark.withValues(alpha: 0.5)
          ..strokeWidth = 1;
        for (
          var x = rect.left - rect.height;
          x < rect.right + rect.height;
          x += 5
        ) {
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
            ..color = metalDark,
        );
      case LegendKind.film:
        final rect = Rect.fromLTWH(2, 3, size.width - 4, size.height - 6);
        canvas.drawRect(rect, Paint()..color = const Color(0x3D5AA7E8));
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = const Color(0xFF4C9BE8),
        );
      case LegendKind.eyelet:
        canvas.drawCircle(center, 6.5, Paint()..color = metal);
        canvas.drawCircle(
          center,
          6.5,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = metalDark,
        );
        canvas.drawCircle(center, 3, Paint()..color = Colors.white);
        canvas.drawCircle(
          center,
          3,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..color = metalDark,
        );
      case LegendKind.buckle:
        final plate = Rect.fromCenter(center: center, width: 22, height: 11);
        canvas.drawRect(plate, Paint()..color = metal);
        canvas.drawRect(
          plate,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.8
            ..color = metalDark,
        );
        canvas.drawCircle(
          center + const Offset(-6, 0),
          2,
          Paint()..color = metalDark,
        );
      case LegendKind.cutout:
        final rect = Rect.fromCenter(center: center, width: 16, height: 12);
        canvas.drawRect(
          rect.inflate(4),
          Paint()..color = edgeColor.withValues(alpha: 0.85),
        );
        canvas.drawRect(rect, Paint()..color = const Color(0xFFF1F5FA));
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = ink,
        );
      case LegendKind.weld:
        final rect = Rect.fromCenter(center: center, width: 22, height: 12);
        canvas.drawRect(rect, Paint()..color = filmEdge.withValues(alpha: 0.2));
        canvas.save();
        canvas.clipRect(rect);
        final hatch = Paint()
          ..color = filmEdge
          ..strokeWidth = 1.2;
        for (
          var x = rect.left - rect.height;
          x < rect.right + rect.height;
          x += 5
        ) {
          canvas.drawLine(
            Offset(x, rect.bottom),
            Offset(x + rect.height, rect.top),
            hatch,
          );
        }
        canvas.restore();
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = filmEdge,
        );
      case LegendKind.lock:
        final square = Rect.fromCenter(
          center: center + const Offset(4, 0),
          width: 7,
          height: 7,
        );
        canvas.drawRect(square, Paint()..color = metal);
        canvas.drawRect(
          square,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = metalDark,
        );
        canvas.drawArc(
          Rect.fromCenter(
            center: center + const Offset(4, 0),
            width: 20,
            height: 20,
          ),
          -math.pi / 2,
          math.pi * 0.65,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = accent,
        );
      case LegendKind.strap:
        final strap = RRect.fromRectAndRadius(
          Rect.fromLTWH(1, center.dy - 3.5, size.width - 2, 7),
          const Radius.circular(3),
        );
        canvas.drawRRect(strap, Paint()..color = const Color(0xFFD8DEE6));
        canvas.drawRRect(
          strap,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = metalDark,
        );
        final buckle = RRect.fromRectAndRadius(
          Rect.fromLTWH(size.width - 16, center.dy - 6, 12, 12),
          const Radius.circular(2.5),
        );
        canvas.drawRRect(buckle, Paint()..color = metal);
        canvas.drawRRect(
          buckle,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.6
            ..color = metalDark,
        );
      case LegendKind.liftStrap:
        final strap = RRect.fromRectAndRadius(
          Rect.fromLTWH(center.dx - 5, 1, 10, size.height - 5),
          const Radius.circular(2),
        );
        canvas.drawRRect(strap, Paint()..color = const Color(0xFFDCE2EA));
        canvas.drawRRect(
          strap,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5
            ..color = metalDark,
        );
        canvas.drawLine(
          Offset(center.dx - 3, 5),
          Offset(center.dx + 3, 5),
          Paint()
            ..color = metalDark
            ..strokeWidth = 1,
        );
        canvas.drawCircle(
          Offset(center.dx, size.height - 6),
          2.4,
          Paint()..color = metalDark,
        );
      case LegendKind.zipperBand:
        final band = Rect.fromLTWH(center.dx - 6, 1, 12, size.height - 2);
        canvas.drawRect(
          band,
          Paint()..color = edgeColor.withValues(alpha: 0.9),
        );
        canvas.drawRect(
          band,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..color = metalDark,
        );
        canvas.drawLine(
          Offset(center.dx, 2),
          Offset(center.dx, size.height - 2),
          Paint()
            ..color = accent
            ..strokeWidth = 1.6,
        );
        for (var y = 4.0; y < size.height - 2; y += 4) {
          canvas.drawLine(
            Offset(center.dx - 3, y),
            Offset(center.dx + 3, y),
            Paint()
              ..color = accent
              ..strokeWidth = 1,
          );
        }
      case LegendKind.zipper:
        canvas.drawLine(
          Offset(center.dx, 2),
          Offset(center.dx, size.height - 2),
          Paint()
            ..color = accent
            ..strokeWidth = 1.6,
        );
        for (var y = 3.0; y < size.height - 2; y += 4) {
          canvas.drawLine(
            Offset(center.dx - 3, y),
            Offset(center.dx + 3, y),
            Paint()
              ..color = accent
              ..strokeWidth = 1,
          );
        }
        canvas.drawRect(
          Rect.fromLTWH(center.dx - 3, 1, 6, 5),
          Paint()..color = accent,
        );
      case LegendKind.pocket:
        final pocket = Rect.fromLTWH(2, 3, size.width - 4, size.height - 6);
        canvas.drawRect(
          pocket,
          Paint()..color = edgeColor.withValues(alpha: 0.7),
        );
        canvas.drawRect(
          Rect.fromLTWH(pocket.left, pocket.top, pocket.width, 4),
          Paint()..color = metalDark.withValues(alpha: 0.6),
        );
        canvas.drawRect(
          pocket,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = metalDark,
        );
      case LegendKind.drain:
        canvas.drawCircle(center, 3.2, Paint()..color = Colors.white);
        canvas.drawCircle(
          center,
          3.2,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.3
            ..color = metalDark,
        );
    }
  }

  @override
  bool shouldRepaint(covariant _LegendPainter oldDelegate) =>
      oldDelegate.kind != kind || oldDelegate.edgeColor != edgeColor;
}

/// Размеры листа чертежа и масштаб — для тестов, превью и диагностики.
///
/// Рамка — прямоугольник, в котором нарисован чертёж с полями под размеры;
/// поле — свободная часть страницы A4 без боковой панели и штампа.
class DrawingSheetMetrics {
  const DrawingSheetMetrics({
    required this.frame,
    required this.area,
    required this.scaleDenominator,
    required this.productSize,
  });

  /// Рамка чертежа на листе, точки.
  final Size frame;

  /// Свободное поле страницы A4 под чертёж, точки.
  final Size area;

  /// Знаменатель масштаба: 20 для «М 1:20».
  final double scaleDenominator;

  /// Габарит изделия на листе, точки.
  final Size productSize;

  /// Доля поля листа, занятая рамкой чертежа (0…1).
  ///
  /// По ней сравнивают листы: у обычного окна, Т-окна с одной и с двумя
  /// пристройками она должна быть сопоставимой — иначе при добавлении
  /// пристройки масштаб «прыгает» и чертёж становится мелким.
  double get frameFill =>
      frame.width * frame.height / (area.width * area.height);

  /// Доля поля листа, занятая самим изделием (0…1).
  double get productFill =>
      productSize.width * productSize.height / (area.width * area.height);

  @override
  String toString() =>
      'DrawingSheetMetrics(1:${scaleDenominator.toStringAsFixed(0)}, '
      'frame=${frame.width.toStringAsFixed(0)}×'
      '${frame.height.toStringAsFixed(0)}, '
      'fill=${(frameFill * 100).toStringAsFixed(1)}%)';
}


/// Перетаскивание люверсов по линии окантовки прямо на чертеже.
///
/// Жест включается только если палец/мышь нажали рядом с люверсом: иначе
/// событие уходит родительскому `InteractiveViewer`, и лист панорамируется
/// как обычно. После перетаскивания рядом с точкой появляется меню:
/// удалить, поставить круглый люверс, пластиковая скоба или поворотную скобу.
class _EyeletDragLayer extends StatefulWidget {
  const _EyeletDragLayer({
    super.key,
    required this.params,
    required this.spec,
    required this.layout,
    required this.onChanged,
    required this.child,
  });

  final WindowParams params;
  final WindowSpec spec;
  final DrawingLayout layout;
  final ValueChanged<WindowParams> onChanged;
  final Widget child;

  @override
  State<_EyeletDragLayer> createState() => _EyeletDragLayerState();
}

class _EyeletDragLayerState extends State<_EyeletDragLayer> {
  static const double _hitRadius = 14;
  static const double _menuWidth = 214;

  EdgeSide? _side;
  int _index = -1;
  List<EyeletPosition> _points = const [];
  Offset _edgeStart = Offset.zero;
  Offset _edgeEnd = Offset.zero;
  OverlayEntry? _menuEntry;

  @override
  void dispose() {
    _closeMenu();
    super.dispose();
  }

  _EyeletCandidate? _findCandidate(Offset local) {
    // Цели: люверсы и ручные замки/скобы — замок на чертеже тоже должен
    // ловиться мышкой, иначе его нельзя ни сдвинуть, ни удалить.
    final targets = <({Offset center, WindowSide side})>[
      for (final eyelet in widget.spec.layers.eyelets)
        (center: eyelet.center, side: eyelet.side),
      for (final fastener in widget.spec.layers.manualFasteners)
        (center: fastener.center, side: fastener.side),
    ];
    if (targets.isEmpty) return null;
    final layout = widget.layout;
    ({Offset center, WindowSide side})? bestTarget;
    var best = _hitRadius;
    for (final target in targets) {
      final point = layout.toPxPoint(target.center);
      final distance = (point - local).distance;
      if (distance < best) {
        best = distance;
        bestTarget = target;
      }
    }
    if (bestTarget == null) return null;
    final side = WindowLayers.edgeSideOf(bestTarget.side);
    final edge = _edgeFor(side);
    if (edge == null) return null;
    final points = _currentPoints(side, edge.$1, edge.$2);
    final dragged = _fractionOf(bestTarget.center, edge.$1, edge.$2);
    var index = 0;
    var closest = double.infinity;
    for (var i = 0; i < points.length; i++) {
      final distance = (points[i].fraction - dragged).abs();
      if (distance < closest) {
        closest = distance;
        index = i;
      }
    }
    return _EyeletCandidate(
      side: side,
      index: index,
      points: points,
      start: edge.$1,
      end: edge.$2,
    );
  }

  /// Ребро контура люверсов для стороны (у обычного окна оно одно).
  (Offset, Offset)? _edgeFor(EdgeSide side) {
    final polygons = widget.spec.layers.eyeletPolygons;
    if (polygons.isEmpty) return null;
    final polygon = polygons.first;
    for (var i = 0; i < polygon.length; i++) {
      final windowSide = widget.spec.layers.sideOfEdge(polygon, i);
      if (WindowLayers.edgeSideOf(windowSide) != side) continue;
      return (polygon[i], polygon[(i + 1) % polygon.length]);
    }
    return null;
  }

  /// Точки стороны: ручные (с их типами) или материализованные из авто-шага.
  List<EyeletPosition> _currentPoints(EdgeSide side, Offset a, Offset b) {
    if (widget.params.hasManualEyelets(side)) {
      return widget.params.eyeletPositions
          .where((position) => position.side == side)
          .toList()
        ..sort((left, right) => left.fraction.compareTo(right.fraction));
    }
    final points = <EyeletPosition>[
      for (final eyelet in widget.spec.layers.eyelets)
        if (WindowLayers.edgeSideOf(eyelet.side) == side)
          EyeletPosition(
            side: side,
            fraction: _fractionOf(eyelet.center, a, b),
          ),
    ]..sort((left, right) => left.fraction.compareTo(right.fraction));
    return points;
  }

  double _fractionOf(Offset point, Offset a, Offset b) {
    final direction = b - a;
    final lengthSquared =
        direction.dx * direction.dx + direction.dy * direction.dy;
    if (lengthSquared < 1e-9) return 0;
    final t =
        ((point.dx - a.dx) * direction.dx +
            (point.dy - a.dy) * direction.dy) /
        lengthSquared;
    return t.clamp(0.0, 1.0);
  }

  bool _canStart(Offset local) => _findCandidate(local) != null;

  void _onStart(DragStartDetails details) {
    _closeMenu();
    final candidate = _findCandidate(details.localPosition);
    if (candidate == null) return;
    setState(() {
      _side = candidate.side;
      _index = candidate.index;
      _points = candidate.points;
      _edgeStart = candidate.start;
      _edgeEnd = candidate.end;
    });
  }

  void _onUpdate(DragUpdateDetails details) {
    final side = _side;
    if (side == null || _index < 0 || _index >= _points.length) return;
    final layout = widget.layout;
    final local = details.localPosition;
    final model = Offset(
      (local.dx - layout.padLeft) / layout.scale + layout.geometry.minX,
      layout.geometry.minY +
          (layout.size.height - layout.padBottom - local.dy) / layout.scale,
    );
    final fraction = _fractionOf(model, _edgeStart, _edgeEnd);
    final next = [..._points];
    next[_index] = next[_index].copyWith(fraction: fraction);
    setState(() => _points = next);
    widget.onChanged(widget.params.withManualPoints(side, next));
  }

  void _onEnd(DragEndDetails details) {
    final side = _side;
    final index = _index;
    if (side == null || index < 0 || index >= _points.length) {
      _reset();
      return;
    }
    final point = _points[index];
    final center =
        _edgeStart + (_edgeEnd - _edgeStart) * point.fraction;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) {
      _reset();
      return;
    }
    final global = box.localToGlobal(widget.layout.toPxPoint(center));
    final current = [..._points];
    _reset();
    _openMenu(global, side, index, current);
  }

  void _reset() {
    if (_side == null && _index < 0) return;
    setState(() {
      _side = null;
      _index = -1;
      _points = const [];
    });
  }

  void _apply(EyeletPosition Function(EyeletPosition point) change) {
    final side = _side;
    final index = _index;
    if (side == null || index < 0 || index >= _points.length) return;
    final next = [..._points];
    next[index] = change(next[index]);
    _closeMenu();
    widget.onChanged(widget.params.withManualPoints(side, next));
  }

  void _deletePoint() {
    final side = _side;
    final index = _index;
    if (side == null || index < 0 || index >= _points.length) return;
    final next = [..._points]..removeAt(index);
    _closeMenu();
    widget.onChanged(widget.params.withManualPoints(side, next));
  }

  void _addPoint() {
    final side = _side;
    final index = _index;
    if (side == null || index < 0 || index >= _points.length) return;
    final current = _points[index];
    final nextFraction = index + 1 < _points.length
        ? (_points[index + 1].fraction + current.fraction) / 2
        : (current.fraction + 1) / 2;
    final next = [..._points, current.copyWith(fraction: nextFraction)]
      ..sort((left, right) => left.fraction.compareTo(right.fraction));
    _closeMenu();
    widget.onChanged(widget.params.withManualPoints(side, next));
  }

  void _openMenu(
    Offset global,
    EdgeSide side,
    int index,
    List<EyeletPosition> points,
  ) {
    _closeMenu();
    setState(() {
      _side = side;
      _index = index;
      _points = points;
    });
    final size = MediaQuery.sizeOf(context);
    final left = global.dx
        .clamp(8.0, math.max(8.0, size.width - _menuWidth - 8))
        .toDouble();
    final top =
        global.dy.clamp(8.0, math.max(8.0, size.height - 250)).toDouble();
    _menuEntry = OverlayEntry(
      builder: (context) => Positioned(
        left: left,
        top: top,
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(10),
          color: Colors.white,
          child: SizedBox(
            width: _menuWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 4, 4),
                  child: Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Люверс',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        key: const Key('eyelet-menu-close'),
                        tooltip: 'Закрыть',
                        iconSize: 16,
                        visualDensity: VisualDensity.compact,
                        onPressed: _closeMenu,
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                _menuItem(
                  key: 'eyelet-menu-round',
                  icon: Icons.circle_outlined,
                  label: 'Круглый люверс',
                  onTap: () => _apply(
                    (point) => point.copyWith(kind: MarkerKind.roundEyelet),
                  ),
                ),
                _menuItem(
                  key: 'eyelet-menu-lock',
                  icon: Icons.lock_outline,
                  label: 'Пластиковая скоба',
                  onTap: () => _apply(
                    (point) => point.copyWith(kind: MarkerKind.frenchLock),
                  ),
                ),
                _menuItem(
                  key: 'eyelet-menu-buckle',
                  icon: Icons.settings_input_component_outlined,
                  label: 'Поворотная скоба',
                  onTap: () => _apply(
                    (point) => point.copyWith(kind: MarkerKind.turnBuckle),
                  ),
                ),
                _menuItem(
                  key: 'eyelet-menu-add',
                  icon: Icons.add_circle_outline,
                  label: 'Добавить точку рядом',
                  onTap: _addPoint,
                ),
                const Divider(height: 1),
                _menuItem(
                  key: 'eyelet-menu-delete',
                  icon: Icons.delete_outline,
                  label: 'Удалить люверс',
                  color: const Color(0xFFB03A3A),
                  onTap: _deletePoint,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_menuEntry!);
  }

  Widget _menuItem({
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      key: Key(key),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            Icon(icon, size: 17, color: color ?? const Color(0xFF41506A)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 12, color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _closeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    return RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: {
        _EyeletPanRecognizer:
            GestureRecognizerFactoryWithHandlers<_EyeletPanRecognizer>(
          () => _EyeletPanRecognizer(canStart: _canStart),
          (recognizer) {
            recognizer
              ..onStart = _onStart
              ..onUpdate = _onUpdate
              ..onEnd = _onEnd
              ..onCancel = _reset;
          },
        ),
      },
      child: widget.child,
    );
  }
}

class _EyeletCandidate {
  const _EyeletCandidate({
    required this.side,
    required this.index,
    required this.points,
    required this.start,
    required this.end,
  });

  final EdgeSide side;
  final int index;
  final List<EyeletPosition> points;
  final Offset start;
  final Offset end;
}

/// Pan-распознаватель, который включается только при нажатии на люверс.
class _EyeletPanRecognizer extends PanGestureRecognizer {
  _EyeletPanRecognizer({required this.canStart});

  final bool Function(Offset local) canStart;

  @override
  bool isPointerAllowed(PointerEvent event) =>
      canStart(event.localPosition) && super.isPointerAllowed(event);

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // Нажали на люверс — сразу забираем жест у InteractiveViewer, иначе
    // лист начнёт панорамироваться вместо перетаскивания точки.
    if (canStart(event.localPosition)) {
      resolve(GestureDisposition.accepted);
    }
  }
}
