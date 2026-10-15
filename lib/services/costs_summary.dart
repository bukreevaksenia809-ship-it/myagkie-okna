import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';
import 'roll_plan.dart';

/// Сводка расхода материалов по всему заказу.
///
/// Используется на вкладке «Расходы» и при сохранении заказов для отчётности.
class CostsSummary {
  CostsSummary(this.project)
      : specs = [for (final window in project.windows) WindowSpec.of(window)],
        rollPlans = buildRollPlans(project) {
    for (final spec in specs) {
      productAreaM2 += spec.productAreaM2;
      // Плёнка закупается и кроится по заготовке. Заготовка бывает двух
      // чисел: габарит без компенсации усадки (filmAreaM2) и фактический
      // раскрой с усадкой (filmAreaWithShrinkageM2) — именно он идёт в
      // расход и деньги, потому что плёнка режется по усадочным размерам.
      //
      // У скрина к заготовке добавляются полосы молний: это отдельные детали
      // из того же материала (ширина полосы × высота полотна на каждую
      // молнию). У ПВХ полоса молнии — тент, он идёт в расход окантовки.
      final zipperBandAreaM2 = spec.screenZipperBandAreaM2;
      filmAreaM2 += spec.filmCutAreaM2 + zipperBandAreaM2;
      filmAreaWithShrinkageM2 +=
          spec.filmCutAreaWithShrinkageM2 + zipperBandAreaM2;
      filmNetAreaM2 += spec.filmAreaM2;
      filmAreaByMaterial.update(
        spec.params.material,
        (value) => value + spec.filmCutAreaM2 + zipperBandAreaM2,
        ifAbsent: () => spec.filmCutAreaM2 + zipperBandAreaM2,
      );
      filmAreaByMaterialWithShrinkage.update(
        spec.params.material,
        (value) => value + spec.filmCutAreaWithShrinkageM2 + zipperBandAreaM2,
        ifAbsent: () =>
            spec.filmCutAreaWithShrinkageM2 + zipperBandAreaM2,
      );
      spec.edgeConsumption.forEach((roll, length) {
        edgeByRoll.update(roll, (value) => value + length,
            ifAbsent: () => length);
      });
      // Люверсы считаем по типу, который реально ставится: по сторонам —
      // выбранный пользователем тип, в углах — всегда круглый. Так расход и
      // смета сходятся с чертежом и с техкартой.
      for (final eyelet in spec.layers.eyelets) {
        final type = spec.layers.typeFor(eyelet);
        eyeletsByType.update(type, (value) => value + 1, ifAbsent: () => 1);
      }
      // Молний в окне может быть две — считаем каждую полосу отдельно,
      // иначе смета на окно с двумя молниями занижается вдвое.
      //
      // У ПВХ полоса впаивается в тент: это спайка шириной 50 мм из рулона
      // 100 мм (идёт в расход окантовки). У скрина полоса — подвёрнутая ткань
      // (накладная полоса из скрина): она считается материалом скрина по
      // площади, а работа подворота/шва — по длине полосы.
      final zipperLength = spec.layers.filmVisibleBounds.height;
      for (final band in spec.layers.zipperBands) {
        zipperCount += 1;
        zipperBandLengthMm += zipperLength;
        if (spec.params.isScreen) {
          screenZipperCount += 1;
          screenZipperBandLengthMm += zipperLength;
          screenZipperBandAreaMm2 += band.width * zipperLength;
          // Шов полосы: работа по длине полосы (шов 3 мм по её краям).
          screenHemLengthMm += zipperLength;
        } else {
          // Спайка — полоса тента 100 мм, сложенная пополам.
          final bandRoll = WindowParams.edgePresets.first;
          edgeByRoll.update(
            bandRoll,
            (value) => value + zipperLength,
            ifAbsent: () => zipperLength,
          );
        }
      }
      if (spec.params.pocket) {
        pocketCount += 1;
        pocketLengthMm += spec.geometry.bottomWidth;
      }
      // Верхний карман — вторая полоса, считается отдельно.
      if (spec.params.pocketTop) {
        pocketCount += 1;
        pocketLengthMm += spec.geometry.topWidth;
      }
      // Скрин подворачивается по всему периметру: длина подворота — периметр.
      if (spec.params.isScreen) {
        screenHemLengthMm += spec.geometry.perimeter;
      }
      strapCount += spec.strapCount;
      pocketWidthMm = spec.params.pocketWidth;
      cutoutCount += spec.params.cutouts.length;
      drainTotal += spec.params.drainHoles && !spec.params.isScreen
          ? spec.params.drainCount.round()
          : 0;
      cutoutPerimeterMm += spec.layers.cutoutPerimeterMm;
      weldLengthMm += spec.layers.weldLengthMm;
    }
  }

  final OrderProject project;
  final List<WindowSpec> specs;
  final List<RollPlan> rollPlans;

  /// Суммарная площадь готовых изделий по наружному контуру, м².
  double productAreaM2 = 0;

  /// Площадь заготовок (габарит) к раскрою: припуск, минус вырезы,
  /// БЕЗ компенсации усадки, м².
  ///
  /// Справочная площадь габаритного прямоугольника. Для расхода и денег
  /// берётся [filmAreaWithShrinkageM2] — фактический раскрой с усадкой.
  double filmAreaM2 = 0;

  /// Фактическая площадь заготовок к раскрою С учётом усадки, м².
  ///
  /// Усадка масштабирует обе стороны заготовки, поэтому это не
  /// `filmAreaM2 × (1 + s/100)`, а площадь по усадочным габаритам. Идёт в
  /// смету, ведомость и работы по раскрою.
  double filmAreaWithShrinkageM2 = 0;

  /// Площадь самого полотна изделий (без припуска) по всем окнам, м².
  ///
  /// Для трапеции это меньше габарита заготовки: справочное число для
  /// подписей «площадь полотна», в деньги не идёт.
  double filmNetAreaM2 = 0;

  /// Площадь заготовок (габарит) без усадки по материалам, м².
  final Map<FilmMaterial, double> filmAreaByMaterial = {};

  /// Площадь заготовок (габарит) с усадкой по материалам, м² — для сметы.
  final Map<FilmMaterial, double> filmAreaByMaterialWithShrinkage = {};

  /// Расход окантовки по ширинам рулонов (мм → мм).
  final Map<double, double> edgeByRoll = {};

  final Map<EyeletType, int> eyeletsByType = {};

  int get eyeletTotal =>
      eyeletsByType.values.fold(0, (sum, value) => sum + value);

  int zipperCount = 0;
  double zipperBandLengthMm = 0;

  int pocketCount = 0;
  double pocketLengthMm = 0;
  double pocketWidthMm = 0;

  /// Длина подворота скрина, мм: периметр готового изделия плюс швы полос
  /// молний (у скрина полоса молнии тоже обрабатывается подворотом/швом).
  double screenHemLengthMm = 0;

  /// Полосы молний у скрина: сколько штук и какова их общая площадь, мм².
  int screenZipperCount = 0;
  double screenZipperBandAreaMm2 = 0;

  /// Суммарная длина полос молний скрина, мм (шов по длине полосы).
  double screenZipperBandLengthMm = 0;

  /// Площадь полос молний скрина, м² — материал скрина поверх заготовки.
  double get screenZipperBandAreaM2 => screenZipperBandAreaMm2 / 1000000;

  int strapCount = 0;

  /// Вырезы в полотне: сколько и какой суммарный контур.
  int cutoutCount = 0;
  double cutoutPerimeterMm = 0;

  /// Спайки с соседними окнами, мм.
  double weldLengthMm = 0;

  /// Всего дренажных отверстий, шт.
  int drainTotal = 0;

  /// Площадь заготовок на рулонах, м².
  double get rollPiecesArea =>
      rollPlans.fold(0, (sum, plan) => sum + plan.piecesArea);

  /// Площадь рулонов, м².
  double get rollArea => rollPlans.fold(0, (sum, plan) => sum + plan.rollArea);

  /// Отход по рулонам, % (0…100). Заготовка с припуском может оказаться шире
  /// выбранного рулона — тогда отход считаем нулевым и предупреждаем об этом
  /// на листе раскладки, а не уходим в минус.
  double get rollWastePercent => rollArea > 0
      ? ((rollArea - rollPiecesArea) / rollArea * 100).clamp(0.0, 100.0)
      : 0;

  /// Подписи расхода окантовки: «Тент 100 мм — 654 см».
  List<String> get edgeConsumptionLabels {
    final entries = edgeByRoll.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        '${edgeBandLabel(entry.key)} — ${formatCm(entry.value)} см',
    ];
  }

  /// Подписи по материалам с усадкой (расход к раскрою):
  /// «Обычный ПВХ — 8,57 м²».
  List<String> get filmByMaterialLabels {
    final entries = filmAreaByMaterialWithShrinkage.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries)
        '${entry.key.label} — ${formatMeters(entry.value)} м²',
    ];
  }

  /// Подписи габарита заготовок без усадки по материалам:
  /// «Обычный ПВХ — 8,32 м²» (справочно, для сверки с чертежом).
  List<String> get filmByMaterialNoShrinkageLabels {
    final entries = filmAreaByMaterial.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries)
        '${entry.key.label} — ${formatMeters(entry.value)} м²',
    ];
  }

  /// Подписи по люверсам: «Круглый Ø10 мм — 28 шт».
  List<String> get eyeletLabels {
    final entries = eyeletsByType.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [
      for (final entry in entries) '${entry.key.label} — ${entry.value} шт',
    ];
  }

  /// Заготовки сопутствующих материалов (молния, карман, ремни).
  List<String> get extraLabels => [
        if (cutoutCount > 0)
          'Вырезы: $cutoutCount шт, окантовка по контуру '
              '${formatMm(cutoutPerimeterMm)} мм',
        if (weldLengthMm > 0)
          'Спайка с соседними окнами: ${formatMm(weldLengthMm)} мм '
              '(окантовка на этих сторонах не ставится)',
        if (zipperCount - screenZipperCount > 0)
          'Спайка молнии: тент ${formatMm(100)} мм × '
              '${formatMm(zipperBandLengthMm - screenZipperBandLengthMm)} мм — '
              '${zipperCount - screenZipperCount} шт',
        if (screenZipperCount > 0)
          'Полоса молнии из скрина: $screenZipperCount шт, ткань '
              '${formatMeters(screenZipperBandAreaM2)} м², шов '
              '${formatMm(screenSeamMm)} мм по краям полосы (длина '
              '${formatMm(screenZipperBandLengthMm)} мм)',
        if (pocketCount > 0)
          'Карман (низ/верх): $pocketCount шт, полоса '
              '${formatMm(pocketLengthMm)} мм',
        if (screenHemLengthMm > 0)
          'Подворот скрина и шов ${formatMm(screenSeamMm)} мм: '
              '${formatMm(screenHemLengthMm)} мм периметра и полос — расход '
              'скрина считается по площади заготовки и полос молний',
        if (drainTotal > 0) 'Дренаж Ø6 мм: $drainTotal шт',
        if (strapCount > 0)
          'Подъёмные ремни: ${formatMm(50)} × ${formatMm(500)} мм — '
              '$strapCount шт',
      ];
}
