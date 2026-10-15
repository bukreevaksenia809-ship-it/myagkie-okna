import 'dart:math' as math;

/// Тип мягкого окна по способу открывания.
enum WindowType {
  fixed,
  lifting;

  String get label => switch (this) {
        WindowType.fixed => 'Глухое',
        WindowType.lifting => 'Подъёмное',
      };

  String get hint => switch (this) {
        WindowType.fixed =>
          'Люверсы по периметру (любого типа, в углах круглые). '
              'Молния и карман — по желанию',
        WindowType.lifting =>
          'Сверху ряд люверсов, ниже скобы; сверху висят подъёмные ремни',
      };
}

/// Технология изделия. Отдельного поля у окна нет: технология выводится из
/// материала полотна, чтобы не было двух противоречащих источников истины
/// (см. [WindowParams.tech] и [WindowParams.isScreen]). Пользователь выбирает
/// материал, а технология, крепёж и документы подстраиваются сами.
enum WindowTech {
  /// ПВХ: окантовка из тента складывается пополам, плёнка напаивается под неё.
  pvcTent('ПВХ с тентом'),

  /// Скрин: подворот материала по периметру и шов [screenSeamMm], тента нет.
  screen('Скрин без тента');

  const WindowTech(this.label);

  final String label;
}

/// Материал полотна: от него зависит вид на чертеже, доступные ширины рулонов
/// и сама технология изделия.
///
/// [FilmMaterial.screen] — это отдельная технология: скрин подворачивается сам,
/// без коричневого тента-окантовки, а крепится только люверсами по подвороту
/// (см. [WindowParams.isScreen], [WindowParams.hemWidths], [screenSeamMm]).
enum FilmMaterial {
  clearPvc(
    'Обычный ПВХ',
    'ПВХ 700 мкм',
    [1400, 1800, 2000, 2400, 2600],
  ),
  tintedPvc(
    'Тонированный ПВХ',
    'ПВХ 700 мкм, тонировка',
    [1400, 1800, 2000, 2400],
  ),
  mosquitoNet(
    'Москитная сетка',
    'сетка ПВХ',
    [1400, 1800, 2000, 2400, 2600, 3000],
  ),
  screen(
    'Скрин',
    'скрин-ткань ПВХ',
    [1400, 1800, 2000, 2400, 2500, 2600, 5000],
  );

  const FilmMaterial(this.label, this.thickness, this.rollWidths);

  final String label;

  /// Строка для примечаний.
  final String thickness;

  /// Доступные ширины рулонов, мм.
  final List<double> rollWidths;

  double get maxRollWidth => rollWidths.last;

  /// Ширина рулона по умолчанию.
  double get defaultRollWidth =>
      rollWidths.contains(2000) ? 2000 : rollWidths.last;

  String get rollWidthsLabel =>
      rollWidths.map((width) => formatCm(width)).join(', ');
}

/// Разумный диапазон ширины рулона окантовки, мм.
const double minEdgeRollWidth = 40;
const double maxEdgeRollWidth = 400;

/// Границы ввода интервала люверсов, мм.
///
/// Интервал задаёт пользователь: 50…2000 мм — это рамки ввода, а не
/// «рекомендация». Значение внутри диапазона принимается всегда, даже если
/// выходит за рекомендуемые 250–450 мм (см. [recommendedEyeletStepMinMm]).
const double minEyeletStepMm = 50;
const double maxEyeletStepMm = 2000;

/// Рекомендуемый интервал люверсов, мм: внутри него полотно держит ветер,
/// а фурнитуры уходит в норму. Выход за диапазон — только подсказка, не запрет.
const double recommendedEyeletStepMinMm = 250;
const double recommendedEyeletStepMaxMm = 450;

/// Технологические пороги интервала люверсов, мм.
///
/// Свыше [looseEyeletStepMm] полотно парусит между креплениями, ниже
/// [denseEyeletStepMm] — перерасход люверсов и узкая перемычка между ними.
const double looseEyeletStepMm = 800;
const double denseEyeletStepMm = 150;

/// Быстрые пресеты интервала люверсов в панели, мм. Пользователь может
/// выбрать любой из них или ввести своё число в поле.
const List<double> eyeletStepPresets = [250, 300, 350, 400, 500];

/// Пресет рулона окантовки — оставлен ради совместимости: по нему читаются
/// старые заказы, где ширина писалась именем типа, и берётся цена прайса.
///
/// Полоса складывается пополам, поэтому готовая ширина окантовки — половина
/// ширины рулона.
enum EdgeRoll {
  roll100(100, 'Тент 100 мм = окантовка 50 мм'),
  roll200(200, 'Тент 200 мм = окантовка 100 мм'),
  roll240(240, 'Тент 240 мм = окантовка 120 мм');

  const EdgeRoll(this.rawWidth, this.label);

  /// Ширина рулона, мм.
  final double rawWidth;

  final String label;

  /// Готовая ширина окантовки после складывания пополам, мм.
  double get finishedWidth => rawWidth / 2;

  String get shortLabel => 'Тент ${rawWidth.toStringAsFixed(0)} мм';

  /// Ширина рулона по имени пресета («roll200» → 200) или null, если имя
  /// не распознано. Нужна для чтения старых заказов с шириной-строкой.
  static double? presetRawWidth(String name) {
    for (final roll in EdgeRoll.values) {
      if (roll.name == name) return roll.rawWidth;
    }
    return null;
  }
}

/// Подпись окантовки по ширине рулона: «Тент 150 мм», в коротком виде —
/// «150 мм». Работает и для пресетов, и для своей ширины.
String edgeBandLabel(double rawWidth, {bool short = false}) {
  if (!rawWidth.isFinite) return short ? '—' : 'Тент — мм';
  final width = '${formatMm(rawWidth)} мм';
  return short ? width : 'Тент $width';
}

/// Материал окантовки: только ПВХ-тент. Других тканей в проекте нет —
/// заказчик работает на ПВХ-тенте, поэтому и шов всегда сварной.
enum EdgeMaterial {
  pvcTent630;

  String get label => switch (this) {
        EdgeMaterial.pvcTent630 => 'ПВХ-тент 630–650 г/м²',
      };

  /// Способ соединения: ПВХ-тент сваривают горячим воздухом.
  String get joining => switch (this) {
        EdgeMaterial.pvcTent630 => 'Сварка горячим воздухом 400–500 °C',
      };

  bool get isWelded => this == EdgeMaterial.pvcTent630;
}

/// Цвет окантовки. Значение — цвет для чертежа.
enum EdgeColor {
  brown(0xFF7A4A21, 'Коричневый'),
  white(0xFFE6E2DA, 'Белый'),
  grey(0xFF9BA2AA, 'Серый'),
  graphite(0xFF4C5157, 'Графит'),
  beige(0xFFD6C3A1, 'Бежевый'),
  black(0xFF2B2D30, 'Чёрный');

  const EdgeColor(this.value, this.label);

  final int value;
  final String label;
}

/// Сторона окна (порядок совпадает с обходом углов: низ, право, верх, лево).
enum EdgeSide {
  bottom,
  right,
  top,
  left;

  String get label => switch (this) {
        EdgeSide.bottom => 'Низ',
        EdgeSide.right => 'Право',
        EdgeSide.top => 'Верх',
        EdgeSide.left => 'Лево',
      };

  /// Противоположная сторона — ею сваривается копия окна: право↔лево,
  /// верх↔низ.
  EdgeSide get opposite => switch (this) {
        EdgeSide.bottom => EdgeSide.top,
        EdgeSide.top => EdgeSide.bottom,
        EdgeSide.left => EdgeSide.right,
        EdgeSide.right => EdgeSide.left,
      };
}

/// Тип люверса: круглый Ø10 мм или овальный 42×22 мм под скобу.
enum EyeletType {
  round10('Круглый Ø10 мм', 22, 22, 10, 10),
  oval42x22('Овальный 42×22 мм', 42, 22, 30, 11);

  const EyeletType(
    this.label,
    this.outerWidth,
    this.outerHeight,
    this.holeWidth,
    this.holeHeight,
  );

  final String label;

  /// Внешние габариты кольца, мм.
  final double outerWidth;
  final double outerHeight;

  /// Размер отверстия, мм.
  final double holeWidth;
  final double holeHeight;

  bool get isRound => this == EyeletType.round10;
}

/// Крепёж подвижных сторон (низ и бока подъёмного окна).
enum FastenerType {
  eyeletsOnly('Только люверсы'),
  turnBuckles('Поворотные скобы'),
  frenchLocks('Французский замок'),
  straps('Силиконовые ремни');

  const FastenerType(this.label);

  final String label;
}

/// Как расположена верхняя кромка относительно нижней.
enum TopAlign {
  center,
  left,
  right,
  custom;

  String get label => switch (this) {
        TopAlign.center => 'По центру',
        TopAlign.left => 'По левому краю',
        TopAlign.right => 'По правому краю',
        TopAlign.custom => 'Вручную',
      };
}

/// Числовые поля, которые вводит пользователь.
enum ParamField {
  bottomWidth,
  topWidth,
  leftHeight,
  rightHeight,
  topOffset,
  eyeletStep,
  eyeletCornerOffset,
  drainCount,
  pocketWidth,
  shrinkagePercent,
  rollGap,
  allowanceWidth,
  allowanceHeight,
  weldOverlap,
  hemBottom,
  hemRight,
  hemTop,
  hemLeft;

  String get label => switch (this) {
        ParamField.bottomWidth => 'Ширина низ',
        ParamField.topWidth => 'Ширина верх',
        ParamField.leftHeight => 'Высота лево',
        ParamField.rightHeight => 'Высота право',
        ParamField.topOffset => 'Смещение верх',
        ParamField.eyeletStep => 'Интервал люверсов',
        ParamField.eyeletCornerOffset => 'Отступ люверса от угла',
        ParamField.drainCount => 'Дренажных отверстий',
        ParamField.pocketWidth => 'Ширина кармана',
        ParamField.shrinkagePercent => 'Усадка ПВХ',
        ParamField.rollGap => 'Зазор при раскладке',
        ParamField.allowanceWidth => 'Припуск на раскрой по ширине',
        ParamField.allowanceHeight => 'Припуск на раскрой по высоте',
        ParamField.weldOverlap => 'Запайка плёнки под окантовку',
        ParamField.hemBottom => 'Подворот скрина снизу',
        ParamField.hemRight => 'Подворот скрина справа',
        ParamField.hemTop => 'Подворот скрина сверху',
        ParamField.hemLeft => 'Подворот скрина слева',
      };

  String get unit => switch (this) {
        ParamField.shrinkagePercent => '%',
        ParamField.drainCount => 'шт',
        _ => 'мм',
      };
}

/// Поле подворота скрина для стороны окна — чтобы замечания и подписи
/// адресовались конкретной стороне, а не «подвороту вообще».
ParamField hemFieldForSide(EdgeSide side) => switch (side) {
      EdgeSide.bottom => ParamField.hemBottom,
      EdgeSide.right => ParamField.hemRight,
      EdgeSide.top => ParamField.hemTop,
      EdgeSide.left => ParamField.hemLeft,
    };

/// Припуск на сварку (напайка, запайка): на сколько плёнка ПВХ заходит под
/// окантовку. Значение по умолчанию — **5 мм** (подсов ПВХ под тент у цеха
/// 5–6 мм); у каждого окна своё поле [WindowParams.weldOverlapMm] (5…60 мм),
/// введённое руками.
const double defaultWeldOverlapMm = 5;
const double minWeldOverlapMm = 5;
const double maxWeldOverlapMm = 60;

/// Шов сварки подворота скрина, мм — с каждой стороны подворота.
const double screenSeamMm = 3;

/// Минимальное расстояние от края полосы молнии до кромки подворота скрина, мм.
///
/// Полоса молнии у скрина — подвёрнутая ткань (или накладная полоса из скрина);
/// если она подходит к линии подворота ближе 100 мм, шов полосы и шов подворота
/// сливаются, кромка теряет тело и рвётся по люверсу/молнии.
const double minScreenZipperHemMm = 100;

/// Подворот скрина: сколько материала подворачивается на каждую сторону.
///
/// Подворот задаётся отдельно на каждую сторону ([WindowParams.hemBottomMm]
/// и соседние), потому что на трапеции и на окне со спайкой стороны бывают
/// разными. Пресеты панели — [screenHemPresets], значение по умолчанию
/// [defaultScreenHemMm].
const double defaultScreenHemMm = 40;
const double minScreenHemMm = 10;
const double maxScreenHemMm = 150;
const List<double> screenHemPresets = [40, 50, 60];

/// Разумный предел припуска на раскрой, мм: больше — почти наверняка опечатка.
const double maxAllowanceMm = 500;

/// Сколько молний и вырезов можно поставить на одно окно.
const int maxZippers = 2;
const int maxCutouts = 4;

/// Полоса спайки, которой сваривают два соседних окна между собой, мм.
const double windowWeldWidth = 25;

/// Молния в полотне: всегда вертикальная, положение — от левого края плёнки.
class ZipperSpec {
  const ZipperSpec({
    this.centered = true,
    this.offsetMm = 0,
    this.bandWidth = defaultZipperBandWidth,
  });

  /// По центру полотна (иначе — по [offsetMm] от левого края).
  final bool centered;

  /// Положение центра молнии от левого внутреннего края плёнки, мм.
  final double offsetMm;

  /// Ширина спайки, в которую впаивается молния (молния по её центру).
  final double bandWidth;

  ZipperSpec copyWith({bool? centered, double? offsetMm, double? bandWidth}) =>
      ZipperSpec(
        centered: centered ?? this.centered,
        offsetMm: offsetMm ?? this.offsetMm,
        bandWidth: bandWidth ?? this.bandWidth,
      );

  Map<String, dynamic> toJson() => {
        'centered': centered,
        'offsetMm': offsetMm,
        'bandWidth': bandWidth,
      };
}

/// Форма выреза в полотне.
enum CutoutShape {
  rect('Прямоугольный'),
  circle('Круглый');

  const CutoutShape(this.label);

  final String label;
}

/// Вырез (отверстие) в полотне: под трубу, вентиляцию, стойку.
class Cutout {
  const Cutout({
    this.shape = CutoutShape.rect,
    this.width = 300,
    this.height = 300,
    this.centerXMm = 0,
    this.centerYMm = 400,
  });

  final CutoutShape shape;

  /// Ширина, мм (у круга — диаметр).
  final double width;

  /// Высота, мм (у круга не используется).
  final double height;

  /// Центр от левого внутреннего края плёнки, мм.
  final double centerXMm;

  /// Центр от нижней внутренней кромки плёнки, мм.
  final double centerYMm;

  Cutout copyWith({
    CutoutShape? shape,
    double? width,
    double? height,
    double? centerXMm,
    double? centerYMm,
  }) =>
      Cutout(
        shape: shape ?? this.shape,
        width: width ?? this.width,
        height: height ?? this.height,
        centerXMm: centerXMm ?? this.centerXMm,
        centerYMm: centerYMm ?? this.centerYMm,
      );

  /// Площадь выреза, мм².
  double get areaMm2 => shape == CutoutShape.circle
      ? math.pi * width * width / 4
      : width * height;

  /// Длина контура выреза, мм — столько окантовки уходит на его обработку.
  double get perimeterMm => shape == CutoutShape.circle
      ? math.pi * width
      : 2 * (width + height);

  Map<String, dynamic> toJson() => {
        'shape': shape.name,
        'width': width,
        'height': height,
        'centerXMm': centerXMm,
        'centerYMm': centerYMm,
      };
}

/// Подъёмный ремень: ширина и длина заготовки, мм.
const double liftStrapWidth = 50;
const double liftStrapLength = 500;

/// Ширина спайки, в которую впаивается молния, мм (5 см).
const double defaultZipperBandWidth = 50;

/// Карман: рулон тента 200 мм складывается пополам → 100 мм.
const double pocketRollWidth = 200;
const double pocketFinishedWidth = 100;

/// На сколько поднимается нижний люверс, чтобы карман открывался, мм.
const double pocketCornerOffset = 50;

/// Параметры одного мягкого окна. Все линейные размеры — в миллиметрах.
class WindowParams {
  const WindowParams({
    this.projectName = 'Мягкое окно',
    this.customer = '',
    this.drawingNumber = '',
    this.windowType = WindowType.fixed,
    this.bottomWidth = 1500,
    this.topWidth = 1500,
    this.leftHeight = 2520,
    this.rightHeight = 2520,
    this.allowanceWidthMm = 0,
    this.allowanceHeightMm = 0,
    this.topAlign = TopAlign.center,
    this.topOffsetMm = 0,
    this.rollBottom = 100,
    this.rollTop = 100,
    this.rollLeft = 100,
    this.rollRight = 100,
    this.edgeMaterial = EdgeMaterial.pvcTent630,
    this.edgeColor = EdgeColor.brown,
    this.weldOverlapMm = defaultWeldOverlapMm,
    this.eyeletType = EyeletType.round10,
    this.material = FilmMaterial.clearPvc,
    this.hemBottomMm = defaultScreenHemMm,
    this.hemRightMm = defaultScreenHemMm,
    this.hemTopMm = defaultScreenHemMm,
    this.hemLeftMm = defaultScreenHemMm,
    this.eyeletStep = 300,
    this.eyeletCornerOffset = 0,
    this.fastenerType = FastenerType.turnBuckles,
    this.zippers = const [],
    this.cutouts = const [],
    this.weldedSides = const [],
    this.removeEyeletsOnWelded = true,
    this.noEyeletsTop = false,
    this.noEyeletsBottom = false,
    this.pocket = false,
    this.pocketTop = false,
    this.pocketWidth = pocketFinishedWidth,
    this.drainHoles = false,
    this.drainCount = 3,
    this.shrinkagePercent = 1.5,
  });

  // Маркировка
  final String projectName;
  final String customer;

  /// Дополнительная маркировка окна (номер заказа, примечание).
  final String drawingNumber;

  /// Тип окна по способу открывания.
  final WindowType windowType;

  // Размеры полотна
  final double bottomWidth;
  final double topWidth;
  final double leftHeight;
  final double rightHeight;

  /// Припуск на раскрой по ширине, мм: плёнка кроится больше замера.
  ///
  /// Припуск прибавляется к ширине низа и верха, а по высоте — к левой и
  /// правой высотам (см. [effectiveBottomWidth] и соседние геттеры), но
  /// ТОЛЬКО к заготовке плёнки в раскрое. Изделие, чертёж, окантовка,
  /// люверсы, площадь изделия и остальные расчёты идут по основным размерам
  /// ([bottomWidth] и т. д.).
  final double allowanceWidthMm;

  /// Припуск на раскрой по высоте, мм (по умолчанию 0).
  final double allowanceHeightMm;

  final TopAlign topAlign;
  final double topOffsetMm;

  /// Пресеты ширины рулона окантовки, мм — быстрые кнопки в панели.
  ///
  /// Свою ширину можно ввести вручную (40…400 мм); эти три значения остались
  /// как готовые варианты и как опорные точки прайса
  /// (PriceList.edgePerMeterForWidth).
  static const List<double> edgePresets = [100, 200, 240];

  // Окантовка: своя ширина рулона на каждую сторону, мм.
  //
  // Полоса складывается пополам, поэтому готовая ширина окантовки — половина
  // ширины рулона (см. [finishedEdgeWidth]).
  final double rollBottom;
  final double rollTop;
  final double rollLeft;
  final double rollRight;

  final EdgeMaterial edgeMaterial;
  final EdgeColor edgeColor;

  /// Запайка (напайка) плёнки под окантовку, мм — вводится руками, 5…60 мм.
  /// От неё зависит размер заготовки плёнки: каждый миллиметр запайки
  /// добавляет по миллиметру с каждой стороны.
  final double weldOverlapMm;

  /// Материал полотна: ПВХ обычный/тонированный, москитная сетка, скрин.
  final FilmMaterial material;

  /// Подворот скрина снизу, мм (только для [FilmMaterial.screen]).
  final double hemBottomMm;

  /// Подворот скрина справа, мм.
  final double hemRightMm;

  /// Подворот скрина сверху, мм.
  final double hemTopMm;

  /// Подворот скрина слева, мм.
  final double hemLeftMm;

  // Крепёж
  final EyeletType eyeletType;

  /// Примерный (заданный) интервал люверсов, мм.
  ///
  /// Пользователь задаёт его сам: [minEyeletStepMm]…[maxEyeletStepMm], по
  /// умолчанию 300. Число интервалов по стороне = ceil(длина / интервал),
  /// поэтому фактический интервал получается НЕ БОЛЬШЕ заданного — люверсы
  /// «не разъезжаются», а лишний остаток уходит в запас (см.
  /// `WindowLayers.eyeletSteps` и `WindowSpec.eyeletStepLabel`).
  final double eyeletStep;

  /// Отступ первого люверса от угла; 0 — люверс стоит в углу.
  final double eyeletCornerOffset;

  /// Чем крепятся подвижные стороны (низ и бока).
  final FastenerType fastenerType;

  // Спецэлементы
  /// Молнии: каждая ставится отдельной кнопкой, все вертикальные.
  final List<ZipperSpec> zippers;

  /// Вырезы (отверстия) в полотне.
  final List<Cutout> cutouts;

  /// Стороны, которыми окно спаяно с соседним (окантовка там не ставится).
  final List<EdgeSide> weldedSides;

  /// Убирать люверсы (крепёж) на спаянных сторонах.
  ///
  /// По умолчанию убираем: спайка держит полотно сама, а люверс в шве
  /// только рвёт тент. Кнопка в панели позволяет оставить крепёж.
  final bool removeEyeletsOnWelded;

  /// Не ставить люверсы сверху.
  ///
  /// Сторона остаётся совсем без крепежа: там предполагается спайка с соседним
  /// окном или крепление полотна к стене/раме другим способом. Углы стороны
  /// тоже не ставятся — они принадлежат ей по правилу обхода (см.
  /// `WindowLayers.eyelets`).
  final bool noEyeletsTop;

  /// Не ставить люверсы снизу — зеркально [noEyeletsTop].
  final bool noEyeletsBottom;

  /// Карман из тента по нижней кромке: утяжитель заводится в его полость.
  /// У скрина карман образуется верхним/нижним подворотом.
  final bool pocket;

  /// Карман по верхней кромке — зеркально нижнему.
  final bool pocketTop;

  /// Готовая ширина кармана, мм (рулон 200 мм складывается пополам).
  final double pocketWidth;

  final bool drainHoles;
  final double drainCount;

  /// Усадка ПВХ, % — плёнка кроится больше на эту величину.
  final double shrinkagePercent;

  bool get hasZipper => zippers.isNotEmpty;

  /// Первая молния — для подписей и совместимости.
  ZipperSpec? get zipper => zippers.isEmpty ? null : zippers.first;

  bool get zipperEnabled => zippers.isNotEmpty;

  bool get zipperCentered => zipper?.centered ?? true;

  double get zipperOffsetMm => zipper?.offsetMm ?? 0;

  double get zipperBandWidth => zipper?.bandWidth ?? defaultZipperBandWidth;

  /// Сколько миллиметров окантовки экономят спайки с соседними окнами.
  bool isWelded(EdgeSide side) => weldedSides.contains(side);

  /// Есть ли припуск на раскрой хотя бы по одной оси.
  bool get hasAllowance => allowanceWidthMm != 0 || allowanceHeightMm != 0;

  /// Припуск по ширине в виде «+120» / «−30» / «0».
  String get allowanceWidthLabel => formatSignedMm(allowanceWidthMm);

  /// Припуск по высоте в виде «+80» / «−30» / «0».
  String get allowanceHeightLabel => formatSignedMm(allowanceHeightMm);

  /// Подпись припуска для документов: «припуск +120/+80 мм».
  String get allowanceLabel => hasAllowance
      ? 'припуск $allowanceWidthLabel/$allowanceHeightLabel мм'
      : 'припуск 0/0 мм';

  // Размеры заготовки плёнки с припуском на раскрой. Изделие при этом
  // остаётся размером замера: геометрия и все расчёты идут по основным
  // размерам, а припуск добавляется только в раскрое плёнки.
  double get effectiveBottomWidth => bottomWidth + allowanceWidthMm;
  double get effectiveTopWidth => topWidth + allowanceWidthMm;
  double get effectiveLeftHeight => leftHeight + allowanceHeightMm;
  double get effectiveRightHeight => rightHeight + allowanceHeightMm;

  /// Тип люверса, который реально ставится.
  ///
  /// Тип выбирает пользователь, и он действует на **любом** типе окна, включая
  /// глухое: овальный 42×22 под скобу — это фурнитура, а не признак
  /// подъёмного окна. Принудительной замены на круглый для глухих больше нет.
  /// Единственное правило по типу — «в углах круглый»: его применяет
  /// `WindowLayers.typeFor`, потому что угол тянет по диагонали и овальный
  /// люверс, развёрнутый вдоль одной стороны, там не держит.
  EyeletType get effectiveEyeletType => eyeletType;

  /// Стороны, на которых люверсы не ставятся (кнопки панели).
  ///
  /// Порядок обхода углов: низ, право, верх, лево.
  List<EdgeSide> get eyeletlessSides => [
        if (noEyeletsBottom) EdgeSide.bottom,
        if (noEyeletsTop) EdgeSide.top,
      ];

  /// Есть ли сторона без люверсов.
  bool get hasEyeletlessSides => noEyeletsTop || noEyeletsBottom;

  /// Сторона окна без люверсов.
  bool hasEyeletsOn(EdgeSide side) => switch (side) {
        EdgeSide.bottom => !noEyeletsBottom,
        EdgeSide.top => !noEyeletsTop,
        EdgeSide.left || EdgeSide.right => true,
      };

  /// Подпись сторон без люверсов: «верх», «низ», «низ и верх».
  String get eyeletlessSidesLabel {
    final labels = [
      for (final side in eyeletlessSides) side.label.toLowerCase(),
    ];
    if (labels.isEmpty) return '';
    if (labels.length == 1) return labels.first;
    return '${labels.sublist(0, labels.length - 1).join(', ')} и ${labels.last}';
  }

  /// Доступные ширины рулонов для выбранного материала, мм.
  List<double> get availableRollWidths => material.rollWidths;

  /// Скрин — самостоятельная технология: у него нет коричневого тента и нет
  /// окантовки, материал подворачивается сам. Источник истины один —
  /// материал: пользователь выбирает [FilmMaterial.screen], а всё остальное
  /// (расчёт, чертёж, документы) выводится из этого признака.
  bool get isScreen => material == FilmMaterial.screen;

  /// Технология изделия, выведенная из материала (см. [WindowTech]).
  WindowTech get tech => isScreen ? WindowTech.screen : WindowTech.pvcTent;

  /// Усадка, которая реально применяется к раскрою: у скрина усадки нет
  /// (ткань не тянется, как плёнка ПВХ), у ПВХ — поле [shrinkagePercent].
  /// Нужен запас — его добавляют припуском на раскрой.
  double get effectiveShrinkagePercent => isScreen ? 0 : shrinkagePercent;

  /// Количество подъёмных ремней: 2 при ширине до 2 м, далее +1 на каждый метр.
  int get liftStrapCount {
    // Скрин крепится только люверсами: ремней у него нет.
    if (!isLifting || isScreen) return 0;
    final width = bottomWidth.isFinite && bottomWidth > 0 ? bottomWidth : 0.0;
    if (width <= 2000) return 2;
    return 2 + ((width - 2000) / 1000).ceil();
  }

  bool get isLifting => windowType == WindowType.lifting;

  /// Готовая (сложенная пополам) ширина окантовки по ширине рулона, мм.
  static double finishedEdgeWidth(double rawWidth) => rawWidth / 2;

  /// Ширина рулона окантовки для стороны с индексом обхода углов:
  /// 0 — низ, 1 — право, 2 — верх, 3 — лево.
  double rollForEdge(int index) => switch (index % 4) {
        0 => rollBottom,
        1 => rollRight,
        2 => rollTop,
        _ => rollLeft,
      };

  /// Ширина рулона окантовки для стороны окна.
  double rollForSide(EdgeSide side) => switch (side) {
        EdgeSide.bottom => rollBottom,
        EdgeSide.right => rollRight,
        EdgeSide.top => rollTop,
        EdgeSide.left => rollLeft,
      };

  /// Подвороты скрина по сторонам в порядке обхода углов:
  /// низ, право, верх, лево (мм).
  ///
  /// Именно этот список идёт в геометрию: заготовка скрина — готовый контур,
  /// расширенный на своё значение с каждой стороны.
  List<double> get hemWidths => [
        hemBottomMm,
        hemRightMm,
        hemTopMm,
        hemLeftMm,
      ];

  /// Подворот скрина для стороны с индексом обхода углов
  /// (0 — низ, 1 — право, 2 — верх, 3 — лево).
  double hemForEdge(int index) => switch (index % 4) {
        0 => hemBottomMm,
        1 => hemRightMm,
        2 => hemTopMm,
        _ => hemLeftMm,
      };

  /// Подворот скрина для стороны окна.
  double hemForSide(EdgeSide side) => switch (side) {
        EdgeSide.bottom => hemBottomMm,
        EdgeSide.right => hemRightMm,
        EdgeSide.top => hemTopMm,
        EdgeSide.left => hemLeftMm,
      };

  /// Сумма подворотов по четырём сторонам, мм.
  ///
  /// Ведомость и смета считают работу подворота по периметру готового
  /// изделия; эта сумма нужна для подписей «на сколько вырастет заготовка».
  double get hemTotalMm => hemBottomMm + hemRightMm + hemTopMm + hemLeftMm;

  /// Все четыре подворота одинаковы — тогда старые версии приложения
  /// поймут заказ по одиночному полю `hemMm` в JSON.
  bool get hasUniformHem =>
      hemBottomMm == hemRightMm &&
      hemRightMm == hemTopMm &&
      hemTopMm == hemLeftMm;

  /// Подпись подворотов по сторонам: «низ 40, право 50, верх 60, лево 40 мм».
  String get hemBySideLabel => 'низ ${formatMm(hemBottomMm)}, '
      'право ${formatMm(hemRightMm)}, верх ${formatMm(hemTopMm)}, '
      'лево ${formatMm(hemLeftMm)} мм';

  /// Короткая подпись подворотов по сторонам: «40/50/60/40 мм»
  /// (низ/право/верх/лево).
  String get hemBySideShortLabel =>
      '${formatMm(hemBottomMm)}/${formatMm(hemRightMm)}/'
      '${formatMm(hemTopMm)}/${formatMm(hemLeftMm)} мм';

  WindowParams copyWith({
    String? projectName,
    String? customer,
    String? drawingNumber,
    WindowType? windowType,
    double? bottomWidth,
    double? topWidth,
    double? leftHeight,
    double? rightHeight,
    double? allowanceWidthMm,
    double? allowanceHeightMm,
    TopAlign? topAlign,
    double? topOffsetMm,
    double? rollBottom,
    double? rollTop,
    double? rollLeft,
    double? rollRight,
    EdgeMaterial? edgeMaterial,
    EdgeColor? edgeColor,
    double? weldOverlapMm,
    FilmMaterial? material,
    double? hemBottomMm,
    double? hemRightMm,
    double? hemTopMm,
    double? hemLeftMm,
    EyeletType? eyeletType,
    double? eyeletStep,
    double? eyeletCornerOffset,
    FastenerType? fastenerType,
    List<ZipperSpec>? zippers,
    List<Cutout>? cutouts,
    List<EdgeSide>? weldedSides,
    bool? removeEyeletsOnWelded,
    bool? noEyeletsTop,
    bool? noEyeletsBottom,
    bool? pocket,
    bool? pocketTop,
    double? pocketWidth,
    bool? drainHoles,
    double? drainCount,
    double? shrinkagePercent,
  }) {
    return WindowParams(
      projectName: projectName ?? this.projectName,
      customer: customer ?? this.customer,
      drawingNumber: drawingNumber ?? this.drawingNumber,
      windowType: windowType ?? this.windowType,
      bottomWidth: bottomWidth ?? this.bottomWidth,
      topWidth: topWidth ?? this.topWidth,
      leftHeight: leftHeight ?? this.leftHeight,
      rightHeight: rightHeight ?? this.rightHeight,
      allowanceWidthMm: allowanceWidthMm ?? this.allowanceWidthMm,
      allowanceHeightMm: allowanceHeightMm ?? this.allowanceHeightMm,
      topAlign: topAlign ?? this.topAlign,
      topOffsetMm: topOffsetMm ?? this.topOffsetMm,
      rollBottom: rollBottom ?? this.rollBottom,
      rollTop: rollTop ?? this.rollTop,
      rollLeft: rollLeft ?? this.rollLeft,
      rollRight: rollRight ?? this.rollRight,
      edgeMaterial: edgeMaterial ?? this.edgeMaterial,
      edgeColor: edgeColor ?? this.edgeColor,
      weldOverlapMm: weldOverlapMm ?? this.weldOverlapMm,
      material: material ?? this.material,
      hemBottomMm: hemBottomMm ?? this.hemBottomMm,
      hemRightMm: hemRightMm ?? this.hemRightMm,
      hemTopMm: hemTopMm ?? this.hemTopMm,
      hemLeftMm: hemLeftMm ?? this.hemLeftMm,
      eyeletType: eyeletType ?? this.eyeletType,
      eyeletStep: eyeletStep ?? this.eyeletStep,
      eyeletCornerOffset: eyeletCornerOffset ?? this.eyeletCornerOffset,
      fastenerType: fastenerType ?? this.fastenerType,
      zippers: zippers ?? this.zippers,
      cutouts: cutouts ?? this.cutouts,
      weldedSides: weldedSides ?? this.weldedSides,
      removeEyeletsOnWelded:
          removeEyeletsOnWelded ?? this.removeEyeletsOnWelded,
      noEyeletsTop: noEyeletsTop ?? this.noEyeletsTop,
      noEyeletsBottom: noEyeletsBottom ?? this.noEyeletsBottom,
      pocket: pocket ?? this.pocket,
      pocketTop: pocketTop ?? this.pocketTop,
      pocketWidth: pocketWidth ?? this.pocketWidth,
      drainHoles: drainHoles ?? this.drainHoles,
      drainCount: drainCount ?? this.drainCount,
      shrinkagePercent: shrinkagePercent ?? this.shrinkagePercent,
    );
  }

  /// Добавить молнию.
  ///
  /// Первая — по центру полотна. Вторая — разносим обе по трети ширины,
  /// чтобы полосы спайки не совпали и между ними осталось полотно.
  WindowParams addZipper() {
    if (zippers.length >= maxZippers) return this;
    if (zippers.isEmpty) {
      return copyWith(zippers: const [ZipperSpec(centered: true)]);
    }
    final third = math.max(bottomWidth / 3, 120.0);
    final bandWidth = zippers.first.bandWidth;
    return copyWith(
      zippers: [
        ZipperSpec(
          centered: false,
          offsetMm: third,
          bandWidth: bandWidth,
        ),
        ZipperSpec(
          centered: false,
          offsetMm: third * 2,
          bandWidth: bandWidth,
        ),
      ],
    );
  }

  WindowParams removeZipper([int index = 0]) {
    if (index < 0 || index >= zippers.length) return this;
    final next = [...zippers]..removeAt(index);
    return copyWith(zippers: next);
  }

  WindowParams updateZipper(int index, ZipperSpec zipper) {
    if (index < 0 || index >= zippers.length) return this;
    final next = [...zippers];
    next[index] = zipper;
    return copyWith(zippers: next);
  }

  WindowParams clearZippers() => copyWith(zippers: const []);

  WindowParams addCutout([Cutout? cutout]) {
    if (cutouts.length >= maxCutouts) return this;
    if (cutout != null) return copyWith(cutouts: [...cutouts, cutout]);
    // Новые вырезы ставим каскадом от центра, чтобы не накладывались.
    final index = cutouts.length;
    return copyWith(
      cutouts: [
        ...cutouts,
        Cutout(
          centerXMm: bottomWidth / 2,
          centerYMm: 400 + index * 450.0,
        ),
      ],
    );
  }

  WindowParams removeCutout(int index) {
    if (index < 0 || index >= cutouts.length) return this;
    final next = [...cutouts]..removeAt(index);
    return copyWith(cutouts: next);
  }

  WindowParams updateCutout(int index, Cutout cutout) {
    if (index < 0 || index >= cutouts.length) return this;
    final next = [...cutouts];
    next[index] = cutout;
    return copyWith(cutouts: next);
  }

  WindowParams toggleWelded(EdgeSide side) {
    final next = [...weldedSides];
    if (!next.remove(side)) next.add(side);
    return copyWith(weldedSides: next);
  }

  WindowParams withField(ParamField field, double value) => switch (field) {
        ParamField.bottomWidth => copyWith(bottomWidth: value),
        ParamField.topWidth => copyWith(topWidth: value),
        ParamField.leftHeight => copyWith(leftHeight: value),
        ParamField.rightHeight => copyWith(rightHeight: value),
        ParamField.topOffset => copyWith(topOffsetMm: value),
        ParamField.eyeletStep => copyWith(eyeletStep: value),
        ParamField.eyeletCornerOffset => copyWith(eyeletCornerOffset: value),
        ParamField.drainCount => copyWith(drainCount: value),
        ParamField.pocketWidth => copyWith(pocketWidth: value),
        ParamField.shrinkagePercent => copyWith(shrinkagePercent: value),
        ParamField.allowanceWidth => copyWith(allowanceWidthMm: value),
        ParamField.allowanceHeight => copyWith(allowanceHeightMm: value),
        ParamField.weldOverlap => copyWith(weldOverlapMm: value),
        ParamField.hemBottom => copyWith(hemBottomMm: value),
        ParamField.hemRight => copyWith(hemRightMm: value),
        ParamField.hemTop => copyWith(hemTopMm: value),
        ParamField.hemLeft => copyWith(hemLeftMm: value),
        // Зазор раскладки живёт в параметрах заказа — здесь только заглушка
        // для единообразия интерфейса.
        ParamField.rollGap => this,
      };

  double valueOf(ParamField field) => switch (field) {
        ParamField.bottomWidth => bottomWidth,
        ParamField.topWidth => topWidth,
        ParamField.leftHeight => leftHeight,
        ParamField.rightHeight => rightHeight,
        ParamField.topOffset => topOffsetMm,
        ParamField.eyeletStep => eyeletStep,
        ParamField.eyeletCornerOffset => eyeletCornerOffset,
        ParamField.drainCount => drainCount,
        ParamField.pocketWidth => pocketWidth,
        ParamField.shrinkagePercent => shrinkagePercent,
        ParamField.allowanceWidth => allowanceWidthMm,
        ParamField.allowanceHeight => allowanceHeightMm,
        ParamField.weldOverlap => weldOverlapMm,
        ParamField.hemBottom => hemBottomMm,
        ParamField.hemRight => hemRightMm,
        ParamField.hemTop => hemTopMm,
        ParamField.hemLeft => hemLeftMm,
        ParamField.rollGap => 0,
      };

  /// Краткая подпись состояния — используется для проверки перерисовки.
  String get signature => [
        projectName,
        customer,
        drawingNumber,
        windowType.name,
        bottomWidth,
        topWidth,
        leftHeight,
        rightHeight,
        allowanceWidthMm,
        allowanceHeightMm,
        topAlign.name,
        topOffsetMm,
        rollBottom,
        rollTop,
        rollLeft,
        rollRight,
        edgeMaterial.name,
        edgeColor.name,
        weldOverlapMm,
        eyeletType.name,
        eyeletStep,
        eyeletCornerOffset,
        material.name,
        hemBottomMm,
        hemRightMm,
        hemTopMm,
        hemLeftMm,
        fastenerType.name,
        for (final zipper in zippers)
          '${zipper.centered}:${zipper.offsetMm}:${zipper.bandWidth}',
        for (final cutout in cutouts)
          '${cutout.shape.name}:${cutout.width}:${cutout.height}:'
              '${cutout.centerXMm}:${cutout.centerYMm}',
        for (final side in weldedSides) side.name,
        removeEyeletsOnWelded,
        noEyeletsTop,
        noEyeletsBottom,
        zipperEnabled,
        zipperCentered,
        zipperOffsetMm,
        zipperBandWidth,
        pocket,
        pocketTop,
        pocketWidth,
        drainHoles,
        drainCount,
        shrinkagePercent,
      ].join('|');
}

/// Что показывать на листе.
class DrawingOptions {
  const DrawingOptions({
    this.showDimensions = true,
    this.showGrid = true,
    this.showEdgeLengths = true,
    this.showCallouts = true,
  });

  final bool showDimensions;
  final bool showGrid;
  final bool showEdgeLengths;
  final bool showCallouts;

  DrawingOptions copyWith({
    bool? showDimensions,
    bool? showGrid,
    bool? showEdgeLengths,
    bool? showCallouts,
  }) {
    return DrawingOptions(
      showDimensions: showDimensions ?? this.showDimensions,
      showGrid: showGrid ?? this.showGrid,
      showEdgeLengths: showEdgeLengths ?? this.showEdgeLengths,
      showCallouts: showCallouts ?? this.showCallouts,
    );
  }

  String get signature =>
      '$showDimensions|$showGrid|$showEdgeLengths|$showCallouts';
}

/// Форматирует миллиметры в стиле «3 000».
String formatMm(double value, {int decimals = 0}) {
  if (!value.isFinite) return '—';
  final text = value.toStringAsFixed(decimals);
  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  final parts = body.split('.');
  final grouped = _groupThousands(parts.first);
  final fraction = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '−' : ''}$grouped$fraction';
}

/// Сантиметры из миллиметров: «654».
String formatCm(double millimeters) => formatMm(millimeters / 10);

/// Знаковое число миллиметров: «+120», «−30» (минус U+2212), «0».
String formatSignedMm(double value) {
  if (!value.isFinite) return '—';
  return value > 0 ? '+${formatMm(value)}' : formatMm(value);
}

/// Метры с разделителем-запятой: «6,75».
String formatMeters(double squareMeters, {int decimals = 2}) {
  if (!squareMeters.isFinite) return '—';
  return squareMeters.toStringAsFixed(decimals).replaceAll('.', ',');
}

/// Проценты с запятой: «1,5 %».
String formatPercent(double percent) {
  if (!percent.isFinite) return '—';
  final text = percent
      .toStringAsFixed(2)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
  return '$text %';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('\u202F');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Разбирает ввод пользователя: поддерживает запятую и точку как разделитель.
double? parseMm(String raw) {
  final normalized = raw
      .trim()
      .replaceAll('\u202F', '')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  return double.tryParse(normalized);
}
