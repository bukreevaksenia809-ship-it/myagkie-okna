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
      // чисел: площадь по фактическому контуру без компенсации усадки
      // (filmAreaM2) и тот же контур с усадкой (filmAreaWithShrinkageM2) —
      // именно он идёт в расход и деньги, потому что плёнка режется по
      // усадочным размерам. Для косого окна это площадь трапеции, а не
      // габаритного прямоугольника (по габариту идёт только упаковка рулона).
      //
      // Полоса молнии скрина уже вычтена из ширины заготовки внутри
      // WindowSpec, поэтому отдельным слагаемым её добавлять нельзя: площадь
      // полосы посчиталась бы дважды. У ПВХ полоса молнии — тент, он идёт в
      // расход окантовки и ширину полотна не меняет.
      filmAreaM2 += spec.filmCutAreaM2;
      filmAreaWithShrinkageM2 += spec.filmCutAreaWithShrinkageM2;
      filmNetAreaM2 += spec.filmAreaM2;
      filmAreaByMaterial.update(
        spec.params.material,
        (value) => value + spec.filmCutAreaM2,
        ifAbsent: () => spec.filmCutAreaM2,
      );
      filmAreaByMaterialWithShrinkage.update(
        spec.params.material,
        (value) => value + spec.filmCutAreaWithShrinkageM2,
        ifAbsent: () => spec.filmCutAreaWithShrinkageM2,
      );
      spec.edgeConsumption.forEach((roll, length) {
        edgeByRoll.update(
          roll,
          (value) => value + length,
          ifAbsent: () => length,
        );
      });
      // Люверсы считаем по типу, который реально ставится: по сторонам —
      // выбранный пользователем тип, в углах — всегда круглый. Так расход и
      // смета сходятся с чертежом и с техкартой.
      for (final eyelet in spec.layers.eyelets) {
        final type = spec.layers.typeFor(eyelet);
        eyeletsByType.update(type, (value) => value + 1, ifAbsent: () => 1);
      }
      // Крепёж подвижных сторон: скоба, замок или ремень ставится в каждую
      // точку низа и боков, кроме углов (в углу круглый люверс). Точек ровно
      // столько, сколько люверсов в `movableSideEyelets`, — по ним же
      // считаются строки сметы и материалы техкарты.
      //
      // «Только люверсы» отдельного крепежа не имеет: 0, люверс уже в расходе
      // выше. Скрин считается по тому же правилу — его крепёж давно разрешён
      // и ставится по подвороту.
      final fastenerType = spec.params.fastenerType;
      if (fastenerType != FastenerType.eyeletsOnly) {
        final count = spec.layers.movableSideEyelets.length;
        if (count > 0) {
          fastenerCount.update(
            fastenerType,
            (value) => value + count,
            ifAbsent: () => count,
          );
        }
      }
      // Саморезы верхнего ряда: у подъёмного окна и у скрина верх крепится
      // к раме саморезами. У глухого ПВХ верхнего ряда нет — он весь на
      // саморезах по окантовке, отдельной строкой не считается.
      if (spec.params.isLifting || spec.params.isScreen) {
        screwCount += spec.layers.topEyelets.length;
      }
      // Молний в окне может быть две — считаем каждую полосу отдельно,
      // иначе смета на окно с двумя молниями занижается вдвое.
      //
      // У ПВХ полоса впаивается в тент: это спайка шириной 50 мм из рулона
      // 100 мм (идёт в расход окантовки). У скрина полоса — подвёрнутая ткань
      // (накладная полоса из скрина). У ВСЕХ материалов ширина полосы вычтена
      // из ширины заготовки ([WindowSpec.filmCutWidth]) — см.
      // [WindowLayers.zipperBandTotalMm]; у скрина дополнительно считается
      // работа подворота/шва по длине полосы.
      final zipperLength = spec.layers.filmVisibleBounds.height;
      for (final band in spec.layers.zipperBands) {
        zipperCount += 1;
        zipperBandLengthMm += zipperLength;
        if (spec.params.isScreen) {
          screenZipperCount += 1;
          screenZipperBandLengthMm += zipperLength;
          screenZipperBandAreaMm2 += band.width * zipperLength;
          screenZipperBandWidthMm += band.width;
          // Шов полосы: работа по длине полосы (шов 3 мм по её краям).
          screenHemLengthMm += zipperLength;
        } else {
          pvcZipperCount += 1;
          pvcZipperBandWidthMm += band.width;
          // Спайка — полоса тента 100 мм, сложенная пополам. Берём именно
          // 100-й рулон (а не первый пресет): молния впаивается в полосу
          // шириной 50 мм, которую даёт рулон 100 мм.
          final bandRoll = EdgeRoll.roll100.rawWidth;
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
      // Верхний фартук (бывший карман) — вторая полоса, считается отдельно.
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
      // Отдельно ведём швы по общим сторонам пристроек Т-окна: в смете это
      // своя операция, а спайки с соседними окнами считаются отдельной
      // строкой. Каждая СПАЯННАЯ пристройка даёт свой шов.
      if (spec.params.isTShape) {
        tShapeSeamMm += spec.tWeldedSeamLength;
      }
    }
  }

  final OrderProject project;
  final List<WindowSpec> specs;
  final List<RollPlan> rollPlans;

  /// Суммарная площадь готовых изделий по наружному контуру, м².
  double productAreaM2 = 0;

  /// Площадь заготовок-прямоугольников к раскрою: припуск, минус вырезы,
  /// БЕЗ компенсации усадки, м².
  ///
  /// Трапеция и окно с разными высотами сторон тоже считаются
  /// прямоугольником по габариту (никакой площади по полигону). Для расхода
  /// и денег берётся [filmAreaWithShrinkageM2] — те же прямоугольники с
  /// усадкой.
  double filmAreaM2 = 0;

  /// Площадь заготовок-прямоугольников к раскрою С учётом усадки, м².
  ///
  /// Усадка растягивает контур по обеим осям, поэтому это площадь уже
  /// усадочного контура, а не `filmAreaM2 × (1 + s/100)`. Идёт в смету,
  /// ведомость и работы по раскрою.
  double filmAreaWithShrinkageM2 = 0;

  /// Площадь самого полотна изделий (без припуска) по всем окнам, м².
  ///
  /// Для трапеции это меньше габарита заготовки: справочное число для
  /// подписей «площадь полотна», в деньги не идёт.
  double filmNetAreaM2 = 0;

  /// Площадь заготовок по контуру без усадки по материалам, м².
  final Map<FilmMaterial, double> filmAreaByMaterial = {};

  /// Площадь заготовок по контуру с усадкой по материалам, м² — для сметы.
  final Map<FilmMaterial, double> filmAreaByMaterialWithShrinkage = {};

  /// Расход окантовки по ширинам рулонов (мм → мм).
  final Map<double, double> edgeByRoll = {};

  final Map<EyeletType, int> eyeletsByType = {};

  /// Крепёж подвижных сторон по типам (низ и бока, кроме углов).
  ///
  /// У «только люверсы» записи нет вовсе: люверсы считаются отдельно.
  /// У скрина крепёж ставится по подвороту и попадает сюда же.
  final Map<FastenerType, int> fastenerCount = {};

  /// Всего крепежа подвижных сторон, шт.
  int get fastenerTotal =>
      fastenerCount.values.fold(0, (sum, value) => sum + value);

  /// Саморезы верхнего ряда (подъёмные окна и скрин), шт.
  int screwCount = 0;

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

  /// Суммарная ширина полос молний скрина, мм — на неё сужена заготовка.
  double screenZipperBandWidthMm = 0;

  /// Молнии ПВХ: сколько штук и суммарная ширина их полос (спаек), мм.
  ///
  /// Сама полоса идёт в расход окантовки (рулон 100 мм), но её ширина
  /// вычитается из ширины кроя полотна — как у скрина.
  int pvcZipperCount = 0;
  double pvcZipperBandWidthMm = 0;

  /// Суммарная длина полос молний скрина, мм (шов по длине полосы).
  double screenZipperBandLengthMm = 0;

  /// Площадь полос молний скрина, м² — справочно для подписей.
  ///
  /// В расход она не добавляется: ширина заготовки уже уменьшена на полосу
  /// ([WindowSpec.filmCutWidth]), поэтому расход идёт по площади суженной
  /// заготовки, а полоса отдельным слагаемым не считается.
  double get screenZipperBandAreaM2 => screenZipperBandAreaMm2 / 1000000;

  int strapCount = 0;

  /// Вырезы в полотне: сколько и какой суммарный контур.
  int cutoutCount = 0;
  double cutoutPerimeterMm = 0;

  /// Спайки с соседними окнами, мм.
  double weldLengthMm = 0;

  /// Длина шва по общей стороне Т-окон, мм.
  double tShapeSeamMm = 0;

  /// Всего дренажных отверстий, шт.
  int drainTotal = 0;

  /// Есть ли в заказе окно с включённой усадкой — для подписей сметы.
  bool get hasShrinkage => specs.any((spec) => spec.params.hasShrinkage);

  /// Есть ли в заказе окно с авто-припуском +10 мм к высоте (ПВХ).
  bool get hasAutoHeightAllowance =>
      specs.any((spec) => spec.params.hasAutoHeightAllowance);

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

  /// Подписи площади заготовок по контуру без усадки по материалам:
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

  /// Подписи крепежа по типам: «Французский замок — 12 шт».
  List<String> get fastenerLabels {
    final entries = fastenerCount.entries.toList()
      ..sort((a, b) => a.key.index.compareTo(b.key.index));
    return [
      for (final entry in entries) '${entry.key.itemTitle} — ${entry.value} шт',
    ];
  }

  /// Заготовки сопутствующих материалов (молния, фартук, ремни).
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
          '${zipperCount - screenZipperCount} шт; ширина кроя полотна '
          'уменьшена на полосу (спайку) '
          '${formatMm(pvcZipperBandWidthMm)} мм',
    if (screenZipperCount > 0)
      'Полоса молнии из скрина: $screenZipperCount шт, '
          '${formatMm(screenZipperBandWidthMm)} мм в сумме — ширина кроя '
          'уже уменьшена на эту полосу (ткань '
          '${formatMeters(screenZipperBandAreaM2)} м² отдельно не '
          'считается), шов ${formatMm(screenSeamMm)} мм по краям полосы '
          '(длина ${formatMm(screenZipperBandLengthMm)} мм)',
    if (pocketCount > 0)
      'Фартук (низ/верх): $pocketCount шт, полоса '
          '${formatMm(pocketLengthMm)} мм',
    if (screenHemLengthMm > 0)
      'Подворот скрина и шов ${formatMm(screenSeamMm)} мм: '
          '${formatMm(screenHemLengthMm)} мм периметра и полос — расход '
          'скрина считается по площади суженной заготовки',
    if (drainTotal > 0) 'Дренаж Ø6 мм: $drainTotal шт',
    if (strapCount > 0)
      'Подъёмные ремни: ${formatMm(50)} × ${formatMm(500)} мм — '
          '$strapCount шт',
  ];
}
