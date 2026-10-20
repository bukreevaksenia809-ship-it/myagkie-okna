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
  pocket('Фартук'),
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
      '${formatMm(spec.geometry.overallHeight)} ${unitSuffix()}';

  /// Тип окна строчными: «глухое», «подъёмное».
  String get typeLabel => params.windowType.label.toLowerCase();

  /// Подпись под заголовком: окантовка, люверсы, крепёж.
  String get subtitle => params.isScreen
      ? 'Скрин без тента: подворот ${params.hemBySideShortLabel} '
            '(низ/право/верх/лево), шов ${formatMm(screenSeamMm)} ${unitSuffix()} · заготовка '
            '${formatMm(spec.filmCutWidthWithAllowance)} × '
            '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()} · '
            'люверсы: ${spec.eyeletCount} шт, интервал '
            '${formatMm(params.eyeletStep)} ${unitSuffix()} (факт. '
            '${spec.eyeletStepLabel}) · '
            'крепёж: ${spec.fastenerSummary.toLowerCase()}'
      : 'Окантовка: ${spec.edgeBySideSummary} · '
            'плёнка в раскрое'
            '${params.hasAllowance ? ' с припуском' : ''}'
            '${params.hasShrinkage ? ' и усадкой' : ''}: '
            '${formatMm(spec.filmCutWidthWithShrinkage)} × '
            '${formatMm(spec.filmCutHeightWithShrinkage)} ${unitSuffix()} · '
            'люверсы: ${spec.eyeletCount} шт, интервал '
            '${formatMm(params.eyeletStep)} ${unitSuffix()} (факт. ${spec.eyeletStepLabel}) · '
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
  ///
  /// Тип берётся из [WindowLayers.typeFor]: по сторонам — выбранный, в углах —
  /// круглый, поэтому сводка сходится и с чертежом, и со сметой.
  static Map<EyeletType, int> orderEyeletsByType(Iterable<TechCard> cards) {
    final totals = <EyeletType, int>{};
    for (final card in cards) {
      for (final eyelet in card.spec.layers.eyelets) {
        final type = card.spec.layers.typeFor(eyelet);
        totals.update(type, (value) => value + 1, ifAbsent: () => 1);
      }
    }
    return totals;
  }

  /// Подписи расхода окантовки: «Тент 100 мм — 654 см».
  static List<String> edgeTotalLabels(Map<double, double> totals) {
    final entries = totals.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    return [
      for (final entry in entries)
        '${edgeBandLabel(entry.key)} — ${formatMm(entry.value)} ${unitSuffix()}',
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
          '${formatMm(geometry.spanX)} × ${formatMm(geometry.overallHeight)} ${unitSuffix()} '
          'плюс прибавка по каждой оси — среднее двух подворотов оси плюс '
          '${formatMm(screenHemAxisExtraMm)} ${unitSuffix()} на шов и запас. '
          'По высоте (низ ${formatMm(params.hemBottomMm)} + верх '
          '${formatMm(params.hemTopMm)}) / 2 + '
          '${formatMm(screenHemAxisExtraMm)} = '
          '${formatMm(params.hemAxisBottomTopIncrease)} ${unitSuffix()}, по ширине '
          '(лево ${formatMm(params.hemLeftMm)} + право '
          '${formatMm(params.hemRightMm)}) / 2 + '
          '${formatMm(screenHemAxisExtraMm)} = '
          '${formatMm(params.hemAxisLeftRightIncrease)} ${unitSuffix()}'
          '${spec.widthSlopeExtraMm.abs() >= 0.5 || spec.heightSlopeExtraMm.abs() >= 0.5 ? ', плюс наклон сторон (по ширине '
                    '${formatSignedMm(spec.widthSlopeExtraMm)}, по высоте '
                    '${formatSignedMm(spec.heightSlopeExtraMm)} ${unitSuffix()})' : ''}'
          '${spec.zipperBandTotalMm > 0 ? ', минус ширина полосы молнии '
                    '${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()}' : ''} → '
          'габарит заготовки '
          '${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()}'
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
              '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()}',
          note:
              'готовый габарит ${formatMm(geometry.spanX)} × '
              '${formatMm(geometry.overallHeight)} ${unitSuffix()} плюс среднее подворотов '
              'по оси + ${formatMm(screenHemAxisExtraMm)} ${unitSuffix()}: высота '
              '+${formatMm(params.hemAxisBottomTopIncrease)}, '
              'ширина +${formatMm(params.hemAxisLeftRightIncrease)} ${unitSuffix()} '
              '(подвороты ${params.hemBySideShortLabel}, низ/право/верх/лево)'
              '${spec.widthSlopeExtraMm.abs() >= 0.5 || spec.heightSlopeExtraMm.abs() >= 0.5 ? '; наклон сторон: по ширине '
                        '${formatSignedMm(spec.widthSlopeExtraMm)}, по высоте '
                        '${formatSignedMm(spec.heightSlopeExtraMm)} ${unitSuffix()}' : ''}'
              '${spec.zipperBandTotalMm > 0 ? '; ширина кроя уменьшена на '
                        'полосу молнии ${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()} '
                        '(${formatMm(spec.filmCutWidthBeforeZipper)} → '
                        '${formatMm(spec.filmCutWidth)} ${unitSuffix()})' : ''}',
        ),
        TechMaterial(
          name: 'Площадь заготовки-прямоугольника в раскрое',
          size: '${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²',
          note: 'ширина × высота заготовки, без площади вырезов',
        ),
      ],
      tool: 'Раскроечный стол, дисковый нож, рулетка, угольник, маркер',
      control:
          'Габарит ${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()} (±5 мм), '
          'заготовка прямоугольная — четыре прямых угла, кромка ровная без '
          'задиров и волн',
      source:
          'WindowSpec.filmCutWidthWithAllowance / filmCutHeightWithAllowance '
          '(готовый размер + среднее подворотов по оси + '
          '${formatMm(screenHemAxisExtraMm)} ${unitSuffix()}: '
          'WindowParams.hemAxisBottomTopIncrease / hemAxisLeftRightIncrease; '
          'подвороты hemBottomMm / hemRightMm / hemTopMm / hemLeftMm; '
          'у окна с молнией ширина кроя минус WindowLayers.zipperBandTotalMm)',
    );
  } else {
    add(
      kind: TechOperationKind.cutting,
      title: 'Раскрой плёнки',
      description:
          '${params.isTShape ? 'Т-образное окно: выкроить основное полотно и пристройки, затем сварить по общим сторонам. ' : ''}'
          'Отрезать полотно по раскрою: видимый размер '
          '${formatMm(visible.width)} × ${formatMm(visible.height)} ${unitSuffix()}, плюс '
          'запайка ${formatMm(params.weldOverlapMm)} ${unitSuffix()} с каждой стороны'
          '${spec.zipperBandTotalMm > 0 ? ', минус полоса молнии '
                    '${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()} (ширина '
                    '${formatMm(spec.filmCutWidthBeforeZipper)}'
                    ' → ${formatMm(spec.filmCutWidth)} ${unitSuffix()} до припуска)' : ''}'
          '${params.hasManualAllowance ? ', плюс припуск на раскрой '
                    '${params.allowanceWidthLabel} по ширине и '
                    '${params.manualAllowanceHeightLabel} по высоте' : ''}'
          '${params.hasAutoHeightAllowance ? ', плюс авто +'
                    '${formatMm(params.autoHeightAllowanceMm)} ${unitSuffix()} к высоте '
                    'заготовки (ПВХ)' : ''}'
          '${params.hasShrinkage ? ', плюс усадка '
                    '${formatPercent(params.effectiveShrinkagePercent)}' : ''}. '
          'Раскрой вести по длинной стороне рулона, кромку не подрезать.',
      materials: [
        TechMaterial(
          name: '${params.material.label} (${params.material.thickness})',
          size:
              '${formatMm(spec.filmCutWidthWithShrinkage)} × '
              '${formatMm(spec.filmCutHeightWithShrinkage)} ${unitSuffix()}',
          note:
              'до усадки ${formatMm(spec.filmCutWidthWithAllowance)} × '
              '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()}'
              '${params.hasAllowance ? ' (с припуском на раскрой)' : ''}'
              '${spec.zipperBandTotalMm > 0 ? '; ширина кроя уменьшена на '
                        'полосу молнии ${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()} '
                        '(${formatMm(spec.filmCutWidthBeforeZipper)}'
                        ' → ${formatMm(spec.filmCutWidth)} ${unitSuffix()} до припуска)' : ''}',
        ),
        TechMaterial(
          name: params.hasShrinkage
              ? 'Площадь заготовки-прямоугольника с усадкой'
              : 'Площадь заготовки-прямоугольника',
          size: '${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²',
          note: params.hasShrinkage
              ? 'ширина × высота заготовки, с припуском и усадкой, без вырезов'
              : 'ширина × высота заготовки, с припуском, без площади вырезов',
        ),
        if (params.isTShape && spec.filmPartBounds.length >= 2) ...[
          TechMaterial(
            name: 'Основное полотно (Т-окно)',
            size:
                '${formatMm(spec.filmPartBounds[0].width)} × '
                '${formatMm(spec.filmPartBounds[0].height)} ${unitSuffix()}',
            note: 'основная часть, припуск под окантовку по внешним сторонам',
          ),
          for (var index = 0; index < spec.layers.tAnnexes.length; index++)
            TechMaterial(
              name:
                  'Пристройка ${spec.layers.tAnnexes[index].number} (Т-окно)',
              size:
                  '${formatMm(spec.filmPartBounds[index + 1].width)} × '
                  '${formatMm(spec.filmPartBounds[index + 1].height)} ${unitSuffix()}',
              note:
                  '${spec.layers.tAnnexes[index].side.label.toLowerCase()}, '
                  'смещение ${formatMm(spec.layers.tAnnexes[index].offset)} ${unitSuffix()}'
                  '${spec.layers.tAnnexes[index].welded ? ', общая сторона — шов' : ', отдельное окно'}',
            ),
        ],
      ],
      tool: 'Раскроечный стол, дисковый нож, рулетка, угольник, маркер',
      control:
          'Габарит ${formatMm(spec.filmCutWidthWithShrinkage)} × '
          '${formatMm(spec.filmCutHeightWithShrinkage)} ${unitSuffix()} (±5 мм), '
          'заготовка прямоугольная — четыре прямых угла, кромка ровная без '
          'задиров и волн',
      source:
          'WindowSpec.filmCutWidthWithShrinkage / filmCutHeightWithShrinkage '
          '(видимый размер + запайка − полоса молнии + припуск на раскрой + '
          'усадка)',
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
        '${side.label.toLowerCase()} ${formatMm(params.hemForSide(side))} ${unitSuffix()}',
    ].join(', ');
    final hemControl = <String>[
      for (final side in EdgeSide.values)
        '${side.label.toLowerCase()} ${formatMm(params.hemForSide(side))} ± 2 мм',
    ].join(', ');
    add(
      kind: TechOperationKind.hem,
      title: 'Подворот и шов ${formatMm(screenSeamMm)} ${unitSuffix()}',
      description:
          'Завернуть материал по периметру на подворот по сторонам — '
          '$hemBySide (низ/право/верх/лево), всего по периметру '
          '${formatMm(spec.edgePerimeterMm)} ${unitSuffix()}, и сварить горячим воздухом '
          'швом ${formatMm(screenSeamMm)} ${unitSuffix()} с каждой стороны. '
          'Запас заготовки под подворот уже заложен по правилу «среднее двух '
          'подворотов оси + ${formatMm(screenHemAxisExtraMm)} ${unitSuffix()}»: по высоте +'
          '${formatMm(params.hemAxisBottomTopIncrease)} ${unitSuffix()}, по ширине +'
          '${formatMm(params.hemAxisLeftRightIncrease)} ${unitSuffix()}'
          '${spec.zipperBandTotalMm > 0 ? ' минус полоса молнии '
                    '${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()}' : ''} — заготовка '
          '${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()}. '
          'Скорость сварки $techWeldSpeedHint, режим уточнить пробным швом '
          'на обрезке. Тента и окантовки у скрина нет.',
      materials: [
        for (final side in EdgeSide.values)
          TechMaterial(
            name: 'Подворот скрина',
            size: '${formatMm(params.hemForSide(side))} ${unitSuffix()}',
            quantity: params.hemForSide(side),
            side: side.label,
            note: 'шов ${formatMm(screenSeamMm)} ${unitSuffix()}',
          ),
        TechMaterial(
          name: 'Длина подворота по периметру',
          size: '${formatMm(spec.edgePerimeterMm)} ${unitSuffix()}',
          quantity: spec.edgePerimeterMm,
          note:
              'периметр готового изделия; расход скрина считается по площади '
              'заготовки',
        ),
      ],
      tool: 'Фен-сварочник (горячий воздух), прижимной ролик, термометр',
      control:
          'Подворот по сторонам: $hemControl; шов '
          '${formatMm(screenSeamMm)} ± 0,5 мм; без прожогов, отслоений и '
          'пропусков; полотно не стянуто',
      source:
          'WindowParams.hemBottomMm / hemRightMm / hemTopMm / hemLeftMm; '
          'запас заготовки — WindowParams.hemAxisBottomTopIncrease / '
          'hemAxisLeftRightIncrease; screenSeamMm = 3 мм',
    );
  } else {
    add(
      kind: TechOperationKind.welding,
      title: isWeldedEdge
          ? 'Напайка: сварка с окантовкой'
          : 'Напайка: шитьё окантовки',
      description:
          'Плёнку завести под окантовку на запайку '
          '${formatMm(params.weldOverlapMm)} ${unitSuffix()} по всему периметру '
          '(${formatMm(spec.edgePerimeterMm)} ${unitSuffix()}). '
          'Соединение: ${params.edgeMaterial.joining}. '
          '${isWeldedEdge ? 'Скорость сварки $techWeldSpeedHint, режим уточнить '
                    'пробным швом на обрезке.' : 'Шов ровный, без посадки полотна.'}'
          '${spec.zipperBandTotalMm > 0 ? ' Ширина заготовки уже уменьшена на '
                    'полосу молнии ${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()} — '
                    'напайка идёт по кромке суженного полотна.' : ''}',
      materials: [
        TechMaterial(
          name: 'Припуск плёнки под окантовку (запайка)',
          size: '${formatMm(params.weldOverlapMm)} ${unitSuffix()} на сторону',
          note: 'периметр окна ${formatMm(spec.edgePerimeterMm)} ${unitSuffix()}',
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

  // ------------------------------------------ 3. спайка полотен / окон
  // У Т-окна со спайкой общая сторона — отдельная операция: по ней
  // свариваются два полотна. Спайки с соседними окнами (weldedSides) идут
  // тем же видом операции, но отдельными материалами по сторонам.
  if (params.weldedSides.isNotEmpty ||
      (params.isTShape && spec.tWeldedSeamLength > 0)) {
    final bySide = layers.edgeLengthsBySide;
    final weldedMaterials = <TechMaterial>[];
    for (final annex in spec.layers.tAnnexes.where((annex) => annex.welded)) {
      weldedMaterials.add(
        TechMaterial(
          name:
              'Спайка по общей стороне пристройки ${annex.number} внахлёст '
              '${formatMm(windowWeldWidth)} ${unitSuffix()}',
          size: '${formatMm(annex.sharedLength)} ${unitSuffix()}',
          quantity: annex.sharedLength,
          note:
              'пристройка ${annex.number} ${formatMm(annex.rect.width)} × '
              '${formatMm(annex.rect.height)} ${unitSuffix()} '
              '${annex.side.label.toLowerCase()}',
        ),
      );
    }
    for (final side in EdgeSide.values) {
      if (!params.isWelded(side)) continue;
      final length = bySide[side] ?? 0;
      if (length <= 0) continue;
      weldedMaterials.add(
        TechMaterial(
          name:
              'Спайка с соседним окном внахлёст '
              '${formatMm(windowWeldWidth)} ${unitSuffix()}',
          size: '${formatMm(length)} ${unitSuffix()}',
          quantity: length,
          side: side.label,
        ),
      );
    }
    add(
      kind: TechOperationKind.weldNeighbor,
      title: params.isTShape && spec.tWeldedSeamLength > 0
          ? 'Спайка полотен по общим сторонам'
          : 'Спайка с соседним окном',
      description:
          '${spec.weldSummary}. Сварку вести с двух сторон шва, шов '
          'прогреть до однородного валика. По общей стороне Т-окна окантовка '
          'не ставится: только шов; окантовка идёт по внешнему периметру '
          '${formatMm(spec.edgePerimeterMm)} ${unitSuffix()}.',
      materials: weldedMaterials,
      tool: 'Фен-сварочник (горячий воздух), прижимной ролик, струбцины',
      control:
          'Шов по всей длине ${formatMm(layers.weldLengthMm)} ${unitSuffix()}, без '
          'расслоения; плоскости полотен совпадают, зазоров нет',
      source: 'WindowParams.tWelded + t2Welded / weldedSides / WindowLayers.weldLengthMm',
    );
  }

  // -------------------------------------------------------- 4. окантовка
  // У скрина окантовки нет: тент не ставится, вместо него подворот (выше).
  if (!isScreen) {
    // Окантовка по сторонам: у Т-окна на одной стороне может быть несколько
    // внешних отрезков (низ основного полотна и низ приставки) — они
    // суммируются в одну строку по стороне. Общая сторона спайки в контур не
    // входит, поэтому окантовки там нет.
    final edgeTotals = <double, double>{};
    final edgeMaterials = <TechMaterial>[];
    final bySide = layers.edgeLengthsBySide;
    for (final side in EdgeSide.values) {
      if (params.isWelded(side)) continue;
      final length = bySide[side] ?? 0;
      if (length <= 0) continue;
      final roll = params.rollForSide(side);
      edgeTotals[roll] = (edgeTotals[roll] ?? 0) + length;
      edgeMaterials.add(
        TechMaterial(
          name:
              '${edgeBandLabel(roll)} → полоса '
              '${formatMm(WindowParams.finishedEdgeWidth(roll))} ${unitSuffix()} '
              '(сложить пополам)',
          size: '${formatMm(length)} ${unitSuffix()}',
          quantity: length,
          roll: roll,
          side: side.label,
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
          size: '${formatMm(perimeter)} ${unitSuffix()}',
          quantity: perimeter,
          roll: roll,
          note: cutout.isCircle
              ? 'Ø${formatMm(cutout.spec.width)} ${unitSuffix()}'
              : '${formatMm(cutout.spec.width)} × '
                    '${formatMm(cutout.spec.height)} ${unitSuffix()}',
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
          '${formatMm(params.weldOverlapMm)} ${unitSuffix()} и '
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
  // Крепёж подвижных сторон. У скрина он ставится по подвороту, у ПВХ — по
  // окантовке, но правило сторон одно: низ и бока, сверху саморезы или
  // люверсы. Тип крепежа у скрина больше не игнорируется.
  // Числа крепежа — те же, что в расходе и смете: точки низа и боков без
  // углов плюс саморезы верхнего ряда.
  final movableFastenerCount = layers.movableSideEyelets.length;
  final topScrewCount = layers.topEyelets.length;
  final String fastenerNote;
  if (params.fastenerType == FastenerType.eyeletsOnly) {
    fastenerNote = isScreen
        ? '${spec.fastenerSummary}. Отдельного крепежа низа и боков нет — '
              'только люверсы.'
        : params.isLifting
        ? '${spec.fastenerSummary}: сверху ряд люверсов под саморезы '
              '($topScrewCount шт), отдельных скоб, замков и ремней нет.'
        : 'Крепёж: ${spec.fastenerSummary.toLowerCase()}.';
  } else {
    fastenerNote = isScreen
        ? '${spec.fastenerSummary}: сверху саморезы ($topScrewCount шт), '
              'низ и бока — ${params.fastenerType.label.toLowerCase()} '
              '($movableFastenerCount шт).'
        : params.isLifting
        ? '${spec.fastenerSummary}: сверху ряд люверсов под саморезы '
              '($topScrewCount шт), низ и бока — '
              '${params.fastenerType.label.toLowerCase()} '
              '($movableFastenerCount шт).'
        : 'Крепёж: ${spec.fastenerSummary.toLowerCase()}.';
  }
  add(
    kind: TechOperationKind.eyelets,
    title: 'Люверсы',
    description:
        'Установить люверсы ${eyeletType.displayLabel.toLowerCase()} — всего '
        '${spec.eyeletCount} шт, интервал задан '
        '${formatMm(params.eyeletStep)} ${unitSuffix()}, фактически '
        '${spec.eyeletStepLabel} по сторонам (число интервалов округляется '
        'вверх, поэтому факт не больше заданного), отступ от угла '
        '${formatMm(params.eyeletCornerOffset)} ${unitSuffix()}. '
        '${params.roundEyeletsEnabled ? 'В углах только круглые '
                  '${EyeletType.round10.label}: овальный люверс угол не держит. ' : 'Круглые люверсы в углах отключены: угловых точек нет ни на '
                  'чертеже, ни в расходе, ни в смете. '}'
        '${params.hasEyeletlessSides ? 'Люверсы не ставятся на сторонах: '
                  '${layers.eyeletlessSidesLabel} — сторона остаётся без крепежа '
                  '(там спайка с соседним окном или крепление к стене). ' : ''}'
        '$fastenerNote',
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
          name: 'Люверсы ${eyeletType.displayLabel}',
          size: '$ovalCount шт',
          quantity: ovalCount.toDouble(),
          unit: 'шт',
          note: 'кроме углов',
        ),
      // Скрин съёмный: саморезы по верху и выбранный крепёж по низу и бокам
      // есть и у него. У «только люверсы» отдельной строки крепежа нет —
      // люверсы уже посчитаны выше.
      if (params.isLifting || isScreen) ...[
        // Саморезов нет, если верхняя сторона оставлена без люверсов.
        if (layers.topEyelets.isNotEmpty)
          TechMaterial(
            name: 'Саморезы по верхнему ряду',
            size: '${layers.topEyelets.length} шт',
            quantity: layers.topEyelets.length.toDouble(),
            unit: 'шт',
            note: 'верхняя кромка крепится к раме',
          ),
        // Строка крепежа есть только у реального крепежа: у «только люверсы»
        // её нет ни на ПВХ, ни на скрине — иначе техкарта разошлась бы с
        // расходом (там fastenerCount для этого типа равен нулю).
        if (layers.movableSideEyelets.isNotEmpty &&
            params.fastenerType != FastenerType.eyeletsOnly &&
            (params.isLifting || isScreen))
          TechMaterial(
            name:
                'Крепёж низа и боков: '
                '${params.fastenerType.label.toLowerCase()}'
                '${isScreen ? ' (по подвороту)' : ''}',
            size: '${layers.movableSideEyelets.length} шт',
            quantity: layers.movableSideEyelets.length.toDouble(),
            unit: 'шт',
            note: isScreen
                ? 'кроме углов — там круглые люверсы; полоса крепежа — подворот'
                : 'кроме углов — там круглые люверсы',
          ),
      ],
    ],
    tool: 'Пресс для люверсов, пробойник, наковальня, молоток',
    control:
        'Интервал задан ${formatMm(params.eyeletStep)} ${unitSuffix()}, фактический '
        '${spec.eyeletStepLabel} (±5 мм), отступ от угла '
        '${formatMm(params.eyeletCornerOffset)} ${unitSuffix()}; люверсы зажаты без '
        'перекосов и задиров, полотно между ними не порвано',
    source: 'WindowLayers.eyelets / eyeletStepLabel / typeFor',
  );

  // ----------------------------------------------------------- 6. молнии
  // У ПВХ молния впаивается в полосу тента, у скрина — в подвёрнутую полосу
  // (накладную полосу) из того же скрина; шов вместо напайки 25 мм — 3 мм.
  if (params.zippers.isNotEmpty) {
    final bands = layers.zipperBands;
    final zipperMaterials = <TechMaterial>[];
    for (var i = 0; i < bands.length; i++) {
      final band = bands[i];
      zipperMaterials
        ..add(
          TechMaterial(
            name: 'Молния №${i + 1} (вертикальная)',
            size: '${formatMm(band.height)} ${unitSuffix()}',
            quantity: band.height,
            note: isScreen
                ? 'вшивается в полосу скрина по центру'
                : 'впаивается в полосу тента по центру',
          ),
        )
        ..add(
          TechMaterial(
            name: isScreen
                ? 'Полоса скрина под молнию №${i + 1}'
                : 'Полоса тента под молнию №${i + 1}',
            size: '${formatMm(band.width)} × ${formatMm(band.height)} ${unitSuffix()}',
            note: isScreen
                ? 'шов ${formatMm(screenSeamMm)} ${unitSuffix()} по краям полосы; подворот '
                      'или накладная полоса из скрина; ширина кроя полотна '
                      'уменьшена на ${formatMm(band.width)} ${unitSuffix()}'
                : 'спайка ${formatMm(band.width)} ${unitSuffix()}; ширина кроя полотна '
                      'уменьшена на ${formatMm(band.width)} ${unitSuffix()}',
          ),
        );
    }
    add(
      kind: TechOperationKind.zipper,
      title: 'Молнии',
      description: isScreen
          ? '${params.zippers.length == 1 ? 'Вшить молнию' : 'Вшить молнии'} '
                'в полосу из скрина: ${spec.zippersSummary}. Полосу подвёрнутой '
                'ткани (или накладную полосу из скрина) шириной '
                '${formatMm(params.zipperBandWidth)} ${unitSuffix()} уложить по всей высоте '
                'полотна и сварить горячим воздухом швом '
                '${formatMm(screenSeamMm)} ${unitSuffix()} по обоим краям полосы; молния идёт '
                'по её середине. Расстояние от края полосы до кромки подворота — '
                'не меньше ${formatMm(minScreenZipperHemMm)} ${unitSuffix()}, за пределы '
                'заготовки полоса не выходит. Ширина заготовки скрина уменьшена '
                'на полосу: ${formatMm(spec.filmCutWidthBeforeZipper)} → '
                '${formatMm(spec.filmCutWidth)} ${unitSuffix()}.'
          : '${params.zippers.length == 1 ? 'Впаять молнию' : 'Впаять молнии'}: '
                '${spec.zippersSummary}. Полосу тента с молнией сварить с '
                'полотном по всей высоте, шов ровный, полотно без волны. '
                'Ширина заготовки уменьшена на полосу (спайку): '
                '${formatMm(spec.filmCutWidthBeforeZipper)}'
                ' → ${formatMm(spec.filmCutWidth)} ${unitSuffix()} до припуска.',
      materials: zipperMaterials,
      tool: isScreen || isWeldedEdge
          ? 'Фен-сварочник, прижимной ролик, шаблон для ровной укладки'
          : 'Швейная машина, лапка для молнии, прочные нитки',
      control: isScreen
          ? 'Молния вертикальна и не смещена, шов '
                '${formatMm(screenSeamMm)} ± 0,5 мм по краям полосы; от полосы до '
                'кромки подворота не меньше ${formatMm(minScreenZipperHemMm)} ${unitSuffix()}; '
                'бегунок ходит свободно'
          : 'Молния вертикальна и не смещена, ширина спайки '
                '${formatMm(params.zipperBandWidth)} ± 2 мм, бегунок ходит свободно',
      source: isScreen
          ? 'WindowLayers.zipperBands / WindowSpec.zippersSummary; '
                'screenSeamMm = 3 мм'
          : 'WindowLayers.zipperBands / WindowSpec.zippersSummary / '
                'zipperBandTotalMm (вычет полосы из ширины кроя)',
    );
  }

  // ---------------------------------------------------------- 7. вырезы
  if (params.cutouts.isNotEmpty) {
    final cutoutMaterials = <TechMaterial>[
      for (final cutout in layers.cutouts)
        TechMaterial(
          name: cutout.isCircle ? 'Вырез круглый' : 'Вырез прямоугольный',
          size: cutout.isCircle
              ? 'Ø${formatMm(cutout.spec.width)} ${unitSuffix()}'
              : '${formatMm(cutout.spec.width)} × '
                    '${formatMm(cutout.spec.height)} ${unitSuffix()}',
          note:
              'центр ${formatMm(cutout.spec.centerXMm)} × '
              '${formatMm(cutout.spec.centerYMm)} ${unitSuffix()} от левого нижнего угла плёнки',
        ),
      TechMaterial(
        name: 'Окантовка по контуру вырезов',
        size: '${formatMm(layers.cutoutPerimeterMm)} ${unitSuffix()}',
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

  // ------------------------------------------- 8. фартук (бывший карман)
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
            '${formatMm(pocketCornerOffset)} ${unitSuffix()}',
      (true, false) =>
        'нижние угловые люверсы не ставим, а крайние боковые подняты на '
            '${formatMm(pocketCornerOffset)} ${unitSuffix()}',
      (false, true) =>
        'верхние угловые люверсы не ставим, а крайние боковые опущены на '
            '${formatMm(pocketCornerOffset)} ${unitSuffix()}',
      (false, false) => '',
    };
    add(
      kind: TechOperationKind.pocket,
      title: 'Фартук $where',
      description: isScreen
          ? 'Фартук $where образовать подворотом материала полосой '
                '${formatMm(params.pocketWidth)} ${unitSuffix()} на всю ширину '
                '${formatMm(pocketLength)} ${unitSuffix()} и приварить по кромке. '
                'В полость фартука заводится утяжитель, поэтому $cornerHint.'
          : 'Полосу тента ${formatMm(pocketRollWidth)} ${unitSuffix()} сложить пополам '
                'до ${formatMm(params.pocketWidth)} ${unitSuffix()} и '
                '${isWeldedEdge ? 'приварить' : 'пришить'} по кромке $where на '
                'всю ширину ${formatMm(pocketLength)} ${unitSuffix()}. В полость фартука '
                'заводится утяжитель, поэтому $cornerHint.',
      materials: [
        TechMaterial(
          name: isScreen
              ? 'Подворот под фартук $where '
                    '(${formatMm(params.pocketWidth)} ${unitSuffix()})'
              : 'Полоса тента под фартук '
                    '(${formatMm(pocketRollWidth)} ${unitSuffix()} → '
                    '${formatMm(params.pocketWidth)} ${unitSuffix()})',
          size: '${formatMm(pocketLength)} ${unitSuffix()}',
          quantity: pocketLength,
        ),
      ],
      tool: 'Раскроечный стол, нож, линейка, фен-сварочник',
      control:
          'Фартук по всей ширине, полость свободно пропускает утяжитель, '
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
          '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} ${unitSuffix()} по '
          'верхней кромке, сверху вниз, равномерно по ширине (2 шт до 2 м '
          'ширины, далее +1 на каждый метр).',
      materials: [
        TechMaterial(
          name: 'Подъёмный ремень (заготовка)',
          size: '${formatMm(liftStrapWidth)} × ${formatMm(liftStrapLength)} ${unitSuffix()}',
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
          '${formatMm(techDrainHoleDiameter)} ${unitSuffix()} в нижней окантовке на равных '
          'расстояниях, не задевая шов и люверсы.',
      materials: [
        TechMaterial(
          name:
              'Дренажные отверстия Ø'
              '${formatMm(techDrainHoleDiameter)} ${unitSuffix()}',
          size: '$drainCount шт',
          quantity: drainCount.toDouble(),
          unit: 'шт',
          note: 'в нижней окантовке',
        ),
      ],
      tool:
          'Пробойник Ø${formatMm(techDrainHoleDiameter)} ${unitSuffix()}, молоток, наковальня',
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
        '${formatMm(geometry.overallHeight)} ${unitSuffix()}, '
        '${params.windowType.label.toLowerCase()}.',
    tool: 'Рулетка, угольник, маркер, упаковочная плёнка',
    control:
        'Размеры по чертежу (±10 мм); интервал люверсов задан '
        '${formatMm(params.eyeletStep)} ${unitSuffix()}, фактический '
        '${spec.eyeletStepLabel}; '
        'нет перекосов, волн и заломов полотна; '
        '${isScreen ? 'подворот ровный, шов ${formatMm(screenSeamMm)} ${unitSuffix()} без '
                  'расслоений' : 'окантовка ровная, швы без расслоений'}; '
        'маркировка номера окна №$index на бирке; упаковать.',
    source: 'сводная проверка WindowSpec / WindowLayers',
  );

  return operations;
}
