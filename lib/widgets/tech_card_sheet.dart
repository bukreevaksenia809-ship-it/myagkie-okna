import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_params.dart';
import '../services/tech_card.dart';

/// Лист «Технологическая карта» — рабочая карта для цеха.
///
/// По каждому окну: что делать и какими размерами, чем делать и что проверить.
/// Все числа карты берутся из модели окна ([TechCard]), поэтому лист сходится
/// с чертежом и ведомостью расхода.
class TechCardSheet extends StatelessWidget {
  const TechCardSheet({
    super.key,
    required this.project,
    this.captureKey,
    this.labelFontFamily,
  });

  final OrderProject project;

  /// Ключ области, которую снимаем для экспорта PDF.
  final GlobalKey? captureKey;

  /// Шрифт подписей листа; null — системный шрифт.
  final String? labelFontFamily;

  static const double titleBlockHeight = 118;
  static const double rowHeight = 34;
  static const double _outerPadding = 20;
  static const double _captionHeight = 42;
  static const double _windowHeaderHeight = 48;
  static const double _tableHeaderHeight = 26;
  static const double _notesBlockHeight = 58;
  static const double _windowGap = 14;

  /// Размер листа техкарты. null — лист заполняет окно программы.
  ///
  /// Лист растёт под число окон и операций: на каждую операцию отводится
  /// столько строк, сколько занимает самый длинный текст её строки.
  static Size? sheetSize(OrderProject project, Size viewport) {
    final paperWidth = math.max(viewport.width - 48, 1320.0);
    final cards = TechCard.forOrder(project);

    var contentHeight = _captionHeight + 14 + 12;
    if (cards.isEmpty) {
      contentHeight += rowHeight * 2;
    } else {
      for (final card in cards) {
        contentHeight += _windowHeaderHeight + _tableHeaderHeight;
        for (final operation in card.operations) {
          contentHeight += operationRowHeight(operation, paperWidth);
        }
        contentHeight += _windowGap;
      }
      contentHeight += _notesBlockHeight;
    }
    contentHeight += titleBlockHeight + _outerPadding * 2;

    if (contentHeight <= viewport.height) return null;
    return Size(paperWidth + _outerPadding * 2, contentHeight);
  }

  /// Оценка высоты строки операции: самая длинная колонка задаёт число строк.
  static double operationRowHeight(
    TechOperation operation,
    double sheetWidth, [
    double tableWidth = 0,
  ]) {
    final width = tableWidth > 0 ? tableWidth : math.max(sheetWidth - 40, 320);
    final what =
        '${operation.title} ${operation.description} '
        '${operation.materialsText}';
    final lines = <int>[
      _estimatedLines(what, width * 9 / 20.5, 6.2),
      _estimatedLines(operation.control, width * 5 / 20.5, 6.2),
      _estimatedLines(operation.tool, width * 3 / 20.5, 6.2),
      _estimatedLines(operation.number.toString(), width * 0.7 / 20.5, 7.0),
    ];
    final maxLines = lines.reduce(math.max);
    return math.max(rowHeight, maxLines * 13.6 + 16);
  }

  static int _estimatedLines(String text, double width, double charWidth) {
    if (text.isEmpty) return 1;
    final perLine = math.max((width / charWidth).floor(), 6);
    var lines = 0;
    for (final paragraph in text.split('\n')) {
      lines += math.max(1, (paragraph.length / perLine).ceil());
    }
    return lines;
  }

  @override
  Widget build(BuildContext context) {
    final cards = TechCard.forOrder(project);

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
                    _caption(cards.length),
                    Expanded(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
                        child: cards.isEmpty
                            ? _emptyOrder()
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  for (final card in cards) ...[
                                    _windowBlock(card),
                                    const SizedBox(height: _windowGap),
                                  ],
                                  _notes(),
                                ],
                              ),
                      ),
                    ),
                    SizedBox(
                      height: titleBlockHeight,
                      child: _TechTitleBlock(cards: cards, font: _font),
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

  String? get _font => labelFontFamily;

  TextStyle _style({
    double size = 10.5,
    FontWeight? weight,
    Color color = const Color(0xFF1B1F27),
    double height = 1.25,
    double? letterSpacing,
  }) => TextStyle(
    fontSize: size,
    fontWeight: weight,
    color: color,
    height: height,
    letterSpacing: letterSpacing,
    fontFamily: _font,
  );

  Widget _caption(int windowCount) {
    return Container(
      height: _captionHeight,
      width: double.infinity,
      color: const Color(0xFF0B62C4),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          Text(
            'Технологическая карта',
            style: _style(
              size: 15,
              weight: FontWeight.w700,
              color: Colors.white,
            ),
          ),
          const Spacer(),
          Text(
            'Окон в заказе: $windowCount',
            style: _style(size: 12, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  Widget _emptyOrder() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Text(
        'В заказе нет окон — техкарту строить не по чему.',
        style: _style(size: 12, color: const Color(0xFF66748A)),
      ),
    );
  }

  /// Одно окно: заголовок с размерами и тип + таблица операций.
  Widget _windowBlock(TechCard card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2F8),
            border: Border.all(color: const Color(0xFFC3CCDA)),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${card.title} — ${card.dimensionsLabel} · ${card.typeLabel}',
                style: _style(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: const Color(0xFF1B1F27),
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                card.subtitle,
                style: _style(
                  size: 9.5,
                  color: const Color(0xFF66748A),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
        _operationsTable(card),
      ],
    );
  }

  Widget _operationsTable(TechCard card) {
    const widths = <double>[0.7, 3, 9, 3, 5];
    const headers = <String>[
      '№',
      'Операция',
      'Что делать / размеры',
      'Инструмент',
      'Контроль',
    ];

    return Table(
      border: TableBorder.all(color: const Color(0xFFC3CCDA), width: 1),
      columnWidths: {
        for (var i = 0; i < widths.length; i++) i: FlexColumnWidth(widths[i]),
      },
      defaultVerticalAlignment: TableCellVerticalAlignment.top,
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFFEEF2F8)),
          children: [
            for (final header in headers)
              _cell(
                header.toUpperCase(),
                size: 8.5,
                weight: FontWeight.w700,
                color: const Color(0xFF5B6B80),
                letterSpacing: 0.3,
                height: 1.2,
              ),
          ],
        ),
        for (final operation in card.operations)
          TableRow(
            children: [
              _cell(
                '${operation.number}',
                size: 10.5,
                weight: FontWeight.w700,
                color: const Color(0xFF5B6B80),
              ),
              _cell(operation.title, size: 10.5, weight: FontWeight.w700),
              _cell(_whatToDo(operation), size: 10.5),
              _cell(operation.tool, size: 9.5, color: const Color(0xFF4A5563)),
              _cell(
                operation.control,
                size: 9.5,
                color: const Color(0xFF4A5563),
              ),
            ],
          ),
      ],
    );
  }

  /// Текст колонки «Что делать / размеры»: описание и материалы списком.
  String _whatToDo(TechOperation operation) {
    final buffer = StringBuffer(operation.description);
    for (final material in operation.materials) {
      buffer.write('\n• ${material.label}');
    }
    return buffer.toString();
  }

  Widget _cell(
    String text, {
    double size = 10.5,
    FontWeight? weight,
    Color color = const Color(0xFF1B1F27),
    double height = 1.3,
    double? letterSpacing,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
      child: Text(
        text,
        style: _style(
          size: size,
          weight: weight,
          color: color,
          height: height,
          letterSpacing: letterSpacing,
        ),
      ),
    );
  }

  /// Примечания внизу листа: порядок операций и источник чисел.
  Widget _notes() {
    final anyScreen =
        project.windows.any((window) => window.material == FilmMaterial.screen);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'ПОРЯДОК ОПЕРАЦИЙ',
          style: _style(
            size: 9,
            weight: FontWeight.w700,
            letterSpacing: 0.6,
            color: const Color(0xFF66748A),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          anyScreen
              ? 'раскрой → подворот и шов 3 мм → спайка окон → люверсы по '
                  'подвороту → вырезы → фартук → контроль и упаковка'
              : 'раскрой → запайка/сварка → спайка окон → окантовка → люверсы → '
                  'молнии → вырезы → фартук → ремни → дренаж → контроль и упаковка',
          style: _style(size: 9.5, color: const Color(0xFF4A5563), height: 1.3),
        ),
        const SizedBox(height: 4),
        Text(
          anyScreen
              ? 'Все размеры карты — из расчёта скрина: заготовка равна готовому '
                  'размеру плюс ПОЛОВИНА подворота каждой стороны, к высоте '
                  'добавляется 20 мм (подвороты низ, право, верх, '
                  'лево — 10…200 мм, обычно 40/50/60/80/100/120), усадки нет, расход '
                  'считается по площади заготовки. Люверсы ставятся по линии '
                  'подворота, шов подворота — 3 мм.'
              : 'Все размеры карты — из расчёта окна: плёнка в раскрое с запайкой '
                  '25 мм (значение окна, 5…60 мм), авто-припуском +10 мм к '
                  'высоте заготовки для ПВХ и усадкой, если она включена в окне; '
                  'расход окантовки по сторонам, люверсы по интервалу, молнии '
                  'и вырезы по чертежу. Окантовка складывается пополам: '
                  '80 → 40, 100 → 50, 120 → 60, 200 → 100, 240 → 120 мм.',
          style: _style(size: 9.5, color: const Color(0xFF66748A), height: 1.3),
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------ штамп

class _TechTitleBlock extends StatelessWidget {
  const _TechTitleBlock({required this.cards, required this.font});

  final List<TechCard> cards;
  final String? font;

  @override
  Widget build(BuildContext context) {
    final first = cards.isEmpty ? null : cards.first.params;
    final now = DateTime.now();
    final date =
        '${now.day.toString().padLeft(2, '0')}.${now.month.toString().padLeft(2, '0')}.${now.year}';

    final edgeTotals = TechCard.orderEdgeTotals(cards);
    final edgeLabels = TechCard.edgeTotalLabels(edgeTotals);
    final eyelets = TechCard.orderEyeletsByType(cards);
    final eyeletLabels = [
      for (final entry in eyelets.entries)
        '${entry.key.label} — ${entry.value} шт',
    ];

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
                  child: _cell('Изделие', first?.projectName ?? '—'),
                ),
                Expanded(
                  flex: 2,
                  child: _cell('Заказчик', first?.customer ?? '—'),
                ),
                Expanded(
                  flex: 2,
                  child: _cell('Окон в заказе', '${cards.length} шт'),
                ),
                Expanded(flex: 2, child: _cell('Дата', date)),
              ],
            ),
          ),
          const Divider(height: 1, thickness: 1, color: Color(0xFFC3CCDA)),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  flex: 4,
                  child: _cell(
                    'Окантовка',
                    edgeLabels.isEmpty ? '—' : edgeLabels.join(' · '),
                  ),
                ),
                Expanded(
                  flex: 4,
                  child: _cell(
                    'Люверсы',
                    eyeletLabels.isEmpty
                        ? '—'
                        : '${eyeletLabels.join(' · ')} · всего '
                              '${eyelets.values.fold(0, (a, b) => a + b)} шт',
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _cell(
                    'Полотно',
                    cards.isEmpty ? '—' : cards.first.params.material.label,
                  ),
                ),
                Expanded(
                  flex: 3,
                  child: _cell(
                    'Крепёж',
                    cards.isEmpty ? '—' : cards.first.spec.fastenerSummary,
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
            style: TextStyle(
              fontSize: 8.5,
              height: 1.15,
              letterSpacing: 0.4,
              color: const Color(0xFF7C8798),
              fontWeight: FontWeight.w600,
              fontFamily: font,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: const Color(0xFF1B1F27),
              fontWeight: FontWeight.w600,
              height: 1.15,
              fontFamily: font,
            ),
          ),
        ],
      ),
    );
  }
}
