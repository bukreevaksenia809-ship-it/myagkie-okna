import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_params.dart';
import '../services/company_branding.dart';
import '../services/estimate.dart';
import 'material_thumb.dart';

/// Лист «Смета на заказ»: стоимость материалов, фурнитуры и работ.
///
/// Расчёт целиком в [Estimate] (по [PriceList] и `CostsSummary` заказа),
/// здесь — только оформление в стиле листа «Ведомость расхода».
///
/// Поведение раскладки:
/// * весь текст листа крупный — ×2 к прежним кеглям (заголовок 15 → 30,
///   шапка таблицы 8.5 → 17, строки 10.5 → 21, примечания 8.5 → 17,
///   итоги 10.5 → 21, штамп 12.5 → 25, ИТОГО 17 → 34);
/// * лист всегда один A4 ([a4Width] × [a4Height]);
/// * свободная высота A4 не остаётся пустой: таблица позиций растягивает
///   строки через `Expanded` (вес строки зависит от наличия примечания),
///   а итоги и штамп прижаты к низу листа;
/// * если заказ гигантский и даже растянутые строки не вмещают текст,
///   каждая ячейка контролируемо ужимается `FittedBox(scaleDown)` —
///   ничего не обрезается и не выходит за границы A4.
class EstimateSheet extends StatelessWidget {
  const EstimateSheet({
    super.key,
    required this.project,
    required this.prices,
    this.captureKey,
    this.labelFontFamily,
    this.company,
  });

  final OrderProject project;
  final PriceList prices;
  final GlobalKey? captureKey;
  final String? labelFontFamily;

  /// Компания для шапки: логотип и строка реквизитов (если включено).
  final CompanyBrandingState? company;

  /// Ключ таблицы позиций — по нему тесты проверяют раскладку листа.
  static const Key tableKey = ValueKey('estimate-table');

  /// Ключ нижнего штампа — по нему тесты проверяют, что контент дошёл до низа.
  static const Key stampKey = ValueKey('estimate-stamp');

  /// Высота штампа: было 118, стало ×2 — 236.
  static const double titleBlockHeight = 236;

  /// Опорная высота строки: было 34, стало ×2 — 68.
  static const double rowHeight = 68;

  static const double _outerPadding = 20;

  /// Высота синей плашки-заголовка: было 42, стало ×2 — 84.
  static const double _captionHeight = 84;

  /// Поля рабочей области листа (было 20/16/20/12 — увеличены под крупный
  /// текст, чтобы строки не слипались с рамкой листа).
  static const EdgeInsets _contentPadding = EdgeInsets.fromLTRB(
    24,
    24,
    24,
    16,
  );

  /// Зазор между таблицей и итогами (было 18).
  static const double _tableGap = 20;

  /// Кегли сметы: всё ×2 к прежним значениям.
  static const double _baseFontSize = 21; // было 10.5
  static const double _headerFontSize = 17; // было 8.5
  static const double _sectionFontSize = 19; // было 9.5
  static const double _noteFontSize = 17; // было 8.5
  static const double _captionFontSize = 30; // было 15
  static const double _captionInfoFontSize = 22; // было 12

  /// Отступы внутри ячейки таблицы (было 6 × 7).
  static const double _cellPadH = 8;
  static const double _cellPadV = 8;

  static const Color _gridColor = Color(0xFFC3CCDA);

  /// Пропорции колонок — как в прежней `Table` (1:12:2:1:3:3).
  static const List<int> _columnFlex = [1, 12, 2, 1, 3, 3];

  static const List<(String, TextAlign)> _headers = [
    ('№', TextAlign.center),
    ('Наименование', TextAlign.left),
    ('Кол-во', TextAlign.right),
    ('Ед.', TextAlign.left),
    ('Цена, ₽', TextAlign.right),
    ('Сумма, ₽', TextAlign.right),
  ];

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
                  _caption(estimate),
                  // Рабочая область: таблица получает всю оставшуюся высоту
                  // (её строки тянутся), итоги прижаты к низу рабочей области.
                  Expanded(
                    child: Padding(
                      padding: _contentPadding,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _positionsTable(estimate)),
                          const SizedBox(height: _tableGap),
                          _totals(estimate),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(
                    key: stampKey,
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

  // ------------------------------------------------------------- шапка листа

  Widget _caption(Estimate estimate) {
    return Container(
      height: _captionHeight,
      width: double.infinity,
      color: const Color(0xFF0B62C4),
      padding: const EdgeInsets.symmetric(horizontal: 28),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          if (company?.isVisible ?? false) ...[
            if (company?.logo != null) ...[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 240),
                child: SizedBox(
                  height: 54,
                  child: Image.memory(
                    company!.logo!,
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(width: 16),
            ],
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  'Смета на заказ',
                  size: _captionFontSize,
                  weight: FontWeight.w700,
                  color: Colors.white,
                ),
                if (company!.details.name.trim().isNotEmpty)
                  _text(
                    company!.details.name.trim(),
                    size: 17,
                    weight: FontWeight.w600,
                    color: Colors.white,
                  ),
                if (company!.contactLine.isNotEmpty)
                  _text(
                    company!.contactLine,
                    size: 14,
                    color: Colors.white70,
                  ),
              ],
            ),
          ] else
            _text(
              'Смета на заказ',
              size: _captionFontSize,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          const Spacer(),
          // Длинное ИТОГО не обрезается и не ломает строку: при нехватке
          // ширины плашка контролируемо ужимается.
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: _text(
                'Окон в заказе: ${project.windowCount}   ·   '
                'ИТОГО: ${formatRubles(estimate.total)}',
                size: _captionInfoFontSize,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------- таблица

  /// Таблица позиций растягивается на всю свободную высоту: каждая строка —
  /// `Expanded` с весом [ _EstimateRowSpec.flex ], поэтому лист не оставляет
  /// пустоты внизу. [rowHeight] — опорная высота строки для проверок.
  Widget _positionsTable(Estimate estimate) {
    final specs = _tableSpecs(estimate);
    return Container(
      key: tableKey,
      decoration: BoxDecoration(border: Border.all(color: _gridColor)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < specs.length; i++)
            Expanded(
              flex: specs[i].flex,
              child: _tableRow(specs[i], last: i == specs.length - 1),
            ),
        ],
      ),
    );
  }

  List<_EstimateRowSpec> _tableSpecs(Estimate estimate) {
    final rows = <_EstimateRowSpec>[_EstimateRowSpec.header()];
    var index = 0;
    for (final group in EstimateGroup.values) {
      final lines = estimate.linesFor(group);
      if (lines.isEmpty) continue;
      rows.add(_EstimateRowSpec.section(group.label));
      for (final line in lines) {
        index += 1;
        rows.add(_EstimateRowSpec.line(index: index, line: line));
      }
    }
    return rows;
  }

  Widget _tableRow(_EstimateRowSpec spec, {required bool last}) {
    final decoration = BoxDecoration(
      color: spec.isHeader
          ? const Color(0xFFEEF2F8)
          : spec.isSection
          ? const Color(0xFFF7F9FC)
          : Colors.white,
      border: Border(
        bottom: last ? BorderSide.none : const BorderSide(color: _gridColor),
      ),
    );

    if (spec.isSection) {
      return Container(
        decoration: decoration,
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Container(
              width: constraints.maxWidth,
              padding: const EdgeInsets.symmetric(
                horizontal: _cellPadH * 2,
                vertical: _cellPadV,
              ),
              child: _text(
                spec.section!.toUpperCase(),
                size: _sectionFontSize,
                weight: FontWeight.w700,
                color: const Color(0xFF0B62C4),
                letterSpacing: 1.0,
              ),
            ),
          ),
        ),
      );
    }

    final cells = spec.isHeader
        ? [
            for (var i = 0; i < _headers.length; i++)
              _tableCell(
                index: i,
                child: _text(
                  _headers[i].$1.toUpperCase(),
                  size: _headerFontSize,
                  weight: FontWeight.w700,
                  color: const Color(0xFF5B6B80),
                  letterSpacing: 0.6,
                  align: _headers[i].$2,
                ),
              ),
          ]
        : _lineCells(spec);

    return Container(
      decoration: decoration,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: cells,
      ),
    );
  }

  List<Widget> _lineCells(_EstimateRowSpec spec) {
    final line = spec.line!;
    final note = line.note;
    return [
      _tableCell(
        index: 0,
        child: _text('${spec.index}', color: const Color(0xFF66748A)),
      ),
      _tableCell(
        index: 1,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _text(line.title),
            if (note != null && note.isNotEmpty)
              _text(
                note,
                size: _noteFontSize,
                color: const Color(0xFF7C8798),
                height: 1.2,
              ),
          ],
        ),
      ),
      _tableCell(
        index: 2,
        child: _text(
          line.quantityLabel,
          align: TextAlign.right,
          weight: FontWeight.w600,
        ),
      ),
      _tableCell(
        index: 3,
        child: _text(line.unit, color: const Color(0xFF66748A)),
      ),
      _tableCell(
        index: 4,
        child: _text(
          line.unitPriceLabel,
          align: TextAlign.right,
          color: const Color(0xFF2B3440),
        ),
      ),
      _tableCell(
        index: 5,
        child: _text(
          line.amountLabel,
          align: TextAlign.right,
          weight: FontWeight.w700,
        ),
      ),
    ];
  }

  /// Ячейка таблицы: ширина — из пропорций колонок, содержимое по центру
  /// ячейки. `FittedBox(scaleDown)` — страховка от обрезки на гигантских
  /// заказах: при обычном заказе масштаб 1:1, кегль не уменьшается.
  Widget _tableCell({required int index, required Widget child}) {
    return Expanded(
      flex: _columnFlex[index],
      child: Container(
        decoration: BoxDecoration(
          border: Border(
            left: index == 0
                ? BorderSide.none
                : const BorderSide(color: _gridColor),
          ),
        ),
        child: LayoutBuilder(
          builder: (context, constraints) => FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.center,
            child: Container(
              width: constraints.maxWidth,
              padding: const EdgeInsets.symmetric(
                horizontal: _cellPadH,
                vertical: _cellPadV,
              ),
              child: child,
            ),
          ),
        ),
      ),
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
            size: 20, // было 10
            weight: FontWeight.w700,
            letterSpacing: 1.6,
            color: const Color(0xFF66748A),
          ),
        ),
        const SizedBox(height: 14), // было 8
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: _summaryBlocks(estimate, project)),
            const SizedBox(width: 16), // было 14
            SizedBox(width: 540, child: _totalsPanel(estimate)),
          ],
        ),
        const SizedBox(height: 20), // было 12
        Text(
          'Цены — из прайса цеха. НДС начисляется сверху на сумму после '
          'наценки и скидки. Площади и расход — из ведомости расхода '
          'материалов; цена за одно окно — ИТОГО, делённое на число окон.',
          style: _style(
            size: 19, // было 9.5
            height: 1.3,
            color: const Color(0xFF66748A),
          ),
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
            padding: const EdgeInsets.all(16), // было 10
            decoration: BoxDecoration(
              color: const Color(0xFFF7F9FC),
              border: Border.all(color: const Color(0xFFD9E0EA)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _text(
                  block.$1.toUpperCase(),
                  size: 18, // было 9
                  weight: FontWeight.w700,
                  color: const Color(0xFF5B6B80),
                  letterSpacing: 0.8,
                ),
                const SizedBox(height: 10), // было 6
                for (final line in block.$2)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4), // было 3
                    child: _text(
                      line,
                      size: _baseFontSize, // было 10.5
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
      padding: const EdgeInsets.all(16), // было 10
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF4F9FF), Color(0xFFEAF2FB)],
        ),
        border: Border.all(color: const Color(0xFFC7DDF6)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _text(
            'МАТЕРИАЛЫ ЗАКАЗА',
            size: 18, // было 9
            weight: FontWeight.w700,
            color: const Color(0xFF0B62C4),
            letterSpacing: 0.8,
          ),
          const SizedBox(height: 10), // было 6
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
              if (hasPvc && hasScreen) const SizedBox(width: 12),
              if (hasScreen)
                Expanded(
                  child: _materialPreview(
                    'Скрин',
                    screen: true,
                    caption:
                        'Защита от пыли, пуха и насекомых. '
                        'Окно проветривается.',
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
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            height: 80, // было 62
            width: double.infinity,
            child: MaterialThumb(screen: screen),
          ),
        ),
        const SizedBox(height: 6), // было 4
        _text(
          label,
          size: _baseFontSize, // было 10.5
          weight: FontWeight.w700,
          color: const Color(0xFF2B3440),
        ),
        const SizedBox(height: 4), // было 2
        _text(
          caption,
          size: _noteFontSize, // было 8.5
          height: 1.25,
          color: const Color(0xFF5B6B80),
        ),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 16, // было 12
                vertical: 10, // было 7
              ),
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
                      size: _baseFontSize, // было 10.5
                      weight: rows[i].$3 ? FontWeight.w700 : FontWeight.w400,
                      color: const Color(0xFF2B3440),
                    ),
                  ),
                  _text(
                    rows[i].$2,
                    size: 23, // было 11.5
                    weight: FontWeight.w700,
                    color: const Color(0xFF1B1F27),
                    align: TextAlign.right,
                  ),
                ],
              ),
            ),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 16, // было 12
              vertical: 12, // было 10
            ),
            decoration: const BoxDecoration(
              color: Color(0xFFEEF2F8),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
              border: Border(top: BorderSide(color: Color(0xFFC3CCDA))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _text(
                    'ИТОГО К ОПЛАТЕ',
                    size: 22, // было 11
                    weight: FontWeight.w700,
                    color: const Color(0xFF2B3440),
                    letterSpacing: 0.8,
                  ),
                ),
                _text(
                  formatRubles(estimate.total),
                  size: 34, // было 17
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
    double size = _baseFontSize,
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
    double size = _baseFontSize,
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

/// Описание строки таблицы сметы. [flex] задаёт долю свободной высоты A4:
/// строка с примечанием получает больше места, шапка и разделы — меньше.
class _EstimateRowSpec {
  const _EstimateRowSpec.header() : section = null, line = null, index = null;

  const _EstimateRowSpec.section(this.section) : line = null, index = null;

  const _EstimateRowSpec.line({required this.index, required this.line})
    : section = null;

  final String? section;
  final EstimateLine? line;
  final int? index;

  bool get isHeader => section == null && line == null;
  bool get isSection => section != null;

  /// Вес строки при распределении высоты: 90 — шапка, 95 — раздел,
  /// 100 — обычная позиция, 145 — позиция с примечанием.
  int get flex {
    if (isHeader) return 90;
    if (isSection) return 95;
    final note = line!.note;
    return note != null && note.isNotEmpty ? 145 : 100;
  }
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
        border: Border(top: BorderSide(color: Color(0xFF1B1F27), width: 2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 6, child: _cell('Изделие', first.projectName)),
          Expanded(flex: 4, child: _cell('Заказчик', first.customer)),
          Expanded(
            flex: 3,
            child: _cell('Окон в заказе', '${project.windowCount} шт'),
          ),
          Expanded(flex: 5, child: _cell('Дата', date)),
          Expanded(
            flex: 5,
            child: _cell(
              'Площадь изделий',
              '${formatMeters(estimate.productAreaM2)} м²',
            ),
          ),
          Expanded(
            flex: 8,
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
      padding: const EdgeInsets.symmetric(
        horizontal: 14, // было 12
        vertical: 12, // было 9
      ),
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
              fontSize: 17, // было 8.5
              height: 1.15,
              letterSpacing: 0.6,
              color: const Color(0xFF7C8798),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8), // было 4
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: fontFamily,
              fontSize: emphasis ? 30 : 25, // было 15 / 12.5
              height: 1.1,
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
