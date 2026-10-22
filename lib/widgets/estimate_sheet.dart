import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_params.dart';
import '../services/estimate.dart';
import 'material_thumb.dart';

/// Лист «Смета на заказ»: стоимость материалов, фурнитуры и работ.
///
/// Расчёт целиком в [Estimate] (по [PriceList] и `CostsSummary` заказа),
/// здесь — только оформление в стиле листа «Ведомость расхода».
class EstimateSheet extends StatelessWidget {
  const EstimateSheet({
    super.key,
    required this.project,
    required this.prices,
    this.captureKey,
    this.labelFontFamily,
  });

  final OrderProject project;
  final PriceList prices;
  final GlobalKey? captureKey;
  final String? labelFontFamily;

  static const double titleBlockHeight = 118;
  static const double rowHeight = 34;
  static const double _outerPadding = 20;
  static const double _captionHeight = 42;

  /// Лист сметы всегда один A4 — как чертёж и раскрой.
  static const double a4Width = 1240;
  static const double a4Height = 1754;

  /// Размер листа сметы — всегда один A4 с полями рабочей области.
  static Size sheetSize(
    OrderProject project,
    Size viewport, {
    PriceList? prices,
  }) => Size(a4Width + _outerPadding * 2, a4Height + _outerPadding * 2);

  @override
  Widget build(BuildContext context) {
    final estimate = Estimate.of(project, prices);

    return Container(
      color: const Color(0xFFE7EBF2),
      padding: const EdgeInsets.all(_outerPadding),
      child: Center(
        child: FittedBox(
          fit: BoxFit.contain,
          child: RepaintBoundary(
            key: captureKey,
            child: Container(
              width: a4Width,
              height: a4Height,
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
                        _text(
                          'Смета на заказ',
                          size: 15,
                          weight: FontWeight.w700,
                          color: Colors.white,
                        ),
                        const Spacer(),
                        _text(
                          'Окон в заказе: ${project.windowCount}   ·   '
                          'ИТОГО: ${formatRubles(estimate.total)}',
                          size: 12,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ClipRect(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.topCenter,
                        child: SizedBox(
                          width: a4Width,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _positionsTable(estimate),
                                const SizedBox(height: 18),
                                _totals(estimate),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    height: titleBlockHeight,
                    child: _EstimateTitleBlock(
                      estimate: estimate,
                      project: project,
                      fontFamily: labelFontFamily,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- таблица

  Widget _positionsTable(Estimate estimate) {
    const headers = <(String, TextAlign)>[
      ('№', TextAlign.center),
      ('Наименование', TextAlign.left),
      ('Кол-во', TextAlign.right),
      ('Ед.', TextAlign.left),
      ('Цена, ₽', TextAlign.right),
      ('Сумма, ₽', TextAlign.right),
    ];
    const widths = <int>[1, 12, 2, 1, 3, 3];

    var index = 0;
    final rows = <TableRow>[
      TableRow(
        decoration: const BoxDecoration(color: Color(0xFFEEF2F8)),
        children: [
          for (final header in headers)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: _text(
                header.$1.toUpperCase(),
                size: 8.5,
                weight: FontWeight.w700,
                color: const Color(0xFF5B6B80),
                letterSpacing: 0.3,
                align: header.$2,
              ),
            ),
        ],
      ),
    ];

    for (final group in EstimateGroup.values) {
      final lines = estimate.linesFor(group);
      if (lines.isEmpty) continue;

      // Раздел: заголовок в широкой колонке «Наименование», остальные ячейки
      // пустые (у Table все строки должны иметь одинаковое число ячеек).
      rows.add(
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFF7F9FC)),
          children: [
            const SizedBox.shrink(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
              child: _text(
                group.label.toUpperCase(),
                size: 9.5,
                weight: FontWeight.w700,
                color: const Color(0xFF0B62C4),
                letterSpacing: 0.5,
              ),
            ),
            for (var i = 2; i < headers.length; i++) const SizedBox.shrink(),
          ],
        ),
      );

      for (final line in lines) {
        index += 1;
        rows.add(
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: _text('$index', color: const Color(0xFF66748A)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _text(line.title),
                    if (line.note != null && line.note!.isNotEmpty)
                      _text(
                        line.note!,
                        size: 8.5,
                        color: const Color(0xFF7C8798),
                        height: 1.2,
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: _text(
                  line.quantityLabel,
                  align: TextAlign.right,
                  weight: FontWeight.w600,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: _text(line.unit, color: const Color(0xFF66748A)),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: _text(
                  line.unitPriceLabel,
                  align: TextAlign.right,
                  color: const Color(0xFF2B3440),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                child: _text(
                  line.amountLabel,
                  align: TextAlign.right,
                  weight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      }
    }

    return Table(
      border: TableBorder.all(color: const Color(0xFFC3CCDA), width: 1),
      columnWidths: {
        for (var i = 0; i < widths.length; i++)
          i: FlexColumnWidth(widths[i].toDouble()),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.middle,
      children: rows,
    );
  }

  // --------------------------------------------------------------- итоги

  Widget _totals(Estimate estimate) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ИТОГИ ПО СМЕТЕ',
          style: _style(
            size: 10,
            weight: FontWeight.w700,
            letterSpacing: 0.8,
            color: const Color(0xFF66748A),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _summaryBlocks(estimate, project)),
            const SizedBox(width: 14),
            SizedBox(width: 540, child: _totalsPanel(estimate)),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Цены — из прайса цеха. НДС начисляется сверху на сумму после '
          'наценки и скидки. Площади и расход — из ведомости расхода '
          'материалов; цена за одно окно — ИТОГО, делённое на число окон.',
          style: _style(size: 9.5, height: 1.3, color: const Color(0xFF66748A)),
        ),
      ],
    );
  }

  Widget _summaryBlocks(Estimate estimate, OrderProject project) {
    final blocks = <(String, List<String>)>[
      (
        'Состав заказа',
        [
          'Окон в заказе: ${estimate.windowCount} шт',
          'Площадь изделий: ${formatMeters(estimate.productAreaM2)} м²',
          'Площадь плёнки в раскрое: ${formatMeters(estimate.filmAreaM2)} м²',
          'Цена за одно окно: ${formatRubles(estimate.pricePerWindow)}',
        ],
      ),
    ];

    return Wrap(
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
                _text(
                  block.$1.toUpperCase(),
                  size: 9,
                  weight: FontWeight.w700,
                  color: const Color(0xFF5B6B80),
                  letterSpacing: 0.5,
                ),
                const SizedBox(height: 6),
                for (final line in block.$2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: _text(
                      line,
                      size: 10.5,
                      color: const Color(0xFF2B3440),
                    ),
                  ),
              ],
            ),
          ),
        if (project.materialsInOrder.isNotEmpty) _materialsCard(project),
      ],
    );
  }

  /// Карточка материалов в смете: те же программные превью, что в прайсе.
  Widget _materialsCard(OrderProject project) {
    final materials = project.materialsInOrder;
    final hasPvc = materials.any((material) => material != FilmMaterial.screen);
    final hasScreen = materials.any(
      (material) => material == FilmMaterial.screen,
    );
    return Container(
      width: 300,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F9FF), Color(0xFFEAF2FB)],
        ),
        border: Border.all(color: const Color(0xFFC7DDF6)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(
            'МАТЕРИАЛЫ ЗАКАЗА',
            size: 9,
            weight: FontWeight.w700,
            color: const Color(0xFF0B62C4),
            letterSpacing: 0.5,
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (hasPvc)
                Expanded(
                  child: _materialPreview(
                    'ПВХ',
                    screen: false,
                    caption: 'Защита от снега и дождя. Срок службы 10 лет.',
                  ),
                ),
              if (hasPvc && hasScreen) const SizedBox(width: 10),
              if (hasScreen)
                Expanded(
                  child: _materialPreview(
                    'Скрин',
                    screen: true,
                    caption:
                        'Защита от пыли, пуха и насекомых. Окно проветривается.',
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _materialPreview(
    String label, {
    required bool screen,
    required String caption,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: 62,
            width: double.infinity,
            child: MaterialThumb(screen: screen),
          ),
        ),
        const SizedBox(height: 4),
        _text(
          label,
          size: 10.5,
          weight: FontWeight.w700,
          color: const Color(0xFF2B3440),
        ),
        const SizedBox(height: 2),
        _text(caption, size: 8.5, height: 1.2, color: const Color(0xFF5B6B80)),
      ],
    );
  }

  Widget _totalsPanel(Estimate estimate) {
    final rows = <(String, String, bool)>[
      (
        EstimateGroup.materials.subtotalLabel,
        formatRubles(estimate.materialsSubtotal),
        false,
      ),
      (
        EstimateGroup.hardware.subtotalLabel,
        formatRubles(estimate.hardwareSubtotal),
        false,
      ),
      (
        EstimateGroup.work.subtotalLabel,
        formatRubles(estimate.workSubtotal),
        false,
      ),
      if (estimate.extraSubtotal > 0)
        (
          EstimateGroup.extra.subtotalLabel,
          formatRubles(estimate.extraSubtotal),
          false,
        ),
      ('Итого по позициям', formatRubles(estimate.subtotal), true),
      if (estimate.installationPerM2 > 0)
        (
          'Монтаж ${formatRubles(estimate.installationPerM2)}/м² '
              '× ${formatMeters(estimate.installationAreaM2)} м²',
          formatRubles(estimate.installationAmount),
          false,
        ),
      if (estimate.markupPercent > 0)
        (
          'Наценка ${_percentText(estimate.markupPercent)} %',
          formatRubles(estimate.markupAmount),
          false,
        ),
      if (estimate.discountPercent > 0)
        (
          'Скидка ${_percentText(estimate.discountPercent)} %',
          '−${formatRubles(estimate.discountAmount)}',
          false,
        ),
      if (estimate.vatPercent > 0)
        (
          'НДС ${_percentText(estimate.vatPercent)} % (сверху)',
          formatRubles(estimate.vatAmount),
          false,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFD9E0EA)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: rows[i].$3 ? const Color(0xFFF7F9FC) : Colors.white,
                border: i == 0
                    ? null
                    : const Border(top: BorderSide(color: Color(0xFFE4E9F1))),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: _text(
                      rows[i].$1,
                      size: 10.5,
                      weight: rows[i].$3 ? FontWeight.w700 : FontWeight.w400,
                      color: const Color(0xFF2B3440),
                    ),
                  ),
                  _text(
                    rows[i].$2,
                    size: 11.5,
                    weight: FontWeight.w700,
                    color: const Color(0xFF1B1F27),
                    align: TextAlign.right,
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFFEEF2F8),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(7)),
              border: Border(top: BorderSide(color: Color(0xFFC3CCDA))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _text(
                    'ИТОГО К ОПЛАТЕ',
                    size: 11,
                    weight: FontWeight.w700,
                    color: const Color(0xFF2B3440),
                    letterSpacing: 0.4,
                  ),
                ),
                _text(
                  formatRubles(estimate.total),
                  size: 17,
                  weight: FontWeight.w700,
                  color: const Color(0xFF0B62C4),
                  align: TextAlign.right,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------------------------------------------------- текст

  /// Текст с общим стилем листа. [labelFontFamily] — семейство подписей:
  /// в приложении null (системный шрифт), в тестах — загруженный шрифт.
  Widget _text(
    String value, {
    double size = 10.5,
    Color color = const Color(0xFF1B1F27),
    FontWeight weight = FontWeight.w400,
    double height = 1.25,
    double letterSpacing = 0,
    TextAlign? align,
  }) => Text(
    value,
    textAlign: align,
    style: _style(
      size: size,
      color: color,
      weight: weight,
      height: height,
      letterSpacing: letterSpacing,
    ),
  );

  TextStyle _style({
    double size = 10.5,
    Color color = const Color(0xFF1B1F27),
    FontWeight weight = FontWeight.w400,
    double height = 1.25,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: labelFontFamily,
    fontSize: size,
    height: height,
    letterSpacing: letterSpacing,
    fontWeight: weight,
    color: color,
  );
}

/// Штамп снизу: изделие, заказчик, окна, дата, площадь, итог.
class _EstimateTitleBlock extends StatelessWidget {
  const _EstimateTitleBlock({
    required this.estimate,
    required this.project,
    this.fontFamily,
  });

  final Estimate estimate;
  final OrderProject project;

  /// Семейство шрифта подписей (см. `EstimateSheet.labelFontFamily`).
  final String? fontFamily;

  @override
  Widget build(BuildContext context) {
    final first = project.windows.isEmpty
        ? const WindowParams()
        : project.windows.first;
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
              '${formatMeters(estimate.productAreaM2)} м²',
            ),
          ),
          Expanded(
            flex: 4,
            child: _cell(
              estimate.vatPercent > 0 ? 'ИТОГО с НДС' : 'ИТОГО',
              formatRubles(estimate.total),
              emphasis: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _cell(String label, String value, {bool emphasis = false}) {
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
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: 8.5,
              height: 1.15,
              letterSpacing: 0.4,
              color: const Color(0xFF7C8798),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: emphasis ? 15 : 12.5,
              color: emphasis
                  ? const Color(0xFF0B62C4)
                  : const Color(0xFF1B1F27),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// Процент без лишних нулей: «20», «7,5».
String _percentText(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}
