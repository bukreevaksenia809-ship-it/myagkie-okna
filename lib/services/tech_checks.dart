import 'dart:math' as math;

import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';

/// Важность технологической проверки.
///
/// [info] — подсказка технологу, [warning] — риск брака или неудобной
/// эксплуатации, [error] — так делать нельзя, изделие уйдёт в переделку.
enum TechSeverity {
  info,
  warning,
  error;

  String get label => switch (this) {
        TechSeverity.info => 'Справка',
        TechSeverity.warning => 'Замечание',
        TechSeverity.error => 'Ошибка',
      };

  /// Порядок показа: сначала ошибки, потом замечания, потом справки.
  int get rank => switch (this) {
        TechSeverity.error => 0,
        TechSeverity.warning => 1,
        TechSeverity.info => 2,
      };
}

/// Одна технологическая проверка: что не так, почему это плохо и что делать.
///
/// В отличие от [ParamIssue] (там проверяется корректность ввода), здесь
/// собраны производственные правила: они объясняют инженерный смысл и дают
/// рекомендацию мастеру. [ruleId] — стабильный идентификатор правила, по нему
/// интерфейс может группировать подсказки и не показывать одну и ту же дважды.
class TechCheck {
  const TechCheck({
    required this.ruleId,
    required this.severity,
    required this.title,
    required this.explanation,
    required this.recommendation,
    this.field,
    this.windowIndex,
  });

  /// Идентификатор правила, например `eyelet-step-loose`.
  final String ruleId;

  final TechSeverity severity;

  /// Короткая формулировка проблемы.
  final String title;

  /// Почему так нельзя или почему стоит поправить — инженерное обоснование.
  final String explanation;

  /// Синоним [explanation] — «почему» в терминах технолога.
  String get reason => explanation;

  /// Что сделать, чтобы проверка прошла.
  final String recommendation;

  /// Поле модели, к которому относится проверка (если есть).
  final ParamField? field;

  /// Номер окна в заказе (0 — первое). Для проверок одного окна — null.
  final int? windowIndex;

  bool get isBlocking => severity == TechSeverity.error;

  /// Копия проверки «для окна №[index]»: заголовок получает номер окна.
  TechCheck forWindow(int index) => TechCheck(
        ruleId: ruleId,
        severity: severity,
        title: 'Окно №${index + 1}: $title',
        explanation: explanation,
        recommendation: recommendation,
        field: field,
        windowIndex: index,
      );
}

// ——— Пороги технологии (реальные допуски для мягких окон из ПВХ) ———

/// Рекомендуемый интервал люверсов: 250–450 мм. Это подсказка, а не запрет:
/// интервал задаёт пользователь в рамках [minEyeletStepMm]…[maxEyeletStepMm].
const double _minEyeletStepMm = recommendedEyeletStepMinMm;
const double _maxEyeletStepMm = recommendedEyeletStepMaxMm;

/// Свыше 800 мм полотно между точками крепления парусит и хлопает.
const double _looseEyeletStepMm = looseEyeletStepMm;

/// Ниже 150 мм люверсы идут слишком часто: перерасход и узкая перемычка.
const double _denseEyeletStepMm = denseEyeletStepMm;

/// Минимальная перемычка окантовки от люверса до угла, мм.
const double _minEyeletCornerClearanceMm = 40;

/// Минимальный запас тента вокруг кольца люверса, мм.
const double _minEyeletMaterialMarginMm = 5;

/// Технологичный диапазон готовой (сложенной) ширины окантовки, мм.
const double _minFinishedEdgeMm = 40;
const double _maxFinishedEdgeMm = 120;

/// Разумный диапазон запайки плёнки под окантовку, мм.
const double _minWeldOverlapMm = 5;
const double _maxWeldOverlapMm = 60;

/// Технологичный подворот скрина, мм на сторону.
const double _minHemMm = 30;
const double _maxHemMm = 80;

/// Полотно плёнки уже 300 мм не удержать в окантовке.
const double _minFilmSideMm = 300;

/// Изделие больше 12 м² требует дополнительной поддержки или разбивки.
const double _maxProductAreaM2 = 12;

/// Заказ больше 40 м² — вопрос сроков и раскроя.
const double _largeOrderAreaM2 = 40;

/// Подъёмное окно шире 2500 мм: ремней становится 3+, растёт нагрузка.
const double _liftingStrapLoadWidthMm = 2500;

/// Подъёмное окно выше 3000 мм тяжело поднимать вручную.
const double _liftingHardHeightMm = 3000;

/// Две молнии ближе 300 мм — неудобно пользоваться.
const double _minZipperSpacingMm = 300;

/// Спайка молнии ближе 150 мм к кромке плёнки — шов слабый.
const double _minZipperToEdgeMm = 150;

/// Вырез ближе 100 мм к окантовке оставляет тонкую перемычку.
const double _minCutoutBridgeMm = 100;

/// Круглый вырез меньше 100 мм обычно не проходит под трубу.
const double _minRoundCutoutMm = 100;

/// Усадка ПВХ выше 3 % — не типовая, партию надо уточнять у поставщика.
const double _maxShrinkagePercent = 3;

/// Разница низа и верха больше 500 мм при высоком окне — сложная трапеция.
const double _maxWidthDiffMm = 500;
const double _tallWindowMm = 2500;

/// Есть ли среди проверок блокирующая (изделие нельзя запускать в цех).
bool hasBlockingTechChecks(List<TechCheck> checks) =>
    checks.any((check) => check.severity == TechSeverity.error);

/// Технологические проверки одного окна.
///
/// Проверки не дублируют [validateParams]: та функция отвечает за корректность
/// введённых чисел, эта — за производственную технологию. Результат
/// отсортирован: сначала ошибки, затем замечания и справки.
List<TechCheck> techChecksFor(WindowParams params) {
  final checks = <TechCheck>[];
  final spec = WindowSpec.of(params);

  _checkEyeletStep(params, checks);
  _checkEyeletClearance(params, spec, checks);
  _checkWeldOverlap(params, checks);
  _checkScreenHem(params, checks);
  _checkEdgeRolls(params, checks);
  _checkFilm(params, spec, checks);
  _checkLifting(params, spec, checks);
  _checkZippers(params, spec, checks);
  _checkPocket(params, spec, checks);
  _checkCutouts(spec, checks);
  _checkWeldedSides(params, spec, checks);
  _checkFastener(params, checks);
  _checkShrinkage(params, checks);
  _checkSection(params, spec, checks);

  return _sorted(checks);
}

/// Технологические проверки всего заказа.
///
/// Возвращает только проверки уровня заказа: дубли одинаковых окон, число
/// разных материалов, суммарную площадь. Проверки конкретного окна даёт
/// [techChecksFor] — их показывает выбранное окно. Сводный экран по всем
/// окнам может пометить проверку номером через [TechCheck.forWindow].
List<TechCheck> techChecksForOrder(OrderProject project) {
  final checks = <TechCheck>[];

  _checkDuplicateWindows(project, checks);
  _checkOrderMaterials(project, checks);
  _checkOrderArea(project, checks);

  return _sorted(checks);
}

// ——————————————————————— Правила по люверсам ———————————————————————

/// Интервал люверсов.
///
/// Интервал задаёт пользователь, поэтому жёсткого коридора «250–400» здесь
/// нет: это замечания технолога, а не запрет. Слишком редкий интервал
/// (свыше 800 мм) оставляет полотно без промежуточных точек: окно парусит,
/// хлопает на ветру, окантовка работает на отрыв. Слишком частый (меньше
/// 150 мм) съедает тент и металл, а перемычка между соседними кольцами
/// становится настолько узкой, что рвётся по пробою. Между 450 и 800 мм —
/// справка «на верхней границе», между 150 и 250 мм — «чаще рекомендуемого».
void _checkEyeletStep(WindowParams params, List<TechCheck> checks) {
  final step = params.eyeletStep;
  if (!step.isFinite || step <= 0) return;

  if (step > _looseEyeletStepMm) {
    checks.add(TechCheck(
      ruleId: 'eyelet-step-loose',
      severity: TechSeverity.warning,
      field: ParamField.eyeletStep,
      title: 'Интервал люверсов ${formatMm(step)} мм — слишком редкий',
      explanation: 'Полотно между точками крепления провисает: при ветре окно '
          'парусит и хлопает, окантовка и люверсы работают на отрыв, '
          'тент вытягивается по пробою.',
      recommendation: 'Уменьшите интервал до 250–450 мм (на ветреных фасадах — '
          'ближе к 250–300 мм) или добавьте промежуточные люверсы по длинным '
          'сторонам.',
    ));
  } else if (step > _maxEyeletStepMm) {
    checks.add(TechCheck(
      ruleId: 'eyelet-step-wide',
      severity: TechSeverity.info,
      field: ParamField.eyeletStep,
      title: 'Интервал люверсов ${formatMm(step)} мм — на верхней границе',
      explanation: 'Формально допустимо, но запас до «парусности» уже небольшой: '
          'на открытом фасаде полотно начнёт хлопать.',
      recommendation: 'Для ветреных мест ставьте 250–300 мм.',
    ));
  } else if (step < _denseEyeletStepMm) {
    checks.add(TechCheck(
      ruleId: 'eyelet-step-tight',
      severity: TechSeverity.warning,
      field: ParamField.eyeletStep,
      title: 'Интервал люверсов ${formatMm(step)} мм — слишком частый',
      explanation: 'Люверсы идут почти вплотную: перерасход тента и фурнитуры, '
          'а узкая перемычка между кольцами рвётся по пробою при нагрузке.',
      recommendation: 'Увеличьте интервал до 250–450 мм.',
    ));
  } else if (step < _minEyeletStepMm) {
    checks.add(TechCheck(
      ruleId: 'eyelet-step-narrow',
      severity: TechSeverity.info,
      field: ParamField.eyeletStep,
      title: 'Интервал люверсов ${formatMm(step)} мм — ниже рекомендуемого',
      explanation: 'Работает, но люверсов и тента уходит больше нормы.',
      recommendation: 'Если окно не на ветреном фасаде, хватит 250–450 мм.',
    ));
  }
}

/// Люверс у угла и у кромки окантовки.
///
/// Люверс ровно в углу — штатное решение: угол тянет по диагонали, и тент
/// работает всей шириной окантовки. Опасен «почти угол»: если отступить на
/// 10–30 мм, остаётся узкая перемычка окантовки, которая при первом же
/// рывке ветра вырывается. Кольцо люверса тоже должно целиком лежать в
/// тента, с запасом материала до кромок окантовки.
void _checkEyeletClearance(
  WindowParams params,
  WindowSpec spec,
  List<TechCheck> checks,
) {
  final offset = params.eyeletCornerOffset;
  if (offset.isFinite && offset > 0 && offset < _minEyeletCornerClearanceMm) {
    checks.add(TechCheck(
      ruleId: 'eyelet-corner-danger',
      severity: TechSeverity.warning,
      field: ParamField.eyeletCornerOffset,
      title: 'Люверс поднят от угла всего на ${formatMm(offset)} мм',
      explanation: 'Между люверсом и углом остаётся узкая перемычка окантовки — '
          'именно по ней рвёт тент, а сам люверс не тянет угол по диагонали.',
      recommendation: 'Поставьте люверс ровно в угол (0 мм) или отступите '
          'не меньше ${formatMm(_minEyeletCornerClearanceMm)} мм.',
    ));
  }

  // Кольцо люверса должно помещаться в окантовку: от линии люверсов до обеих
  // кромок ленты ровно половина готовой ширины окантовки. У скрина окантовки
  // нет — люверсы стоят по подвороту, и запас считаем по самому узкому
  // подвороту ([WindowParams.hemWidths]).
  if (params.isScreen) {
    final ringHalf = params.effectiveEyeletType.outerHeight / 2;
    final minHem = params.hemWidths.reduce(math.min);
    if (minHem / 2 - ringHalf < _minEyeletMaterialMarginMm) {
      checks.add(TechCheck(
        ruleId: 'eyelet-hem-material',
        severity: TechSeverity.warning,
        title: 'Люверсу не хватает подворота: запас всего '
            '${formatMm(math.max(minHem / 2 - ringHalf, 0))} мм',
        explanation: 'Кольцо ${params.effectiveEyeletType.label.toLowerCase()} '
            'почти выходит за самый узкий подворот ${formatMm(minHem)} мм: '
            'ткань под кольцом продавливается и рвётся.',
        recommendation: 'Увеличьте подворот до '
            '${formatMm(math.max(minHem, _minHemMm * 2))} мм на каждой стороне '
            'или поставьте люверс меньшего размера.',
      ));
    }
    return;
  }

  final minFinished = spec.layers.finishedWidths.reduce(math.min);
  final ringHalf = params.effectiveEyeletType.outerHeight / 2;
  final margin = minFinished / 2 - ringHalf;
  if (margin < _minEyeletMaterialMarginMm) {
    checks.add(TechCheck(
      ruleId: 'eyelet-corner-material',
      severity: TechSeverity.warning,
      title: 'Люверсу не хватает тента: запас всего '
          '${formatMm(math.max(margin, 0))} мм',
      explanation: 'Кольцо ${params.effectiveEyeletType.label.toLowerCase()} '
          'почти выходит за окантовку ${formatMm(minFinished)} мм: тент '
          'под кольцом продавливается и рвётся.',
      recommendation: 'Возьмите рулон окантовки шире (готовых 100 мм) или '
          'поставьте люверс меньшего размера.',
    ));
  }
}

// ——————————————————————— Правила по окантовке ———————————————————————

/// Запайка (напайка) плёнки под окантовку — вводится руками, 5…60 мм.
///
/// От запайки напрямую зависит размер заготовки: каждый миллиметр добавляет
/// по миллиметру с каждой стороны. Слишком мало — шов без тела, слишком много
/// — перерасход плёнки и толстый валик под лентой.
void _checkWeldOverlap(WindowParams params, List<TechCheck> checks) {
  if (params.isScreen) return;
  final overlap = params.weldOverlapMm;
  if (!overlap.isFinite ||
      overlap < _minWeldOverlapMm ||
      overlap > _maxWeldOverlapMm) {
    checks.add(TechCheck(
      ruleId: 'weld-overlap-range',
      severity: TechSeverity.error,
      field: ParamField.weldOverlap,
      title: 'Запайка ${formatMm(overlap)} мм — вне диапазона '
          '${formatMm(_minWeldOverlapMm)}–${formatMm(_maxWeldOverlapMm)} мм',
      explanation: 'Плёнка заходит под окантовку на запайку; при значении вне '
          'диапазона заготовка считается неверно: мало — шов рвётся по кромке, '
          'много — перерасход плёнки и бугор под лентой.',
      recommendation: 'Поставьте запайку 10–40 мм (обычно 25 мм) и проверьте '
          'размер заготовки в раскрое.',
    ));
  }
}

/// Подворот скрина — проверяется по каждой стороне.
///
/// Скрин подворачивается сам: подворот 40–60 мм держит люверс и даёт
/// заготовку 2080–2120 мм на готовое окно 2000 мм (по сторонам значения
/// складываются). Меньше 30 мм — ткань вырывается по люверсу, больше 80 мм —
/// перерасход ткани без пользы.
void _checkScreenHem(WindowParams params, List<TechCheck> checks) {
  if (!params.isScreen) return;
  for (final side in EdgeSide.values) {
    final hem = params.hemForSide(side);
    final field = hemFieldForSide(side);
    final name = side.label.toLowerCase();
    if (!hem.isFinite || hem <= 0) {
      checks.add(TechCheck(
        ruleId: 'screen-hem-missing',
        severity: TechSeverity.error,
        field: field,
        title: 'Подворот скрина не задан: $name',
        explanation: 'Без подворота скрин не за что закрепить: люверсы ставятся '
            'по линии подворота, а шов держит кромку. Сторона «$name» осталась '
            'без подворота.',
        recommendation: 'Поставьте подворот 40, 50 или 60 мм на каждую сторону.',
      ));
      continue;
    }
    if (hem < _minHemMm || hem > _maxHemMm) {
      checks.add(TechCheck(
        ruleId: 'screen-hem-range',
        severity: TechSeverity.warning,
        field: field,
        title: 'Подворот скрина, $name: ${formatMm(hem)} мм — вне обычного '
            'диапазона ${formatMm(_minHemMm)}–${formatMm(_maxHemMm)} мм',
        explanation: 'Подворот держит кольцо люверса и шов кромки. Узкий '
            'подворот вырывается по люверсу, широкий — лишний расход ткани.',
        recommendation: 'Для типового скрина берите подворот 40, 50 или 60 мм.',
      ));
    }
  }
}

/// Ширина готовой (сложенной) окантовки.
///
/// Лента уже 40 мм после складывания не держит кольцо люверса; шире 120 мм —
/// неоправданный расход тента и лишний вес по периметру. Отдельно проверяем
/// запайку: плёнка заходит под окантовку на [WindowParams.weldOverlapMm] с
/// каждой стороны, поэтому окантовка уже 2 × запайка оставляет шов без тела —
/// плёнке буквально не за что зацепиться. У скрина окантовки нет — правила
/// не применяются.
void _checkEdgeRolls(WindowParams params, List<TechCheck> checks) {
  if (params.isScreen) return;
  final narrow = <EdgeSide>[];
  final wide = <EdgeSide>[];
  final weakWeld = <EdgeSide>[];

  for (final side in EdgeSide.values) {
    final finished = WindowParams.finishedEdgeWidth(params.rollForSide(side));
    if (finished < _minFinishedEdgeMm) narrow.add(side);
    if (finished > _maxFinishedEdgeMm) wide.add(side);
    if (finished < params.weldOverlapMm + 15) weakWeld.add(side);
  }

  if (narrow.isNotEmpty) {
    checks.add(TechCheck(
      ruleId: 'edge-too-narrow',
      severity: TechSeverity.error,
      title: 'Окантовка уже ${formatMm(_minFinishedEdgeMm)} мм '
          '(${_sidesLabel(narrow)})',
      explanation: 'В узкую ленту не помещается кольцо люверса: тент под кольцом '
          'продавливается, люверс вырывает кромку.',
      recommendation: 'Поставьте на эти стороны рулон 100 мм (готовых 50 мм) '
          'или шире.',
    ));
  }

  if (wide.isNotEmpty) {
    checks.add(TechCheck(
      ruleId: 'edge-too-wide',
      severity: TechSeverity.warning,
      title: 'Окантовка шире ${formatMm(_maxFinishedEdgeMm)} мм '
          '(${_sidesLabel(wide)})',
      explanation: 'Перерасход тента и лишний вес по периметру; широкая лента '
          'тяжелее сваривается без складок.',
      recommendation: 'Для обычного окна хватает готовых 50–100 мм.',
    ));
  }

  if (weakWeld.isNotEmpty) {
    final minEdge = params.weldOverlapMm + 15;
    checks.add(TechCheck(
      ruleId: 'edge-weld-insufficient',
      severity: TechSeverity.error,
      title: 'Окантовка уже ${formatMm(minEdge)} мм — плёнке не за '
          'что зацепиться (${_sidesLabel(weakWeld)})',
      explanation: 'Плёнка заходит под окантовку на '
          '${formatMm(params.weldOverlapMm)} мм с каждой стороны; при готовой '
          'окантовке меньше ${formatMm(minEdge)} мм запайка съедает всю ленту '
          'и шов остаётся без тела.',
      recommendation: 'Возьмите рулон шире: 200 мм (готовых 100 мм) или '
          '240 мм (готовых 120 мм), либо уменьшите запайку.',
    ));
  }
}

// ——————————————————————— Правила по полотну ———————————————————————

/// Полотно плёнки.
///
/// Слишком узкая видимая плёнка (меньше 300 мм) — это уже не окно: окантовка,
/// напайка и люверсы съедают почти всё, полотно не держит форму. Большая
/// площадь (свыше 12 м²) на ветру собирает такую парусность, что нужны
/// дополнительные точки крепления или разбивка на секции со спайкой.
void _checkFilm(WindowParams params, WindowSpec spec, List<TechCheck> checks) {
  final bounds = spec.layers.filmVisibleBounds;
  if (bounds.width < _minFilmSideMm || bounds.height < _minFilmSideMm) {
    checks.add(TechCheck(
      ruleId: 'film-narrow',
      severity: TechSeverity.error,
      field: ParamField.bottomWidth,
      title: 'Плёнка ${formatMm(bounds.width)} × ${formatMm(bounds.height)} мм '
          '— уже ${formatMm(_minFilmSideMm)} мм',
      explanation: 'Окантовка, напайка и люверсы занимают почти всю ширину '
          'изделия: плёнке не остаётся места, окно не держит форму и '
          'собирается складками.',
      recommendation: 'Увеличьте габарит окна или возьмите окантовку уже — '
          'видимая плёнка должна быть не меньше ${formatMm(_minFilmSideMm)} мм.',
    ));
  }

  final area = spec.productAreaM2;
  if (area > _maxProductAreaM2) {
    checks.add(TechCheck(
      ruleId: 'film-area-large',
      severity: TechSeverity.warning,
      title: 'Площадь изделия ${formatMeters(area)} м² — больше '
          '${formatMeters(_maxProductAreaM2)} м²',
      explanation: 'Большое полотно парусит и работает как парус: нагрузка на '
          'люверсы и окантовку растёт, плёнку вытягивает.',
      recommendation: 'Разделите окно на секции со спайкой или добавьте '
          'промежуточные точки крепления и усиление по периметру.',
    ));
  }
}

// ——————————————————————— Правила по подъёмному окну ———————————————————————

/// Подъёмное окно.
///
/// Ремни считаются автоматически: 2 шт до 2 м, далее +1 на метр. Поэтому
/// отдельно предупреждаем не о количестве, а о нагрузке: с 2500 мм ремней
/// три и больше, и каждый держит всё более тяжёлое полотно — точки крепления
/// ремней к верхней окантовке надо усиливать. Высокое окно (свыше 3000 мм)
/// ещё и тяжело поднимать вручную: нужен помощник или лебёдка.
void _checkLifting(
  WindowParams params,
  WindowSpec spec,
  List<TechCheck> checks,
) {
  if (!params.isLifting) return;

  final width = spec.geometry.bottomWidth;
  if (width > _liftingStrapLoadWidthMm) {
    checks.add(TechCheck(
      ruleId: 'lifting-strap-load',
      severity: TechSeverity.warning,
      title: 'Подъёмное окно шириной ${formatMm(width)} мм — '
          '${params.liftStrapCount} ремня(ей)',
      explanation: 'Ремни считаются автоматически (2 шт до 2 м, далее +1 на метр), '
          'но с ростом ширины растёт нагрузка на каждый ремень и на верхнюю '
          'окантовку, к которой они крепятся.',
      recommendation: 'Усильте верхнюю окантовку в местах крепления ремней '
          'и проверьте, что окно поднимают за все ремни сразу.',
    ));
  }

  final height = spec.geometry.overallHeight;
  if (height > _liftingHardHeightMm) {
    checks.add(TechCheck(
      ruleId: 'lifting-height',
      severity: TechSeverity.warning,
      field: ParamField.leftHeight,
      title: 'Подъёмное окно высотой ${formatMm(height)} мм — тяжело '
          'поднимать',
      explanation: 'Полотно большой высоты поднимают вручную за ремни: чем выше '
          'окно, тем больше ход и масса, тем тяжелее работать и тем выше '
          'риск перекоса.',
      recommendation: 'Заложите подъём вдвоём или лебёдку, проверьте ход '
          'ремней и свободный вход полотна в окантовку.',
    ));
  }
}

// ——————————————————————— Правила по молниям ———————————————————————

/// Молнии в полотне.
///
/// Две молнии ближе 300 мм друг к другу неудобны в работе: створки мешают
/// друг другу, а между спайками остаётся узкая полоса плёнки. Спайка молнии
/// ближе 150 мм к кромке плёнки — это слабый шов: с одной стороны спайки
/// остаётся слишком мало полотна, и шов работает на отрыв. Молния выходит на
/// нижнюю кромку, где устроен карман: спайка и шов кармана делят одну
/// окантовку, а утяжителю нужно свободно заводиться в полость кармана.
void _checkZippers(
  WindowParams params,
  WindowSpec spec,
  List<TechCheck> checks,
) {
  if (params.zippers.isEmpty) return;

  final gaps = spec.layers.zipperGapsAll;
  for (var i = 0; i < gaps.length; i++) {
    final gap = gaps[i];
    if (gap.left < _minZipperToEdgeMm || gap.right < _minZipperToEdgeMm) {
      checks.add(TechCheck(
        ruleId: 'zipper-edge-near',
        severity: TechSeverity.warning,
        title: 'Молния №${i + 1}: от спайки до кромки плёнки меньше '
            '${formatMm(_minZipperToEdgeMm)} мм',
        explanation: 'С одной стороны спайки остаётся узкая полоса плёнки '
          '(слева ${formatMm(gap.left)} мм, справа ${formatMm(gap.right)} мм): '
          'шов слабый, при натяжении полотно рвёт вдоль спайки.',
        recommendation: 'Сместите молнию так, чтобы от спайки до кромок '
            'плёнки было не меньше ${formatMm(_minZipperToEdgeMm)} мм.',
      ));
    }
  }

  final bands = spec.layers.zipperBands;
  for (var i = 0; i < bands.length; i++) {
    for (var j = i + 1; j < bands.length; j++) {
      final distance = (bands[i].center.dx - bands[j].center.dx).abs();
      if (distance < _minZipperSpacingMm) {
        checks.add(TechCheck(
          ruleId: 'zipper-spacing-near',
          severity: TechSeverity.warning,
          title: 'Молнии №${i + 1} и №${j + 1} стоят в '
              '${formatMm(distance)} мм друг от друга',
          explanation: 'Две молнии ближе ${formatMm(_minZipperSpacingMm)} мм '
              'неудобны в эксплуатации: створки мешают друг другу, между '
              'спайками остаётся узкая полоса полотна.',
          recommendation: 'Разнесите молнии по ширине окна (например, на '
              'трети ширины) или оставьте одну.',
        ));
      }
    }
  }

  if (params.pocket || params.pocketTop) {
    checks.add(const TechCheck(
      ruleId: 'zipper-pocket-axis',
      severity: TechSeverity.warning,
      title: 'Молния в окне с карманом',
      explanation: 'Вертикальная молния доходит до кромки, где идёт карман: '
          'спайка молнии и шов кармана делят одну окантовку, а утяжителю '
          'нужно свободно заводиться в полость кармана.',
      recommendation: 'Сместите молнию от середины кармана, укоротите её до '
          'кармана или разорвите карман в месте прохода молнии.',
    ));
  }
}

// ——————————————————————— Правила по карману ———————————————————————

/// Карман под утяжитель.
///
/// Карман — это полость по нижней кромке, куда заводится утяжитель. Нижние
/// угловые люверсы в ней физически мешают: их либо не ставят, либо поднимают
/// на [pocketCornerOffset] мм. Геометрия делает это автоматически, поэтому
/// правило проверяет результат: если угловой крепёж всё-таки попал в зону
/// кармана — утяжителю некуда заводиться.
void _checkPocket(
  WindowParams params,
  WindowSpec spec,
  List<TechCheck> checks,
) {
  if (!params.pocket) return;

  final line = spec.layers.eyeletLine;
  if (line.length < 2) return;
  final bottomLeft = line[0];
  final bottomRight = line[1];

  final blockers = <String>[];
  for (final eyelet in spec.layers.eyelets) {
    final toLeft = (eyelet.center - bottomLeft).distance;
    final toRight = (eyelet.center - bottomRight).distance;
    if (toLeft < pocketCornerOffset - 1 || toRight < pocketCornerOffset - 1) {
      blockers.add('${eyelet.side.label} ${formatMm(toLeft < toRight ? toLeft : toRight)} мм');
    }
  }

  if (blockers.isNotEmpty) {
    checks.add(TechCheck(
      ruleId: 'pocket-corner-lifted',
      severity: TechSeverity.warning,
      title: 'Нижние угловые люверсы не подняты под карман',
      explanation: 'Крепёж стоит в зоне кармана (${blockers.join(', ')}): '
          'утяжителю некуда заводиться, а люверс продавливает шов кармана.',
      recommendation: 'Поднимите нижние угловые люверсы на '
          '${formatMm(pocketCornerOffset)} мм или уберите их — как это делает '
          'автоматическая раскладка кармана.',
    ));
  }
}

// ——————————————————————— Правила по вырезам ———————————————————————

/// Вырезы в полотне.
///
/// Вырез ближе 100 мм к окантовке оставляет тонкую перемычку: плёнка между
/// вырезом и швом не держит нагрузку и рвётся по кромке выреза. Круглый вырез
/// меньше 100 мм под трубу или стойку обычно не проходит — это чаще всего
/// ошибка в размере.
void _checkCutouts(WindowSpec spec, List<TechCheck> checks) {
  final bounds = spec.layers.filmVisibleBounds;
  final cutouts = spec.layers.cutouts;

  for (var i = 0; i < cutouts.length; i++) {
    final cutout = cutouts[i];
    final cutBounds = cutout.bounds;

    final bridge = <double>[
      cutBounds.left - bounds.left,
      bounds.right - cutBounds.right,
      cutBounds.top - bounds.top,
      bounds.bottom - cutBounds.bottom,
    ].reduce(math.min);

    if (bridge >= 0 && bridge < _minCutoutBridgeMm) {
      checks.add(TechCheck(
        ruleId: 'cutout-bridge-thin',
        severity: TechSeverity.warning,
        title: 'Вырез №${i + 1}: до окантовки всего ${formatMm(bridge)} мм',
        explanation: 'Между вырезом и швом окантовки остаётся тонкая перемычка '
            'меньше ${formatMm(_minCutoutBridgeMm)} мм — по ней плёнка рвётся '
            'при первой же нагрузке.',
        recommendation: 'Сместите вырез от кромки или уменьшите его так, чтобы '
            'до окантовки оставалось не меньше '
            '${formatMm(_minCutoutBridgeMm)} мм.',
      ));
    }

    if (cutout.isCircle && cutout.spec.width < _minRoundCutoutMm) {
      checks.add(TechCheck(
        ruleId: 'cutout-circle-small',
        severity: TechSeverity.info,
        title: 'Круглый вырез №${i + 1} Ø${formatMm(cutout.spec.width)} мм — '
            'меньше ${formatMm(_minRoundCutoutMm)} мм',
        explanation: 'Под трубу, стойку или вентиляцию такой диаметр обычно не '
            'проходит: скорее всего ошибка в размере или это дренаж, который '
            'делается иначе.',
        recommendation: 'Уточните, что заводится в отверстие, и при '
            'необходимости увеличьте диаметр до ${formatMm(_minRoundCutoutMm)} мм '
            'и больше.',
      ));
    }
  }
}

// ——————————————————————— Правила по спайке окон ———————————————————————

/// Спайка стороны с соседним окном.
///
/// На спаянной стороне окантовки нет — там сварены два полотна. Люверс в этом
/// шве рвёт тент: он пробивает сварку и работает на отрыв по шву. Поэтому
/// крепёж на спаянной стороне — предупреждение. Если спаяны обе боковые
/// стороны, окно жёстко зажато между соседями: при монтаже не остаётся
/// допуска на неточность замеров и температурное расширение.
void _checkWeldedSides(
  WindowParams params,
  WindowSpec spec,
  List<TechCheck> checks,
) {
  if (params.weldedSides.isEmpty) return;

  if (!params.removeEyeletsOnWelded) {
    final withFastener = <EdgeSide>[];
    for (final side in params.weldedSides) {
      final windowSide = _windowSide(side);
      if (spec.layers.eyelets.any((eyelet) => eyelet.side == windowSide)) {
        withFastener.add(side);
      }
    }
    if (withFastener.isNotEmpty) {
      checks.add(TechCheck(
        ruleId: 'welded-side-fastener',
        severity: TechSeverity.warning,
        title: 'На спаянной стороне остался крепёж '
            '(${_sidesLabel(withFastener)})',
        explanation: 'Люверс пробивает шов сварки двух полотен и рвёт тент именно '
            'по шву: спайка держит полотно сама, точечный крепёж там лишний.',
        recommendation: 'Включите удаление крепежа на спаянных сторонах или '
            'снимите люверсы с ${_sidesLabel(withFastener)} вручную.',
      ));
    }
  }

  final weldedLeft = params.isWelded(EdgeSide.left);
  final weldedRight = params.isWelded(EdgeSide.right);
  if (weldedLeft && weldedRight) {
    checks.add(const TechCheck(
      ruleId: 'welded-both-sides',
      severity: TechSeverity.warning,
      title: 'Спаяны обе боковые стороны — окно зажато между соседями',
      explanation: 'Окно жёстко зафиксировано с двух сторон: нет допуска на '
          'неточность замера и на температурное расширение, монтаж придётся '
          'делать строго по месту.',
      recommendation: 'Проверьте замеры соседних окон и порядок монтажа: '
          'такое окно ставят после соседей, с контролем диагоналей.',
    ));
  }
}

// ——————————————————————— Правила по крепежу ———————————————————————

/// Крепёж окна.
///
/// У глухого окна по технологии только круглые люверсы: овальный люверс под
/// скобу там не держит. Если пользователь выбрал овальный — он не попадёт на
/// чертёж, об этом надо сказать. Подъёмное окно с крепежом «только люверсы»
/// поднимать нечем: за люверс не тянут, нужны скобы, замки или ремни.
void _checkFastener(WindowParams params, List<TechCheck> checks) {
  // Скрин крепится только люверсами: выбранный крепёж игнорируется.
  if (params.isScreen) {
    if (params.fastenerType != FastenerType.eyeletsOnly) {
      checks.add(const TechCheck(
        ruleId: 'screen-fastener-ignored',
        severity: TechSeverity.info,
        title: 'Крепёж скрина: только люверсы',
        explanation: 'Скрин крепится по подвороту люверсами; скобы, замки и '
            'ремни в нём не ставятся, поэтому выбранный тип крепежа не '
            'учитывается.',
        recommendation: 'Для скрина оставьте «Только люверсы» — остальное '
            'приложение проигнорирует.',
      ));
    }
    return;
  }

  if (params.windowType == WindowType.fixed &&
      params.eyeletType != EyeletType.round10) {
    checks.add(const TechCheck(
      ruleId: 'fixed-window-oval-eyelet',
      severity: TechSeverity.warning,
      title: 'Для глухого окна выбран овальный люверс',
      explanation: 'У глухого окна крепёж — саморезы по окантовке, овальный люверс '
          'под скобу там не нужен; при расчёте он всё равно заменяется на '
          'круглый Ø10 мм.',
      recommendation: 'Выберите круглый люверс Ø10 мм или переключите окно на '
          'подъёмное, если планируется скоба.',
    ));
  }

  if (params.isLifting && params.fastenerType == FastenerType.eyeletsOnly) {
    checks.add(const TechCheck(
      ruleId: 'lifting-eyelets-only',
      severity: TechSeverity.warning,
      title: 'Подъёмное окно с крепежом «только люверсы»',
      explanation: 'Поднимать полотно нечем: люверс не держит рывок, он только '
          'фиксирует край. Для подъёма нужны скобы, замки или ремни, за '
          'которые тянут.',
      recommendation: 'Выберите поворотные скобы, французский замок или '
          'силиконовые ремни для низа и боков.',
    ));
  }
}

// ——————————————————————— Усадка и сечение ———————————————————————

/// Усадка ПВХ.
///
/// Типовая усадка плёнки — 1–2 % (её и компенсирует раскрой). Больше 3 % —
/// признак другой партии или другого производителя: деталь может уйти в
/// минус по размеру после прогрева на солнце.
void _checkShrinkage(WindowParams params, List<TechCheck> checks) {
  final shrinkage = params.shrinkagePercent;
  if (shrinkage.isFinite && shrinkage > _maxShrinkagePercent) {
    checks.add(TechCheck(
      ruleId: 'shrinkage-high',
      severity: TechSeverity.warning,
      field: ParamField.shrinkagePercent,
      title: 'Усадка ${formatPercent(shrinkage)} — выше '
          '${formatPercent(_maxShrinkagePercent)}',
      explanation: 'Типовая усадка ПВХ 1–2 %. Большее значение говорит о другой '
          'партии или поставщике; при ошибке изделие уйдёт в минус по размеру.',
      recommendation: 'Уточните усадку партии у поставщика и подтвердите '
          'припуск на раскрой.',
    ));
  }
}

/// Сечение окна: разница низа и верха.
///
/// Если низ и верх отличаются больше чем на 500 мм, а окно высокое (от
/// [tallWindowMm] мм), боковые швы идут с большим скосом: трапецию сложнее
/// сварить без складок, окантовку приходится тянуть по косой, а полотно
/// сильнее уводит при раскрое.
void _checkSection(
  WindowParams params,
  WindowSpec spec,
  List<TechCheck> checks,
) {
  final bottom = params.bottomWidth;
  final top = params.topWidth;
  if (!bottom.isFinite || !top.isFinite) return;

  final diff = (bottom - top).abs();
  if (diff > _maxWidthDiffMm && spec.geometry.overallHeight >= _tallWindowMm) {
    checks.add(TechCheck(
      ruleId: 'section-large-diff',
      severity: TechSeverity.warning,
      field: ParamField.topWidth,
      title: 'Низ и верх отличаются на ${formatMm(diff)} мм при высоте '
          '${formatMm(spec.geometry.overallHeight)} мм',
      explanation: 'Высокая трапеция со скосом больше ${formatMm(_maxWidthDiffMm)} мм '
          'сваривается со складками: боковые швы идут по косой, окантовку '
          'тянет и полотно уводит при раскрое.',
      recommendation: 'Проверьте замеры, разбейте окно по высоте или '
          'согласуйте раскладку косых сторон с технологом.',
    ));
  }
}

// ——————————————————————— Правила по заказу ———————————————————————

/// Окна с одинаковыми параметрами.
///
/// Дубли — это не ошибка, но их полезно видеть: одинаковые окна считаются и
/// кроятся одинаково, а разница только в маркировке. Если дубль появился
/// случайно, его лучше объединить в позицию с количеством.
void _checkDuplicateWindows(OrderProject project, List<TechCheck> checks) {
  final groups = <String, List<int>>{};
  for (var i = 0; i < project.windows.length; i++) {
    final key = _techSignature(project.windows[i]);
    groups.putIfAbsent(key, () => <int>[]).add(i);
  }

  for (final group in groups.values) {
    if (group.length < 2) continue;
    final numbers = [for (final index in group) '№${index + 1}'];
    final label = numbers.length == 2
        ? '${numbers[0]} и ${numbers[1]}'
        : '${numbers.sublist(0, numbers.length - 1).join(', ')} и '
            '${numbers.last}';
    checks.add(TechCheck(
      ruleId: 'order-duplicate-window',
      severity: TechSeverity.info,
      title: 'Окна $label совпадают по параметрам',
      explanation: 'Совпадают все технологические параметры: размеры, окантовка, '
          'люверсы, молнии, вырезы и спайки. Различается только маркировка.',
      recommendation: 'Проверьте, не появился ли дубль случайно: одинаковые '
          'окна удобно держать одной позицией с количеством.',
    ));
  }
}

/// Число разных материалов плёнки в заказе.
///
/// Каждый материал раскладывается на своём рулоне со своей шириной и своим
/// отходом. Чем больше материалов, тем сложнее раскладка и тем больше обрезков.
void _checkOrderMaterials(OrderProject project, List<TechCheck> checks) {
  final materials = {for (final window in project.windows) window.material};
  if (materials.length > 2) {
    checks.add(const TechCheck(
      ruleId: 'order-many-materials',
      severity: TechSeverity.warning,
      title: 'В заказе больше двух разных материалов плёнки',
      explanation: 'Каждый материал кроится на своём рулоне: раскладка усложняется, '
          'растёт отход и риск перепутать заготовки.',
      recommendation: 'Проверьте, нельзя ли свести заказ к одному-двум '
          'материалам, и разложите окна по материалам при раскрое.',
    ));
  }
}

/// Суммарная площадь заказа.
///
/// Больше 40 м² — это уже не одно изделие, а партия: нужно планировать сроки,
/// расход рулонов и место в цехе.
void _checkOrderArea(OrderProject project, List<TechCheck> checks) {
  var area = 0.0;
  for (final window in project.windows) {
    area += WindowSpec.of(window).productAreaM2;
  }
  if (area > _largeOrderAreaM2) {
    checks.add(TechCheck(
      ruleId: 'order-area-large',
      severity: TechSeverity.info,
      title: 'Суммарная площадь заказа ${formatMeters(area)} м²',
      explanation: 'Это партия больше ${formatMeters(_largeOrderAreaM2)} м²: важно '
          'заранее проверить наличие рулонов, сроки сварки и место в цехе.',
      recommendation: 'Проверьте сроки и раскрой до запуска: заложите запас по '
          'рулонам и людям.',
    ));
  }
}

// ——————————————————————— Служебное ———————————————————————

/// Технологическая подпись окна: всё, кроме маркировки. По ней ищем дубли.
String _techSignature(WindowParams params) => params
    .copyWith(drawingNumber: '', projectName: '', customer: '')
    .signature;

/// Русская подпись стороны окна для текста проверки.
String _sidesLabel(List<EdgeSide> sides) =>
    sides.map((side) => _sideLabel(side)).join(', ');

String _sideLabel(EdgeSide side) => switch (side) {
      EdgeSide.bottom => 'низ',
      EdgeSide.right => 'право',
      EdgeSide.top => 'верх',
      EdgeSide.left => 'лево',
    };

/// Сторона окна в терминах геометрии.
WindowSide _windowSide(EdgeSide side) => switch (side) {
      EdgeSide.bottom => WindowSide.bottom,
      EdgeSide.right => WindowSide.right,
      EdgeSide.top => WindowSide.top,
      EdgeSide.left => WindowSide.left,
    };

/// Сортировка по важности: ошибки, замечания, справки.
List<TechCheck> _sorted(List<TechCheck> checks) {
  final result = <TechCheck>[...checks];
  result.sort((a, b) {
    final bySeverity = a.severity.rank.compareTo(b.severity.rank);
    if (bySeverity != 0) return bySeverity;
    return (a.windowIndex ?? -1).compareTo(b.windowIndex ?? -1);
  });
  return List.unmodifiable(result);
}
