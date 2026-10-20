import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_params.dart';
import '../services/costs_summary.dart';

/// Лист «Ведомость расхода материалов» — отдельная вкладка для отчётности.
class CostsSheet extends StatelessWidget {
  const CostsSheet({
    super.key,
    required this.project,
    this.captureKey,
    this.labelFontFamily,
  });

  final OrderProject project;
  final GlobalKey? captureKey;
  final String? labelFontFamily;

  static const double titleBlockHeight = 118;
  static const double rowHeight = 34;
  static const double _outerPadding = 20;
  static const double _captionHeight = 42;

  /// Размер листа расхода. null — лист заполняет окно программы.
  static Size? sheetSize(OrderProject project, Size viewport) {
    final paperWidth = math.max(viewport.width - 48, 1320.0);
    // Блоки итогов идут Wrap по 300 px: с блоком крепежа их стало на один
    // больше, поэтому закладываем запас по высоте — лист не должен обрезать
    // последний ряд блоков.
    final contentHeight =
        _captionHeight +
        150 +
        (project.windowCount + 1) * rowHeight +
        330 +
        titleBlockHeight +
        _outerPadding * 2;
    if (contentHeight <= viewport.height) return null;
    return Size(paperWidth + _outerPadding * 2, contentHeight);
  }

  @override
  Widget build(BuildContext context) {
    final summary = CostsSummary(project);

    return LayoutBuilder(
      builder: (context, constraints) {
        final sheetWidth = math.max(
          constraints.maxWidth - _outerPadding * 2,
          320.0,
        );
        final sheetHeight = math.max(
          constraints.maxHeight - _outerPadding * 2,
          320.0,
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
                      height: _captionHeight,
                      width: double.infinity,
                      color: const Color(0xFF0B62C4),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.centerLeft,
                      child: Row(
                        children: [
                          const Text(
                            'Ведомость расхода материалов',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            'Окон в заказе: ${project.windowCount}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _costsTable(summary),
                            const SizedBox(height: 18),
                            _totals(summary),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(
                      height: titleBlockHeight,
                      child: _CostsTitleBlock(summary: summary),
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

  Widget _costsTable(CostsSummary summary) {
    final rows = <List<String>>[];
    for (var i = 0; i < project.windowCount; i++) {
      final window = project.windows[i];
      final spec = summary.specs[i];
      final extras = <String>[
        if (spec.params.zippers.length > 1)
          'молний ${spec.params.zippers.length}',
        if (spec.params.hasZipper)
          'молния ${formatMm(spec.zipperBandPiece?.$2 ?? 0)}',
        if (spec.params.cutouts.isNotEmpty)
          'вырезов ${spec.params.cutouts.length}',
        if (spec.layers.weldLengthMm > 0)
          'спайка ${formatMm(spec.layers.weldLengthMm)}'
              '${spec.params.isTShape ? ' (общие стороны Т)' : ''}',
        if (spec.params.pocket)
          'фартук снизу ${formatMm(spec.params.pocketWidth)}',
        if (spec.params.pocketTop)
          'фартук сверху ${formatMm(spec.params.pocketWidth)}',
        if (spec.params.isScreen)
          'подворот ${spec.params.hemBySideShortLabel} + шов '
              '${formatMm(screenSeamMm)}',
        if (spec.strapCount > 0) 'ремни ${spec.strapCount}',
        // Крепёж подвижных сторон — по числу точек низа и боков (без углов).
        if (spec.params.fastenerType != FastenerType.eyeletsOnly &&
            spec.layers.movableSideEyelets.isNotEmpty)
          '${spec.params.fastenerType.itemTitle.toLowerCase()} '
              '${spec.layers.movableSideEyelets.length}',
        if ((spec.params.isLifting || spec.params.isScreen) &&
            spec.layers.topEyelets.isNotEmpty)
          'саморезы ${spec.layers.topEyelets.length}',
        if (spec.params.drainHoles && !spec.params.isScreen)
          'дренаж ${spec.params.drainCount.round()}',
      ];
      rows.add([
        '№${i + 1}',
        window.windowType.label,
        window.material.label,
        // Размеры изделия — только основные (припуск в изделие не входит).
        // У Т-окна показываем основное полотно и каждую пристройку со своей
        // стороной: у угловой формы их две.
        window.isTShape
            ? [
                '${formatMm(window.bottomWidth)}×${formatMm(window.leftHeight)}',
                // Берём ФАКТИЧЕСКИ построенные пристройки: если две стоят на
                // одной стороне, вторая в расчёте не участвует — и в
                // ведомости её быть не должно.
                for (final annex in spec.layers.tAnnexes)
                  '${formatMm(annex.rect.width)}×${formatMm(annex.rect.height)} '
                      '${annex.side.label.toLowerCase()}',
              ].join(' + ')
            : '${formatMm(window.bottomWidth)}/${formatMm(window.topWidth)} · '
                  '${formatMm(window.leftHeight)}/${formatMm(window.rightHeight)}',
        // Плёнка в раскрое — заготовка с припуском и усадкой.
        '${formatMm(spec.filmCutWidthWithShrinkage)} × '
            '${formatMm(spec.filmCutHeightWithShrinkage)}',
        formatMeters(spec.productAreaM2),
        // Заготовка-прямоугольник к раскрою, с усадкой.
        formatMeters(spec.filmCutAreaWithShrinkageM2),
        '${spec.eyeletCount}',
        spec.params.isScreen
            ? 'подворот ${spec.params.hemBySideShortLabel}'
            : spec.edgeConsumptionLabels.join('; '),
        extras.isEmpty ? '—' : extras.join(', '),
      ]);
    }

    final headers = [
      '№',
      'Тип',
      'Материал полотна',
      'Размеры полотна, ${unitSuffix()}',
      'Полотно в раскрое с усадкой, ${unitSuffix()}',
      'Площадь изделия, м²',
      'Площадь заготовки-прямоугольника, м²',
      'Люверсы, шт',
      'Окантовка / подворот',
      'Спецэлементы',
    ];
    const widths = <int>[1, 3, 3, 4, 4, 2, 2, 2, 5, 4];

    return Table(
      border: TableBorder.all(color: const Color(0xFFC3CCDA), width: 1),
      columnWidths: {
        for (var i = 0; i < widths.length; i++)
          i: FlexColumnWidth(widths[i].toDouble()),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFEEF2F8)),
          children: [
            for (final header in headers)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Text(
                  header.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 8.5,
                    height: 1.2,
                    letterSpacing: 0.3,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF5B6B80),
                  ),
                ),
              ),
          ],
        ),
        for (final row in rows)
          TableRow(
            children: [
              for (final cell in row)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 7,
                  ),
                  child: Text(
                    cell,
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.25,
                      color: Color(0xFF1B1F27),
                    ),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// Подписи подворотов по окнам: «Окно №1: низ 40, право 50, верх 60,
  /// лево 40 мм» — по одной строке на каждое окно из скрина.
  List<String> _screenHemLabels() => [
    for (var i = 0; i < project.windows.length; i++)
      if (project.windows[i].isScreen)
        'Окно №${i + 1}: ${project.windows[i].hemBySideLabel}',
  ];

  Widget _totals(CostsSummary summary) {
    final blocks = <(String, List<String>)>[
      (
        'Площадь изделий',
        [
          'Готовые изделия (по наружному контуру): '
              '${formatMeters(summary.productAreaM2)} м²',
          'Окон в заказе: ${summary.project.windowCount} шт',
        ],
      ),
      (
        'Полотно (плёнка)',
        [
          ...summary.filmByMaterialLabels,
          'Итого заготовки-прямоугольника: '
              '${formatMeters(summary.filmAreaWithShrinkageM2)} м²',
          'Заготовки-прямоугольника без усадки: '
              '${formatMeters(summary.filmAreaM2)} м²',
          'Площадь полотна изделий (без припуска): '
              '${formatMeters(summary.filmNetAreaM2)} м²',
          if (summary.project.windows.every((window) => window.isScreen))
            'Усадки нет: у скрина она равна 0 %'
          else if (summary.hasShrinkage)
            'В расход и деньги идёт заготовка с усадкой'
          else
            'Усадка не учитывается: заготовка считается без запаса на усадку',
        ],
      ),
      (
        'Окантовка (по типам рулонов)',
        [
          if (summary.edgeConsumptionLabels.isEmpty) '—',
          ...summary.edgeConsumptionLabels,
        ],
      ),
      if (summary.screenHemLengthMm > 0)
        (
          'Скрин: подворот и шов 3 мм',
          [
            ..._screenHemLabels(),
            summary.screenZipperCount > 0
                ? 'Длина подворота по периметру и швов полос молний: '
                      '${formatMm(summary.screenHemLengthMm)} ${unitSuffix()} '
                      '(полосы — ${formatMm(summary.screenZipperBandLengthMm)} ${unitSuffix()})'
                : 'Длина подворота по периметру: '
                      '${formatMm(summary.screenHemLengthMm)} ${unitSuffix()}',
            'Расход скрина — по площади заготовок в раскрое (готовый размер '
                'плюс среднее подворотов по оси + 20 мм'
                '${summary.screenZipperCount > 0 ? ', ширина кроя уменьшена на '
                          'полосу молнии '
                          '${formatMm(summary.screenZipperBandWidthMm)} ${unitSuffix()}' : ''})',
          ],
        ),
      (
        'Люверсы',
        [...summary.eyeletLabels, 'Всего: ${summary.eyeletTotal} шт'],
      ),
      if (summary.fastenerTotal > 0 || summary.screwCount > 0)
        (
          'Крепёж подвижных сторон',
          [
            if (summary.fastenerLabels.isEmpty)
              'Скобы, замки и ремни: —'
            else
              ...summary.fastenerLabels,
            if (summary.fastenerTotal > 0)
              'Всего крепежа: ${summary.fastenerTotal} шт',
            if (summary.screwCount > 0)
              'Саморезы верхнего ряда: ${summary.screwCount} шт',
            if (summary.fastenerTotal > 0)
              'Ставится по низу и бокам, в точках люверсов; круглые люверсы '
                  'в углах — по тумблеру «Круглые люверсы в углах» (у замка и '
                  'скобы в углу отдельного крепежа нет)',
          ],
        ),
      (
        'Сопутствующие материалы',
        [if (summary.extraLabels.isEmpty) '—', ...summary.extraLabels],
      ),
      (
        'Раскладка на рулонах',
        [
          for (final plan in summary.rollPlans)
            '${plan.material.label}: рулон ${formatMm(plan.rollWidth)} ${unitSuffix()} × '
                '${formatMm(plan.layout.requiredLength)} ${unitSuffix()} — '
                'отход ${formatPercent(plan.wastePercent)}',
          'Общий отход по рулонам: ${formatPercent(summary.rollWastePercent)}',
        ],
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ИТОГИ ПО ЗАКАЗУ',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
            color: Color(0xFF66748A),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final block in blocks)
              Container(
                width: 300,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF7F9FC),
                  border: Border.all(color: const Color(0xFFD9E0EA)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      block.$1.toUpperCase(),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                        color: Color(0xFF5B6B80),
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final line in block.$2)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 3),
                        child: Text(
                          line,
                          style: const TextStyle(
                            fontSize: 10.5,
                            height: 1.25,
                            color: Color(0xFF2B3440),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          summary.screenHemLengthMm > 0
              ? 'Скрин — технология без тента и окантовки: материал '
                    'подворачивается по периметру (шов 3 мм), крепёж — только '
                    'люверсы по подвороту. Подворот задаётся на каждую сторону '
                    '(низ, право, верх, лево), заготовка = готовый размер плюс '
                    'прибавка по каждой оси — среднее двух подворотов + 20 мм, '
                    'усадки нет; расход скрина считается '
                    'по площади заготовки. Припуск на раскрой увеличивает только '
                    'заготовку, размеры изделия считаются по замеру. Для ПВХ '
                    'действует запайка плёнки под окантовку (5…60 мм).'
              : 'Запайка плёнки под окантовку — значение окна (5…60 мм, по '
                    'умолчанию 5 мм). Окантовка складывается пополам: рулон '
                    '100 → 50 мм, 200 → 100 мм, 240 → 120 мм. Плёнка ПВХ 700 мкм, '
                    'морозостойкость до −30 °C. Припуск на раскрой увеличивает '
                    'только заготовку плёнки; размеры изделия и площадь изделий '
                    'считаются по замеру.',
          style: const TextStyle(
            fontSize: 9.5,
            height: 1.3,
            color: Color(0xFF66748A),
          ),
        ),
      ],
    );
  }
}

class _CostsTitleBlock extends StatelessWidget {
  const _CostsTitleBlock({required this.summary});

  final CostsSummary summary;

  @override
  Widget build(BuildContext context) {
    final project = summary.project;
    final first = project.windows.first;
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';
    final rolls = summary.rollPlans
        .map(
          (plan) =>
              '${plan.material.label.split(' ').first} '
              '${formatMm(plan.rollWidth)}×${formatMm(plan.layout.requiredLength)}',
        )
        .join(' · ');

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1B1F27), width: 1.4)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _cell('Изделие', first.projectName)),
          Expanded(flex: 2, child: _cell('Заказчик', first.customer)),
          Expanded(
            flex: 2,
            child: _cell('Окон в заказе', '${project.windowCount} шт'),
          ),
          Expanded(flex: 2, child: _cell('Дата', date)),
          Expanded(
            flex: 3,
            child: _cell(
              'Площадь изделий',
              '${formatMeters(summary.productAreaM2)} м²',
            ),
          ),
          Expanded(
            flex: 3,
            child: _cell(
              'Заготовки-прямоугольника с усадкой',
              '${formatMeters(summary.filmAreaWithShrinkageM2)} м²',
            ),
          ),
          Expanded(flex: 4, child: _cell('Рулоны (ширина × длина)', rolls)),
          Expanded(
            flex: 2,
            child: _cell('Отход', formatPercent(summary.rollWastePercent)),
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
