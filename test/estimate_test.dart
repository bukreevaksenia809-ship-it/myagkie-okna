// Тесты прайс-листа и сметы заказа + запись PNG-превью листа «Смета».
//
// Запуск: flutter test test/estimate_test.dart
// Превью: build/preview/smeta.png
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart' as model;
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/estimate_sheet.dart';

import 'test_fonts.dart';

/// Типовое окно заказа: 1500 × 2520 мм, всё по умолчанию.
const _window = WindowParams(
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
);

const _project = OrderProject(windows: [_window]);

/// Семейство шрифта для превью.
///
/// Системный Arial, который грузит `test/test_fonts.dart`, не содержит
/// знака рубля (U+20BD) — в PNG он превратился бы в пустой квадратик.
/// Поэтому для превью подставляем шрифт с ₽ (в приложении такой проблемы
/// нет: там системный шрифт macOS знак рубля содержит).
const _previewFontFamily = 'SmetaPreview';

const _rublesFontCandidates = [
  '/System/Library/Fonts/SFNS.ttf',
  '/System/Library/Fonts/NewYork.ttf',
  '/System/Library/Fonts/Supplemental/STIXTwoText.ttf',
];

/// Регистрирует шрифт со знаком рубля и возвращает семейство подписей.
Future<String> loadRublesFont() async {
  for (final path in _rublesFontCandidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    try {
      final bytes = file.readAsBytesSync();
      final loader = FontLoader(_previewFontFamily)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
      return _previewFontFamily;
    } catch (_) {
      // Шрифт не подошёл — пробуем следующий.
    }
  }
  return testFontFamily;
}

/// Окно для превью: подъёмное, с молнией, карманом и дренажом — в смете
/// видны все разделы.
const _previewWindow = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов И. И.',
  drawingNumber: 'МО-014',
  windowType: WindowType.lifting,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  zippers: [ZipperSpec(centered: false, offsetMm: 500)],
  pocket: true,
  drainHoles: true,
  drainCount: 3,
);

void main() {
  setUpAll(loadRealFonts);

  test('смета окна 1500×2520: ИТОГО, разделы и цена за окно', () {
    final estimate = Estimate.of(_project, PriceList.defaults());

    expect(estimate.windowCount, 1);
    expect(estimate.total, greaterThan(0));
    expect(estimate.materialsSubtotal, greaterThan(0));
    expect(estimate.workSubtotal, greaterThan(0));
    expect(estimate.linesFor(EstimateGroup.materials), isNotEmpty);
    expect(estimate.linesFor(EstimateGroup.work), isNotEmpty);
    expect(estimate.productAreaM2, greaterThan(1));
    expect(estimate.filmAreaM2, greaterThan(0));

    // Одно окно — цена за окно равна ИТОГО.
    expect(estimate.pricePerWindow, closeTo(estimate.total, 0.001));

    // Смета одного окна совпадает со сметой заказа из одного окна.
    final single = Estimate.ofWindow(_window, PriceList.defaults());
    expect(single.total, closeTo(estimate.total, 0.001));
  });

  test('количества совпадают с ведомостью расхода', () {
    final summary = CostsSummary(_project);
    final estimate = Estimate.of(_project, PriceList.defaults());

    // Окантовка: расход из CostsSummary, переведённый в метры.
    final edgeMm =
        summary.edgeByRoll.values.fold<double>(0, (sum, value) => sum + value);
    expect(edgeMm, greaterThan(0));
    final edgeLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Окантовка'));
    expect(edgeLine.unit, 'м');
    expect(edgeLine.quantity, closeTo(edgeMm / 1000, 1e-9));

    // Люверсы: ровно столько, сколько в сводке.
    final eyeletLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Люверсы'));
    expect(eyeletLine.unit, 'шт');
    expect(eyeletLine.quantity, closeTo(summary.eyeletTotal.toDouble(), 1e-9));

    // Плёнка: площадь заготовки (габарит) с усадкой — та, по которой
    // реально кроится полотно.
    final filmLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Полотно'));
    expect(filmLine.quantity, closeTo(summary.filmAreaWithShrinkageM2, 1e-9));
    expect(filmLine.quantity,
        greaterThanOrEqualTo(summary.filmAreaM2 - 1e-9));

    // Люверс считается с установкой.
    final prices = PriceList.defaults();
    expect(
      eyeletLine.unitPrice,
      closeTo(prices.eyeletPrice + prices.eyeletInstall, 1e-9),
    );
  });

  test('смета скрина: без окантовки и тента, с подворотом и швом 3 мм', () {
    const screen = WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      hemBottomMm: 40,
      hemRightMm: 40,
      hemTopMm: 40,
      hemLeftMm: 40,
    );
    const project = OrderProject(windows: [screen]);
    final summary = CostsSummary(project);
    final estimate = Estimate.of(project, PriceList.defaults());

    // Окантовки у скрина нет вовсе.
    expect(summary.edgeByRoll, isEmpty);
    expect(
      estimate.lines.any((line) => line.title.startsWith('Окантовка')),
      isFalse,
    );
    // Тента, напайки и молний в смете скрина тоже нет.
    final allTitles = estimate.lines.map((line) => line.title).join(' | ');
    expect(allTitles, isNot(contains('Тент')));
    expect(allTitles, isNot(contains('напайк')));
    expect(allTitles, isNot(contains('Напайк')));
    expect(allTitles, isNot(contains('Молния')));
    // Полотно скрина: площадь заготовки 2080 × 2080 = 4,33 м².
    final filmLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Полотно'));
    expect(filmLine.title, contains('Скрин'));
    expect(filmLine.quantity, closeTo(4.3264, 1e-9));
    // Цена — из прайса скрина, подпись объясняет площадь заготовки.
    final prices = PriceList.defaults();
    expect(filmLine.unitPrice, prices.filmScreenPerM2);
    expect(filmLine.note, contains('заготовка'));
    expect(filmLine.note, contains('4,33'));
    expect(filmLine.note, contains('${prices.filmScreenPerM2.toStringAsFixed(0)} ₽/м²'));
    // Работа: подворот по периметру 4 × 2 м и шов 3 мм.
    final hemLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Подворот скрина'));
    expect(hemLine.title, contains('3'));
    expect(hemLine.quantity, closeTo(8.0, 1e-9));
    expect(hemLine.unit, 'м');
    expect(hemLine.unitPrice, prices.screenHemPerM);
    expect(hemLine.note, contains('8,00'));
    expect(hemLine.note, contains('низ, право, верх, лево'));
    // Люверсы скрина — по цене люверса с установкой.
    final eyeletLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Люверсы'));
    expect(eyeletLine.quantity,
        closeTo(summary.eyeletTotal.toDouble(), 1e-9));
    expect(eyeletLine.unitPrice,
        closeTo(prices.eyeletPrice + prices.eyeletInstall, 1e-9));
    // Усадки нет — площадь с усадкой совпадает с заготовкой.
    expect(
      summary.filmAreaWithShrinkageM2,
      closeTo(summary.filmAreaM2, 1e-9),
    );
  });

  test('смета скрина: смешанные подвороты меняют заготовку, но не периметр', () {
    // Низ 40, право 50, верх 60, лево 40 → прибавка по оси — удвоенный больший
    // подворот: ширина 2000 + 2 × 50 = 2100, высота 2000 + 2 × 60 = 2120,
    // периметр готового изделия остаётся 8000 мм.
    const screen = WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      hemBottomMm: 40,
      hemRightMm: 50,
      hemTopMm: 60,
      hemLeftMm: 40,
    );
    final project = const OrderProject(windows: [screen]);
    final summary = CostsSummary(project);
    final estimate = Estimate.of(project, PriceList.defaults());

    expect(summary.filmAreaM2, closeTo(2.100 * 2.120, 1e-9));
    expect(summary.screenHemLengthMm, closeTo(8000, 1e-9));
    final filmLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Полотно'));
    // Площадь заготовки скрина идёт в смету, а не площадь изделия.
    expect(filmLine.quantity, closeTo(4.452, 1e-3));
    expect(filmLine.quantity, isNot(closeTo(4.0, 1e-6)));
    final hemLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Подворот скрина'));
    expect(hemLine.quantity, closeTo(8.0, 1e-9));
  });

  test('смета скрина с крепежом: цена овального люверса под скобу', () {
    // Скрин с французским замком: по низу и бокам ставится выбранный крепёж,
    // под него идёт овальный люверс — цена берётся из прайса (цена + установка).
    const screen = WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      hemBottomMm: 40,
      hemRightMm: 40,
      hemTopMm: 40,
      hemLeftMm: 40,
      windowType: WindowType.lifting,
      fastenerType: FastenerType.frenchLocks,
      eyeletType: EyeletType.oval42x22,
    );
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(screen, prices);
    final ovalLine = estimate.lines
        .firstWhere((line) => line.title.contains(EyeletType.oval42x22.label));
    final roundLine = estimate.lines
        .firstWhere((line) => line.title.contains(EyeletType.round10.label));

    // Цена выбранного крепежа/люверса — из прайса.
    expect(ovalLine.unitPrice, prices.eyeletOvalPrice + prices.eyeletInstall);
    expect(ovalLine.quantity, greaterThan(0));
    // В углах всегда круглые люверсы — их ровно 4.
    expect(roundLine.quantity, 4);
    expect(roundLine.unitPrice, prices.eyeletPrice + prices.eyeletInstall);
    // Строк про тент и окантовку у скрина нет.
    final titles = estimate.lines.map((line) => line.title).join(' | ');
    expect(titles, isNot(contains('Окантовка')));
    expect(titles, isNot(contains('Тент')));
  });

  test('смета скрина с молнией: ткань скрина, молния и работа шва', () {
    const screen = WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      hemBottomMm: 40,
      hemRightMm: 40,
      hemTopMm: 40,
      hemLeftMm: 40,
      zippers: [ZipperSpec(centered: true)],
    );
    const project = OrderProject(windows: [screen]);
    final summary = CostsSummary(project);
    final prices = PriceList.defaults();
    final estimate = Estimate.of(project, prices);
    final titles = estimate.lines.map((line) => line.title).join(' | ');

    expect(titles, contains('Полотно: Скрин'));
    expect(titles, contains('Молния тракторная'));
    expect(titles, contains('Подворот скрина'));
    expect(titles, isNot(contains('Окантовка')));

    // Полоса молнии — материал скрина: 50 × 2000 = 0,1 м² поверх заготовки.
    expect(summary.screenZipperBandAreaM2, closeTo(0.1, 1e-9));
    expect(summary.filmAreaWithShrinkageM2, closeTo(4.3264 + 0.1, 1e-9));
    final filmLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Полотно'));
    expect(filmLine.quantity, closeTo(4.4264, 1e-9));
    expect(filmLine.unitPrice, prices.filmScreenPerM2);
    expect(filmLine.note, contains('полосы молний'));

    // Работа: периметр 8 м плюс шов полосы 2 м — по цене подворота скрина.
    final hemLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Подворот скрина'));
    expect(hemLine.quantity, closeTo(10.0, 1e-9));
    expect(hemLine.unitPrice, prices.screenHemPerM);
    expect(hemLine.note, contains('швы полос молний'));

    // Молния: 2 м по цене прайса, подпись про полосу скрина.
    final zipperLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Молния'));
    expect(zipperLine.quantity, closeTo(2.0, 1e-9));
    expect(zipperLine.unitPrice, prices.zipperPerM);
    expect(zipperLine.note, contains('скрина'));
    // Полосы тента (окантовки) у скрина в расходе нет.
    expect(summary.edgeByRoll, isEmpty);
  });

  test('смета: сторона без люверсов уменьшает строку люверсов', () {
    const withoutTop = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      noEyeletsTop: true,
    );
    final summary = CostsSummary(const OrderProject(windows: [withoutTop]));
    final estimate = Estimate.ofWindow(withoutTop, PriceList.defaults());
    final eyeletLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Люверсы'));

    // Окно 2000 × 1500 даёт 24 люверса, верх без люверсов — 17.
    expect(summary.eyeletTotal, 17);
    expect(eyeletLine.quantity, 17);
    expect(eyeletLine.note, contains('установка'));
  });

  test('смета: овальный люверс на глухом окне — по цене овального', () {
    const fixedOval = WindowParams(
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 1500,
      rightHeight: 1500,
      eyeletType: EyeletType.oval42x22,
    );
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(fixedOval, prices);
    final ovalLine = estimate.lines.firstWhere(
      (candidate) => candidate.title.contains(EyeletType.oval42x22.label),
    );
    final roundLine = estimate.lines.firstWhere(
      (candidate) => candidate.title.contains(EyeletType.round10.label),
    );

    // 24 люверса: 20 овальных по сторонам и 4 круглых в углах.
    expect(ovalLine.quantity, 20);
    expect(ovalLine.unitPrice, prices.eyeletOvalPrice + prices.eyeletInstall);
    expect(roundLine.quantity, 4);
    expect(roundLine.unitPrice, prices.eyeletPrice + prices.eyeletInstall);
    expect(
      prices.eyeletOvalPrice,
      greaterThan(prices.eyeletPrice),
      reason: 'овальный люверс дороже круглого',
    );
  });

  test('смета: своя ширина окантовки 150 мм — интерполяция цены и подпись', () {
    final prices = PriceList.defaults();
    const custom = WindowParams(
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2520,
      rightHeight: 2520,
      rollBottom: 150,
    );
    final estimate = Estimate.ofWindow(custom, prices);
    final line = estimate.lines
        .firstWhere((candidate) => candidate.title.contains('Тент 150 мм'));

    // Ожидание считаем от пресетов прайса: 150 мм лежит между 120 и 200.
    final expected = prices.edge120PerM +
        (prices.edge200PerM - prices.edge120PerM) * (150 - 120) / (200 - 120);
    expect(expected, closeTo(189.375, 1e-9));
    expect(prices.edgePerMeterForWidth(150), closeTo(expected, 1e-9));
    expect(line.unitPrice, closeTo(expected, 1e-9));
    expect(line.title, 'Окантовка Тент 150 мм');
    expect(line.note, contains('75'));
    expect(line.quantity, closeTo(1.5, 1e-9));

    // Пресеты считаются по своим ценам — включая новые 80 и 120 мм.
    expect(prices.edgePerMeterForWidth(80), prices.edge80PerM);
    expect(prices.edgePerMeterForWidth(100), prices.edge100PerM);
    expect(prices.edgePerMeterForWidth(120), prices.edge120PerM);
    expect(prices.edgePerMeterForWidth(200), prices.edge200PerM);
    expect(prices.edgePerMeterForWidth(240), prices.edge240PerM);

    // Вне диапазона — экстраполяция по ближайшему отрезку, без деления на ноль.
    final below = prices.edgePerMeterForWidth(50);
    expect(below.isFinite, isTrue);
    expect(below, lessThan(prices.edge80PerM));
    final above = prices.edgePerMeterForWidth(300);
    expect(above.isFinite, isTrue);
    expect(
      above,
      closeTo(
        prices.edge240PerM +
            (prices.edge240PerM - prices.edge200PerM) * (60 / 40),
        1e-9,
      ),
    );
  });

  test('скидка 10 % уменьшает ИТОГО ровно на 10 %', () {
    final base = PriceList.defaults();
    final full = Estimate.of(_project, base);
    final discounted =
        Estimate.of(_project, base.copyWith(discountPercent: 10));

    expect(discounted.discountAmount,
        closeTo(discounted.afterMarkup * 0.1, 0.005));
    // Скидка считается от суммы после наценки, а та округлена до копейки,
    // поэтому итог отличается от «× 0,9» на копейки — допускаем 2 копейки.
    expect(discounted.total, closeTo(full.total * 0.9, 0.02));
  });

  test('наценка 20 % увеличивает подытог на 20 %', () {
    final base = PriceList.defaults();
    final full = Estimate.of(_project, base);
    final marked = Estimate.of(_project, base.copyWith(markupPercent: 20));

    expect(marked.subtotal, closeTo(full.subtotal, 0.001));
    expect(marked.markupAmount, closeTo(full.subtotal * 0.2, 0.01));
    expect(marked.afterMarkup, closeTo(full.subtotal * 1.2, 0.01));
  });

  test('НДС считается от суммы после наценки и скидки', () {
    final prices = PriceList.defaults()
        .copyWith(markupPercent: 10, discountPercent: 10);
    final estimate = Estimate.of(_project, prices);

    expect(estimate.markupAmount,
        closeTo(estimate.subtotal * 0.1, 0.005));
    expect(estimate.discountAmount,
        closeTo(estimate.afterMarkup * 0.1, 0.005));
    expect(
      estimate.taxableAmount,
      closeTo(estimate.afterMarkup - estimate.discountAmount, 0.001),
    );
    expect(estimate.vatAmount,
        closeTo(estimate.taxableAmount * 0.2, 0.005));
    expect(
      estimate.total,
      closeTo(estimate.taxableAmount + estimate.vatAmount, 0.001),
    );

    // Нулевой НДС — ИТОГО равно сумме после скидки.
    final noVat = Estimate.of(_project, prices.copyWith(vatPercent: 0));
    expect(noVat.vatAmount, 0);
    expect(noVat.total, closeTo(noVat.taxableAmount, 0.001));
  });

  test('пустой заказ и нулевые цены не ломают расчёт', () {
    final empty = Estimate.of(const OrderProject(windows: []), PriceList.defaults());
    expect(empty.total, 0);
    expect(empty.pricePerWindow, 0);
    expect(empty.lines, isEmpty);

    final free = Estimate.of(
      _project,
      const PriceList(
        filmClearPerM2: 0,
        filmTintedPerM2: 0,
        filmMeshPerM2: 0,
        edge100PerM: 0,
        edge200PerM: 0,
        edge240PerM: 0,
        eyeletPrice: 0,
        eyeletOvalPrice: 0,
        eyeletInstall: 0,
        zipperPerM: 0,
        weldPerM: 0,
        pocketPerM: 0,
        strapPrice: 0,
        drainPrice: 0,
        cutoutPrice: 0,
        laborPerM2: 0,
        cuttingPerM2: 0,
        vatPercent: 0,
      ),
    );
    expect(free.total, 0);
    expect(free.lines, isNotEmpty);
  });

  test('JSON прайса: round-trip сохраняет цены', () {
    final source = model.PriceList.defaults().copyWith(
      filmClearPerM2: 1015.5,
      filmTintedPerM2: 1199,
      filmMeshPerM2: 455,
      edge80PerM: 125.5,
      edge100PerM: 149.9,
      edge120PerM: 172.25,
      edge200PerM: 249,
      edge240PerM: 289,
      eyeletPrice: 72,
      eyeletOvalPrice: 133,
      eyeletInstall: 31,
      zipperPerM: 830,
      weldPerM: 470,
      pocketPerM: 395,
      strapPrice: 205,
      drainPrice: 95,
      cutoutPrice: 370,
      laborPerM2: 750,
      cuttingPerM2: 275,
      markupPercent: 12,
      discountPercent: 7.5,
      vatPercent: 0,
    );

    final restored = model.PriceList.fromJson(source.toJson());
    expect(restored.toJson(), equals(source.toJson()));
    expect(restored.filmClearPerM2, 1015.5);
    expect(restored.discountPercent, 7.5);
    expect(restored.vatPercent, 0);
    expect(restored.edge80PerM, 125.5);
    expect(restored.edge120PerM, 172.25);

    // Битые и выходящие за границы значения заменяются дефолтами.
    // Отрицательная цена — не цена: берём значение по умолчанию.
    final broken = model.PriceList.fromJson({
      'filmClearPerM2': 'дорого',
      'edge100PerM': -5,
      'vatPercent': -5,
      'discountPercent': 250,
      'currency': 42,
    });
    expect(broken.filmClearPerM2, model.defaultFilmClearPerM2);
    expect(broken.edge100PerM, model.defaultEdge100PerM);
    expect(broken.vatPercent, model.defaultVatPercent);
    expect(broken.discountPercent, 100);
    expect(broken.currency, model.defaultCurrencySymbol);

    // Разбор ввода цены в панели.
    expect(model.parsePrice('1 234,56'), closeTo(1234.56, 1e-9));
    expect(model.parsePrice('1234.56'), closeTo(1234.56, 1e-9));
    expect(model.parsePrice('2 000 ₽'), closeTo(2000, 1e-9));
    expect(model.parsePrice('−500'), 0);
    expect(model.parsePrice('abc'), isNull);
    expect(model.parsePrice(''), isNull);
  });

  test('прайс: цены 80 и 120 мм берутся из прайса, а не интерполяцией', () {
    final prices = model.PriceList.defaults();

    // Значения по умолчанию: 80 → 120 ₽/м, 120 → 165 ₽/м.
    expect(prices.edge80PerM, model.defaultEdge80PerM);
    expect(prices.edge120PerM, model.defaultEdge120PerM);
    expect(prices.edge80PerM, 120);
    expect(prices.edge120PerM, 165);
    // Точное попадание в пресет — цена пресета, без интерполяции.
    expect(prices.edgePerMeterForWidth(80), prices.edge80PerM);
    expect(prices.edgePerMeterForWidth(120), prices.edge120PerM);

    // Заданные в прайсе цены важнее любых опорных точек.
    final custom = prices.copyWith(edge80PerM: 111, edge120PerM: 222);
    expect(custom.edgePerMeterForWidth(80), 111);
    expect(custom.edgePerMeterForWidth(120), 222);
  });

  test('прайс: старый JSON без цен 80/120 читается дефолтами', () {
    final json = model.PriceList.defaults().toJson()
      ..remove('edge80PerM')
      ..remove('edge120PerM');
    final restored = model.PriceList.fromJson(json);

    expect(restored.edge80PerM, model.defaultEdge80PerM);
    expect(restored.edge120PerM, model.defaultEdge120PerM);
    expect(restored.edgePerMeterForWidth(80), model.defaultEdge80PerM);
    expect(restored.edgePerMeterForWidth(120), model.defaultEdge120PerM);
  });

  test('форматирование денег', () {
    expect(formatRubles(12345.678), '12 345,68 ₽');
    expect(formatRubles(0), '0,00 ₽');
    expect(formatRubles(999.994), '999,99 ₽');
    expect(formatRubles(-500.5), '−500,50 ₽');
    expect(formatRubles(double.nan), '—');
    expect(formatQuantity(8.04, 'м'), '8,04');
    expect(formatQuantity(28, 'шт'), '28');
  });

  test('размер листа: пустой — заполняет окно, длинный — задаёт высоту', () {
    // Небольшая смета в большом окне — лист заполняет окно (null).
    expect(
      EstimateSheet.sheetSize(_project, const Size(1720, 1080)),
      isNull,
    );
    // В маленьком окне лист становится длиннее окна.
    final small = EstimateSheet.sheetSize(_project, const Size(900, 700));
    expect(small, isNotNull);
    expect(small!.height, greaterThan(700));
    expect(small.width, greaterThanOrEqualTo(1320));
    // Большой заказ — лист выше окна.
    final many = EstimateSheet.sheetSize(
      OrderProject(windows: List.filled(6, _window)),
      const Size(1720, 1080),
    );
    expect(many, isNotNull);
    expect(many!.height, greaterThan(1080));
  });

  testWidgets('пишет PNG-превью листа «Смета»', (tester) async {
    tester.view.physicalSize = const Size(1720, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final captureKey = GlobalKey();
    final fontFamily = await loadRublesFont();
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          body: EstimateSheet(
            project: const OrderProject(windows: [_previewWindow]),
            prices: PriceList.defaults(),
            captureKey: captureKey,
            labelFontFamily: fontFamily,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final bytes = await tester.runAsync(() async {
      final boundary = captureKey.currentContext!.findRenderObject()!
          as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    final file = File('build/preview/smeta.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    expect(file.lengthSync(), greaterThan(5000));
    // ignore: avoid_print
    print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
  });
}
