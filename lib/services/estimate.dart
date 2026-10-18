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
    show PriceField, PriceItemKeys, PriceList, formatRubles, parsePrice;

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
    this.itemKey,
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

  /// Ключ позиции прайса ([PriceItemKeys]) — по нему видно, какой тумблер
  /// панели управляет строкой (может быть null у сводных строк).
  final String? itemKey;

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

  /// Суммарная площадь заготовок по контуру в раскрое С усадкой, м² — по ней
  /// считаются позиции плёнки и работы раскроя.
  final double filmAreaM2;

  /// Смета всего заказа.
  factory Estimate.of(OrderProject project, PriceList prices) {
    final summary = CostsSummary(project);
    final lines = <EstimateLine>[];

    // --- Материалы: полотно по материалам --------------------------------
    // Берём площадь заготовки по контуру С усадкой: плёнка кроится по
    // усадочным габаритам, поэтому без усадки цена была бы занижена.
    final filmEntries = summary.filmAreaByMaterialWithShrinkage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in filmEntries) {
      if (!(entry.value > 0)) continue;
      // Выключенный в прайсе материал не попадает в смету: строку не создаём
      // вовсе (нулевая строка только засоряет лист «Смета»).
      final itemKey = PriceList.filmItemKey(entry.key);
      if (!prices.isEnabled(itemKey)) continue;
      final pricePerM2 = prices.filmPerM2(entry.key);
      lines.add(EstimateLine(
        title: 'Полотно: ${entry.key.label}',
        // У скрина полотно считается по площади заготовки: готовый размер
        // плюс прибавка по каждой оси — среднее двух подворотов плюс 20 мм,
        // а если стоят молнии — ширина заготовки уже уменьшена на полосы под
        // них. У ПВХ полоса (спайка) вычитается из ширины так же — подпись
        // показывает это человеку прямо в смете.
        note: entry.key == FilmMaterial.screen
            ? 'скрин: заготовка по контуру ${formatMeters(entry.value)} м² × '
                '${_unitPriceLabel(pricePerM2)} ₽/м² — готовый размер плюс '
                'среднее подворотов по оси + 20 мм'
                '${summary.screenZipperCount > 0 ? ', ширина кроя уменьшена на '
                    'полосу молнии '
                    '${formatMm(summary.screenZipperBandWidthMm)} мм' : ''}'
            : '${entry.key.thickness}; заготовка по контуру'
                '${summary.hasShrinkage ? ' с компенсацией усадки' : ''}'
                '${summary.hasAutoHeightAllowance
                    ? '${summary.hasShrinkage ? ' и' : ' с'} авто-припуском '
                        '+10 мм к высоте (ПВХ)'
                    : ''}'
                '${summary.pvcZipperCount > 0 ? ', ширина кроя уменьшена на '
                    'полосу (спайку) молнии '
                    '${formatMm(summary.pvcZipperBandWidthMm)} мм' : ''}',
        quantity: entry.value,
        unit: 'м²',
        unitPrice: pricePerM2,
        group: EstimateGroup.materials,
        itemKey: itemKey,
      ));
    }

    // --- Материалы: окантовка по ширинам рулонов -------------------------
    final edgeEntries = summary.edgeByRoll.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    for (final entry in edgeEntries) {
      final meters = entry.value / 1000;
      if (!(meters > 0)) continue;
      final rawWidth = entry.key;
      // Тумблер пресета убирает строку этого рулона. Своя ширина позиции в
      // прайсе не имеет (цена интерполируется), поэтому её строка остаётся.
      final itemKey = PriceList.edgeItemKey(rawWidth);
      if (itemKey != null && !prices.isEnabled(itemKey)) continue;
      lines.add(EstimateLine(
        title: 'Окантовка ${edgeBandLabel(rawWidth)}',
        note: 'готовая полоса '
            '${formatMm(WindowParams.finishedEdgeWidth(rawWidth))} мм',
        quantity: meters,
        unit: 'м',
        unitPrice: prices.edgePerMeterForWidth(rawWidth),
        group: EstimateGroup.materials,
        itemKey: itemKey,
      ));
    }

    // --- Фурнитура: люверсы по типам -------------------------------------
    final eyeletEntries = summary.eyeletsByType.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    for (final entry in eyeletEntries) {
      if (entry.value <= 0) continue;
      final isRound = entry.key == EyeletType.round10;
      final itemKey =
          isRound ? PriceItemKeys.eyeletRound : PriceItemKeys.eyeletOval;
      if (!prices.isEnabled(itemKey)) continue;
      // Установка отдельной строки не имеет — она в цене люверса, поэтому её
      // тумблер убирает из цены надбавку за установку.
      final installEnabled = prices.isEnabled(PriceItemKeys.eyeletInstall);
      lines.add(EstimateLine(
        title: 'Люверсы ${entry.key.label}',
        note: installEnabled
            ? 'в том числе установка'
            : 'без установки: установка выключена в прайсе',
        quantity: entry.value.toDouble(),
        unit: 'шт',
        unitPrice: prices.eyeletPerEach(entry.key),
        group: EstimateGroup.hardware,
        itemKey: itemKey,
      ));
    }

    // --- Фурнитура: крепёж подвижных сторон по типам --------------------
    // Скоба, замок и ремень ставятся в каждую точку низа и боков, кроме
    // углов. Люверс под них — отдельная строка выше: замок ставится через
    // люверс, и это две разные позиции прайса.
    final fastenerEntries = summary.fastenerCount.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    for (final entry in fastenerEntries) {
      if (entry.value <= 0) continue;
      final itemKey = _fastenerItemKey(entry.key);
      if (!prices.isEnabled(itemKey)) continue;
      final unitPrice = prices.fastenerPerEach(entry.key);
      lines.add(EstimateLine(
        title: entry.key.itemTitle,
        note: '${entry.value} шт × ${_unitPriceLabel(unitPrice)} ₽/шт — '
            'низ и бока, в точках люверсов (люверс — отдельной строкой)',
        quantity: entry.value.toDouble(),
        unit: 'шт',
        unitPrice: unitPrice,
        group: EstimateGroup.hardware,
        itemKey: itemKey,
      ));
    }

    // Саморезы верхнего ряда: у подъёмного окна и скрина верх идёт к раме.
    if (summary.screwCount > 0 && prices.isEnabled(PriceItemKeys.screw)) {
      lines.add(EstimateLine(
        title: 'Саморезы верхнего ряда',
        note: '${summary.screwCount} шт × '
            '${_unitPriceLabel(prices.screwPrice)} ₽/шт — верхняя кромка '
            'крепится к раме',
        quantity: summary.screwCount.toDouble(),
        unit: 'шт',
        unitPrice: prices.screwPrice,
        group: EstimateGroup.hardware,
        itemKey: PriceItemKeys.screw,
      ));
    }

    if (summary.zipperCount > 0 &&
        summary.zipperBandLengthMm > 0 &&
        prices.isEnabled(PriceItemKeys.zipper)) {
      final note = summary.screenZipperCount == 0
          ? 'полотно и вставка с впайкой, ${summary.zipperCount} шт'
          : summary.screenZipperCount == summary.zipperCount
              ? 'полотно и вставка; полоса из скрина со швом '
                  '${formatMm(screenSeamMm)} мм по краям — '
                  '${summary.screenZipperCount} шт'
              : 'полотно и вставка: с полосой тента '
                  '${summary.zipperCount - summary.screenZipperCount} шт, '
                  'с полосой скрина ${summary.screenZipperCount} шт (шов '
                  '${formatMm(screenSeamMm)} мм)';
      lines.add(EstimateLine(
        title: 'Молния тракторная',
        note: note,
        quantity: summary.zipperBandLengthMm / 1000,
        unit: 'м',
        unitPrice: prices.zipperPerM,
        group: EstimateGroup.hardware,
        itemKey: PriceItemKeys.zipper,
      ));
    }

    if (summary.pocketCount > 0 &&
        summary.pocketLengthMm > 0 &&
        prices.isEnabled(PriceItemKeys.pocket)) {
      lines.add(EstimateLine(
        title: 'Фартук под утяжитель',
        note: 'нижний/верхний фартук, ${summary.pocketCount} шт',
        quantity: summary.pocketLengthMm / 1000,
        unit: 'м',
        unitPrice: prices.pocketPerM,
        group: EstimateGroup.hardware,
        itemKey: PriceItemKeys.pocket,
      ));
    }

    if (summary.strapCount > 0 && prices.isEnabled(PriceItemKeys.strap)) {
      lines.add(EstimateLine(
        title: 'Подъёмные ремни',
        note: '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} мм',
        quantity: summary.strapCount.toDouble(),
        unit: 'шт',
        unitPrice: prices.strapPrice,
        group: EstimateGroup.hardware,
        itemKey: PriceItemKeys.strap,
      ));
    }

    final drainTotal = _drainTotal(summary);
    if (drainTotal > 0 && prices.isEnabled(PriceItemKeys.drain)) {
      lines.add(EstimateLine(
        title: 'Дренажные отверстия',
        note: 'Ø6 мм в нижней окантовке',
        quantity: drainTotal.toDouble(),
        unit: 'шт',
        unitPrice: prices.drainPrice,
        group: EstimateGroup.hardware,
        itemKey: PriceItemKeys.drain,
      ));
    }

    if (summary.cutoutCount > 0 && prices.isEnabled(PriceItemKeys.cutout)) {
      lines.add(EstimateLine(
        title: 'Вырезы в полотне',
        note: 'обработка контура; окантовка учтена в расходе выше',
        quantity: summary.cutoutCount.toDouble(),
        unit: 'шт',
        unitPrice: prices.cutoutPrice,
        group: EstimateGroup.hardware,
        itemKey: PriceItemKeys.cutout,
      ));
    }

    // --- Работы -----------------------------------------------------------
    if (summary.productAreaM2 > 0 && prices.isEnabled(PriceItemKeys.labor)) {
      lines.add(EstimateLine(
        title: 'Сварка и сборка изделий',
        note: 'по площади готовых изделий',
        quantity: summary.productAreaM2,
        unit: 'м²',
        unitPrice: prices.laborPerM2,
        group: EstimateGroup.work,
        itemKey: PriceItemKeys.labor,
      ));
    }
    if (summary.filmAreaWithShrinkageM2 > 0 &&
        prices.isEnabled(PriceItemKeys.cutting)) {
      lines.add(EstimateLine(
        title: 'Раскрой плёнки и разметка',
        note: 'по площади заготовки по контуру с усадкой',
        quantity: summary.filmAreaWithShrinkageM2,
        unit: 'м²',
        unitPrice: prices.cuttingPerM2,
        group: EstimateGroup.work,
        itemKey: PriceItemKeys.cutting,
      ));
    }
    if (summary.weldLengthMm > 0 && prices.isEnabled(PriceItemKeys.weld)) {
      lines.add(EstimateLine(
        title: 'Спайка полотен между окнами',
        note: 'на спаянных сторонах окантовка не ставится',
        quantity: summary.weldLengthMm / 1000,
        unit: 'м',
        unitPrice: prices.weldPerM,
        group: EstimateGroup.work,
        itemKey: PriceItemKeys.weld,
      ));
    }
    // Скрин: вместо окантовки — подворот по сторонам и шов 3 мм. Работа
    // считается по длине подворота: периметр готового изделия, а если у окна
    // есть молнии — плюс шов по длине полосы каждой молнии.
    if (summary.screenHemLengthMm > 0 &&
        prices.isEnabled(PriceItemKeys.screenHem)) {
      final hemMeters = summary.screenHemLengthMm / 1000;
      lines.add(EstimateLine(
        title: 'Подворот скрина и шов ${formatMm(screenSeamMm)} мм',
        note: 'подворот по сторонам (низ, право, верх, лево): '
            '${formatMeters(hemMeters)} м × '
            '${_unitPriceLabel(prices.screenHemPerM)} ₽/м — '
            '${summary.screenZipperCount > 0 ? 'периметр готового изделия плюс '
                'швы полос молний '
                '(${formatMm(summary.screenZipperBandLengthMm)} мм)' : 'длина по периметру '
                'готового изделия'}',
        quantity: hemMeters,
        unit: 'м',
        unitPrice: prices.screenHemPerM,
        group: EstimateGroup.work,
        itemKey: PriceItemKeys.screenHem,
      ));
    }

    return Estimate(
      prices: prices,
      lines: lines,
      windowCount: project.windowCount,
      productAreaM2: summary.productAreaM2,
      filmAreaM2: summary.filmAreaWithShrinkageM2,
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

/// Ключ позиции прайса для типа крепежа: скоба, замок, ремень.
///
/// У «только люверсы» своего крепежа нет, строки для него не бывает —
/// возвращаем ключ ремня как безопасный запасной вариант.
String _fastenerItemKey(FastenerType type) => switch (type) {
      FastenerType.eyeletsOnly => PriceItemKeys.strap,
      FastenerType.turnBuckles => PriceItemKeys.turnBuckle,
      FastenerType.frenchLocks => PriceItemKeys.frenchLock,
      FastenerType.straps => PriceItemKeys.strap,
    };

/// Сумма дренажных отверстий по заказу.
///
/// В [CostsSummary] нет готового счётчика дренажа (только подписи), поэтому
/// берём параметры из уже посчитанных спецификаций заказа — геометрия
/// при этом не пересчитывается.
int _drainTotal(CostsSummary summary) {
  var total = 0;
  for (final spec in summary.specs) {
    // У скрина нет нижней окантовки — дренаж не считается.
    if (!spec.params.drainHoles || spec.params.isScreen) continue;
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

/// Цена за единицу без символа валюты: «520» или «520,50».
///
/// Нужна для подписей вида «4,33 м² × 520 ₽/м²» — цена стоит рядом с единицей
/// измерения, поэтому символ валюты в подписи не дублируется.
String _unitPriceLabel(double value) {
  if (!value.isFinite) return '—';
  if (value == value.roundToDouble()) {
    return groupThousands(value.toStringAsFixed(0));
  }
  return value.toStringAsFixed(2).replaceAll('.', ',');
}

/// Десятичное число с запятой и пробелами между разрядами: «1 234,50».
String _formatDecimal(double value, int decimals) {
  final text = value.toStringAsFixed(decimals);
  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  final parts = body.split('.');
  final fraction = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '−' : ''}${groupThousands(parts.first)}$fraction';
}
