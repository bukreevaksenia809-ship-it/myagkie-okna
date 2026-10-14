import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';

/// Диаметр дренажного отверстия в нижней окантовке, мм — как в примечаниях
/// приложения («Дренаж: N отв. Ø6 мм в нижней окантовке»).
const double techDrainHoleDiameter = 6;

/// Типовая скорость сварки ПВХ горячим воздухом. Температура (400–500 °C)
/// берётся из [EdgeMaterial.joining], скорость — типовой режим, который
/// уточняется пробным швом на обрезке.
const String techWeldSpeedHint = '2–3 м/мин';

/// Вид операции. По нему строится порядок операций и оформление листа.
enum TechOperationKind {
  cutting('Раскрой'),
  welding('Сварка'),
  weldNeighbor('Спайка окон'),
  edging('Окантовка'),
  hem('Подворот'),
  eyelets('Люверсы'),
  zipper('Молнии'),
  cutouts('Вырезы'),
  pocket('Карман'),
  straps('Ремни'),
  drain('Дренаж'),
  control('Контроль');

  const TechOperationKind(this.label);

  final String label;
}

/// Материал или заготовка одной операции с размером и количеством.
///
/// Числа не выдумываются: размеры берутся из [WindowSpec] и [WindowLayers],
/// количество — из параметров окна, [quantity] хранится для расчётов и тестов.
class TechMaterial {
  const TechMaterial({
    required this.name,
    required this.size,
    this.quantity,
    this.unit = 'мм',
    this.roll,
    this.side,
    this.note,
  });

  /// Название материала или заготовки.
  final String name;

  /// Размер словами: «1 450 × 2 470 мм», «24 шт».
  final String size;

  /// Числовое количество в [unit] — для суммирования и проверок.
  final double? quantity;

  /// Единица измерения количества: мм, шт, м².
  final String unit;

  /// Тип рулона окантовки (только для позиций окантовки): ширина рулона, мм.
  final double? roll;

  /// Сторона окна (только для позиций окантовки и спаек).
  final String? side;

  /// Пояснение к позиции.
  final String? note;

  /// Готовая подпись для таблицы: «Низ: Тент 100 мм — 1 500 мм (полоса 50 мм)».
  String get label {
    final buffer = StringBuffer();
    if (side != null && side!.isNotEmpty) buffer.write('$side: ');
    buffer.write(name);
    if (size.isNotEmpty) buffer.write(' — $size');
    if (note != null && note!.isNotEmpty) buffer.write(' ($note)');
    return buffer.toString();
  }
}

/// Одна операция технологической карты.
class TechOperation {
  const TechOperation({
    required this.number,
    required this.kind,
    required this.title,
    required this.description,
    required this.tool,
    required this.control,
    this.materials = const [],
    this.edgeTotals = const {},
    this.source = '',
  });

  /// Номер по порядку, с единицы.
  final int number;

  final TechOperationKind kind;

  /// Короткое название операции: «Раскрой плёнки», «Окантовка», «Люверсы».
  final String title;

  /// Что делать и какими размерами.
  final String description;

  /// Материалы и заготовки операции.
  final List<TechMaterial> materials;

  /// Чем делать.
  final String tool;

  /// Что проверить по этой операции.
  final String control;

  /// Суммарный расход по ширинам рулонов — заполняется у операции «Окантовка»
  /// и совпадает с [WindowLayers.edgeConsumption].
  final Map<double, double> edgeTotals;

  /// Откуда взяты числа операции (поле модели) — для разбора в цехе.
  final String source;

  /// Материалы одной строкой, каждый с новой строки.
  String get materialsText =>
      materials.isEmpty ? '—' : materials.map((m) => m.label).join('\n');

  /// Весь текст операции — для подписей и проверок.
  String get text =>
      [title, description, materialsText, tool, control].join(' ');
}

/// Технологическая карта одного окна.
///
/// Карта строится только из модели окна: [WindowSpec] и [WindowLayers].
/// Никаких отдельных расчётных чисел — все размеры на листе сходятся
/// с чертежом, ведомостью расхода и раскладкой.
class TechCard {
  TechCard._(this.params, this.spec, this.index, this.operations);

  /// Карта одного окна. [index] — номер окна в заказе, с единицы.
  factory TechCard.forWindow(WindowParams params, {int index = 1}) {
    final spec = WindowSpec.of(params);
    return TechCard._(params, spec, index, _buildOperations(spec, index));
  }

  /// Карты всех окон заказа: по одной карте на окно, в порядке заказа.
  static List<TechCard> forOrder(OrderProject project) => [
    for (var i = 0; i < project.windows.length; i++)
      TechCard.forWindow(project.windows[i], index: i + 1),
  ];

  final WindowParams params;
  final WindowSpec spec;

  /// Номер окна в заказе, с единицы.
  final int index;

  /// Операции в технологическом порядке.
  final List<TechOperation> operations;

  /// Заголовок карты: «Окно №1».
  String get title => 'Окно №$index';

  /// Габарит изделия: «1 500 × 2 520 мм».
  String get dimensionsLabel =>
      '${formatMm(spec.geometry.spanX)} × '
      '${formatMm(spec.geometry.overallHeight)} мм';

  /// Тип окна строчными: «глухое», «подъёмное».
  String get typeLabel => params.windowType.label.toLowerCase();

  /// Подпись под заголовком: окантовка, люверсы, крепёж.
  String get subtitle => params.isScreen
      ? 'Скрин без тента: подворот ${params.hemBySideShortLabel} '
          '(низ/право/верх/лево), шов ${formatMm(screenSeamMm)} мм · заготовка '
          '${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} мм · '
          'люверсы: ${spec.eyeletCount} шт, шаг ${spec.eyeletStepLabel} · '
          'крепёж: только люверсы'
      : 'Окантовка: ${spec.edgeBySideSummary} · '
          'плёнка в раскрое с припуском и усадкой: '
          '${formatMm(spec.filmCutWidthWithShrinkage)} × '
          '${formatMm(spec.filmCutHeightWithShrinkage)} мм · '
          'люверсы: ${spec.eyeletCount} шт, шаг ${spec.eyeletStepLabel} · '
          'крепёж: ${spec.fastenerSummary.toLowerCase()}';

  /// Расход окантовки по ширинам рулонов — из модели.
  Map<double, double> get edgeTotals => spec.edgeConsumption;

  /// Всего окантовки, мм.
  double get edgeTotalMm =>
      edgeTotals.values.fold(0, (sum, value) => sum + value);

  int get eyeletCount => spec.eyeletCount;

  /// Суммарный расход окантовки по всем картам заказа.
  static Map<double, double> orderEdgeTotals(Iterable<TechCard> cards) {
    final totals = <double, double>{};
    for (final card in cards) {
      card.edgeTotals.forEach((roll, length) {
        totals[roll] = (totals[roll] ?? 0) + length;
      });
    }
    return totals;
  }

  /// Люверсы заказа по типам: тип → количество.
  static Map<EyeletType, int> orderEyeletsByType(Iterable<TechCard> cards) {
    final totals = <EyeletType, int>{};
    for (final card in cards) {
      totals.update(
        card.spec.eyeletType,
        (value) => value + card.eyeletCount,
        ifAbsent: () => card.eyeletCount,
      );
    }
    return totals;
  }

  /// Подписи расхода окантовки: «Тент 100 мм — 654 см».
  static List<String> edgeTotalLabels(Map<double, double> totals) {
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        '${edgeBandLabel(entry.key)} — ${formatCm(entry.value)} см',
    ];
  }
}

/// Строит операции окна в технологическом порядке:
/// раскрой → сварка → спайка окон → окантовка → люверсы → фурнитура →
/// контроль и упаковка.
List<TechOperation> _buildOperations(WindowSpec spec, int index) {
  final params = spec.params;
  final geometry = spec.geometry;
  final layers = spec.layers;
  final operations = <TechOperation>[];
  var number = 0;

  void add({
    required TechOperationKind kind,
    required String title,
    required String description,
    required String tool,
    required String control,
    List<TechMaterial> materials = const [],
    Map<double, double> edgeTotals = const {},
    String source = '',
  }) {
    number += 1;
    operations.add(
      TechOperation(
        number: number,
        kind: kind,
        title: title,
        description: description,
        materials: materials,
        tool: tool,
        control: control,
        edgeTotals: edgeTotals,
        source: source,
      ),
    );
  }

  final visible = layers.filmVisibleBounds;
  final isScreen = params.isScreen;

  // ---------------------------------------------------------- 1. раскрой
  if (isScreen) {
    add(
      kind: TechOperationKind.cutting,
      title: 'Раскрой скрина',
      description:
          'Отрезать полотно скрина по заготовке: готовый размер '
          '${formatMm(geometry.spanX)} × ${formatMm(geometry.overallHeight)} мм '
          'плюс подворот по сторонам — ${params.hemBySideLabel} '
          '(низ/право/верх/лево) → '
          '${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} мм'
          '${params.hasAllowance ? ', плюс припуск на раскрой '
                    '${params.allowanceWidthLabel} по ширине и '
                    '${params.allowanceHeightLabel} по высоте' : ''}. '
          'Усадки у скрина нет. Раскрой вести по длинной стороне рулона, '
          'кромку не подрезать.',
      materials: [
        TechMaterial(
          name: '${params.material.label} (${params.material.thickness})',
          size:
              '${formatMm(spec.filmCutWidthWithAllowance)} × '
              '${formatMm(spec.filmCutHeightWithAllowance)} мм',
          note:
              'готовый размер ${formatMm(geometry.spanX)} × '
              '${formatMm(geometry.overallHeight)} мм плюс подворот по сторонам '
              '${params.hemBySideShortLabel} (низ/право/верх/лево)',
        ),
        TechMaterial(
          name: 'Площадь заготовки (габарит) в раскрое',
          size: '${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²',
          note: 'расход скрина считается по площади заготовки, без вырезов',
        ),
      ],
      tool: 'Раскроечный стол, дисковый нож, рулетка, угольник, маркер',
      control:
          'Габарит ${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} мм (±5 мм), углы 90°, '
          'кромка ровная без задиров и волн',
      source:
          'WindowSpec.filmCutWidthWithAllowance / filmCutHeightWithAllowance '
          '(готовый размер + подворот по сторонам: WindowParams.hemBottomMm / '
          'hemRightMm / hemTopMm / hemLeftMm)',
    );
  } else {
    add(
      kind: TechOperationKind.cutting,
      title: 'Раскрой плёнки',
      description:
          'Отрезать полотно по раскрою: видимый размер '
          '${formatMm(visible.width)} × ${formatMm(visible.height)} мм, плюс '
          'запайка ${formatMm(params.weldOverlapMm)} мм с каждой стороны'
          '${params.hasAllowance ? ', плюс припуск на раскрой '
                    '${params.allowanceWidthLabel} по ширине и '
                    '${params.allowanceHeightLabel} по высоте' : ''}'
          ', плюс усадка '
          '${formatPercent(params.effectiveShrinkagePercent)}. Раскрой вести '
          'по длинной стороне рулона, кромку не подрезать.',
      materials: [
        TechMaterial(
          name: '${params.material.label} (${params.material.thickness})',
          size:
              '${formatMm(spec.filmCutWidthWithShrinkage)} × '
              '${formatMm(spec.filmCutHeightWithShrinkage)} мм',
          note:
              'до усадки ${formatMm(spec.filmCutWidthWithAllowance)} × '
              '${formatMm(spec.filmCutHeightWithAllowance)} мм'
              '${params.hasAllowance ? ' (с припуском на раскрой)' : ''}',
        ),
        TechMaterial(
          name: 'Площадь заготовки (габарит) с усадкой',
          size: '${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²',
          note: 'с припуском на раскрой и усадкой, без площади вырезов',
        ),
      ],
      tool: 'Раскроечный стол, дисковый нож, рулетка, угольник, маркер',
      control:
          'Габарит ${formatMm(spec.filmCutWidthWithShrinkage)} × '
          '${formatMm(spec.filmCutHeightWithShrinkage)} мм (±5 мм), углы 90°, '
          'кромка ровная без задиров и волн',
      source:
          'WindowSpec.filmCutWidthWithShrinkage / filmCutHeightWithShrinkage '
          '(припуск на раскрой + усадка)',
    );
  }

  // ------------------------------------- 2. подворот скрина / напайка ПВХ
  final isWeldedEdge = params.edgeMaterial.isWelded;
  if (isScreen) {
    // Скрин подворачивается сам: вместо напайки под окантовку — подворот
    // по периметру и шов 3 мм. Подворот перечисляется по каждой стороне:
    // на трапеции и на окне со спайкой стороны бывают разными.
    final hemBySide = <String>[
      for (final side in EdgeSide.values)
        '${side.label.toLowerCase()} ${formatMm(params.hemForSide(side))} мм',
    ].join(', ');
    final hemControl = <String>[
      for (final side in EdgeSide.values)
        '${side.label.toLowerCase()} ${formatMm(params.hemForSide(side))} ± 2 мм',
    ].join(', ');
    add(
      kind: TechOperationKind.hem,
      title: 'Подворот и шов ${formatMm(screenSeamMm)} мм',
      description:
          'Завернуть материал по периметру на подворот по сторонам — '
          '$hemBySide (низ/право/верх/лево), всего по периметру '
          '${formatMm(geometry.perimeter)} мм, и сварить горячим воздухом '
          'швом ${formatMm(screenSeamMm)} мм с каждой стороны. '
          'Скорость сварки $techWeldSpeedHint, режим уточнить пробным швом '
          'на обрезке. Тента и окантовки у скрина нет.',
      materials: [
        for (final side in EdgeSide.values)
          TechMaterial(
            name: 'Подворот скрина',
            size: '${formatMm(params.hemForSide(side))} мм',
            quantity: params.hemForSide(side),
            side: side.label,
            note: 'шов ${formatMm(screenSeamMm)} мм',
          ),
        TechMaterial(
          name: 'Длина подворота по периметру',
          size: '${formatMm(geometry.perimeter)} мм',
          quantity: geometry.perimeter,
          note: 'периметр готового изделия; расход скрина считается по площади '
              'заготовки',
        ),
      ],
      tool: 'Фен-сварочник (горячий воздух), прижимной ролик, термометр',
      control:
          'Подворот по сторонам: $hemControl; шов '
          '${formatMm(screenSeamMm)} ± 0,5 мм; без прожогов, отслоений и '
          'пропусков; полотно не стянуто',
      source: 'WindowParams.hemBottomMm / hemRightMm / hemTopMm / hemLeftMm; '
          'screenSeamMm = 3 мм',
    );
  } else {
    add(
      kind: TechOperationKind.welding,
      title: isWeldedEdge
          ? 'Напайка: сварка с окантовкой'
          : 'Напайка: шитьё окантовки',
      description:
          'Плёнку завести под окантовку на запайку '
          '${formatMm(params.weldOverlapMm)} мм по всему периметру '
          '(${formatMm(geometry.perimeter)} мм). '
          'Соединение: ${params.edgeMaterial.joining}. '
          '${isWeldedEdge ? 'Скорость сварки $techWeldSpeedHint, режим уточнить '
                    'пробным швом на обрезке.' : 'Шов ровный, без посадки полотна.'}',
      materials: [
        TechMaterial(
          name: 'Припуск плёнки под окантовку (запайка)',
          size: '${formatMm(params.weldOverlapMm)} мм на сторону',
          note: 'периметр окна ${formatMm(geometry.perimeter)} мм',
        ),
      ],
      tool: isWeldedEdge
          ? 'Фен-сварочник (горячий воздух), прижимной ролик, термометр'
          : 'Промышленная швейная машина, лапка, прочные нитки',
      control:
          'Шов без прожогов, отслоений и пропусков; запайка '
          '${formatMm(params.weldOverlapMm)} ± 2 мм; полотно не стянуто',
      source: 'WindowParams.weldOverlapMm (5…60 мм); EdgeMaterial.joining',
    );
  }

  // ------------------------------------------ 3. спайка с соседним окном
  if (params.weldedSides.isNotEmpty) {
    final sideLengths = geometry.sideLengths;
    final weldedMaterials = <TechMaterial>[];
    for (var i = 0; i < EdgeSide.values.length && i < sideLengths.length; i++) {
      if (!layers.isSideWelded(i)) continue;
      weldedMaterials.add(
        TechMaterial(
          name:
              'Спайка с соседним окном внахлёст '
              '${formatMm(windowWeldWidth)} мм',
          size: '${formatMm(sideLengths[i])} мм',
          quantity: sideLengths[i],
          side: EdgeSide.values[i].label,
        ),
      );
    }
    add(
      kind: TechOperationKind.weldNeighbor,
      title: 'Спайка с соседним окном',
      description:
          '${spec.weldSummary}. Сварку вести с двух сторон шва, шов '
          'прогреть до однородного валика.',
      materials: weldedMaterials,
      tool: 'Фен-сварочник (горячий воздух), прижимной ролик, струбцины',
      control:
          'Шов по всей длине ${formatMm(layers.weldLengthMm)} мм, без '
          'расслоения; плоскости соседних окон совпадают, зазоров нет',
      source: 'WindowParams.weldedSides / WindowLayers.weldLengthMm',
    );
  }

  // -------------------------------------------------------- 4. окантовка
  // У скрина окантовки нет: тент не ставится, вместо него подворот (выше).
  if (!isScreen) {
    final sideLengths = geometry.sideLengths;
    final edgeTotals = <double, double>{};
    final edgeMaterials = <TechMaterial>[];
    for (var i = 0; i < EdgeSide.values.length && i < sideLengths.length; i++) {
      if (layers.isSideWelded(i)) continue;
      final roll = layers.rolls[i];
      final length = sideLengths[i];
      edgeTotals[roll] = (edgeTotals[roll] ?? 0) + length;
      edgeMaterials.add(
        TechMaterial(
          name:
              '${edgeBandLabel(roll)} → полоса '
              '${formatMm(WindowParams.finishedEdgeWidth(roll))} мм '
              '(сложить пополам)',
          size: '${formatMm(length)} мм',
          quantity: length,
          roll: roll,
          side: EdgeSide.values[i].label,
        ),
      );
    }
    for (final cutout in layers.cutouts) {
      final roll = layers.rolls[0];
      final perimeter = cutout.perimeterMm;
      edgeTotals[roll] = (edgeTotals[roll] ?? 0) + perimeter;
      edgeMaterials.add(
        TechMaterial(
          name: '${edgeBandLabel(roll)} → окантовка выреза',
          size: '${formatMm(perimeter)} мм',
          quantity: perimeter,
          roll: roll,
          note: cutout.isCircle
              ? 'Ø${formatMm(cutout.spec.width)} мм'
              : '${formatMm(cutout.spec.width)} × '
                    '${formatMm(cutout.spec.height)} мм',
        ),
      );
    }
    final totalsText = edgeTotals.isEmpty
        ? 'все стороны спаяны с соседними окнами — окантовка не ставится'
        : TechCard.edgeTotalLabels(edgeTotals).join(', ');
    add(
      kind: TechOperationKind.edging,
      title: 'Окантовка',
      description:
          'Окантовку цвета «${params.edgeColor.label.toLowerCase()}» '
          '(${params.edgeMaterial.label}) сложить пополам по всей длине: готовая '
          'полоса — половина рулона (пресеты: 100 → 50 мм, 200 → 100 мм, '
          '240 → 120 мм; свою ширину на каждую сторону мастер берёт из карты). '
          'Полосу наложить на плёнку с запайкой '
          '${formatMm(params.weldOverlapMm)} мм и '
          '${isWeldedEdge ? 'приварить' : 'пришить'}. Итого по ширинам: '
          '$totalsText.',
      materials: edgeMaterials,
      tool: isWeldedEdge
          ? 'Раскроечный стол, нож, линейка; фен-сварочник, прижимной ролик'
          : 'Раскроечный стол, нож, линейка; швейная машина',
      control:
          'Полоса сложена ровно, кромки совпадают, готовая ширина равна '
          'половине рулона; ширина каждой стороны — из карты; стыки сторон без '
          'зазоров и нахлёстов',
      edgeTotals: edgeTotals,
      source:
          'WindowLayers.edgeConsumption (стороны без спаек + контуры вырезов)',
    );
  }

  // ---------------------------------------------------------- 5. люверсы
  final eyeletType = spec.eyeletType;
  final roundCount = layers.eyelets
      .where((eyelet) => layers.typeFor(eyelet).isRound)
      .length;
  final ovalCount = spec.eyeletCount - roundCount;
  add(
    kind: TechOperationKind.eyelets,
    title: 'Люверсы',
    description:
        'Установить люверсы ${eyeletType.label.toLowerCase()} — всего '
        '${spec.eyeletCount} шт, шаг ${spec.eyeletStepLabel} (номинал '
        '${formatMm(params.eyeletStep)} мм), отступ от угла '
        '${formatMm(params.eyeletCornerOffset)} мм. В углах только круглые '
        '${EyeletType.round10.label}: овальный люверс угол не держит. '
        '${isScreen ? 'Люверсы ставятся по линии подворота; крепёж скрина — '
                  'только люверсы, без скоб, замков и ремней.' : params.isLifting ? '${spec.fastenerSummary}: сверху ряд люверсов под '
                  'саморезы, низ и бока — '
                  '${params.fastenerType.label.toLowerCase()}.' : 'Крепёж: '
                  '${spec.fastenerSummary.toLowerCase()}.'}',
    materials: [
      if (roundCount > 0)
        TechMaterial(
          name: ovalCount > 0
              ? 'Люверсы ${EyeletType.round10.label} (в углах)'
              : 'Люверсы ${EyeletType.round10.label}',
          size: '$roundCount шт',
          quantity: roundCount.toDouble(),
          unit: 'шт',
        ),
      if (ovalCount > 0)
        TechMaterial(
          name: 'Люверсы ${eyeletType.label}',
          size: '$ovalCount шт',
          quantity: ovalCount.toDouble(),
          unit: 'шт',
          note: 'кроме углов',
        ),
      if (params.isLifting && !isScreen) ...[
        TechMaterial(
          name: 'Саморезы по верхнему ряду',
          size: '${layers.topEyelets.length} шт',
          quantity: layers.topEyelets.length.toDouble(),
          unit: 'шт',
          note: 'верхняя кромка крепится к раме',
        ),
        TechMaterial(
          name:
              'Крепёж низа и боков: '
              '${params.fastenerType.label.toLowerCase()}',
          size: '${layers.movableSideEyelets.length} шт',
          quantity: layers.movableSideEyelets.length.toDouble(),
          unit: 'шт',
          note: 'кроме углов — там круглые люверсы',
        ),
      ],
    ],
    tool: 'Пресс для люверсов, пробойник, наковальня, молоток',
    control:
        'Шаг ${spec.eyeletStepLabel} (±5 мм), отступ от угла '
        '${formatMm(params.eyeletCornerOffset)} мм; люверсы зажаты без '
        'перекосов и задиров, полотно между ними не порвано',
    source: 'WindowLayers.eyelets / eyeletStepLabel / typeFor',
  );

  // ----------------------------------------------------------- 6. молнии
  // Молния впаивается в полосу тента — у скрина её нет.
  if (params.zippers.isNotEmpty && !isScreen) {
    final bands = layers.zipperBands;
    final zipperMaterials = <TechMaterial>[];
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      zipperMaterials
        ..add(
          TechMaterial(
            name: 'Молния №${i + 1} (вертикальная)',
            size: '${formatMm(band.height)} мм',
            quantity: band.height,
            note: 'впаивается в полосу тента по центру',
          ),
        )
        ..add(
          TechMaterial(
            name: 'Полоса тента под молнию №${i + 1}',
            size: '${formatMm(band.width)} × ${formatMm(band.height)} мм',
            note: 'спайка ${formatMm(band.width)} мм',
          ),
        );
    }
    add(
      kind: TechOperationKind.zipper,
      title: 'Молнии',
      description:
          '${params.zippers.length == 1 ? 'Впаять молнию' : 'Впаять молнии'}: '
          '${spec.zippersSummary}. Полосу тента с молнией сварить с полотном по '
          'всей высоте, шов ровный, полотно без волны.',
      materials: zipperMaterials,
      tool: isWeldedEdge
          ? 'Фен-сварочник, прижимной ролик, шаблон для ровной укладки'
          : 'Швейная машина, лапка для молнии, прочные нитки',
      control:
          'Молния вертикальна и не смещена, ширина спайки '
          '${formatMm(params.zipperBandWidth)} ± 2 мм, бегунок ходит свободно',
      source: 'WindowLayers.zipperBands / WindowSpec.zippersSummary',
    );
  }

  // ---------------------------------------------------------- 7. вырезы
  if (params.cutouts.isNotEmpty) {
    final cutoutMaterials = <TechMaterial>[
      for (final cutout in layers.cutouts)
        TechMaterial(
          name: cutout.isCircle ? 'Вырез круглый' : 'Вырез прямоугольный',
          size: cutout.isCircle
              ? 'Ø${formatMm(cutout.spec.width)} мм'
              : '${formatMm(cutout.spec.width)} × '
                    '${formatMm(cutout.spec.height)} мм',
          note:
              'центр ${formatMm(cutout.spec.centerXMm)} × '
              '${formatMm(cutout.spec.centerYMm)} мм от левого нижнего угла плёнки',
        ),
      TechMaterial(
        name: 'Окантовка по контуру вырезов',
        size: '${formatMm(layers.cutoutPerimeterMm)} мм',
        note: 'учтена в расходе окантовки',
      ),
    ];
    add(
      kind: TechOperationKind.cutouts,
      title: 'Вырезы',
      description:
          'Вырезать ${params.cutouts.length} шт по разметке: '
          '${spec.cutoutsSummary}. Кромку обработать окантовкой по всему '
          'контуру.',
      materials: cutoutMaterials,
      tool: 'Нож, шаблон или циркуль, маркер, фен-сварочник',
      control:
          'Размеры и положение вырезов по чертежу (±5 мм), контур '
          'обработан окантовкой, полотно вокруг не надрезано',
      source: 'WindowSpec.cutoutsSummary / WindowLayers.cutoutPerimeterMm',
    );
  }

  // ----------------------------------------------------------- 8. карман
  if (params.pocket || params.pocketTop) {
    final where = switch ((params.pocket, params.pocketTop)) {
      (true, true) => 'снизу и сверху',
      (true, false) => 'снизу',
      (false, true) => 'сверху',
      (false, false) => '',
    };
    // Длина полосы: снизу — по низу, сверху — по верху; если оба, суммируем.
    final bottomLength = params.pocket ? geometry.bottomWidth : 0.0;
    final topLength = params.pocketTop ? geometry.topWidth : 0.0;
    final pocketLength = bottomLength + topLength;
    final cornerHint = switch ((params.pocket, params.pocketTop)) {
      (true, true) =>
        'угловые люверсы снизу и сверху убраны, боковые смещены на '
            '${formatMm(pocketCornerOffset)} мм',
      (true, false) =>
        'нижние угловые люверсы не ставим, а крайние боковые подняты на '
            '${formatMm(pocketCornerOffset)} мм',
      (false, true) =>
        'верхние угловые люверсы не ставим, а крайние боковые опущены на '
            '${formatMm(pocketCornerOffset)} мм',
      (false, false) => '',
    };
    add(
      kind: TechOperationKind.pocket,
      title: 'Карман $where',
      description: isScreen
          ? 'Карман $where образовать подворотом материала полосой '
              '${formatMm(params.pocketWidth)} мм на всю ширину '
              '${formatMm(pocketLength)} мм и приварить по кромке. '
              'В полость кармана заводится утяжитель, поэтому $cornerHint.'
          : 'Полосу тента ${formatMm(pocketRollWidth)} мм сложить пополам '
              'до ${formatMm(params.pocketWidth)} мм и '
              '${isWeldedEdge ? 'приварить' : 'пришить'} по кромке $where на '
              'всю ширину ${formatMm(pocketLength)} мм. В полость кармана '
              'заводится утяжитель, поэтому $cornerHint.',
      materials: [
        TechMaterial(
          name: isScreen
              ? 'Подворот под карман $where '
                  '(${formatMm(params.pocketWidth)} мм)'
              : 'Полоса тента под карман '
                  '(${formatMm(pocketRollWidth)} мм → '
                  '${formatMm(params.pocketWidth)} мм)',
          size: '${formatMm(pocketLength)} мм',
          quantity: pocketLength,
        ),
      ],
      tool: 'Раскроечный стол, нож, линейка, фен-сварочник',
      control:
          'Карман по всей ширине, полость свободно пропускает утяжитель, '
          'шов без зазоров и перекосов',
      source: isScreen
          ? 'WindowParams.pocket / pocketTop / pocketWidth (подворот скрина)'
          : 'WindowParams.pocket / pocketTop / pocketWidth (тент 200 мм → 100 мм)',
    );
  }

  // --------------------------------------------------- 9. подъёмные ремни
  if (params.isLifting && !isScreen && spec.strapCount > 0) {
    add(
      kind: TechOperationKind.straps,
      title: 'Подъёмные ремни',
      description:
          'Приварить/пришить ${spec.strapCount} шт ремней '
          '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} мм по '
          'верхней кромке, сверху вниз, равномерно по ширине (2 шт до 2 м '
          'ширины, далее +1 на каждый метр).',
      materials: [
        TechMaterial(
          name: 'Подъёмный ремень (заготовка)',
          size: '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} мм',
          quantity: spec.strapCount.toDouble(),
          unit: 'шт',
        ),
      ],
      tool: 'Швейная машина или фен-сварочник, линейка, маркер',
      control:
          'Ремни на одном уровне, шаг равный, шов на всю ширину ремня; '
          'нагрузку держат',
      source: 'WindowParams.liftStrapCount; ремень 50 × 500 мм',
    );
  }

  // ---------------------------------------------------------- 10. дренаж
  final drainCount = params.drainCount.round();
  if (params.drainHoles && drainCount > 0 && !isScreen) {
    add(
      kind: TechOperationKind.drain,
      title: 'Дренаж',
      description:
          'Пробить $drainCount отв. Ø'
          '${formatMm(techDrainHoleDiameter)} мм в нижней окантовке на равных '
          'расстояниях, не задевая шов и люверсы.',
      materials: [
        TechMaterial(
          name:
              'Дренажные отверстия Ø'
              '${formatMm(techDrainHoleDiameter)} мм',
          size: '$drainCount шт',
          quantity: drainCount.toDouble(),
          unit: 'шт',
          note: 'в нижней окантовке',
        ),
      ],
      tool:
          'Пробойник Ø${formatMm(techDrainHoleDiameter)} мм, молоток, наковальня',
      control:
          'Отверстия в нижней окантовке, вода выходит свободно, шов и '
          'люверсы не задеты',
      source: 'WindowParams.drainHoles / drainCount; Ø6 мм из примечаний',
    );
  }

  // ------------------------------------------------ 11. контроль, упаковка
  add(
    kind: TechOperationKind.control,
    title: 'Контроль',
    description:
        'Перед упаковкой проверить изделие и промаркировать: окно '
        '№$index, ${formatMm(geometry.spanX)} × '
        '${formatMm(geometry.overallHeight)} мм, '
        '${params.windowType.label.toLowerCase()}.',
    tool: 'Рулетка, угольник, маркер, упаковочная плёнка',
    control:
        'Размеры по чертежу (±10 мм); шаг люверсов ${spec.eyeletStepLabel}; '
        'нет перекосов, волн и заломов полотна; '
        '${isScreen ? 'подворот ровный, шов ${formatMm(screenSeamMm)} мм без '
                  'расслоений' : 'окантовка ровная, швы без расслоений'}; '
        'маркировка номера окна №$index на бирке; упаковать.',
    source: 'сводная проверка WindowSpec / WindowLayers',
  );

  return operations;
}
