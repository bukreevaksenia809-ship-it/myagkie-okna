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
      // Плёнка закупается и кроится по заготовке: с припуском на раскрой.
      filmAreaM2 += spec.filmCutAreaM2;
      filmAreaWithShrinkageM2 += spec.filmCutAreaWithShrinkageM2;
      filmAreaByMaterial.update(
        spec.params.material,
        (value) => value + spec.filmCutAreaM2,
        ifAbsent: () => spec.filmCutAreaM2,
      );
      spec.edgeConsumption.forEach((roll, length) {
        edgeByRoll.update(roll, (value) => value + length,
            ifAbsent: () => length);
      });
      eyeletsByType.update(
        spec.eyeletType,
        (value) => value + spec.eyeletCount,
        ifAbsent: () => spec.eyeletCount,
      );
      // Молний в окне может быть две — считаем каждую полосу отдельно,
      // иначе смета на окно с двумя молниями занижается вдвое.
      final zipperLength = spec.layers.filmVisibleBounds.height;
      for (var i = 0; i < spec.layers.zipperBands.length; i++) {
        zipperCount += 1;
        zipperBandLengthMm += zipperLength;
        // Спайка — полоса тента 100 мм, сложенная пополам.
        final bandRoll = WindowParams.edgePresets.first;
        edgeByRoll.update(
          bandRoll,
          (value) => value + zipperLength,
          ifAbsent: () => zipperLength,
        );
      }
      if (spec.params.pocket) {
        pocketCount += 1;
        pocketLengthMm += spec.geometry.bottomWidth;
      }
      strapCount += spec.strapCount;
      pocketWidthMm = spec.params.pocketWidth;
      cutoutCount += spec.params.cutouts.length;
      drainTotal += spec.params.drainHoles ? spec.params.drainCount.round() : 0;
      cutoutPerimeterMm += spec.layers.cutoutPerimeterMm;
      weldLengthMm += spec.layers.weldLengthMm;
    }
  }

  final OrderProject project;
  final List<WindowSpec> specs;
  final List<RollPlan> rollPlans;

  /// Суммарная площадь готовых изделий по наружному контуру, м².
  double productAreaM2 = 0;

  /// Площадь заготовок плёнки к раскрою (с припуском, минус вырезы), м².
  double filmAreaM2 = 0;

  /// Площадь заготовок плёнки с учётом усадки, м².
  double filmAreaWithShrinkageM2 = 0;

  final Map<FilmMaterial, double> filmAreaByMaterial = {};

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

  /// Подписи по материалам: «Обычный ПВХ — 8,57 м²».
  List<String> get filmByMaterialLabels {
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
        if (zipperCount > 0)
          'Спайка молнии: тент ${formatMm(100)} мм × '
              '${formatMm(zipperBandLengthMm)} мм — $zipperCount шт',
        if (pocketCount > 0)
          'Карман: тент ${formatMm(200)} мм × ${formatMm(pocketLengthMm)} мм — '
              '$pocketCount шт',
        if (drainTotal > 0) 'Дренаж Ø6 мм: $drainTotal шт',
        if (strapCount > 0)
          'Подъёмные ремни: ${formatMm(50)} × ${formatMm(500)} мм — '
              '$strapCount шт',
      ];
}
