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

    // Плёнка: площадь из сводки.
    final filmLine = estimate.lines
        .firstWhere((line) => line.title.startsWith('Полотно'));
    expect(filmLine.quantity, closeTo(summary.filmAreaM2, 1e-9));

    // Люверс считается с установкой.
    final prices = PriceList.defaults();
    expect(
      eyeletLine.unitPrice,
      closeTo(prices.eyeletPrice + prices.eyeletInstall, 1e-9),
    );
  });

  test('скидка 10 % уменьшает ИТОГО ровно на 10 %', () {
    final base = PriceList.defaults();
    final full = Estimate.of(_project, base);
    final discounted =
        Estimate.of(_project, base.copyWith(discountPercent: 10));

    expect(discounted.discountAmount,
        closeTo(discounted.afterMarkup * 0.1, 0.005));
    expect(discounted.total, closeTo(full.total * 0.9, 0.01));
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
      edge100PerM: 149.9,
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
