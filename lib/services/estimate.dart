// Расчёт сметы заказа: позиции по материалам, фурнитуре и работам.
//
// Все количества берутся из [CostsSummary] — готовая сводка расхода уже
// посчитала площади, метры окантовки, люверсы и спецэлементы. Здесь
// геометрия заново не пересчитывается, только умножается на цены
// [PriceList]. Flutter UI в файле нет — только чистый Dart.

import 'dart:math' as math;

import '../models/order_project.dart';
import '../models/price_list.dart';
import '../models/window_params.dart';
import 'costs_summary.dart';

// Удобные реэкспорты: смете нужен прайс, а деньги форматируются там же.
export '../models/price_list.dart'
    show PriceField, PriceList, formatRubles, parsePrice;

/// Раздел сметы — по нему позиции группируются в листе.
enum EstimateGroup {
  materials,
  hardware,
  work;

  String get label => switch (this) {
        EstimateGroup.materials => 'Материалы',
        EstimateGroup.hardware => 'Фурнитура и спецэлементы',
        EstimateGroup.work => 'Работы',
      };

  /// Подпись для итоговой строки раздела.
  String get subtotalLabel => switch (this) {
        EstimateGroup.materials => 'Итого материалы',
        EstimateGroup.hardware => 'Итого фурнитура',
        EstimateGroup.work => 'Итого работы',
      };
}

/// Строка сметы: наименование, количество с единицей, цена и сумма.
class EstimateLine {
  const EstimateLine({
    required this.title,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.group,
    this.note,
  });

  final String title;

  /// Количество в [unit]: м², м или шт.
  final double quantity;

  /// Единица измерения: «м²», «м», «шт».
  final String unit;

  /// Цена за единицу, ₽.
  final double unitPrice;

  final EstimateGroup group;

  /// Уточнение под наименованием (может быть null).
  final String? note;

  /// Сумма позиции, округлённая до копейки.
  double get amount => roundMoney(quantity * unitPrice);

  String get quantityLabel => formatQuantity(quantity, unit);

  String get unitPriceLabel => formatRubles(unitPrice);

  String get amountLabel => formatRubles(amount);
}

/// Смета заказа: позиции, подытоги по разделам, наценка, скидка, НДС, ИТОГО.
///
/// Порядок расчёта: подытог по позициям → наценка → скидка → НДС «сверху»
/// (см. [PriceList]) → ИТОГО. Наценка и скидка считаются от денежных сумм,
/// а не от процентов друг друга, поэтому «скидка 10 %» уменьшает ИТОГО
/// ровно на 10 %.
class Estimate {
  Estimate({
    required this.prices,
    required List<EstimateLine> lines,
    required this.windowCount,
    required this.productAreaM2,
    required this.filmAreaM2,
  }) : lines = List.unmodifiable(lines);

  final PriceList prices;
  final List<EstimateLine> lines;

  /// Сколько окон в заказе (для цены за одно окно).
  final int windowCount;

  /// Суммарная площадь готовых изделий, м².
  final double productAreaM2;

  /// Суммарная площадь плёнки в раскрое, м².
  final double filmAreaM2;

  /// Смета всего заказа.
  factory Estimate.of(OrderProject project, PriceList prices) {
    final summary = CostsSummary(project);
    final lines = <EstimateLine>[];

    // --- Материалы: полотно по материалам --------------------------------
    final filmEntries = summary.filmAreaByMaterial.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in filmEntries) {
      if (!(entry.value > 0)) continue;
      lines.add(EstimateLine(
        title: 'Полотно: ${entry.key.label}',
        note: entry.key == FilmMaterial.screen
            ? 'скрин: расход по площади заготовки (готовый размер + подворот)'
            : entry.key.thickness,
        quantity: entry.value,
        unit: 'м²',
        unitPrice: prices.filmPerM2(entry.key),
        group: EstimateGroup.materials,
      ));
    }

    // --- Материалы: окантовка по ширинам рулонов -------------------------
    final edgeEntries = summary.edgeByRoll.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in edgeEntries) {
      final meters = entry.value / 1000;
      if (!(meters > 0)) continue;
      final rawWidth = entry.key;
      lines.add(EstimateLine(
        title: 'Окантовка ${edgeBandLabel(rawWidth)}',
        note: 'готовая полоса '
            '${formatMm(WindowParams.finishedEdgeWidth(rawWidth))} мм',
        quantity: meters,
        unit: 'м',
        unitPrice: prices.edgePerMeterForWidth(rawWidth),
        group: EstimateGroup.materials,
      ));
    }

    // --- Фурнитура: люверсы по типам -------------------------------------
    final eyeletEntries = summary.eyeletsByType.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    for (final entry in eyeletEntries) {
      if (entry.value <= 0) continue;
      lines.add(EstimateLine(
        title: 'Люверсы ${entry.key.label}',
        note: 'в том числе установка',
        quantity: entry.value.toDouble(),
        unit: 'шт',
        unitPrice: prices.eyeletPerEach(entry.key),
        group: EstimateGroup.hardware,
      ));
    }

    if (summary.zipperCount > 0 && summary.zipperBandLengthMm > 0) {
      lines.add(EstimateLine(
        title: 'Молния тракторная',
        note: 'полотно и вставка с впайкой, ${summary.zipperCount} шт',
        quantity: summary.zipperBandLengthMm / 1000,
        unit: 'м',
        unitPrice: prices.zipperPerM,
        group: EstimateGroup.hardware,
      ));
    }

    if (summary.pocketCount > 0 && summary.pocketLengthMm > 0) {
      lines.add(EstimateLine(
        title: 'Карман под утяжитель',
        note: 'нижний/верхний карман, ${summary.pocketCount} шт',
        quantity: summary.pocketLengthMm / 1000,
        unit: 'м',
        unitPrice: prices.pocketPerM,
        group: EstimateGroup.hardware,
      ));
    }

    if (summary.strapCount > 0) {
      lines.add(EstimateLine(
        title: 'Подъёмные ремни',
        note: '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} мм',
        quantity: summary.strapCount.toDouble(),
        unit: 'шт',
        unitPrice: prices.strapPrice,
        group: EstimateGroup.hardware,
      ));
    }

    final drainTotal = _drainTotal(summary);
    if (drainTotal > 0) {
      lines.add(EstimateLine(
        title: 'Дренажные отверстия',
        note: 'Ø6 мм в нижней окантовке',
        quantity: drainTotal.toDouble(),
        unit: 'шт',
        unitPrice: prices.drainPrice,
        group: EstimateGroup.hardware,
      ));
    }

    if (summary.cutoutCount > 0) {
      lines.add(EstimateLine(
        title: 'Вырезы в полотне',
        note: 'обработка контура; окантовка учтена в расходе выше',
        quantity: summary.cutoutCount.toDouble(),
        unit: 'шт',
        unitPrice: prices.cutoutPrice,
        group: EstimateGroup.hardware,
      ));
    }

    // --- Работы -----------------------------------------------------------
    if (summary.productAreaM2 > 0) {
      lines.add(EstimateLine(
        title: 'Сварка и сборка изделий',
        note: 'по площади готовых изделий',
        quantity: summary.productAreaM2,
        unit: 'м²',
        unitPrice: prices.laborPerM2,
        group: EstimateGroup.work,
      ));
    }
    if (summary.filmAreaM2 > 0) {
      lines.add(EstimateLine(
        title: 'Раскрой плёнки и разметка',
        note: 'по площади плёнки в раскрое',
        quantity: summary.filmAreaM2,
        unit: 'м²',
        unitPrice: prices.cuttingPerM2,
        group: EstimateGroup.work,
      ));
    }
    if (summary.weldLengthMm > 0) {
      lines.add(EstimateLine(
        title: 'Спайка полотен между окнами',
        note: 'на спаянных сторонах окантовка не ставится',
        quantity: summary.weldLengthMm / 1000,
        unit: 'м',
        unitPrice: prices.weldPerM,
        group: EstimateGroup.work,
      ));
    }
    // Скрин: вместо окантовки — подворот по периметру и шов 3 мм.
    if (summary.screenHemLengthMm > 0) {
      lines.add(EstimateLine(
        title: 'Подворот скрина и шов ${formatMm(screenSeamMm)} мм',
        note: 'расход скрина — по площади заготовки (готовый размер плюс '
            'подворот)',
        quantity: summary.screenHemLengthMm / 1000,
        unit: 'м',
        unitPrice: prices.screenHemPerM,
        group: EstimateGroup.work,
      ));
    }

    return Estimate(
      prices: prices,
      lines: lines,
      windowCount: project.windowCount,
      productAreaM2: summary.productAreaM2,
      filmAreaM2: summary.filmAreaM2,
    );
  }

  /// Смета одного окна — тот же расчёт по заказу из одного окна.
  factory Estimate.ofWindow(WindowParams params, PriceList prices) =>
      Estimate.of(OrderProject(windows: [params]), prices);

  /// Позиции раздела в порядке добавления.
  List<EstimateLine> linesFor(EstimateGroup group) =>
      List.unmodifiable(lines.where((line) => line.group == group));

  /// Подытог раздела, ₽.
  double subtotalFor(EstimateGroup group) => roundMoney(
        lines
            .where((line) => line.group == group)
            .fold<double>(0, (sum, line) => sum + line.amount),
      );

  double get materialsSubtotal => subtotalFor(EstimateGroup.materials);
  double get hardwareSubtotal => subtotalFor(EstimateGroup.hardware);
  double get workSubtotal => subtotalFor(EstimateGroup.work);

  /// Сумма всех позиций без наценки, скидки и НДС.
  double get subtotal => roundMoney(
        materialsSubtotal + hardwareSubtotal + workSubtotal,
      );

  double get markupPercent =>
      prices.markupPercent.isFinite ? math.max(prices.markupPercent, 0) : 0;

  double get discountPercent => prices.discountPercent.isFinite
      ? prices.discountPercent.clamp(0, 100).toDouble()
      : 0;

  double get vatPercent =>
      prices.vatPercent.isFinite ? prices.vatPercent.clamp(0, 100).toDouble() : 0;

  /// Наценка в рублях.
  double get markupAmount => roundMoney(subtotal * markupPercent / 100);

  /// Сумма с наценкой — база для скидки.
  double get afterMarkup => roundMoney(subtotal + markupAmount);

  /// Скидка в рублях.
  double get discountAmount => roundMoney(afterMarkup * discountPercent / 100);

  /// Сумма после скидки — база для НДС.
  double get taxableAmount => roundMoney(afterMarkup - discountAmount);

  /// НДС «сверху», ₽.
  double get vatAmount => roundMoney(taxableAmount * vatPercent / 100);

  /// ИТОГО к оплате, ₽.
  double get total => roundMoney(taxableAmount + vatAmount);

  /// Цена за одно окно, ₽ (0 при пустом заказе).
  double get pricePerWindow =>
      windowCount > 0 ? roundMoney(total / windowCount) : 0;

  /// Пустая ли смета (нет позиций).
  bool get isEmpty => lines.isEmpty;
}

/// Сумма дренажных отверстий по заказу.
///
/// В [CostsSummary] нет готового счётчика дренажа (только подписи), поэтому
/// берём параметры из уже посчитанных спецификаций заказа — геометрия
/// при этом не пересчитывается.
int _drainTotal(CostsSummary summary) {
  var total = 0;
  for (final spec in summary.specs) {
    if (!spec.params.drainHoles) continue;
    final count = spec.params.drainCount;
    if (count.isFinite && count > 0) total += count.round();
  }
  return total;
}

/// Количество с единицей: «12,34», «8,04», «28».
String formatQuantity(double value, String unit) {
  if (!value.isFinite) return '—';
  if (unit == 'шт') return groupThousands(value.round().toString());
  return _formatDecimal(value, 2);
}

/// Округление денег до копейки. Нечисловые значения приводим к нулю.
double roundMoney(double value) =>
    value.isFinite ? (value * 100).roundToDouble() / 100 : 0;

/// Десятичное число с запятой и пробелами между разрядами: «1 234,50».
String _formatDecimal(double value, int decimals) {
  final text = value.toStringAsFixed(decimals);
  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  final parts = body.split('.');
  final fraction = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '−' : ''}${groupThousands(parts.first)}$fraction';
}
