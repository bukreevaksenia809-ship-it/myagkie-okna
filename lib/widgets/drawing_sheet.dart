import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';
import 'window_painter.dart';

/// Лист чертежа: одно окно подробно или несколько окон заказа с нумерацией.
class DrawingSheet extends StatelessWidget {
  const DrawingSheet({
    super.key,
    required this.project,
    this.captureKey,
    this.labelFontFamily,
  });

  final OrderProject project;

  /// Ключ области, которую снимаем для экспорта.
  final GlobalKey? captureKey;

  /// Шрифт подписей на чертеже; null — системный шрифт.
  final String? labelFontFamily;

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

  static const double titleBlockHeight = 132;

  /// Ширина боковой панели: компактно под A4 (≈36 мм).
  static const double sidePanelWidth = 210;

  static const double _outerPadding = 20;
  static const double _captionHeight = 42;

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

  /// Доли высоты листа, по которым PDF режется ровно по границам A4.
  ///
  /// Лист собран из страниц A4 одинаковой высоты, поэтому резать можно только
  /// между страницами: окно никогда не окажется разрезанным. Одна страница —
  /// резать нечего.
  static List<double>? safeBreakFractions(
    OrderProject project,
    Size viewport,
  ) {
    final pages = a4PageCount(project);
    if (pages < 2) return null;
    return [for (var page = 1; page < pages; page++) page / pages];
  }

  @override
  Widget build(BuildContext context) {
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
        child: _showGrid ? _buildGridPages(pages) : _buildSingle(),
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

  /// Запас к размеру рамки: страхует пересчёт масштаба от погрешности.
  static const double _frameSlack = 2;

  /// Раскладка чертежа для свободного поля [area] (в точках листа).
  ///
  /// Чертёж всегда считается в «экранных» точках 96 dpi — в них стандартный
  /// масштаб (1:10, 1:15, 1:20 …) совпадает с масштабной линейкой. Поэтому
  /// поле переводим в эти точки делением на [paintScale], а поля оставляем
  /// как есть: их размеры заданы в тех же точках, что и выноски чертежа.
  DrawingLayout _drawingLayout(
    Size area,
    WindowSpec spec, {
    double paintScale = _paintScale,
    double padLeft = _detailPadLeft,
    double padRight = _detailPadRight,
    double padTop = _detailPadTop,
    double padBottom = _detailPadBottom,
  }) =>
      DrawingLayout(
        size: area / paintScale,
        geometry: spec.geometry,
        padLeft: padLeft,
        padRight: padRight,
        padTop: padTop,
        padBottom: padBottom,
      );

  /// Рамка чертежа: масштаб выбираем по свободному полю, затем строим рамку
  /// ровно под сам чертёж плюс поля под размеры и выноски.
  ///
  /// К размеру рамки добавлен небольшой запас: тогда масштаб, пересчитанный
  /// от рамки, не «прыгнет» на следующий стандартный из-за погрешности
  /// округления, и чертёж гарантированно влезает в рамку.
  Size _drawingFrame(
    Size area,
    WindowSpec spec, {
    double paintScale = _paintScale,
    double padLeft = _detailPadLeft,
    double padRight = _detailPadRight,
    double padTop = _detailPadTop,
    double padBottom = _detailPadBottom,
  }) {
    final layout = _drawingLayout(
      area,
      spec,
      paintScale: paintScale,
      padLeft: padLeft,
      padRight: padRight,
      padTop: padTop,
      padBottom: padBottom,
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
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF9FB0C6)),
                ),
                child: CustomPaint(
                  painter: WindowDrawingPainter(
                    params: params,
                    layout: layout,
                    layers: spec.layers,
                    options: project.options,
                    labelFontFamily: labelFontFamily,
                    showScaleBar: false,
                    labelScale: labelScale,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Лист одного окна (или одного выбранного окна заказа): одна страница A4.
  Widget _buildSingle() {
    final params = project.selected;
    final spec = WindowSpec.of(params);
    final area = Size(
      math.max(a4Width - sidePanelWidth - 1, 160.0),
      math.max(a4Height - titleBlockHeight - _captionHeight, 120.0),
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
        SizedBox(
          height: titleBlockHeight,
          child: _TitleBlock(
            project: project,
            scaleLabel: layout.scaleLabel,
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
  Widget _buildGridPages(int pages) {
    final columns = project.gridColumns == 0
        ? _columnsFor(project.windowCount)
        : project.gridColumns;

    return Column(
      children: [
        for (var page = 0; page < pages; page++)
          SizedBox(
            height: a4Height,
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: _buildGridRow(page, columns)),
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
                          scaleLabel: 'по окнам',
                          // У набора окон масштаб у каждого свой — линейку
                          // показывает только лист одного окна.
                          scaleDenominator: 0,
                        ),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: titleBlockHeight,
                  child: _TitleBlock(
                    project: project,
                    scaleLabel: 'по окнам',
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Ряд окон одной страницы A4.
  Widget _buildGridRow(int page, int columns) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
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

  Widget _buildCell(int index, Size cellSize) {
    if (index >= project.windows.length) return const SizedBox.shrink();
    final params = project.windows[index];
    final spec = WindowSpec.of(params);
    final isSelected = index == project.selectedIndex;
    final area = Size(
      math.max(cellSize.width - 12, 80.0),
      math.max(cellSize.height - 12 - _captionHeight, 60.0),
    );
    final frame = _drawingFrame(
      area,
      spec,
      paintScale: 1,
      padLeft: _cellPad,
      padRight: _cellPad,
      padTop: _cellPad,
      padBottom: _cellPad,
    );
    final layout = _drawingLayout(
      frame,
      spec,
      paintScale: 1,
      padLeft: _cellPad,
      padRight: _cellPad,
      padTop: _cellPad,
      padBottom: _cellPad,
    );

    return Container(
      margin: const EdgeInsets.all(6),
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
                labelScale: 0.9,
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

/// Подпись окна под ячейкой: номер обязателен.
class _Caption extends StatelessWidget {
  const _Caption({
    required this.number,
    required this.params,
    required this.spec,
    required this.highlighted,
  });

  final int number;
  final WindowParams params;
  final WindowSpec spec;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final extra = params.drawingNumber.trim().isEmpty
        ? ''
        : ' · ${params.drawingNumber.trim()}';
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
          Text(
            '${formatMm(spec.geometry.spanX)}×${formatMm(spec.geometry.overallHeight)} мм · '
            '${formatMeters(spec.productAreaM2)} м² · '
            '${params.windowType.label.toLowerCase()} · люверсов ${spec.eyeletCount}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5,
              height: 1.15,
              color: highlighted ? Colors.white70 : const Color(0xFF66748A),
            ),
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------------ штамп

/// Размеры одного окна для штампа: только основные размеры изделия.
///
/// Припуск на раскрой в размеры изделия не входит — он виден в примечаниях
/// и в раскрое плёнки.
String _sizesLabel(WindowParams params) =>
    '${formatMm(params.bottomWidth)}/${formatMm(params.topWidth)} · '
    '${formatMm(params.leftHeight)}/${formatMm(params.rightHeight)}';

/// Короткая запись размера окна для заказа из нескольких окон.
String _shortSizeLabel(WindowParams params) =>
    '${formatMm(params.bottomWidth)}×${formatMm(params.leftHeight)}';

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.project, required this.scaleLabel});

  /// Настоящий масштаб листа — тот же, что на масштабной линейке.
  final String scaleLabel;

  final OrderProject project;

  @override
  Widget build(BuildContext context) {
    final windows = project.windows;
    final specs = [for (final params in windows) WindowSpec.of(params)];
    // Плёнка на листе — заготовка (габарит) к раскрою: с припуском, а
    // усадка показана отдельным числом (и учтена в totalFilmAreaWithShrinkage).
    final totalFilmArea =
        specs.fold<double>(0, (sum, spec) => sum + spec.filmCutAreaM2);
    final totalFilmAreaWithShrinkage = specs.fold<double>(
      0,
      (sum, spec) => sum + spec.filmCutAreaWithShrinkageM2,
    );
    final totalProductArea =
        specs.fold<double>(0, (sum, spec) => sum + spec.productAreaM2);
    final totalEyelets =
        specs.fold<int>(0, (sum, spec) => sum + spec.eyeletCount);
    final consumption = <double, double>{};
    for (final spec in specs) {
      spec.edgeConsumption.forEach((roll, length) {
        consumption[roll] = (consumption[roll] ?? 0) + length;
      });
    }
    final consumptionLabels = consumption.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final first = windows.first;

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1B1F27), width: 1.4)),
      ),
      child: Column(
        children: [
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _cell('Изделие', first.projectName),
                ),
                Expanded(flex: 2, child: _cell('Заказчик', first.customer)),
                Expanded(
                  flex: 2,
                  child: _cell(
                    'Окон в заказе',
                    '${windows.length} шт'
                        '${windows.length > 1 ? ' · №1…№${windows.length}' : ''}',
                  ),
                ),
                Expanded(flex: 2, child: _cell('Дата', date)),
                Expanded(
                  flex: 3,
                  child: _cell(
                    'Окантовка',
                    consumptionLabels.isEmpty
                        ? '—'
                        : consumptionLabels
                            .map((entry) =>
                                '${edgeBandLabel(entry.key)} — ${formatCm(entry.value)} см')
                            .join(' · '),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: _cell(
                    'Масштаб',
                    scaleLabel,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFC3CCDA)),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: _cell(
                    'Размеры окон, мм',
                    windows.length == 1
                        ? _sizesLabel(first)
                        : windows
                            .asMap()
                            .entries
                            .map((entry) =>
                                '№${entry.key + 1}: ${_shortSizeLabel(entry.value)}')
                            .join(' · '),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _cell(
                    first.isScreen
                        ? 'Скрин: подворот по сторонам'
                        : 'Окантовка по сторонам',
                    windows.length == 1
                        ? specs.first.edgeBySideSummary
                        : 'см. подписи и расход',
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _cell(
                    'Полотно',
                    windows.length == 1
                        ? windows.first.material.label
                        : '${windows.first.material.label} и др.',
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _cell(
                    'Люверсы',
                    'всего $totalEyelets шт · '
                        'шаг ${specs.first.eyeletStepLabel}',
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _cell(
                    first.isScreen
                        ? 'Скрин: заготовка с подворотом '
                            '${first.hemBySideShortLabel} (низ/право/верх/лево)'
                        : 'Полотно: раскрой с запайкой '
                            '${formatMm(first.weldOverlapMm)} мм',
                    windows.length == 1
                        ? '${formatMm(specs.first.filmCutWidthWithAllowance)} × '
                            '${formatMm(specs.first.filmCutHeightWithAllowance)}'
                        : 'итого ${formatMeters(totalFilmArea)} м²',
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _cell(
                    first.isScreen
                        ? 'Усадка'
                        : 'С усадкой '
                            '${formatPercent(first.effectiveShrinkagePercent)}',
                    windows.length == 1
                        ? (first.isScreen
                            ? 'нет'
                            : '${formatMm(specs.first.filmCutWidthWithShrinkage)} × '
                                '${formatMm(specs.first.filmCutHeightWithShrinkage)}')
                        : '${formatMeters(totalFilmAreaWithShrinkage)} м²',
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _cell(
                    'Площадь изделий',
                    '${formatMeters(totalProductArea)} м²',
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _cell(
                    'Заготовки (габарит) с усадкой',
                    '${formatMeters(totalFilmAreaWithShrinkage)} м²',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value, {int maxLines = 1}) {
    // Двухстрочное значение (размеры с припуском) набираем мельче и с
    // меньшими отступами, чтобы клетка штампа не переполнялась.
    final dense = maxLines > 1;
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: dense ? 5 : 9),
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
            maxLines: maxLines,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: dense ? 11.5 : 12.5,
              height: dense ? 1.15 : null,
              color: const Color(0xFF1B1F27),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

// --------------------------------------------------- легенда и примечания

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

  @override
  Widget build(BuildContext context) {
    final windows = project.windows;
    final params = windows.first;
    final anyLifting = windows.any((window) => window.isLifting);
    final anyMovable =
        windows.any((window) => window.windowType != WindowType.fixed);
    final anyZipper = windows.any((window) => window.hasZipper);
    final anyCutout = windows.any((window) => window.cutouts.isNotEmpty);
    final anyWeld = windows.any((window) => window.weldedSides.isNotEmpty);
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
              '${formatMm(screenSeamMm)} мм'
        )
      else ...[
        (
          LegendKind.edge,
          'Окантовка по сторонам: ${_widthList(windows)} мм'
        ),
        (LegendKind.seam, 'Запайка ${formatMm(params.weldOverlapMm)} мм'),
      ],
      (
        LegendKind.film,
        'Полотно: ${materials.map((material) => material.label.toLowerCase()).join(', ')}'
      ),
      (
        LegendKind.eyelet,
        params.isScreen
            ? 'Люверс ${params.eyeletType.label.toLowerCase()} по подвороту'
            : 'Люверс ${params.eyeletType.label.toLowerCase()}'
      ),
      if (anyMovable && !params.isScreen)
        switch (params.fastenerType) {
          FastenerType.turnBuckles => (LegendKind.buckle, 'Поворотная скоба'),
          FastenerType.frenchLocks => (LegendKind.lock, 'Французский замок'),
          FastenerType.straps => (LegendKind.strap, 'Силиконовый ремень'),
          FastenerType.eyeletsOnly => (LegendKind.eyelet, 'Крепление саморезами'),
        },
      if (anyLifting) (LegendKind.liftStrap, 'Подъёмный ремень 50×500 мм'),
      if (anyZipper)
        (
          LegendKind.zipperBand,
          // У скрина полоса под молнию — из скрина, со швом 3 мм по краям;
          // у ПВХ — спайка тента шириной 50 мм.
          params.isScreen
              ? 'Полоса скрина ${formatMm(params.zipperBandWidth)} мм с молнией '
                  '(шов ${formatMm(screenSeamMm)} мм)'
              : 'Спайка ${formatMm(params.zipperBandWidth)} мм с молнией по центру'
        ),
      if (anyCutout)
        (
          LegendKind.cutout,
          'Вырез в полотне с окантовкой по контуру'
        ),
      if (anyWeld)
        (
          LegendKind.weld,
          'Спайка с соседним окном $windowWeldWidth мм'
        ),
      if (anyPocket)
        (
          LegendKind.pocket,
          params.isScreen
              ? 'Карман ${formatMm(params.pocketWidth)} мм (подворот)'
              : 'Карман ${formatMm(params.pocketWidth)} мм (тент 200 мм ×2)'
        ),
      if (anyDrain) (LegendKind.drain, 'Дренаж Ø6 мм'),
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
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF2B3440)),
                    ),
                  ),
                ],
              ),
            ),
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
                          const Padding(
                            padding: EdgeInsets.only(top: 1.5),
                            child: Text(
                              '•',
                              style: TextStyle(
                                  fontSize: 11, color: Color(0xFF7C8798)),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              note,
                              style: const TextStyle(
                                fontSize: 10.5,
                                height: 1.25,
                                color: Color(0xFF4A5563),
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
    final totalEyelets =
        specs.fold<int>(0, (sum, spec) => sum + spec.eyeletCount);
    final first = project.windows.first;
    final materials = <FilmMaterial>{
      for (final window in project.windows) window.material,
    };
    final rollSummary = materials
        .map((material) =>
            '${material.label.toLowerCase()} — рулон '
            '${formatMm(project.rollWidthFor(material))} мм')
        .join('; ');

    return [
      'Окон в заказе: ${project.windows.length}; номера окон указаны под каждым чертежом',
      if (first.isScreen)
        'Скрин: подворот по сторонам ${first.hemBySideLabel} '
            '(низ/право/верх/лево), шов '
            '${formatMm(screenSeamMm)} мм; тента и окантовки нет'
      else
        'Окантовка складывается пополам, запайка плёнки под окантовку '
            '${formatMm(first.weldOverlapMm)} мм по всему периметру',
      if (!first.isScreen)
        'Расход окантовки: '
            '${labels.map((entry) => '${edgeBandLabel(entry.key)} — ${formatCm(entry.value)} см').join(', ')}',
      'Люверсы: всего $totalEyelets шт, шаг ${specs.first.eyeletStepLabel}',
      'Крепёж: ${specs.first.fastenerSummary.toLowerCase()}',
      'Полотно: усадка '
          '${formatPercent(first.effectiveShrinkagePercent)} учтена в раскрое',
      'Раскладка полотна на рулоне ($rollSummary) — на отдельном листе',
      'Полотно: ${materials.map((material) => '${material.label} (${material.thickness})').join('; ')}',
      'Доступные рулоны: '
          '${materials.map((material) => '${material.label.toLowerCase()} — '
              '${material.rollWidthsLabel} см').join('; ')}',
      if (first.isScreen)
        'Скрин сваривается горячим воздухом 400–500 °C, морозостойкость '
            'до −30 °C'
      else
        '${first.edgeMaterial.joining}, морозостойкость до −30 °C',
    ];
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
  _RulerPainter({required this.scaleDenominator, required this.labelStyle});

  final double scaleDenominator;
  final TextStyle labelStyle;

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
            : '0 — ${formatMm(step)} мм',
        style: labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(0, top + barHeight + 2));
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) =>
      oldDelegate.scaleDenominator != scaleDenominator ||
      oldDelegate.labelStyle != labelStyle;
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
        canvas.drawRect(rect, Paint()..color = edgeColor.withValues(alpha: 0.88));
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
        for (var x = rect.left - rect.height;
            x < rect.right + rect.height;
            x += 5) {
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
        final plate = Rect.fromCenter(
          center: center,
          width: 22,
          height: 11,
        );
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
        final rect = Rect.fromCenter(
          center: center,
          width: 16,
          height: 12,
        );
        canvas.drawRect(
          rect.inflate(4),
          Paint()..color = edgeColor.withValues(alpha: 0.85),
        );
        canvas.drawRect(
          rect,
          Paint()..color = const Color(0xFFF1F5FA),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..color = ink,
        );
      case LegendKind.weld:
        final rect = Rect.fromCenter(center: center, width: 22, height: 12);
        canvas.drawRect(
          rect,
          Paint()..color = filmEdge.withValues(alpha: 0.2),
        );
        canvas.save();
        canvas.clipRect(rect);
        final hatch = Paint()
          ..color = filmEdge
          ..strokeWidth = 1.2;
        for (var x = rect.left - rect.height; x < rect.right + rect.height; x += 5) {
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
        canvas.drawRect(band, Paint()..color = edgeColor.withValues(alpha: 0.9));
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
