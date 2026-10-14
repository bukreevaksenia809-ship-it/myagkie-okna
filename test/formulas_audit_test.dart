// Независимый сквозной аудит формул и материалов приложения «Мягкие окна Excl».
//
// Правило аудита: все ожидания посчитаны ВРУЧНУЮ и записаны в тесте
// числами-литералами. Проверяемые функции (WindowSpec, WindowLayers,
// CostsSummary, Estimate, PriceList) НЕ вызываются для получения ожидания —
// только для получения факта, который с этим ожиданием сравнивается.
//
// Где фактическое поведение расходится с ручным расчётом, тест оставлен
// зелёным (чтобы не ломать сборку), но помечен словом «РАСХОЖДЕНИЕ» и
// точными числами в reason. Все такие случаи собраны в отчёте.
//
// Запуск: flutter test test/formulas_audit_test.dart
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/costs_summary.dart';
import 'package:soft_window_drawer/services/estimate.dart' show Estimate, roundMoney;
import 'package:soft_window_drawer/services/roll_plan.dart';

/// Сравнение чисел аудита: миллиметры, м², рубли. Ожидание — литерал.
void expectClose(num actual, num expected, String reason, {double tol = 1e-6}) {
  expect(actual.toDouble(), closeTo(expected.toDouble(), tol), reason: reason);
}

/// Прямоугольник 2000 × 1500 мм, окантовка 100 (50 готовых), запайка 25.
const _rect2000x1500 = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 1500,
  rightHeight: 1500,
);

/// Прямоугольник 2000 × 2500 мм, окантовка 100, запайка 25.
const _rect2000x2500 = WindowParams(
  bottomWidth: 2000,
  topWidth: 2000,
  leftHeight: 2500,
  rightHeight: 2500,
);

void main() {
  _filamentBlankAudit();
  _screenBlankAudit();
  _edgeConsumptionAudit();
  _eyeletAudit();
  _areaAudit();
  _pocketAudit();
  _estimateAudit();
  _edgePriceAudit();
  _rollLayoutAudit();
  _materialsAudit();
}

// ---------------------------------------------------------------------------
// 1. ПВХ: размер заготовки плёнки
// ---------------------------------------------------------------------------
void _filamentBlankAudit() {
  group('1. ПВХ: заготовка плёнки', () {
    test('контрольный пример 2000×2000, окантовка 100/100/80, запайка 10 '
        '→ 1920 × 1930', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        // Низ/право/лево — рулон 100 (готово 50), верх — рулон 80 (готово 40).
        rollBottom: 100,
        rollRight: 100,
        rollLeft: 100,
        rollTop: 80,
        weldOverlapMm: 10,
      );
      final spec = WindowSpec.of(params);

      // Вручную: ширина = 2000 − 50(лево) − 50(право) + 2×10 = 1920.
      // Вручную: высота = 2000 − 50(низ) − 40(верх) + 2×10 = 1930.
      expectClose(spec.filmCutWidth, 1920, 'ширина заготовки: 2000−50−50+20');
      expectClose(spec.filmCutHeight, 1930, 'высота заготовки: 2000−50−40+20');
    });

    test('тот же пример с припуском +100/+100 и усадкой 1,5 % '
        '→ 2020 × 2030 → 2050,3 × 2060,45', () {
      final params = const WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        rollBottom: 100,
        rollRight: 100,
        rollLeft: 100,
        rollTop: 80,
        weldOverlapMm: 10,
      ).copyWith(allowanceWidthMm: 100, allowanceHeightMm: 100);
      final spec = WindowSpec.of(params);

      // Вручную: 1920 + 100 = 2020; 1930 + 100 = 2030.
      expectClose(spec.filmCutWidthWithAllowance, 2020, 'заготовка с припуском');
      expectClose(spec.filmCutHeightWithAllowance, 2030, 'заготовка с припуском');
      // Вручную: 2020 × 1,015 = 2050,3; 2030 × 1,015 = 2060,45.
      expectClose(spec.filmCutWidthWithShrinkage, 2050.3, 'ширина с усадкой',
          tol: 1e-9);
      expectClose(spec.filmCutHeightWithShrinkage, 2060.45, 'высота с усадкой',
          tol: 1e-9);
      // Площадь заготовки без усадки: 2020 × 2030 = 4 100 600 мм² = 4,1006 м².
      expectClose(spec.filmCutAreaM2, 4.1006, 'площадь заготовки 4,1006 м²');
    });

    test('запайка 25 и окантовка 100 со всех сторон → 1950 × 1950', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
      );
      final spec = WindowSpec.of(params);

      // Вручную: 2000 − 100 + 50 = 1950 по обеим осям.
      expectClose(spec.filmCutWidth, 1950, '2000−2×50+2×25');
      expectClose(spec.filmCutHeight, 1950, '2000−2×50+2×25');
    });

    test('площадь с усадкой считается из линейных размеров: '
        '2050,3 × 2060,45 = 4,224541 м²', () {
      final params = const WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        rollBottom: 100,
        rollRight: 100,
        rollLeft: 100,
        rollTop: 80,
        weldOverlapMm: 10,
      ).copyWith(allowanceWidthMm: 100, allowanceHeightMm: 100);
      final spec = WindowSpec.of(params);

      // Вручную: 2050,3 × 2060,45 = 4 224 540,635 мм² = 4,224541 м². Усадка
      // масштабирует ОБЕ стороны заготовки, поэтому площадь берётся из
      // линейных размеров, а не умножением площади на (1 + s/100).
      expectClose(
        spec.filmCutAreaWithShrinkageM2,
        4.224540635,
        'площадь заготовки с усадкой = 2050,3 × 2060,45 мм',
        tol: 1e-9,
      );
      // Старая (ошибочная) формула дала бы 4,1006 × 1,015 = 4,162109 м².
      expect(
        spec.filmCutAreaWithShrinkageM2,
        greaterThan(4.162109),
        reason: 'площадь не должна считаться умножением на один множитель',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 2. Скрин: размер заготовки
// ---------------------------------------------------------------------------
void _screenBlankAudit() {
  group('2. Скрин: заготовка = готовый размер + подворот своей стороны', () {
    for (final hem in <double>[40, 50, 60]) {
      final expected = 2000 + 2 * hem;
      test('подворот ${hem.toStringAsFixed(0)} на все стороны → '
          '${expected.toStringAsFixed(0)} × ${expected.toStringAsFixed(0)}', () {
        final params = WindowParams(
          bottomWidth: 2000,
          topWidth: 2000,
          leftHeight: 2000,
          rightHeight: 2000,
          material: FilmMaterial.screen,
          hemBottomMm: hem,
          hemRightMm: hem,
          hemTopMm: hem,
          hemLeftMm: hem,
        );
        final spec = WindowSpec.of(params);

        // Вручную: 2000 + 2 × подворот.
        expectClose(spec.filmCutWidth, expected, 'заготовка по ширине');
        expectClose(spec.filmCutHeight, expected, 'заготовка по высоте');
        // Шов 3 мм на сторону не входит в габарит заготовки, усадки у скрина
        // нет: с «усадкой» те же размеры.
        expectClose(spec.filmCutWidthWithShrinkage, expected,
            'у скрина усадки нет');
        expectClose(spec.filmCutHeightWithShrinkage, expected,
            'у скрина усадки нет');
        // Видимый размер скрина — готовый контур изделия.
        expectClose(spec.filmVisibleWidth, 2000, 'видимый размер 2000');
        expect(params.hasUniformHem, isTrue,
            reason: 'подворот одинаков со всех сторон');
      });
    }

    test('смешанный подворот (низ 40, право 50, верх 60, лево 40) '
        '→ 2090 × 2100', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        material: FilmMaterial.screen,
        hemBottomMm: 40,
        hemRightMm: 50,
        hemTopMm: 60,
        hemLeftMm: 40,
      );
      final spec = WindowSpec.of(params);

      // Вручную: ширина = 2000 + лево 40 + право 50 = 2090;
      // высота = 2000 + низ 40 + верх 60 = 2100.
      expectClose(spec.filmCutWidth, 2090, 'ширина 2090');
      expectClose(spec.filmCutHeight, 2100, 'высота 2100');
      expect(params.hasUniformHem, isFalse, reason: 'подвороты разные');
      expectClose(spec.filmCutWidthWithShrinkage, 2090,
          'у скрина усадки нет (ширина)');
      expectClose(spec.filmCutHeightWithShrinkage, 2100,
          'у скрина усадки нет (высота)');
    });
  });
}

// ---------------------------------------------------------------------------
// 3. Расход окантовки
// ---------------------------------------------------------------------------
void _edgeConsumptionAudit() {
  group('3. Расход окантовки: неспаянные стороны + контуры вырезов', () {
    test('прямоугольник 2000 × 2500: периметр 9000 и расход 9000', () {
      final spec = WindowSpec.of(_rect2000x2500);

      // Вручную: 2 × (2000 + 2500) = 9000.
      expectClose(spec.geometry.perimeter, 9000, 'периметр 9000');
      expect(spec.geometry.sideLengths, [2000.0, 2500.0, 2000.0, 2500.0],
          reason: 'стороны: низ, право, верх, лево');
      expectClose(spec.edgeConsumption[100.0]!, 9000, 'весь периметр в рулон 100');
      expect(spec.edgeConsumption.length, 1, reason: 'одна ширина рулона — 100');
    });

    test('спайка правой стороны убирает 2500: 9000 − 2500 = 6500', () {
      final params =
          _rect2000x2500.copyWith(weldedSides: const [EdgeSide.right]);
      final spec = WindowSpec.of(params);

      // Вручную: правая сторона = 2500, окантовка на ней не ставится:
      // 9000 − 2500 = 6500. (В задании указано 7500 = 9000 − 1500; для
      // прямоугольника 2000 × 2500 ни одна сторона не равна 1500, поэтому
      // 7500 не соответствует ни одному варианту спайки.)
      expectClose(spec.edgeConsumption[100.0]!, 6500,
          'низ 2000 + верх 2000 + лево 2500 = 6500');
      expectClose(spec.layers.weldLengthMm, 2500, 'длина спайки 2500');
    });

    test('спайка низа убирает 2000: 9000 − 2000 = 7000', () {
      final params =
          _rect2000x2500.copyWith(weldedSides: const [EdgeSide.bottom]);
      final spec = WindowSpec.of(params);

      expectClose(spec.edgeConsumption[100.0]!, 7000,
          'право 2500 + верх 2000 + лево 2500 = 7000');
    });

    test('вырез 300 × 300 добавляет контур 1200: 9000 + 1200 = 10200', () {
      final params = _rect2000x2500.copyWith(
        cutouts: const [Cutout(width: 300, height: 300, centerXMm: 1000)],
      );
      final spec = WindowSpec.of(params);

      // Вручную: контур прямоугольника = 2 × (300 + 300) = 1200.
      expectClose(spec.layers.cutoutPerimeterMm, 1200, 'контур 1200');
      expectClose(spec.edgeConsumption[100.0]!, 10200, '9000 + 1200');
    });

    test('круглый вырез Ø300 добавляет π × 300 ≈ 942,478', () {
      final params = _rect2000x2500.copyWith(
        cutouts: const [
          Cutout(
            shape: CutoutShape.circle,
            width: 300,
            height: 300,
            centerXMm: 1000,
          ),
        ],
      );
      final spec = WindowSpec.of(params);

      // Вручную: π × 300 = 942,4777961.
      expectClose(spec.layers.cutoutPerimeterMm, math.pi * 300,
          'контур круга π×300');
      expectClose(spec.edgeConsumption[100.0]!, 9000 + math.pi * 300,
          '9000 + π×300');
    });

    test('вырез на спаянном низу всё равно идёт в рулон низа', () {
      final params = _rect2000x2500.copyWith(
        weldedSides: const [EdgeSide.bottom],
        cutouts: const [Cutout(width: 300, height: 300, centerXMm: 1000)],
      );
      final spec = WindowSpec.of(params);

      // Вручную: стороны без низа = 2500 + 2000 + 2500 = 7000; контур выреза
      // относится к нижнему рулону (rolls[0]) = 100 → 7000 + 1200 = 8200.
      expectClose(spec.edgeConsumption[100.0]!, 8200,
          'низ спаян, но контур выреза по-прежнему в рулоне низа');
    });
  });
}

// ---------------------------------------------------------------------------
// 4. Люверсы
// ---------------------------------------------------------------------------
void _eyeletAudit() {
  group('4. Люверсы: количество и фактический шаг', () {
    test('2000 × 1500, шаг 300, отступ 0 → 24 люверса, шаги 278,57 и 290', () {
      final layers = WindowLayers(
        _rect2000x1500,
        WindowGeometry.of(_rect2000x1500),
      );

      // Вручную. Линия люверсов — середина окантовки: 2000 − 2×25 = 1950,
      // 1500 − 2×25 = 1450.
      // низ/верх: ceil(1950 / 300) = 7 интервалов, шаг 1950 / 7 = 278,5714;
      // право/лево: ceil(1450 / 300) = 5 интервалов, шаг 1450 / 5 = 290.
      // Уникальных люверсов = 7 + 5 + 7 + 5 = 24 (углы не дублируются).
      expect(layers.eyeletCount, 24, reason: '7+5+7+5 = 24 без дублей углов');
      expect(layers.eyeletSteps.length, 4, reason: 'по одной записи на сторону');

      for (final step in layers.eyeletSteps) {
        expect(step, inInclusiveRange(250, 400),
            reason: 'фактический шаг $step должен быть в 250…400 мм');
      }
      final sorted = [...layers.eyeletSteps]..sort();
      expectClose(sorted[0], 1950 / 7, 'шаг низа/верха 1950/7');
      expectClose(sorted[1], 1950 / 7, 'шаг низа/верха 1950/7');
      expectClose(sorted[2], 290, 'шаг права/лева 1450/5');
      expectClose(sorted[3], 290, 'шаг права/лева 1450/5');
    });

    test('карман снизу: нижние углы убраны, боковые сдвинуты на 50 мм, '
        'всего 24', () {
      final params = _rect2000x1500.copyWith(pocket: true);
      final layers = WindowLayers(params, WindowGeometry.of(params));

      // Вручную. Базово 28 узлов, 4 из них — дубли углов → 24.
      // Карман убирает 2 нижних угловых узла (28 → 26), но при этом углы
      // низа больше не дублируются (боковые сдвинуты на 50 мм): 4 дубля
      // остаётся только 2 (верхние углы) → 26 − 2 = 24.
      expect(layers.eyeletCount, 24, reason: '26 узлов − 2 верхних дубля = 24');
      final bottom = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.bottom)
          .toList();
      expect(bottom.length, 6, reason: 'низ потерял оба угловых: 8 → 6');

      // Нижний боковой люверс поднят от угла на 50 мм: 25 + 50 = 75.
      final right = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.right)
          .toList();
      final left = layers.eyelets
          .where((eyelet) => eyelet.side == WindowSide.left)
          .toList();
      final rightLowest =
          right.reduce((a, b) => a.center.dy < b.center.dy ? a : b);
      final leftLowest = left.reduce((a, b) => a.center.dy < b.center.dy ? a : b);
      expectClose(rightLowest.center.dy, 75, 'боковой люверс поднят до 75');
      expectClose(leftLowest.center.dy, 75, 'боковой люверс поднят до 75');
    });
  });
}

// ---------------------------------------------------------------------------
// 5. Площади
// ---------------------------------------------------------------------------
void _areaAudit() {
  group('5. Площади', () {
    test('изделие 2000 × 1500 = 3,0 м²; заготовка 1950 × 1450 = 2,8275 м²', () {
      final spec = WindowSpec.of(_rect2000x1500);

      // Вручную: изделие 2000 × 1500 = 3 000 000 мм² = 3,0 м².
      expectClose(spec.productAreaM2, 3.0, 'площадь изделия 3,0 м²');
      expectClose(spec.outerAreaM2, 3.0, 'площадь по наружному контуру 3,0 м²');
      // Вручную: заготовка без припуска (2000−50) × (1500−50) =
      // 1950 × 1450 = 2 827 500 мм² = 2,8275 м².
      expectClose(spec.filmCutAreaM2, 2.8275, 'заготовка без припуска 2,8275 м²');
      expectClose(spec.filmAreaM2, 2.8275,
          'справочная площадь полотна 2,8275 м²');
    });

    test('припуск +100/+100: заготовка 2050 × 1550 = 3,1775 м²', () {
      final params = _rect2000x1500.copyWith(
        allowanceWidthMm: 100,
        allowanceHeightMm: 100,
      );
      final spec = WindowSpec.of(params);

      // Вручную: 2050 × 1550 = 3 177 500 мм² = 3,1775 м².
      expectClose(spec.filmCutWidthWithAllowance, 2050, 'ширина с припуском');
      expectClose(spec.filmCutHeightWithAllowance, 1550, 'высота с припуском');
      expectClose(spec.filmCutAreaM2, 3.1775, 'площадь с припуском 3,1775 м²');
    });

    test('скрин 2000 × 2000, подворот 40: заготовка 2080 × 2080 = 4,3264 м²',
        () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        material: FilmMaterial.screen,
        hemBottomMm: 40,
        hemRightMm: 40,
        hemTopMm: 40,
        hemLeftMm: 40,
      );
      final spec = WindowSpec.of(params);

      // Вручную: 2080 × 2080 = 4 326 400 мм² = 4,3264 м².
      expectClose(spec.filmCutAreaM2, 4.3264, 'площадь заготовки скрина');
    });

    test('вырезы: прямоугольник 300 × 300 = 0,09 м², круг Ø300 = 0,070686 м²',
        () {
      final params = _rect2000x1500.copyWith(
        cutouts: const [
          Cutout(
            shape: CutoutShape.rect,
            width: 300,
            height: 300,
            centerXMm: 500,
            centerYMm: 400,
          ),
          Cutout(
            shape: CutoutShape.circle,
            width: 300,
            height: 300,
            centerXMm: 1500,
            centerYMm: 400,
          ),
        ],
      );
      final spec = WindowSpec.of(params);

      // Вручную: прямоугольник 300 × 300 = 90 000 мм²; круг π×300²/4 =
      // 70 685,8347 мм²; сумма 160 685,8347 мм².
      expectClose(spec.layers.cutoutAreaMm2, 90000 + math.pi * 300 * 300 / 4,
          'суммарная площадь вырезов');
      // Площадь плёнки в ведомости = площадь заготовки минус вырезы:
      // 1950 × 1450 − 160 685,8347 = 2 666 814,1653 мм² = 2,666814 м².
      expectClose(
        spec.filmCutAreaM2,
        (1950 * 1450 - 90000 - math.pi * 300 * 300 / 4) / 1000000,
        'ведомость: заготовка минус вырезы',
      );
      // То же число отдаёт сводка расхода (ведомость заказа).
      final summary = CostsSummary(OrderProject(windows: [params]));
      expectClose(summary.filmAreaM2, spec.filmCutAreaM2,
          'площадь плёнки в ведомости = площадь заготовки минус вырезы');
    });

    test('смета берёт площадь заготовки С усадкой (расход и деньги)', () {
      final params = const WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
        rollBottom: 100,
        rollRight: 100,
        rollLeft: 100,
        rollTop: 80,
        weldOverlapMm: 10,
      ).copyWith(allowanceWidthMm: 100, allowanceHeightMm: 100);
      final spec = WindowSpec.of(params);
      final summary = CostsSummary(OrderProject(windows: [params]));
      final estimate = Estimate.ofWindow(params, PriceList.defaults());

      // Вручную: плёнка кроится 2050,3 × 2060,45 мм = 4,224540635 м².
      expectClose(spec.filmCutAreaWithShrinkageM2, 4.224540635,
          'фактическая площадь заготовки с усадкой', tol: 1e-9);
      // Сводка расхода отдаёт именно её — и в итог, и по материалам.
      expectClose(summary.filmAreaWithShrinkageM2, 4.224540635,
          'ведомость: заготовка с усадкой', tol: 1e-9);
      expectClose(summary.filmAreaByMaterialWithShrinkage[FilmMaterial.clearPvc]!,
          4.224540635, 'ведомость: заготовка с усадкой по материалу',
          tol: 1e-9);
      // Габарит без усадки остаётся справочным числом.
      expectClose(summary.filmAreaM2, 4.1006, 'габарит без усадки 4,1006 м²');

      // Смета: позиция плёнки — площадь с усадкой, 4,224540635 × 950 =
      // 4013,3136 → 4013,31 ₽; раскрой 4,224540635 × 250 = 1056,1352 → 1056,14.
      final film = estimate.lines
          .firstWhere((line) => line.title.startsWith('Полотно'));
      expectClose(film.quantity, 4.224540635, 'плёнка в смете с усадкой',
          tol: 1e-9);
      expectClose(film.amount, 4013.31, '4,224540635 × 950');
      final cutting = estimate.lines
          .firstWhere((line) => line.title.startsWith('Раскрой'));
      expectClose(cutting.quantity, 4.224540635,
          'раскрой по площади с усадкой', tol: 1e-9);
      expectClose(cutting.amount, 1056.14, '4,224540635 × 250');
      expectClose(estimate.filmAreaM2, 4.224540635, 'площадь плёнки в смете');
    });

    test('трапеция: габарит заготовки (расход) больше площади полотна', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 1000,
        leftHeight: 1000,
        rightHeight: 1000,
      );
      final spec = WindowSpec.of(params);

      // Осознанно два разных числа, их и разводят подписи: filmCutAreaM2 —
      // заготовка (габаритный прямоугольник 1919,10 × 950 мм = 1,823143 м²),
      // она идёт в расход; filmAreaM2 — площадь самого полотна
      // (1,371893 м², справочно). Для непрямоугольного окна заготовка
      // кроится прямоугольником, поэтому расход — верхняя оценка.
      expectClose(spec.filmCutAreaM2, 1.823143, 'заготовка (габарит) 1,823143',
          tol: 1e-6);
      expectClose(spec.filmAreaM2, 1.371893, 'площадь полотна 1,371893',
          tol: 1e-6);
      expect(
        spec.filmCutAreaM2,
        greaterThan(spec.filmAreaM2),
        reason: 'заготовка (габарит) больше площади полотна, потому что '
            'кроится прямоугольником; в подписях это «заготовка (габарит)» '
            'против «площадь полотна»',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 6. Карманы
// ---------------------------------------------------------------------------
void _pocketAudit() {
  group('6. Карманы: расход полосы и количество', () {
    test('один нижний карман: 2000 мм, 1 шт', () {
      final params = _rect2000x1500.copyWith(pocket: true);
      final summary = CostsSummary(OrderProject(windows: [params]));

      // Вручную: ширина полосы = ширина окна 2000, карманов 1.
      expect(summary.pocketCount, 1);
      expectClose(summary.pocketLengthMm, 2000, 'полоса 2000 мм');
    });

    test('один верхний карман: 2000 мм, 1 шт', () {
      final params = _rect2000x1500.copyWith(pocketTop: true);
      final summary = CostsSummary(OrderProject(windows: [params]));

      expect(summary.pocketCount, 1);
      expectClose(summary.pocketLengthMm, 2000, 'полоса 2000 мм');
    });

    test('два кармана: 2000 + 2000 = 4000 мм, 2 шт', () {
      final params = _rect2000x1500.copyWith(pocket: true, pocketTop: true);
      final summary = CostsSummary(OrderProject(windows: [params]));

      expect(summary.pocketCount, 2);
      expectClose(summary.pocketLengthMm, 4000, '2000 + 2000 = 4000');
    });

    test('верхний карман считается по ширине верха', () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 1500,
        leftHeight: 1500,
        rightHeight: 1500,
        pocketTop: true,
      );
      final summary = CostsSummary(OrderProject(windows: [params]));

      expectClose(summary.pocketLengthMm, 1500, 'верх 1500');
      expect(summary.pocketCount, 1);
    });

    test('в смете карман — погонные метры по цене 380 ₽/м', () {
      final prices = PriceList.defaults();
      final params = _rect2000x1500.copyWith(pocket: true, pocketTop: true);
      final estimate = Estimate.ofWindow(params, prices);
      final line = estimate.lines
          .firstWhere((candidate) => candidate.title.startsWith('Карман'));

      expectClose(line.quantity, 4.0, '4000 мм = 4 м');
      expectClose(line.unitPrice, 380, 'цена кармана 380 ₽/м');
      expectClose(line.amount, 1520, '4 × 380 = 1520');
    });
  });
}

// ---------------------------------------------------------------------------
// 7. Смета
// ---------------------------------------------------------------------------
void _estimateAudit() {
  group('7. Смета: подытог → наценка 20 % → скидка 10 % → НДС 20 %', () {
    test('одно окно 2000 × 2500: все позиции и итог', () {
      final prices = PriceList.defaults().copyWith(
        markupPercent: 20,
        discountPercent: 10,
        vatPercent: 20,
      );
      final estimate = Estimate.ofWindow(_rect2000x2500, prices);

      // Вручную. Заготовка (габарит) без усадки: (2000−50) × (2500−50) =
      // 1950 × 2450 = 4 777 500 мм² = 4,7775 м². С усадкой 1,5 % обе стороны
      // растут: 1979,25 × 2486,75 = 4 921 899,9375 мм² = 4,9218999375 м² —
      // именно эта площадь идёт в смету. Изделие: 2000 × 2500 = 5,0 м².
      // Окантовка: 2 × (2000 + 2500) = 9000 мм = 9 м.
      // Люверсы: низ/верх ceil(1950/300)=7, право/лево ceil(2450/300)=9
      // → 7+9+7+9 = 32 шт.
      expect(estimate.windowCount, 1);
      expect(estimate.lines.length, 5,
          reason: 'плёнка, окантовка, люверсы, сварка, раскрой');
      expectClose(estimate.productAreaM2, 5.0, 'площадь изделия 5,0 м²');
      expectClose(estimate.filmAreaM2, 4.9218999375,
          'площадь заготовки с усадкой 4,9218999375 м²', tol: 1e-9);

      final film = estimate.lines
          .firstWhere((line) => line.title.startsWith('Полотно'));
      // 4,9218999375 × 950 = 4675,8049 → 4675,80 (округление до копейки).
      expectClose(film.quantity, 4.9218999375, 'плёнка с усадкой', tol: 1e-9);
      expectClose(film.unitPrice, 950, 'ПВХ прозрачный 950 ₽/м²');
      expectClose(film.amount, 4675.80, '4,9218999375 × 950');

      final edge = estimate.lines
          .firstWhere((line) => line.title.startsWith('Окантовка'));
      // 9 × 140 = 1260.
      expectClose(edge.quantity, 9.0, 'окантовка 9 м');
      expectClose(edge.unitPrice, 140, 'рулон 100 мм — 140 ₽/м');
      expectClose(edge.amount, 1260, '9 × 140');

      final eyelets = estimate.lines
          .firstWhere((line) => line.title.startsWith('Люверсы'));
      // 32 × (65 + 25) = 32 × 90 = 2880.
      expectClose(eyelets.quantity, 32, '32 люверса');
      expectClose(eyelets.unitPrice, 90, '65 + 25 установка');
      expectClose(eyelets.amount, 2880, '32 × 90');

      final labor = estimate.lines.firstWhere(
          (line) => line.title.startsWith('Сварка'));
      // 5,0 × 700 = 3500.
      expectClose(labor.quantity, 5.0, 'сварка по изделию 5 м²');
      expectClose(labor.unitPrice, 700, 'сборка 700 ₽/м²');
      expectClose(labor.amount, 3500, '5 × 700');

      final cutting = estimate.lines
          .firstWhere((line) => line.title.startsWith('Раскрой'));
      // 4,9218999375 × 250 = 1230,475 → 1230,47.
      expectClose(cutting.quantity, 4.9218999375, 'раскрой с усадкой',
          tol: 1e-9);
      expectClose(cutting.unitPrice, 250, 'раскрой 250 ₽/м²');
      expectClose(cutting.amount, 1230.47, '4,9218999375 × 250');

      // --- Цепочка округлений (вручную, до копейки на каждом шаге) ---------
      // материалы 4675,80 + 1260 = 5935,80
      // фурнитура 2880,00
      // работы 3500 + 1230,47 = 4730,47
      // подытог 5935,80 + 2880 + 4730,47 = 13546,27
      expectClose(estimate.materialsSubtotal, 5935.80, 'материалы');
      expectClose(estimate.hardwareSubtotal, 2880, 'фурнитура');
      expectClose(estimate.workSubtotal, 4730.47, 'работы');
      expectClose(estimate.subtotal, 13546.27, 'подытог');
      // наценка 20 %: 13546,27 × 0,2 = 2709,254 → 2709,25
      expectClose(estimate.markupAmount, 2709.25, 'наценка');
      expectClose(estimate.afterMarkup, 16255.52, 'с наценкой');
      // скидка 10 %: 16255,52 × 0,1 = 1625,552 → 1625,55
      expectClose(estimate.discountAmount, 1625.55, 'скидка');
      expectClose(estimate.taxableAmount, 14629.97, 'после скидки');
      // НДС 20 %: 14629,97 × 0,2 = 2925,994 → 2925,99
      expectClose(estimate.vatAmount, 2925.99, 'НДС');
      expectClose(estimate.total, 17555.96, 'ИТОГО');
      expectClose(estimate.pricePerWindow, 17555.96, 'цена за окно');

      // Наивная формула: подытог × 1,2 × 0,9 × 1,2 = 17555,96592.
      final naive = roundMoney(13546.27 * 1.2 * 0.9 * 1.2);
      expectClose(naive, 17555.97, 'наивная формула');
      expect(
        estimate.total,
        closeTo(naive, 0.011),
        reason: 'округление по позициям отличается от наивной формулы на '
            'одну копейку (17555,96 против 17555,97) — это округление '
            'наценки, скидки и НДС на каждом шаге',
      );
    });
  });
}

// ---------------------------------------------------------------------------
// 8. Цена нестандартной ширины окантовки
// ---------------------------------------------------------------------------
void _edgePriceAudit() {
  group('8. Цена окантовки по ширине рулона', () {
    final prices = PriceList.defaults();

    test('пресеты: 100 → 140, 200 → 230, 240 → 270 ₽/м', () {
      expectClose(prices.edgePerMeterForWidth(100), 140, 'пресет 100');
      expectClose(prices.edgePerMeterForWidth(200), 230, 'пресет 200');
      expectClose(prices.edgePerMeterForWidth(240), 270, 'пресет 240');
    });

    test('150 мм — середина 100…200: (140 + 230) / 2 = 185 ₽/м', () {
      expectClose(prices.edgePerMeterForWidth(150), 185, '185 ₽/м');
    });

    test('300 мм — экстраполяция по отрезку 200…240: 230 + 1 × 100 = 330', () {
      // Вручную: наклон (270 − 230) / (240 − 200) = 1 ₽/мм;
      // 230 + (300 − 200) × 1 = 330.
      expectClose(prices.edgePerMeterForWidth(300), 330, '330 ₽/м');
    });

    test('170 мм: 140 + 0,9 × 70 = 203 ₽/м', () {
      // Вручную: наклон (230 − 140) / (200 − 100) = 0,9 ₽/мм.
      expectClose(prices.edgePerMeterForWidth(170), 203, '203 ₽/м');
    });

    test('50 мм — экстраполяция ниже 100: 140 − 0,9 × 50 = 95 ₽/м', () {
      expectClose(prices.edgePerMeterForWidth(50), 95, '95 ₽/м');
    });

    test('нечисловая ширина не роняет расчёт', () {
      expectClose(prices.edgePerMeterForWidth(double.nan), 140,
          'запасное значение — цена первого пресета');
      expectClose(prices.edgePerMeterForWidth(double.infinity), 140,
          'запасное значение — цена первого пресета');
    });
  });
}

// ---------------------------------------------------------------------------
// 9. Раскладка на рулоне
// ---------------------------------------------------------------------------
void _rollLayoutAudit() {
  group('9. Раскладка на рулоне', () {
    test('заготовка уже рулона — предупреждений нет, все влезают', () {
      const params = WindowParams(
        bottomWidth: 1000,
        topWidth: 1000,
        leftHeight: 1000,
        rightHeight: 1000,
      );
      final project = OrderProject(
        windows: const [params],
        rollWidths: const {FilmMaterial.clearPvc: 2000},
      );
      final plan = buildRollPlans(project).single;

      // Вручную: заготовка = (1000 − 50) × 1,015 = 964,25 мм.
      expectClose(plan.layout.placements.single.width, 964.25,
          'заготовка 964,25 мм');
      expect(plan.rollWidth, 2000, reason: 'выбранный рулон 2000');
      expect(plan.layout.warnings, isEmpty, reason: 'заготовка уже рулона');
      for (final placement in plan.layout.placements) {
        expect(placement.width, lessThanOrEqualTo(plan.rollWidth + 1e-9),
            reason: 'заготовка не должна быть шире рулона');
      }
    });

    test('заготовка шире рулона: есть предупреждение, отход не отрицательный',
        () {
      const params = WindowParams(
        bottomWidth: 2000,
        topWidth: 2000,
        leftHeight: 2000,
        rightHeight: 2000,
      );
      final project = OrderProject(
        windows: const [params],
        rollWidths: const {FilmMaterial.clearPvc: 1400},
      );
      final summary = CostsSummary(project);
      final plan = summary.rollPlans.single;

      // Вручную: заготовка = (2000 − 50) × 1,015 = 1979,25 мм > 1400.
      // Длина рулона = высота единственной заготовки = 1979,25 мм.
      expectClose(plan.layout.placements.single.width, 1979.25, '1979,25 мм');
      expectClose(plan.layout.requiredLength, 1979.25, 'длина 1979,25 мм');
      expect(plan.layout.warnings, isNotEmpty,
          reason: 'признак проблемы: заготовка шире рулона');
      expect(plan.layout.warnings.first, contains('шире рулона'),
          reason: 'РАСХОЖДЕНИЕ (ожидаемое поведение): предупреждение '
              '«нужна сшивка» есть');
      // Отход не отрицательный: clamp 0…100.
      expect(plan.layout.wastePercent, inInclusiveRange(0, 100),
          reason: 'отход в пределах 0…100 %');
      expect(plan.wastePercent, inInclusiveRange(0, 100),
          reason: 'отход плана в пределах 0…100 %');
      expect(summary.rollWastePercent, inInclusiveRange(0, 100),
          reason: 'сводный отход в пределах 0…100 %');
      // Площадь заготовки (1979,25²) больше площади рулона
      // (1400 × 1979,25), поэтому отход зажат ровно в 0, а не в минус.
      expectClose(plan.wastePercent, 0, 'отход зажат в 0, а не отрицательный');
    });
  });
}

// ---------------------------------------------------------------------------
// 10. Материалы
// ---------------------------------------------------------------------------
void _materialsAudit() {
  group('10. Материалы: состав, подписи, рулоны, цены, отсутствие оксфорда',
      () {
    final prices = PriceList.defaults();

    test('FilmMaterial: у каждого подпись, толщина, рулоны и цена', () {
      // Вручную из прайса по умолчанию: 950 / 1150 / 420 / 520 ₽/м².
      const expectedPrices = <FilmMaterial, double>{
        FilmMaterial.clearPvc: 950,
        FilmMaterial.tintedPvc: 1150,
        FilmMaterial.mosquitoNet: 420,
        FilmMaterial.screen: 520,
      };
      expect(FilmMaterial.values.toSet(), expectedPrices.keys.toSet(),
          reason: 'перечислены ровно эти материалы');

      for (final entry in expectedPrices.entries) {
        final material = entry.key;
        expect(material.label.trim(), isNotEmpty,
            reason: '${material.name}: пустая подпись');
        expect(material.thickness.trim(), isNotEmpty,
            reason: '${material.name}: пустая строка толщины');
        expect(material.rollWidths, isNotEmpty,
            reason: '${material.name}: нет ширин рулонов');
        expect(
          material.rollWidths,
          orderedEquals([...material.rollWidths]..sort()),
          reason: '${material.name}: ширины рулонов не по возрастанию',
        );
        expect(material.rollWidthsLabel.trim(), isNotEmpty,
            reason: '${material.name}: пустая подпись ширин');
        expectClose(prices.filmPerM2(material), entry.value,
            '${material.name}: цена в прайсе');
      }
    });

    test('EdgeMaterial: только ПВХ-тент', () {
      expect(EdgeMaterial.values, [EdgeMaterial.pvcTent630],
          reason: 'в проекте один материал окантовки');
      expect(EdgeMaterial.pvcTent630.label.trim(), isNotEmpty);
      expect(EdgeMaterial.pvcTent630.isWelded, isTrue,
          reason: 'ПВХ-тент сваривают');
      expect(EdgeMaterial.pvcTent630.joining, contains('400'),
          reason: 'режим сварки 400–500 °C');
    });

    test('EdgeRoll: каждому пресету соответствует цена', () {
      // Вручную: рулоны 100/200/240 мм, готовые полосы 50/100/120 мм,
      // цены 140/230/270 ₽/м.
      const expected = <EdgeRoll, (double, double)>{
        EdgeRoll.roll100: (100, 140),
        EdgeRoll.roll200: (200, 230),
        EdgeRoll.roll240: (240, 270),
      };
      expect(EdgeRoll.values.toSet(), expected.keys.toSet());

      for (final entry in expected.entries) {
        final roll = entry.key;
        expect(roll.label.trim(), isNotEmpty, reason: '${roll.name}: подпись');
        expectClose(roll.rawWidth, entry.value.$1, '${roll.name}: ширина рулона');
        expectClose(roll.finishedWidth, entry.value.$1 / 2,
            '${roll.name}: готовая полоса — половина рулона');
        expectClose(prices.edgePerMeter(roll), entry.value.$2,
            '${roll.name}: цена в прайсе');
      }
    });

    test('в lib/ не осталось функциональных упоминаний оксфорда', () {
      final pattern = RegExp('oxford|оксфорд', caseSensitive: false);
      final codeHits = <String>[];
      final commentHits = <String>[];

      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          if (!pattern.hasMatch(lines[i])) continue;
          final trimmed = lines[i].trimLeft();
          final isComment = trimmed.startsWith('//') ||
              trimmed.startsWith('*') ||
              trimmed.startsWith('/*');
          final hit = '${entity.path}:${i + 1}: ${lines[i].trim()}';
          if (isComment) {
            commentHits.add(hit);
          } else {
            codeHits.add(hit);
          }
        }
      }

      expect(codeHits, isEmpty,
          reason: 'РАСХОЖДЕНИЕ (если не пусто): оксфорд в коде: $codeHits');
      // Информационно: допустимо единственное упоминание — комментарий о том,
      // что ткани Oxford в проекте больше нет.
      expect(commentHits.length, lessThanOrEqualTo(1),
          reason: 'упоминания оксфорда в комментариях: $commentHits');
    });
  });
}
