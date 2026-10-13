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

  static const double titleBlockHeight = 132;

  /// Высота одной строки в подробном режиме (одно окно в ряду).
  static const double detailedRowHeight = 640;

  /// Размер листа: всегда подробный режим, лист растёт под содержимое.
  ///
  /// Одно окно — лист по пропорциям окна (чертёж крупный, поля ровные),
  /// несколько — по строке на окно, чтобы каждому хватило места.
  /// Возвращает null только если лист должен заполнить окно программы
  /// (так рисуется раскладка на рулоне, у неё свой размер).
  static Size? detailedSheetSize(OrderProject project, Size viewport) {
    final paperWidth = math.max(viewport.width - 48, 1320.0);
    if (!project.isMultiWindow) {
      // Одно окно: высота чертежа подбирается под пропорции окна.
      final spec = WindowSpec.of(project.selected);
      final aspect = spec.geometry.spanX / math.max(spec.geometry.spanY, 1);
      final drawingHeight = math.max(viewport.height * 0.92, 760.0);
      final drawingWidth = drawingHeight * aspect;
      final frameWidth = drawingWidth + _detailPadLeft + _detailPadRight;
      final frameHeight = drawingHeight + _detailPadTop + _detailPadBottom;
      return Size(
        math.max(frameWidth + sidePanelWidth + 2, 720) + _outerPadding * 2,
        titleBlockHeight + _captionHeight + frameHeight + _outerPadding * 2,
      );
    }
    final columns = project.gridColumns == 0
        ? _columnsFor(project.windowCount)
        : project.gridColumns;
    final rows = (project.windowCount / math.max(columns, 1)).ceil();
    return Size(
      paperWidth + _outerPadding * 2,
      titleBlockHeight + _outerPadding * 2 + rows * detailedRowHeight,
    );
  }
  static const double sidePanelWidth = 236;
  static const double _outerPadding = 20;
  static const double _captionHeight = 42;

  /// Показывать сетку всех окон или подробно одно выбранное.
  bool get _showGrid =>
      project.sheetMode == SheetMode.grid && project.isMultiWindow;

  /// Доли высоты листа, по которым можно резать PDF, не разрывая окно.
  ///
  /// В подробном режиме это границы между окнами, иначе — null (режем по A3).
  static List<double>? safeBreakFractions(
    OrderProject project,
    Size viewport,
  ) {
    final sheetSize = detailedSheetSize(project, viewport);
    if (sheetSize == null) return null;
    final count = project.windowCount;
    if (count < 2) return null;

    // В PDF попадает сам лист (белое поле), без внешних отступов рабочей
    // области, поэтому доли считаем от высоты листа.
    const gridPadding = 12.0; // внутренние отступы сетки (8 сверху + 4 снизу)
    const gridTop = 8.0;
    final paperHeight = sheetSize.height - _outerPadding * 2;
    final gridHeight = paperHeight - titleBlockHeight - gridPadding;
    if (gridHeight <= 0) return null;
    final rowHeight = gridHeight / count;
    return [
      for (var i = 1; i < count; i++)
        // Чуть выше границы окна: рез попадает в пустой отступ строки.
        (gridTop + rowHeight * i - 4) / paperHeight,
    ];
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sheetWidth =
            math.max(constraints.maxWidth - _outerPadding * 2, 320.0);
        final sheetHeight =
            math.max(constraints.maxHeight - _outerPadding * 2, 320.0);

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
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: _showGrid
                                ? _buildGrid(sheetWidth, sheetHeight)
                                : _buildSingle(sheetWidth, sheetHeight),
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
                              scaleLabel:
                                  _sheetScaleLabel(sheetWidth, sheetHeight),
                              scaleDenominator: _sheetScaleDenominator(
                                sheetWidth,
                                sheetHeight,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: titleBlockHeight,
                      child: _TitleBlock(
                        project: project,
                        scaleLabel: _sheetScaleLabel(sheetWidth, sheetHeight),
                      ),
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

  /// Поля подробного чертежа — под размеры и выноски.
  static const double _detailPadLeft = 104;
  static const double _detailPadRight = 104;
  static const double _detailPadTop = 86;
  static const double _detailPadBottom = 96;

  /// Рамка чертежа под пропорции окна: лист не растягивается на всё окно,
  /// а чертится в аккуратной рамке с равными полями.
  Size _drawingFrame(Size area, WindowSpec spec) {
    final availableWidth =
        math.max(area.width - _detailPadLeft - _detailPadRight, 80.0);
    final availableHeight =
        math.max(area.height - _detailPadTop - _detailPadBottom, 80.0);
    final aspect = spec.geometry.spanX / math.max(spec.geometry.spanY, 1);
    double width;
    double height;
    if (availableWidth / availableHeight > aspect) {
      height = availableHeight;
      width = height * aspect;
    } else {
      width = availableWidth;
      height = width / aspect;
    }
    return Size(
      width + _detailPadLeft + _detailPadRight,
      height + _detailPadTop + _detailPadBottom,
    );
  }

  /// Знаменатель масштаба листа (для линейки в панели).
  double _sheetScaleDenominator(double sheetWidth, double sheetHeight) {
    if (project.windowCount != 1) return 1;
    final spec = WindowSpec.of(project.windows.first);
    final drawingWidth = math.max(sheetWidth - sidePanelWidth - 1, 160.0);
    final drawingHeight =
        math.max(sheetHeight - titleBlockHeight - _captionHeight, 120.0);
    return DrawingLayout(
      size: Size(drawingWidth, drawingHeight),
      geometry: spec.geometry,
    ).scaleDenominator;
  }

  /// Масштаб листа для штампа: у одного окна — настоящий, у набора — «по окнам».
  String _sheetScaleLabel(double sheetWidth, double sheetHeight) {
    if (project.windowCount != 1) return 'по окнам';
    final spec = WindowSpec.of(project.windows.first);
    final drawingWidth = math.max(sheetWidth - sidePanelWidth - 1, 160.0);
    final drawingHeight =
        math.max(sheetHeight - titleBlockHeight - _captionHeight, 120.0);
    return DrawingLayout(
      size: Size(drawingWidth, drawingHeight),
      geometry: spec.geometry,
    ).scaleLabel;
  }

  Widget _buildSingle(double sheetWidth, double sheetHeight) {
    final params = project.selected;
    final spec = WindowSpec.of(params);
    final area = Size(
      math.max(sheetWidth - sidePanelWidth - 1, 160.0),
      math.max(sheetHeight - titleBlockHeight - _captionHeight, 120.0),
    );
    final frame = _drawingFrame(area, spec);
    final layout = DrawingLayout(
      size: frame,
      geometry: spec.geometry,
      padLeft: _detailPadLeft,
      padRight: _detailPadRight,
      padTop: _detailPadTop,
      padBottom: _detailPadBottom,
    );

    return Column(
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
          child: ClipRect(
            child: Center(
              child: SizedBox(
                width: frame.width,
                height: frame.height,
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
                    ),
                    size: Size.infinite,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGrid(double sheetWidth, double sheetHeight) {
    final windows = project.windows;
    final count = windows.length;
    final columns =
        project.gridColumns == 0 ? _columnsFor(count) : project.gridColumns;
    final rows = (count / columns).ceil();
    final gridWidth = math.max(sheetWidth - sidePanelWidth - 1, 160.0);
    final gridHeight = math.max(sheetHeight - titleBlockHeight, 160.0);
    final cellWidth = gridWidth / columns;
    final cellHeight = gridHeight / rows;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 4, 4),
      child: Column(
        children: [
          for (var row = 0; row < rows; row++)
            Expanded(
              child: Row(
                children: [
                  for (var column = 0; column < columns; column++)
                    Expanded(
                      child: _buildCell(
                        row * columns + column,
                        Size(cellWidth - 10, cellHeight - 10),
                      ),
                    ),
                ],
              ),
            ),
        ],
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
    final drawingHeight = math.max(cellSize.height - _captionHeight, 60.0);
    final layout = DrawingLayout(
      size: Size(math.max(cellSize.width, 80), drawingHeight),
      geometry: spec.geometry,
      // Всегда подробный режим: показываем размеры, оставляем под них место.
      padLeft: _detailPadLeft,
      padRight: _detailPadRight,
      padTop: _detailPadTop,
      padBottom: _detailPadBottom,
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
            child: CustomPaint(
              painter: WindowDrawingPainter(
                params: params,
                layout: layout,
                layers: spec.layers,
                options: project.options,
                labelFontFamily: labelFontFamily,
                showScaleBar: false,
                // Подробный режим: подписи крупные, в ячейке они чуть мельче.
                labelScale: 0.9,
              ),
              size: Size.infinite,
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
              fontSize: 12,
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
              fontSize: 9.5,
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

class _TitleBlock extends StatelessWidget {
  const _TitleBlock({required this.project, required this.scaleLabel});

  /// Настоящий масштаб листа — тот же, что на масштабной линейке.
  final String scaleLabel;

  final OrderProject project;

  @override
  Widget build(BuildContext context) {
    final windows = project.windows;
    final specs = [for (final params in windows) WindowSpec.of(params)];
    final totalFilmArea =
        specs.fold<double>(0, (sum, spec) => sum + spec.filmAreaM2);
    final totalProductArea =
        specs.fold<double>(0, (sum, spec) => sum + spec.productAreaM2);
    final totalEyelets =
        specs.fold<int>(0, (sum, spec) => sum + spec.eyeletCount);
    final consumption = <EdgeRoll, double>{};
    for (final spec in specs) {
      spec.edgeConsumption.forEach((roll, length) {
        consumption[roll] = (consumption[roll] ?? 0) + length;
      });
    }
    final consumptionLabels = consumption.entries.toList()
      ..sort((a, b) => a.key.rawWidth.compareTo(b.key.rawWidth));
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
                                '${entry.key.shortLabel} — ${formatCm(entry.value)} см')
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
                        ? '${formatMm(first.bottomWidth)}/${formatMm(first.topWidth)} · '
                            '${formatMm(first.leftHeight)}/${formatMm(first.rightHeight)}'
                        : windows
                            .asMap()
                            .entries
                            .map((entry) =>
                                '№${entry.key + 1}: ${formatMm(entry.value.bottomWidth)}×'
                                '${formatMm(entry.value.leftHeight)}')
                            .join(' · '),
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _cell(
                    'Окантовка по сторонам',
                    windows.length == 1 ? specs.first.edgeBySideSummary : 'см. подписи и расход',
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
                    'Плёнка: раскрой с напайкой $weldOverlap мм',
                    windows.length == 1
                        ? '${formatMm(specs.first.filmCutWidth)} × '
                            '${formatMm(specs.first.filmCutHeight)}'
                        : 'итого ${formatMeters(totalFilmArea)} м²',
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: _cell(
                    'С усадкой ${formatPercent(first.shrinkagePercent)}',
                    windows.length == 1
                        ? '${formatMm(specs.first.filmCutWidthWithShrinkage)} × '
                            '${formatMm(specs.first.filmCutHeightWithShrinkage)}'
                        : '${formatMeters(totalFilmArea * (1 + first.shrinkagePercent / 100))} м²',
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
                    'Площадь плёнки',
                    '${formatMeters(totalFilmArea)} м²',
                  ),
                ),
              ],
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
      (
        LegendKind.edge,
        'Окантовка по сторонам: ${_widthList(windows)} мм'
      ),
      (LegendKind.seam, 'Напайка $weldOverlap мм'),
      (
        LegendKind.film,
        'Полотно: ${materials.map((material) => material.label.toLowerCase()).join(', ')}'
      ),
      (LegendKind.eyelet, 'Люверс ${params.eyeletType.label.toLowerCase()}'),
      if (anyMovable)
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
          'Спайка ${formatMm(params.zipperBandWidth)} мм с молнией по центру'
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
          'Карман ${formatMm(params.pocketWidth)} мм (тент 200 мм ×2)'
        ),
      if (anyDrain) (LegendKind.drain, 'Дренаж Ø6 мм'),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
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
                    width: 38,
                    height: 20,
                    child: CustomPaint(
                      painter: _LegendPainter(
                        kind: entry.$1,
                        edgeColor: Color(params.edgeColor.value),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.$2,
                      style: const TextStyle(
                          fontSize: 10.5, color: Color(0xFF2B3440)),
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
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2B3440),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  height: 34,
                  child: CustomPaint(
                    painter: _RulerPainter(
                      scaleDenominator: scaleDenominator,
                      labelStyle: TextStyle(
                        fontSize: 9.5,
                        fontFamily: labelFontFamily,
                        color: const Color(0xFF66748A),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'Лист построен ровно в этом масштабе: распечатайте без '
                  'масштабирования, приложите линейку — размеры сойдутся.',
                  style: TextStyle(
                    fontSize: 9.5,
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
                                  fontSize: 10, color: Color(0xFF7C8798)),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Expanded(
                            child: Text(
                              note,
                              style: const TextStyle(
                                fontSize: 9.5,
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
      for (final roll in [
        window.rollBottom,
        window.rollTop,
        window.rollLeft,
        window.rollRight,
      ]) {
        widths.add(roll.finishedWidth);
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
    final consumption = <EdgeRoll, double>{};
    for (final spec in specs) {
      spec.edgeConsumption.forEach((roll, length) {
        consumption[roll] = (consumption[roll] ?? 0) + length;
      });
    }
    final labels = consumption.entries.toList()
      ..sort((a, b) => a.key.rawWidth.compareTo(b.key.rawWidth));
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
      'Окантовка складывается пополам, напайка на плёнку $weldOverlap мм '
          'по всему периметру',
      'Расход окантовки: '
          '${labels.map((entry) => '${entry.key.shortLabel} — ${formatCm(entry.value)} см').join(', ')}',
      'Люверсы: всего $totalEyelets шт, шаг ${specs.first.eyeletStepLabel}',
      'Крепёж: ${specs.first.fastenerSummary.toLowerCase()}',
      'Плёнка: усадка ${formatPercent(first.shrinkagePercent)} учтена в раскрое',
      'Раскладка плёнки на рулоне ($rollSummary) — на отдельном листе',
      'Полотно: ${materials.map((material) => '${material.label} (${material.thickness})').join('; ')}',
      'Доступные рулоны: '
          '${materials.map((material) => '${material.label.toLowerCase()} — '
              '${material.rollWidthsLabel} см').join('; ')}',
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
        fontSize: 9.5,
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

  static const double _pxPerPaperMm = 96 / 25.4;
  static const List<double> _steps = [100, 200, 250, 500, 1000, 2000, 5000];

  @override
  void paint(Canvas canvas, Size size) {
    const maxWidth = 168.0;
    var step = _steps.first;
    for (final candidate in _steps) {
      if (candidate / scaleDenominator * _pxPerPaperMm <= maxWidth) {
        step = candidate;
      }
    }
    final barWidth = step / scaleDenominator * _pxPerPaperMm;
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
