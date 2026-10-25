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
import 'package:soft_window_drawer/models/document.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart' as model;
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/company_branding.dart';
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

/// Трапеция ПВХ для тестов отхода: низ 2000, верх 1000, высоты 1000,
/// запайка 25 мм. Заготовка к раскрою: низ 1950, верх 950, высота 960
/// (авто-припуск +10 мм к высоте), площадь контура 1,392 м².
const _trapezoidPvc = WindowParams(
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  weldOverlapMm: 25,
);

/// Трапеция скрина: те же 2000/1000 × 1000, подворот 40 мм со всех сторон.
/// Заготовка: низ 2040, верх 1040, высота 1060, площадь контура 1,6324 м².
const _trapezoidScreen = WindowParams(
  material: FilmMaterial.screen,
  bottomWidth: 2000,
  topWidth: 1000,
  leftHeight: 1000,
  rightHeight: 1000,
  hemBottomMm: 40,
  hemRightMm: 40,
  hemTopMm: 40,
  hemLeftMm: 40,
);

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

/// Окно для превью: подъёмное, с молнией, фартуком и дренажом — в смете
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
  zippers: [ZipperSpec(centered: false, offsetMm: 500, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)],
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
    final edgeMm = summary.edgeByRoll.values.fold<double>(
      0,
      (sum, value) => sum + value,
    );
    expect(edgeMm, greaterThan(0));
    final edgeLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Окантовка'),
    );
    expect(edgeLine.unit, 'м');
    expect(edgeLine.quantity, closeTo(edgeMm / 1000, 1e-9));

    // Люверсы: ровно столько, сколько в сводке.
    final eyeletLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Люверсы'),
    );
    expect(eyeletLine.unit, 'шт');
    expect(eyeletLine.quantity, closeTo(summary.eyeletTotal.toDouble(), 1e-9));

    // Плёнка: площадь заготовки по контуру с усадкой — та, по которой
    // реально кроится полотно.
    final filmLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    expect(filmLine.quantity, closeTo(summary.filmAreaWithShrinkageM2, 1e-9));
    expect(filmLine.quantity, greaterThanOrEqualTo(summary.filmAreaM2 - 1e-9));

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
    // Полотно скрина: площадь заготовки 2040 × 2060 = 4,20 м².
    final filmLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    expect(filmLine.title, contains('Скрин'));
    expect(filmLine.quantity, closeTo(4.2024, 1e-9));
    // Цена — из прайса скрина, подпись объясняет площадь заготовки.
    final prices = PriceList.defaults();
    expect(filmLine.unitPrice, prices.filmScreenPerM2);
    expect(filmLine.note, contains('заготовка'));
    expect(filmLine.note, contains('4,20'));
    expect(
      filmLine.note,
      contains('${prices.filmScreenPerM2.toStringAsFixed(0)} ₽/м²'),
    );
    // Работа: подворот по периметру 4 × 2 м и шов 3 мм.
    final hemLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Подворот скрина'),
    );
    expect(hemLine.title, contains('3'));
    expect(hemLine.quantity, closeTo(8.0, 1e-9));
    expect(hemLine.unit, 'м');
    expect(hemLine.unitPrice, prices.screenHemPerM);
    expect(hemLine.note, contains('8,00'));
    expect(hemLine.note, contains('низ, право, верх, лево'));
    // Люверсы скрина — по цене люверса с установкой.
    final eyeletLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Люверсы'),
    );
    expect(eyeletLine.quantity, closeTo(summary.eyeletTotal.toDouble(), 1e-9));
    expect(
      eyeletLine.unitPrice,
      closeTo(prices.eyeletPrice + prices.eyeletInstall, 1e-9),
    );
    // Усадки нет — площадь с усадкой совпадает с заготовкой.
    expect(summary.filmAreaWithShrinkageM2, closeTo(summary.filmAreaM2, 1e-9));
  });

  test(
    'смета скрина: смешанные подвороты меняют заготовку, но не периметр',
    () {
      // Низ 40, право 50, верх 60, лево 40 → половина каждой стороны:
      // ширина 2000 + 20 + 25 = 2045, высота 2000 + 20 + 30 + 20 = 2070,
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

      expect(summary.filmAreaM2, closeTo(2.045 * 2.070, 1e-9));
      expect(summary.screenHemLengthMm, closeTo(8000, 1e-9));
      final filmLine = estimate.lines.firstWhere(
        (line) => line.title.startsWith('Полотно'),
      );
      // Площадь заготовки скрина идёт в смету, а не площадь изделия.
      expect(filmLine.quantity, closeTo(4.23315, 1e-3));
      expect(filmLine.quantity, isNot(closeTo(4.0, 1e-6)));
      final hemLine = estimate.lines.firstWhere(
        (line) => line.title.startsWith('Подворот скрина'),
      );
      expect(hemLine.quantity, closeTo(8.0, 1e-9));
    },
  );

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
    final ovalLine = estimate.lines.firstWhere(
      (line) => line.title.contains(EyeletType.oval42x22.label),
    );
    final roundLine = estimate.lines.firstWhere(
      (line) => line.title.contains(EyeletType.round10.label),
    );

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
      zippers: [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)],
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

    // Молния делит полотно на сегменты; площадь — по двум сегментам.
    // Площадь самой полосы (0,1 м²) справочная и в расход не добавляется.
    expect(summary.screenZipperBandAreaM2, closeTo(0.1, 1e-9));
    expect(summary.filmAreaWithShrinkageM2, closeTo(4.0994, 1e-9));
    final filmLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    expect(filmLine.quantity, closeTo(4.0994, 1e-9));
    expect(filmLine.unitPrice, prices.filmScreenPerM2);
    expect(filmLine.note, contains('полосу молнии 50 мм'));

    // Работа: периметр 8 м плюс шов полосы 2 м — по цене подворота скрина.
    final hemLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Подворот скрина'),
    );
    expect(hemLine.quantity, closeTo(10.0, 1e-9));
    expect(hemLine.unitPrice, prices.screenHemPerM);
    expect(hemLine.note, contains('швы полос молний'));

    // Молния: 2 м по цене прайса, подпись про полосу скрина.
    final zipperLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Молния'),
    );
    expect(zipperLine.quantity, closeTo(2.0, 1e-9));
    expect(zipperLine.unitPrice, prices.zipperPerM);
    expect(zipperLine.note, contains('скрина'));
    // Полосы тента (окантовки) у скрина в расходе нет.
    expect(summary.edgeByRoll, isEmpty);
  });

  test('смета скрина: молния сужает заготовку — полотно и раскрой дешевле', () {
    const withZipper = WindowParams(
      material: FilmMaterial.screen,
      bottomWidth: 2000,
      topWidth: 2000,
      leftHeight: 2000,
      rightHeight: 2000,
      hemBottomMm: 40,
      hemRightMm: 40,
      hemTopMm: 40,
      hemLeftMm: 40,
      zippers: [ZipperSpec(centered: true, zipWidthMm: 10, tentWidthMm: 40, weldMm: 20)],
    );
    final withoutZipper = withZipper.clearZippers();
    final prices = PriceList.defaults();
    final a = Estimate.ofWindow(withoutZipper, prices);
    final b = Estimate.ofWindow(withZipper, prices);

    // Заготовка без молнии 2040 × 2060 = 4,2024 м², с полосой 50 мм —
    // Площадь меньше полной: зазор молнии не входит в полотно.
    final filmA = a.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    final filmB = b.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    expect(filmA.quantity, closeTo(4.2024, 1e-9));
    expect(filmB.quantity, closeTo(4.0994, 1e-9));
    expect(filmA.quantity - filmB.quantity, closeTo(0.103, 1e-9));
    expect(filmB.note, contains('полосу молнии 50 мм'));

    // Раскрой считается по той же площади заготовки — тоже дешевле.
    final cutA = a.lines.firstWhere((line) => line.title.startsWith('Раскрой'));
    final cutB = b.lines.firstWhere((line) => line.title.startsWith('Раскрой'));
    expect(cutA.quantity - cutB.quantity, closeTo(0.103, 1e-9));

    // Деньги: полотно и раскрой уменьшились на площадь полосы по своим
    // ценам; строка молнии и шов по её длине добавились отдельно.
    expect(
      filmA.amount - filmB.amount,
      closeTo(0.103 * prices.filmScreenPerM2, 0.02),
    );
    expect(
      cutA.amount - cutB.amount,
      closeTo(0.103 * prices.cuttingPerM2, 0.02),
    );
    // Материалы скрина (полотно) стали дешевле ровно на полосу.
    expect(
      a.materialsSubtotal - b.materialsSubtotal,
      closeTo(0.103 * prices.filmScreenPerM2, 0.02),
    );
    final zipperLine = b.lines.firstWhere(
      (line) => line.title.startsWith('Молния'),
    );
    expect(zipperLine.quantity, closeTo(2.0, 1e-9));
    // Готовая площадь изделия не меняется: молния не уменьшает само окно.
    expect(b.productAreaM2, closeTo(a.productAreaM2, 1e-9));
  });

  test('отход трапеции ПВХ: прямоугольник минус фактическая площадь', () {
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(_trapezoidPvc, prices);
    final waste = estimate.lines.firstWhere(
      (line) => line.title == 'Отход ПВХ косых окон',
    );

    // Заготовка трапеции: низ 2000−50+50 = 1950, верх 1000−50+50 = 950,
    // высота 1000−50−50+50+10(авто) = 960.
    // Прямоугольник: 1950 × 960 = 1 872 000 мм² = 1,872 м².
    // Контур: (1950 + 950) / 2 × 960 = 1 392 000 мм² = 1,392 м².
    // Отход: 1,872 − 1,392 = 0,48 м²; 0,48 × 950 = 456,00 ₽.
    expect(waste.quantity, closeTo(0.48, 1e-9));
    expect(waste.unit, 'м²');
    expect(waste.unitPrice, prices.filmClearPerM2);
    expect(waste.amount, closeTo(456.00, 1e-9));
    expect(waste.group, EstimateGroup.materials);
    expect(waste.itemKey, PriceItemKeys.filmClear);
    expect(waste.note, contains('1,87'));
    expect(waste.note, contains('1,39'));
    expect(waste.note, contains('0,48'));
    expect(waste.note, contains('припуск'));

    // Полотно посчитано по контуру: отход — добавка, а не замена площади.
    final film = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    expect(film.quantity, closeTo(1.392, 1e-9));
    expect(estimate.filmAreaM2, closeTo(1.392, 1e-9));
    // Без двойного счёта: контур + отход = габаритный прямоугольник.
    expect(film.quantity + waste.quantity, closeTo(1.872, 1e-9));
    // Раскрой считается по контуру, отход в него не попадает.
    final cutting = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Раскрой'),
    );
    expect(cutting.quantity, closeTo(1.392, 1e-9));
  });

  test('отход трапеции скрина: прямоугольник минус контур', () {
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(_trapezoidScreen, prices);
    final waste = estimate.lines.firstWhere(
      (line) => line.title == 'Отход скрина косых окон',
    );

    // Заготовка скрина: низ 2000+20+20 = 2040, верх 1000+20+20 = 1040,
    // высота 1000+20+20+20 = 1060.
    // Прямоугольник: 2040 × 1060 = 2 162 400 мм² = 2,1624 м².
    // Контур: (2040 + 1040) / 2 × 1060 = 1 632 400 мм² = 1,6324 м².
    // Отход: 2,1624 − 1,6324 = 0,53 м²; 0,53 × 520 = 275,60 ₽.
    expect(waste.quantity, closeTo(0.53, 1e-9));
    expect(waste.unitPrice, prices.filmScreenPerM2);
    expect(waste.amount, closeTo(275.60, 1e-9));
    expect(waste.itemKey, PriceItemKeys.filmScreen);
    expect(
      estimate.lines.any((line) => line.title.startsWith('Отход ПВХ')),
      isFalse,
      reason: 'у скрина отдельная строка, ПВХ-строки быть не должно',
    );

    final film = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    expect(film.quantity, closeTo(1.6324, 1e-9));
    expect(film.quantity + waste.quantity, closeTo(2.1624, 1e-9));
  });

  test('отход трапеции с усадкой: габарит и контур в одном масштабе', () {
    // Усадка 10 % растягивает обе стороны заготовки: 1950 × 960 →
    // 2145 × 1056 мм. Прямоугольник 2,26512 м², контур 1,392 × 1,1² =
    // 1,68432 м², отход 0,5808 м² (а не 0,87312 м², если габарит взять с
    // усадкой, а контур — без неё).
    final shrunk = _trapezoidPvc.copyWith(
      shrinkageEnabled: true,
      shrinkagePercent: 10,
    );
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(shrunk, prices);
    final waste = estimate.lines.firstWhere(
      (line) => line.title == 'Отход ПВХ косых окон',
    );

    expect(waste.quantity, closeTo(0.5808, 1e-9));
    expect(waste.amount, closeTo(551.76, 1e-9));
    expect(waste.quantity, isNot(closeTo(0.87312, 1e-6)));
    final film = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    expect(film.quantity, closeTo(1.68432, 1e-9));
    expect(film.quantity + waste.quantity, closeTo(2.26512, 1e-9));
  });

  test('отход суммируется по материалам, прямоугольник строки не даёт', () {
    final project = OrderProject(
      windows: [
        _trapezoidPvc,
        _trapezoidPvc,
        _trapezoidScreen,
        // Прямоугольное окно того же ПВХ: отхода у него нет.
        _window,
      ],
    );
    final prices = PriceList.defaults();
    final estimate = Estimate.of(project, prices);

    final wasteLines = estimate.lines
        .where((line) => line.title.startsWith('Отход'))
        .toList();
    expect(wasteLines, hasLength(2));
    // Сортировка по величине отхода: ПВХ 2 × 0,48 = 0,96 м², скрин 0,53 м².
    expect(wasteLines.first.title, 'Отход ПВХ косых окон');
    expect(wasteLines.first.quantity, closeTo(0.96, 1e-9));
    expect(wasteLines.first.amount, closeTo(912.00, 1e-9));
    expect(wasteLines.last.title, 'Отход скрина косых окон');
    expect(wasteLines.last.quantity, closeTo(0.53, 1e-9));
    expect(wasteLines.last.amount, closeTo(275.60, 1e-9));

    // Площадь полотна в смете — только фактические контуры окон, без отхода:
    // 2 × 1,392 (трапеции ПВХ) + 1,6324 (скрин) + 3,4404 (прямоугольник
    // 1500 × 2520: 1410 × 2440 с авто-припуском) = 7,8568 м².
    expect(estimate.filmAreaM2, closeTo(7.8568, 1e-9));
  });

  test('прямоугольное окно: строки отхода косых окон нет', () {
    final estimate = Estimate.of(_project, PriceList.defaults());
    expect(
      estimate.lines.any((line) => line.title.contains('Отход')),
      isFalse,
      reason: 'прямоугольник кроится без отхода',
    );
  });

  test('тонированный ПВХ: своя строка отхода по цене прайса', () {
    // Один и тот же косой контур, но материал тонированный: строка не
    // сливается с обычным ПВХ, иначе цена 1150 ₽/м² потерялась бы.
    final tinted = _trapezoidPvc.copyWith(material: FilmMaterial.tintedPvc);
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(tinted, prices);
    final waste = estimate.lines.firstWhere(
      (line) => line.title == 'Отход ПВХ косых окон (тонированный)',
    );

    expect(waste.quantity, closeTo(0.48, 1e-9));
    expect(waste.itemKey, PriceItemKeys.filmTinted);
    expect(waste.unitPrice, prices.filmTintedPerM2);
    expect(waste.amount, closeTo(0.48 * prices.filmTintedPerM2, 1e-9));
    expect(
      estimate.lines.any((line) => line.title == 'Отход ПВХ косых окон'),
      isFalse,
    );
  });

  test('отход: цена из прайса, выключенная позиция убирает строку', () {
    final prices = PriceList.defaults().copyWith(
      filmClearPerM2: 1000,
      filmScreenPerM2: 600,
    );
    final project = OrderProject(windows: [_trapezoidPvc, _trapezoidScreen]);

    final estimate = Estimate.of(project, prices);
    final pvcWaste = estimate.lines.firstWhere(
      (line) => line.title == 'Отход ПВХ косых окон',
    );
    final screenWaste = estimate.lines.firstWhere(
      (line) => line.title == 'Отход скрина косых окон',
    );
    expect(pvcWaste.unitPrice, 1000);
    expect(pvcWaste.amount, closeTo(480.00, 1e-9));
    expect(screenWaste.unitPrice, 600);
    expect(screenWaste.amount, closeTo(318.00, 1e-9));

    // Правило 10: выключенный материал не попадает в смету — ни «Полотно»,
    // ни «Отход». Второй материал остаётся.
    final withoutPvc = Estimate.of(
      project,
      prices.withItem(PriceItemKeys.filmClear, enabled: false),
    );
    expect(
      withoutPvc.lines.any((line) => line.title == 'Отход ПВХ косых окон'),
      isFalse,
    );
    expect(
      withoutPvc.lines.any((line) => line.title == 'Отход скрина косых окон'),
      isTrue,
    );
    expect(
      withoutPvc.lines.any(
        (line) => line.title == 'Полотно: ${FilmMaterial.clearPvc.label}',
      ),
      isFalse,
    );

    final withoutScreen = Estimate.of(
      project,
      prices.withItem(PriceItemKeys.filmScreen, enabled: false),
    );
    expect(
      withoutScreen.lines.any(
        (line) => line.title == 'Отход скрина косых окон',
      ),
      isFalse,
    );
    expect(
      withoutScreen.lines.any((line) => line.title == 'Отход ПВХ косых окон'),
      isTrue,
    );
  });

  test('отход не меняет площадь полотна и раскроя', () {
    final prices = PriceList.defaults();
    final estimate = Estimate.ofWindow(_trapezoidPvc, prices);
    final summary = CostsSummary(const OrderProject(windows: [_trapezoidPvc]));

    // Отход — отдельная ДОБАВКА: площадь в смете и в сводке остаётся
    // площадью контура, а не габаритного прямоугольника.
    expect(estimate.filmAreaM2, closeTo(summary.filmAreaWithShrinkageM2, 1e-9));
    expect(estimate.filmAreaM2, closeTo(1.392, 1e-9));
    expect(summary.filmAreaWithShrinkageM2, isNot(closeTo(1.872, 1e-6)));
    final film = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Полотно'),
    );
    final waste = estimate.lines.firstWhere(
      (line) => line.title == 'Отход ПВХ косых окон',
    );
    expect(film.quantity, closeTo(estimate.filmAreaM2, 1e-9));
    expect(
      film.amount + waste.amount,
      closeTo(
        1.392 * prices.filmClearPerM2 + 0.48 * prices.filmClearPerM2,
        0.01,
      ),
    );
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
    final eyeletLine = estimate.lines.firstWhere(
      (line) => line.title.startsWith('Люверсы'),
    );

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
    final line = estimate.lines.firstWhere(
      (candidate) => candidate.title.contains('Тент 150 мм'),
    );

    // Ожидание считаем от пресетов прайса: 150 мм лежит между 120 и 200.
    final expected =
        prices.edge120PerM +
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
    final discounted = Estimate.of(
      _project,
      base.copyWith(discountPercent: 10),
    );

    expect(
      discounted.discountAmount,
      closeTo(discounted.afterMarkup * 0.1, 0.005),
    );
    // Скидка считается от суммы после наценки, а та округлена до копейки,
    // поэтому итог отличается от «× 0,9» на копейки — допускаем 2 копейки.
    expect(discounted.total, closeTo(full.total * 0.9, 0.02));
  });

  test('наценка 20 % увеличивает подытог на 20 %', () {
    final base = PriceList.defaults().copyWith(installationPerM2: 0);
    final full = Estimate.of(_project, base);
    final marked = Estimate.of(_project, base.copyWith(markupPercent: 20));

    expect(marked.subtotal, closeTo(full.subtotal, 0.001));
    expect(marked.markupAmount, closeTo(full.subtotal * 0.2, 0.01));
    expect(marked.afterMarkup, closeTo(full.subtotal * 1.2, 0.01));
  });

  test('НДС считается от суммы после наценки и скидки', () {
    final prices = PriceList.defaults().copyWith(
      markupPercent: 10,
      discountPercent: 10,
    );
    final estimate = Estimate.of(_project, prices);

    expect(estimate.markupAmount, closeTo(estimate.subtotal * 0.1, 0.005));
    expect(estimate.discountAmount, closeTo(estimate.afterMarkup * 0.1, 0.005));
    expect(
      estimate.taxableAmount,
      closeTo(estimate.afterMarkup - estimate.discountAmount, 0.001),
    );
    expect(estimate.vatAmount, closeTo(estimate.taxableAmount * 0.2, 0.005));
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
    final empty = Estimate.of(
      const OrderProject(windows: []),
      PriceList.defaults(),
    );
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
        aluminumBoxPerM: 0,
        drainPrice: 0,
        cutoutPrice: 0,
        laborPerM2: 0,
        cuttingPerM2: 0,
        installationPerM2: 0,
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

  test('размер листа сметы — строго один A4', () {
    for (final project in [
      _project,
      OrderProject(windows: List.filled(6, _window)),
    ]) {
      for (final viewport in const [
        Size(1720, 1080),
        Size(900, 700),
        Size(2400, 1800),
      ]) {
        final size = EstimateSheet.sheetSize(project, viewport);
        expect(size.width, EstimateSheet.a4Width + 40);
        expect(size.height, EstimateSheet.a4Height + 40);
      }
    }
  });

  testWidgets('смета на 6 окон не выходит за A4', (tester) async {
    tester.view.physicalSize = const Size(
      EstimateSheet.a4Width + 40,
      EstimateSheet.a4Height + 40,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: OrderProject(windows: List.filled(6, _window)),
            prices: model.PriceList.defaults(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  test('константы сметы: кегль ×2, лист по-прежнему один A4', () {
    expect(EstimateSheet.a4Width, 1240);
    expect(EstimateSheet.a4Height, 1754);
    // Было 34 и 118 — стало ×2.
    expect(EstimateSheet.rowHeight, 68);
    expect(EstimateSheet.titleBlockHeight, 236);
  });

  Future<void> pumpSheetOnA4(
    WidgetTester tester,
    OrderProject project,
  ) async {
    tester.view.physicalSize = const Size(
      EstimateSheet.a4Width + 40,
      EstimateSheet.a4Height + 40,
    );
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: EstimateSheet(
            project: project,
            prices: model.PriceList.defaults(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('смета: шапка таблицы 8.5 → 17, строки 10.5 → 21, ИТОГО 17 → 34', (
    tester,
  ) async {
    await pumpSheetOnA4(tester, const OrderProject(windows: [_previewWindow]));

    // Заголовок листа: было 15, стало 30.
    final caption = tester.getRect(find.text('Смета на заказ'));
    expect(caption.height, closeTo(30 * 1.25, 0.8));

    // Шапка таблицы: было 8.5, стало 17 (line-height 1.25).
    final header = tester.getRect(find.text('НАИМЕНОВАНИЕ'));
    expect(header.height, closeTo(17 * 1.25, 0.8));

    // Обычная строка/итоги: было 10.5, стало 21.
    final totalRowLabel = tester.getRect(find.text('Итого по позициям'));
    expect(totalRowLabel.height, closeTo(21 * 1.25, 0.8));

    // ИТОГО К ОПЛАТЕ: значение было 17, стало 34. Для обычного заказа
    // FittedBox не ужимает текст — эффективный кегль остаётся 34.
    final estimate = Estimate.of(
      const OrderProject(windows: [_previewWindow]),
      model.PriceList.defaults(),
    );
    final totalValue = tester.getRect(
      find.text(formatRubles(estimate.total)).first,
    );
    expect(totalValue.height, closeTo(34 * 1.25, 0.8));

    expect(tester.takeException(), isNull);
  });

  testWidgets('смета заполняет A4: таблица тянется, итоги вплотную к штампу', (
    tester,
  ) async {
    await pumpSheetOnA4(
      tester,
      OrderProject(windows: List.filled(6, _window)),
    );

    final table = tester.getRect(find.byKey(EstimateSheet.tableKey));
    final stamp = tester.getRect(find.byKey(EstimateSheet.stampKey));
    final heading = tester.getRect(find.text('ИТОГИ ПО СМЕТЕ'));
    final note = tester.getRect(find.textContaining('Цены — из прайса цеха'));

    // Лист целиком: 1240 × 1754 внутри поля 20.
    expect(stamp.bottom - 20, closeTo(EstimateSheet.a4Height, 1));
    expect(stamp.height, EstimateSheet.titleBlockHeight);

    // Таблица растянута на всю свободную высоту, а не сжата в верхнюю часть.
    expect(table.height, greaterThan(600));

    // Между таблицей и итогами — только заданный зазор (20).
    expect(heading.top - table.bottom, closeTo(20, 2));

    // Последний блок контента (сноска) упирается в штамп: внизу не пусто.
    expect(stamp.top - note.bottom, closeTo(16, 2));
    expect(note.bottom, greaterThan(stamp.top - 40));
    expect(tester.takeException(), isNull);
  });

  testWidgets('смета на 6 окон: строки не наезжают друг на друга и на итоги', (
    tester,
  ) async {
    await pumpSheetOnA4(
      tester,
      OrderProject(windows: List.filled(6, _window)),
    );

    // Все строки таблицы идут строго по порядку без пересечений.
    final rows = [
      tester.getRect(find.text('НАИМЕНОВАНИЕ')),
      tester.getRect(find.text('МАТЕРИАЛЫ')),
      tester.getRect(find.text('ФУРНИТУРА И СПЕЦЭЛЕМЕНТЫ')),
      tester.getRect(find.text('РАБОТЫ')),
    ];
    for (var i = 1; i < rows.length; i++) {
      expect(rows[i].top, greaterThan(rows[i - 1].bottom));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('пишет PNG-превью сметы с компанией и логотипом', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1720, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Простой логотип: синий круг с «МО» — проверяем место, а не картинку.
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawCircle(
      const Offset(60, 60),
      58,
      Paint()..color = const Color(0xFFFFFFFF),
    );
    canvas.drawCircle(
      const Offset(60, 60),
      46,
      Paint()
        ..color = const Color(0xFF0B62C4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4,
    );
    (TextPainter(
      text: const TextSpan(
        text: 'МО',
        style: TextStyle(
          color: Color(0xFF0B62C4),
          fontSize: 44,
          fontWeight: FontWeight.w800,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout()).paint(canvas, const Offset(24, 32));
    final logoImage = await tester.runAsync(() async {
      final image = await recorder.endRecording().toImage(120, 120);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    expect(logoImage, isNotNull, reason: 'логотип должен собраться');
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
            company: CompanyBrandingState(
              details: const CompanyDetails(
                name: 'ООО «Мягкие окна»',
                inn: '7701234567',
                phone: '+7 999 123-45-67',
                address: 'Москва, ул. Примерная, 1',
              ),
              logo: logoImage,
              showOnSheets: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // В тестовой среде картинка декодируется асинхронно — прогреваем её,
    // иначе на превью логотип останется пустым местом.
    await tester.runAsync(() async {
      await precacheImage(
        MemoryImage(logoImage!),
        tester.element(find.byType(EstimateSheet)),
      );
    });
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final bytes = await tester.runAsync(() async {
      final boundary =
          captureKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.2);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    });

    final file = File('build/preview/smeta-company.png')
      ..parent.createSync(recursive: true)
      ..writeAsBytesSync(bytes!);
    expect(file.lengthSync(), greaterThan(5000));
    // ignore: avoid_print
    print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
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
      final boundary =
          captureKey.currentContext!.findRenderObject()!
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
