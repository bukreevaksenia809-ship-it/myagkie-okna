import 'dart:math' as math;

import 'crossbar.dart';

import '../services/units.dart';

// Единицы и подписи доступны всем, кто импортирует модель параметров:
// подавляющее большинство подписей живёт рядом с formatMm.
export '../services/units.dart';

/// Тип мягкого окна по способу открывания.
enum WindowType {
  fixed,
  lifting,

  /// Т-образное (или Г-образное) окно: основное полотно плюс приставка,
  /// сваренные по общей стороне. См. [WindowParams.tSide] и соседние поля.
  tShape,

  /// Составное окно: основное полотно из ПВХ и второй сегмент из другого
  /// материала (скрин или ПВХ), спаянные по общей линии шва.
  ///
  /// В отличие от Т-образного, второй материал может пристраиваться с любой
  /// стороны и по диагональному шву; см. [CompositeSpec].
  composite,

  /// Треугольное окно: основание — ширина, высота — высота, вершина может
  /// смещаться от центра.
  triangle,

  /// Домик: прямоугольная стена плюс треугольная крыша.
  house;

  String get label => switch (this) {
    WindowType.fixed => 'Глухое',
    WindowType.lifting => 'Подъёмное',
    WindowType.tShape => 'Т-образное',
    WindowType.composite => 'Составное',
    WindowType.triangle => 'Треугольник',
    WindowType.house => 'Домик',
  };

  String get hint => switch (this) {
    WindowType.fixed =>
      'Люверсы по периметру (любого типа; в углах круглые, если включён '
          'тумблер «Круглые люверсы в углах»). Молния и фартук — по желанию',
    WindowType.lifting =>
      'Сверху ряд люверсов, ниже скобы; сверху висят подъёмные ремни',
    WindowType.tShape =>
      'Два полотна — основное и приставка — свариваются по общей стороне. '
          'Окантовка идёт только по внешнему периметру, общая сторона — шов',
    WindowType.composite =>
      'Основное полотно из ПВХ и второй материал (скрин или ПВХ) спаяны по '
          'общему шву. Второй сегмент можно пристроить с любой стороны, в том '
          'числе по диагональному шву',
    WindowType.triangle =>
      'Основание — ширина, высота — общая высота, вершина смещается от центра',
    WindowType.house =>
      'Прямоугольная стена плюс треугольная крыша; высота крыши и свес '
          'задаются отдельно',
  };
}

/// Какая кромка окна остаётся строго горизонтальной при разных высотах
/// сторон.
///
/// [bottom] — низ горизонтален, весь перепад уходит на верхнюю кромку;
/// [top] — верх горизонтален на максимальной высоте, нижние углы смещены;
/// [none] — перепад делится поровну: верх и низ наклоняются в разные стороны.
enum LevelEdge {
  bottom('Низ ровно'),
  top('Верх ровно'),
  none('Нет');

  const LevelEdge(this.label);

  final String label;

  /// Короткая подпись для компактного переключателя.
  String get shortLabel => switch (this) {
    LevelEdge.bottom => 'Низ',
    LevelEdge.top => 'Верх',
    LevelEdge.none => 'Нет',
  };
}

/// Сторона основного полотна, к которой приваривается приставка Т-окна.
///
/// [right] — приставка справа (общая сторона вертикальная), [left] — слева,
/// [top] — сверху (общая сторона горизонтальная), [bottom] — снизу.
enum TShapeSide {
  right('Справа'),
  left('Слева'),
  top('Сверху'),
  bottom('Снизу');

  const TShapeSide(this.label);

  final String label;

  /// Сторона окна, которая является общей (спайкой).
  EdgeSide get sharedEdge => switch (this) {
    TShapeSide.right => EdgeSide.right,
    TShapeSide.left => EdgeSide.left,
    TShapeSide.top => EdgeSide.top,
    TShapeSide.bottom => EdgeSide.bottom,
  };
}

/// Пристройка Т-образного окна: сторона, размеры, смещение и спайка.
///
/// У окна может быть до двух пристроек (угловая форма: например, справа и
/// снизу). Пристройка — прямоугольник [width] × [height], приваренный к
/// стороне [side] основного полотна; [offset] — смещение вдоль общей стороны
/// (от низа для правой/левой, от левого края для верхней/нижней).
class TShapeAnnex {
  const TShapeAnnex({
    required this.number,
    required this.side,
    required this.width,
    required this.height,
    required this.offset,
    required this.welded,
  });

  /// Номер пристройки в панели и документах: 1 или 2.
  final int number;

  final TShapeSide side;
  final double width;
  final double height;
  final double offset;

  /// Спайка по общей стороне; false — отдельное окно.
  final bool welded;

  /// Подпись блока в панели и техкарте: «Пристройка 1».
  String get label => 'Пристройка $number';

  /// Сторона основного полотна, по которой идёт общая сторона (шов).
  EdgeSide get sharedEdge => side.sharedEdge;
}

/// Форма шва составного окна.
enum CompositeSeam {
  /// Шов параллелен выбранной стороне основного полотна: второй сегмент —
  /// прямоугольник, пристроенный снаружи стороны.
  straight('Прямой'),

  /// Шов пересекает сторону под углом: основной сегмент подрезается линией
  /// шва, второй встаёт к ней встык. Геометрия — честный многоугольник.
  diagonal('Диагональный');

  const CompositeSeam(this.label);

  final String label;
}

/// Второй сегмент составного окна.
///
/// Основное полотно — ПВХ с четырьмя габаритами ([WindowParams.bottomWidth] и
/// соседние): окантовка идёт по трём свободным сторонам, четвёртая — шов.
/// Второй сегмент пристраивается к любой стороне [side] и тоже имеет
/// окантовку/подворот по свободным сторонам, а сторона шва остаётся без
/// окантовки и без подворота.
///
/// [width] — размер второго сегмента вдоль шва, [depth] — вынос от шва
/// наружу, [offset] — смещение вдоль стороны основного полотна (от низа для
/// правой/левой, от левого края для верхней/нижней).
///
/// Для [CompositeSeam.diagonal] линия шва проходит через точку на стороне
/// ([seamOffset], доля 0…1 вдоль стороны) под углом [seamAngleDeg] к стороне;
/// второй конец линии шва лежит на контуре основного полотна. Второй сегмент
/// — четырёхугольник между линией шва и её выносом наружу на [depth].
class CompositeSpec {
  const CompositeSpec({
    this.side = EdgeSide.right,
    this.material = FilmMaterial.screen,
    this.width = 700,
    this.depth = 500,
    this.offset = 0,
    this.seam = CompositeSeam.straight,
    this.seamOffset = 0.5,
    this.seamAngleDeg = 25,
  });

  final EdgeSide side;
  final FilmMaterial material;
  final double width;
  final double depth;
  final double offset;
  final CompositeSeam seam;

  /// Доля 0…1 вдоль стороны, где линия диагонального шва пересекает сторону.
  final double seamOffset;

  /// Угол диагонального шва к стороне, градусы (0…80).
  final double seamAngleDeg;

  bool get isDiagonal => seam == CompositeSeam.diagonal;

  /// Угол шва в радианах.
  double get seamAngleRad => seamAngleDeg * math.pi / 180;

  /// Материал второго сегмента — скрин или ПВХ.
  bool get isScreen => material == FilmMaterial.screen;

  CompositeSpec copyWith({
    EdgeSide? side,
    FilmMaterial? material,
    double? width,
    double? depth,
    double? offset,
    CompositeSeam? seam,
    double? seamOffset,
    double? seamAngleDeg,
  }) =>
      CompositeSpec(
        side: side ?? this.side,
        material: material ?? this.material,
        width: width ?? this.width,
        depth: depth ?? this.depth,
        offset: offset ?? this.offset,
        seam: seam ?? this.seam,
        seamOffset: seamOffset ?? this.seamOffset,
        seamAngleDeg: seamAngleDeg ?? this.seamAngleDeg,
      );

  @override
  bool operator ==(Object other) =>
      other is CompositeSpec &&
      other.side == side &&
      other.material == material &&
      other.width == width &&
      other.depth == depth &&
      other.offset == offset &&
      other.seam == seam &&
      other.seamOffset == seamOffset &&
      other.seamAngleDeg == seamAngleDeg;

  @override
  int get hashCode => Object.hash(
        side,
        material,
        width,
        depth,
        offset,
        seam,
        seamOffset,
        seamAngleDeg,
      );
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
  clearPvc('Обычный ПВХ', 'ПВХ 700 мкм', [
    1400,
    1800,
    2000,
    2400,
    2600,
    3000,
  ]),
  tintedPvc('Тонированный ПВХ', 'ПВХ 700 мкм, тонировка', [
    1400,
    1800,
    2000,
    2400,
    3000,
  ]),
  mosquitoNet('Москитная сетка', 'сетка ПВХ', [
    1400,
    1800,
    2000,
    2400,
    2600,
    3000,
  ]),
  screen('Скрин', 'скрин-ткань ПВХ', [
    1400,
    1800,
    2000,
    2400,
    2500,
    2600,
    3000,
    5000,
  ]);

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
      rollWidths.map((width) => formatMm(width)).join(', ');
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

/// Пресет рулона окантовки: по нему читаются старые заказы, где ширина
/// писалась именем типа, и берётся цена прайса. Порядок значений — по ширине
/// рулона, он же порядок опорных точек цены ([PriceList.edgePerMeterForWidth]).
///
/// Полоса складывается пополам, поэтому готовая ширина окантовки — половина
/// ширины рулона.
enum EdgeRoll {
  roll80(80, 'Тент 80 мм = окантовка 40 мм'),
  roll100(100, 'Тент 100 мм = окантовка 50 мм'),
  roll120(120, 'Тент 120 мм = окантовка 60 мм'),
  roll200(200, 'Тент 200 мм = окантовка 100 мм'),
  roll240(240, 'Тент 240 мм = окантовка 120 мм');

  const EdgeRoll(this.rawWidth, this.label);

  /// Ширина рулона, мм.
  final double rawWidth;

  final String label;

  /// Готовая ширина окантовки после складывания пополам, мм.
  double get finishedWidth => rawWidth / 2;

  String get shortLabel => 'Тент ${rawWidth.toStringAsFixed(0)} ${unitSuffix()}';

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
  final width = '${formatMm(rawWidth)} ${unitSuffix()}';
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

  /// Размер в текущей единице: «Ø10 мм» или «Ø1,0 см», «42×22 мм» / «4,2×2,2 см».
  String get sizeLabel => isRound
      ? 'Ø${formatMm(10)} ${unitSuffix()}'
      : '${formatMm(42)}×${formatMm(22)} ${unitSuffix()}';

  /// Полное название для подписей: «Круглый Ø10 мм», «Овальный 42×22 мм».
  String get displayLabel => isRound ? 'Круглый $sizeLabel' : 'Овальный $sizeLabel';
}

/// Крепёж подвижных сторон (низ и бока подъёмного окна).
enum FastenerType {
  eyeletsOnly('Только люверсы'),
  turnBuckles('Поворотные скобы'),
  frenchLocks('Пластиковая скоба'),
  metalFrenchLock('Французский замок'),
  straps('Силиконовые ремни');

  const FastenerType(this.label);

  final String label;

  /// Название крепежа в единственном числе — для сметы и ведомости, где
  /// строка считается за штуку: «Поворотная скоба — 12 шт».
  String get itemTitle => switch (this) {
    FastenerType.eyeletsOnly => 'Только люверсы',
    FastenerType.turnBuckles => 'Поворотная скоба',
    FastenerType.frenchLocks => 'Пластиковая скоба',
    FastenerType.metalFrenchLock => 'Французский замок',
    FastenerType.straps => 'Силиконовый ремень',
  };
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
  tWidth,
  tHeight,
  tOffset,
  t2Width,
  t2Height,
  t2Offset,
  compositeWidth,
  compositeDepth,
  compositeOffset,
  compositeAngle,
  zipperTentOverlap,
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
    ParamField.tWidth => 'Ширина приставки',
    ParamField.tHeight => 'Высота приставки',
    ParamField.tOffset => 'Смещение приставки',
    ParamField.t2Width => 'Ширина пристройки 2',
    ParamField.t2Height => 'Высота пристройки 2',
    ParamField.t2Offset => 'Смещение пристройки 2',
    ParamField.compositeWidth => 'Ширина второго сегмента',
    ParamField.compositeDepth => 'Вынос второго сегмента',
    ParamField.compositeOffset => 'Смещение второго сегмента',
    ParamField.compositeAngle => 'Угол шва',
    ParamField.zipperTentOverlap => 'Напайка тента молнии',
    ParamField.eyeletStep => 'Интервал люверсов',
    ParamField.eyeletCornerOffset => 'Отступ люверса от угла',
    ParamField.drainCount => 'Дренажных отверстий',
    ParamField.pocketWidth => 'Ширина фартука',
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
    ParamField.compositeAngle => '°',
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

/// Добавка к ВЫСОТЕ заготовки скрина, мм — на шов и запас.
///
/// В заготовку идёт половина введённого подворота с каждой стороны. По ширине
/// прибавка — ровно `лево / 2 + право / 2`; по высоте к ней добавляются эти
/// 20 мм: `низ / 2 + верх / 2 + 20`. См.
/// [WindowParams.hemAxisLeftRightIncrease] и
/// [WindowParams.hemAxisBottomTopIncrease].
const double screenHemAxisExtraMm = 20;

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
/// разными. Пресеты панели — [screenHemPresets] (40/50/60 и крупные
/// 80/100/120), значение по умолчанию [defaultScreenHemMm].
const double defaultScreenHemMm = 40;
const double minScreenHemMm = 10;

/// Верхняя граница подворота, мм. Поднята до 200, чтобы пресеты 80/100/120
/// проходили с запасом и технолог мог ввести крупный подворот руками.
const double maxScreenHemMm = 200;
const List<double> screenHemPresets = [40, 50, 60, 80, 100, 120];

/// Разумный предел припуска на раскрой, мм: больше — почти наверняка опечатка.
const double maxAllowanceMm = 500;

/// Авто-припуск к ВЫСОТЕ заготовки для ПВХ-полотна, мм.
///
/// По умолчанию цех кроит ПВХ на 10 мм выше: ролики и шов напайки по верхней
/// и нижней кромке «съедают» высоту, и без запаса полотно после сварки уходит
/// в минус по замеру. Припуск — только на РАСКРОЙ (заготовку): изделие,
/// чертёж, окантовка и люверсы считаются по замеру. У скрина запаса нет —
/// он подворачивается и кроится по половинам подворотов,
/// см. [WindowParams.hemAxisBottomTopIncrease].
const double pvcHeightAllowanceMm = 10;

/// Усадка ПВХ, % — значение, которое панель подставляет в поле, когда
/// технолог включает тумблер «Учитывать усадку ПВХ».
///
/// Сам тумблер по умолчанию выключен, и тогда заготовка кроится без запаса
/// на усадку ([WindowParams.effectiveShrinkagePercent] = 0). Типовая усадка
/// плёнки — 1–2 %, поэтому при включении подставляем 1,5 %.
const double defaultShrinkagePercent = 1.5;

/// Рамка ввода поля усадки, %: 0…5. Больше — уже не типовая партия.
const double maxShrinkageFieldPercent = 5;

/// Сколько молний и вырезов можно поставить на одно окно.
const int maxZippers = 5;
const int maxCutouts = 4;

/// Полоса спайки, которой сваривают два соседних окна между собой, мм.
const double windowWeldWidth = 25;

/// Молния в полотне: всегда вертикальная, положение — от левого края плёнки.
class ZipperSpec {
  const ZipperSpec({
    this.centered = true,
    this.offsetMm = 0,
    this.zipWidthMm = defaultZipperWidthMm,
    this.tentWidthMm = defaultZipperTentWidthMm,
    this.weldMm = defaultZipperWeldMm,
    this.atEdge = false,
    this.edgeRight = false,
  });

  /// По центру полотна (иначе — по [offsetMm] от левого края).
  final bool centered;

  /// Положение центра молнии от левого внутреннего края плёнки, мм.
  final double offsetMm;

  /// Ширина самой молнии, мм.
  final double zipWidthMm;

  /// Ширина тента с одной стороны от молнии, мм.
  final double tentWidthMm;

  /// Напайка тента на полотно (с одной стороны), мм.
  final double weldMm;

  /// Молния стоит вплотную к окантовке (слева или справа).
  final bool atEdge;

  /// При [atEdge] — сторона примыкания: справа (иначе слева).
  final bool edgeRight;

  /// Полоса молнии посередине полотна: молния + два тента − две напайки.
  double get bandWidth =>
      math.max(zipWidthMm + 2 * tentWidthMm - 2 * weldMm, 1);

  /// Полоса молнии у края: готовая окантовка + молния + тент − напайка.
  double edgeBandWidth(double edgeFinishedMm) =>
      math.max(edgeFinishedMm + zipWidthMm + tentWidthMm - weldMm, 1);

  /// Полоса с учётом положения: у края считаем окантовку, в середине — два
  /// тента.
  double bandWidthFor(double edgeFinishedMm) =>
      atEdge ? edgeBandWidth(edgeFinishedMm) : bandWidth;

  ZipperSpec copyWith({
    bool? centered,
    double? offsetMm,
    double? zipWidthMm,
    double? tentWidthMm,
    double? weldMm,
    bool? atEdge,
    bool? edgeRight,
  }) => ZipperSpec(
    centered: centered ?? this.centered,
    offsetMm: offsetMm ?? this.offsetMm,
    zipWidthMm: zipWidthMm ?? this.zipWidthMm,
    tentWidthMm: tentWidthMm ?? this.tentWidthMm,
    weldMm: weldMm ?? this.weldMm,
    atEdge: atEdge ?? this.atEdge,
    edgeRight: edgeRight ?? this.edgeRight,
  );

  Map<String, dynamic> toJson() => {
    'centered': centered,
    'offsetMm': offsetMm,
    'zipWidthMm': zipWidthMm,
    'tentWidthMm': tentWidthMm,
    'weldMm': weldMm,
    'atEdge': atEdge,
    'edgeRight': edgeRight,
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
  }) => Cutout(
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
  double get perimeterMm =>
      shape == CutoutShape.circle ? math.pi * width : 2 * (width + height);

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

/// Ширина молнии по умолчанию, мм.
const double defaultZipperWidthMm = 15;

/// Ширина тента с одной стороны молнии по умолчанию, мм.
const double defaultZipperTentWidthMm = 50;

/// Напайка тента на полотно по умолчанию, мм.
const double defaultZipperWeldMm = 20;

/// Старое имя ширины полосы — оставлено для чтения старых заказов.
const double defaultZipperBandWidth = 50;

/// Ширина молнии в режиме «доп. настройки»: 5 см тент + 1 см молния + 5 см
/// тент. 2 см тента с каждой стороны напаивается на полотно, поэтому зазор
/// между сегментами — 7 см.
const double zipperSegmentBandWidth = 110;

/// Напайка тента молнии на полотно с каждой стороны по умолчанию, мм.
const double defaultZipperTentOverlapMm = 20;
const double minZipperTentOverlapMm = 5;
const double maxZipperTentOverlapMm = 50;

/// Фартук (бывший карман): рулон тента 200 мм складывается пополам → 100 мм.
const double pocketRollWidth = 200;
const double pocketFinishedWidth = 100;

/// Что именно стоит в ручной точке на чертеже.
enum MarkerKind {
  /// Обычный люверс: тип берётся из настроек окна (в углах — правило угла).
  eyelet('Люверс'),

  /// Круглый люверс — явно выбран при добавлении из меню.
  roundEyelet('Круглый люверс'),

  /// Пластиковая скоба в этой точке.
  frenchLock('Пластиковая скоба'),

  /// Поворотная скоба в этой точке.
  turnBuckle('Поворотная скоба');

  const MarkerKind(this.label);

  final String label;
}

/// Ручное положение люверса на стороне окна.
///
/// Задаётся долей вдоль ребра контура (0 — начало ребра, 1 — конец), поэтому
/// при изменении размеров люверсы остаются на своих местах. Сторона без
/// записей расставляется автоматически по интервалу.
class EyeletPosition {
  const EyeletPosition({
    required this.side,
    required this.fraction,
    this.kind = MarkerKind.eyelet,
  });

  final EdgeSide side;

  /// Доля 0…1 вдоль ребра наружного контура.
  final double fraction;

  /// Что стоит в точке: люверс, круглый, замок или скоба.
  final MarkerKind kind;

  EyeletPosition copyWith({
    EdgeSide? side,
    double? fraction,
    MarkerKind? kind,
  }) =>
      EyeletPosition(
        side: side ?? this.side,
        fraction: fraction ?? this.fraction,
        kind: kind ?? this.kind,
      );

  Map<String, dynamic> toJson() => {
    'side': side.name,
    'fraction': fraction,
    'kind': kind.name,
  };

  factory EyeletPosition.fromJson(Map<String, dynamic> json) {
    final sideName = json['side'];
    final rawFraction = json['fraction'];
    final kindName = json['kind'];
    return EyeletPosition(
      side: EdgeSide.values.firstWhere(
        (side) => side.name == sideName,
        orElse: () => EdgeSide.bottom,
      ),
      fraction: rawFraction is num && rawFraction.isFinite
          ? rawFraction.toDouble().clamp(0.0, 1.0)
          : 0.5,
      kind: MarkerKind.values.firstWhere(
        (kind) => kind.name == kindName,
        orElse: () => MarkerKind.eyelet,
      ),
    );
  }
}

/// На сколько поднимается нижний люверс, чтобы фартук открывался, мм.
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
    this.levelEdge = LevelEdge.bottom,
    this.tSide = TShapeSide.right,
    this.tWidth = 800,
    this.tHeight = 600,
    this.tOffset = 0,
    this.tWelded = true,
    this.tEnabled = true,
    this.t2Enabled = false,
    this.t2Side = TShapeSide.bottom,
    this.t2Width = 700,
    this.t2Height = 500,
    this.t2Offset = 0,
    this.t2Welded = true,
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
    this.screenColor = '',
    this.apexOffsetMm = 0,
    this.roofHeightMm = 500,
    this.roofOverhangMm = 0,
    this.wallHeightMm = 0,
    this.crossbars = const [],
    this.fastenerOffsets = const {},
    this.eyeletStep = 300,
    this.eyeletCornerOffset = 0,
    this.roundEyeletsEnabled = true,
    this.fastenerType = FastenerType.turnBuckles,
    this.zippers = const [],
    this.zipperSegments = false,
    this.zipperTentOverlap = defaultZipperTentOverlapMm,
    this.liftStrapOffsets = const [],
    this.cutouts = const [],
    this.eyeletPositions = const [],
    this.manualEyeletSides = const [],
    this.composite = const CompositeSpec(),
    this.noEyeletsTop = false,
    this.noEyeletsBottom = false,
    this.pocket = false,
    this.pocketTop = false,
    this.pocketWidth = pocketFinishedWidth,
    this.drainHoles = false,
    this.drainCount = 3,
    this.shrinkageEnabled = false,
    this.shrinkagePercent = 0,
    this.pvcHeightAllowanceEnabled = true,
  });

  // Маркировка
  final String projectName;
  final String customer;

  /// Дополнительная маркировка окна (номер заказа, примечание).
  final String drawingNumber;

  /// Цвет скрина для клиентского отчёта (например «серый», «белый»).
  final String screenColor;

  /// Смещение вершины треугольника/крыши от центра, мм (+ вправо).
  final double apexOffsetMm;

  /// Высота крыши домика, мм.
  final double roofHeightMm;

  /// Свес крыши домика за стену с каждой стороны, мм.
  final double roofOverhangMm;

  /// Явная высота стены домика, мм (0 — считать как общая − крыша).
  final double wallHeightMm;

  /// Перемычки внутри полотна.
  final List<CrossbarSpec> crossbars;

  /// Положение крепежа в полосе окантовки: 0 — внутренний край,
  /// 0.5 — середина, 1 — внешний. По сторонам независимо.
  final Map<EdgeSide, double> fastenerOffsets;

  double fastenerOffsetFor(EdgeSide side) =>
      (fastenerOffsets[side] ?? 0.5).clamp(0.05, 0.95).toDouble();

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

  /// Припуск на раскрой по высоте, мм — вводится вручную (по умолчанию 0).
  ///
  /// К заготовке ПВХ добавляется ещё авто-припуск [pvcHeightAllowanceMm]
  /// (см. [effectiveAllowanceHeightMm]) — он учитывается только в раскрое.
  final double allowanceHeightMm;

  /// Тумблер «+10 мм к высоте по умолчанию (ПВХ)».
  ///
  /// Включён по умолчанию: заготовка ПВХ кроится на [pvcHeightAllowanceMm]
  /// выше замера ([autoHeightAllowanceMm]). Для скрина флаг не действует:
  /// у скрина авто-припуска нет никогда.
  final bool pvcHeightAllowanceEnabled;

  final TopAlign topAlign;
  final double topOffsetMm;

  /// Какая кромка остаётся горизонтальной при разных высотах сторон.
  ///
  /// По умолчанию [LevelEdge.bottom] — низ ровно: низ горизонтален, верх
  /// наклонён (прежняя геометрия). [LevelEdge.top] фиксирует верх, [none]
  /// делит перепад поровну между верхом и низом.
  final LevelEdge levelEdge;

  // --- Т-образное окно (windowType == WindowType.tShape) -------------------
  //
  // Пристройка — прямоугольник [tWidth] × [tHeight], приваренный к стороне
  // [tSide] основного полотна. [tOffset] — смещение вдоль общей стороны:
  // от низа для правой/левой, от левого края для верхней/нижней.
  // При [tWelded] == false это два отдельных окна: окантовка считается по
  // периметру каждой части, шва по общей стороне нет.
  //
  // Вторая пристройка ([t2Side] и соседние поля) — для угловой формы: две
  // пристройки на разных сторонах, например справа и снизу. У старых заказов
  // её нет, поэтому [t2Enabled] по умолчанию выключен: чтение старого JSON
  // даёт ровно прежнее Т-окно с одной пристройкой.

  /// Включена ли первая пристройка. По умолчанию включена: у старого заказа
  /// без поля Т-окно остаётся прежним — основное полотно плюс пристройка.
  final bool tEnabled;

  /// Сторона основного полотна, к которой крепится пристройка.
  final TShapeSide tSide;

  /// Ширина приставки (по горизонтали), мм.
  final double tWidth;

  /// Высота приставки (по вертикали), мм.
  final double tHeight;

  /// Смещение приставки вдоль общей стороны, мм.
  final double tOffset;

  /// Спайка по общей стороне. false — два отдельных окна.
  final bool tWelded;

  /// Включена ли вторая пристройка (угловая форма). У старых заказов — нет.
  final bool t2Enabled;

  /// Сторона второй пристройки. Должна отличаться от [tSide]: две пристройки
  /// на одной стороне запрещены (см. [tAnnexSideConflict]).
  final TShapeSide t2Side;

  /// Ширина второй пристройки, мм.
  final double t2Width;

  /// Высота второй пристройки, мм.
  final double t2Height;

  /// Смещение второй пристройки вдоль общей стороны, мм.
  final double t2Offset;

  /// Спайка второй пристройки по общей стороне.
  final bool t2Welded;

  /// Включённые пристройки в порядке номеров.
  ///
  /// Пустой список — Т-окно без пристроек (только основное полотно).
  List<TShapeAnnex> get tAnnexes => !isTShape
      ? const []
      : [
          if (tEnabled)
            TShapeAnnex(
              number: 1,
              side: tSide,
              width: tWidth,
              height: tHeight,
              offset: tOffset,
              welded: tWelded,
            ),
          if (t2Enabled)
            TShapeAnnex(
              number: 2,
              side: t2Side,
              width: t2Width,
              height: t2Height,
              offset: t2Offset,
              welded: t2Welded,
            ),
        ];

  /// Есть ли включённые пристройки (только для Т-окна).
  bool get hasTAnnexes => isTShape && tAnnexes.isNotEmpty;

  /// Есть ли вторая включённая пристройка.
  bool get hasSecondAnnex => isTShape && tEnabled && t2Enabled;

  /// Есть ли хотя бы одна спайка пристройки с основным полотном.
  bool get tAnyWelded => tAnnexes.any((annex) => annex.welded);

  /// Спаяны ли все пристройки с основным полотном (или пристроек нет).
  bool get tAllWelded =>
      tAnnexes.isEmpty || tAnnexes.every((annex) => annex.welded);

  /// Обе пристройки стоят на одной стороне — так нельзя.
  ///
  /// Проверка параметров и панель показывают предупреждение, а геометрия
  /// оставляет только первую пристройку: расчёт не ломается и не рисует
  /// наложение двух пристроек в одном месте.
  bool get tAnnexSideConflict => hasSecondAnnex && t2Side == tSide;

  /// Подпись сторон пристроек для документов:
  /// «Пристройка 1 — справа; Пристройка 2 — снизу».
  String get tAnnexSidesLabel => tAnnexes
      .map((annex) => '${annex.label} — ${annex.side.label.toLowerCase()}')
      .join('; ');

  /// Пресеты ширины рулона окантовки, мм — быстрые кнопки в панели.
  ///
  /// Свою ширину можно ввести вручную (40…400 мм); эти пять значений —
  /// готовые варианты в панели и одновременно опорные точки прайса
  /// (PriceList.edgePerMeterForWidth): у каждого пресета есть своя цена,
  /// поэтому нестандартная ширина между ними считается интерполяцией.
  /// Порядок — по возрастанию ширины рулона.
  static const List<double> edgePresets = [80, 100, 120, 200, 240];

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

  /// Ставить ли круглые люверсы в углах полотна.
  ///
  /// Включено по умолчанию: угол тянет по диагонали, поэтому именно там
  /// ставится круглый Ø10 мм, даже если по сторонам выбран овальный люверс.
  /// Выключение убирает угловую точку **полностью** — не только с чертежа,
  /// но и из расхода и сметы: заказчик получает окно без единого круглого
  /// люверса (например, когда всё крепление — пластиковые скобы или скобы).
  ///
  /// Флаг не влияет на люверсы, сдвинутые от угла на
  /// [eyeletCornerOffset]: это обычные точки стороны, а не угловые.
  final bool roundEyeletsEnabled;

  /// Чем крепятся подвижные стороны (низ и бока).
  final FastenerType fastenerType;

  // Спецэлементы
  /// Молнии: каждая ставится отдельной кнопкой, все вертикальные.
  final List<ZipperSpec> zippers;

  /// Положения подъёмных ремней вручную: центр от левого края полотна, мм.
  ///
  /// Пустой список — прежняя автоматическая расстановка по числу
  /// [liftStrapCount]. Непустой — ровно эти ремни; каждый привязан к линии
  /// тента на своей высоте (на косом окне линии тоже косая).
  final List<double> liftStrapOffsets;

  /// «Доп. настройка молнии»: делить полотно на сегменты по молниям.
  ///
  /// Выключено — прежнее поведение: ширина молнии просто вычитается из
  /// ширины заготовки. Включено — ширина полосы 11 см (5 тент + 1 молния +
  /// 5 тент), молния между сегментами даёт зазор 7 см (по 2 см тента
  /// напаивается на каждый сегмент), впритык к канту — без деления.
  final bool zipperSegments;

  /// Напайка тента молнии на полотно с каждой стороны, мм (по умолчанию 20).
  ///
  /// В режиме сегментов из ширины вычитается `ширина молнии − 2 × напайка`:
  /// 11 см при напайке 2 см дают 7 см — и для молнии между сегментами
  /// (зазор), и для молнии впритык к канту (вычет из кроя).
  final double zipperTentOverlap;

  /// Вырезы (отверстия) в полотне.
  final List<Cutout> cutouts;

  /// Ручные положения люверсов (перетащены мышкой на чертеже).
  ///
  /// Пусто — автоматическая расстановка по интервалу. Если для стороны есть
  /// записи, на ней ставятся ровно они; остальные стороны остаются авто.
  final List<EyeletPosition> eyeletPositions;

  /// Стороны, у которых люверсы заданы вручную (в том числе пустым списком).
  ///
  /// Именно этот список отличает «сторону без люверсов» от «стороны с
  /// автоматической расстановкой»: если сторона в нём есть, берутся только
  /// [eyeletPositions], даже когда их ноль.
  final List<EdgeSide> manualEyeletSides;

  /// Второй сегмент составного окна ([WindowType.composite]).
  ///
  /// У остальных типов окна поле не используется и пишется в JSON только для
  /// составного окна, чтобы старые заказы не менялись.
  final CompositeSpec composite;

  /// Спайка с соседним окном удалена: старые заказы с полем `weldedSides`
  /// открываются без шва (поле в JSON игнорируется). Взамен — составное окно.

  /// Не ставить люверсы сверху.
  ///
  /// Сторона остаётся совсем без крепежа: там предполагается спайка с соседним
  /// окном или крепление полотна к стене/раме другим способом. Углы стороны
  /// тоже не ставятся — они принадлежат ей по правилу обхода (см.
  /// `WindowLayers.eyelets`).
  final bool noEyeletsTop;

  /// Не ставить люверсы снизу — зеркально [noEyeletsTop].
  final bool noEyeletsBottom;

  /// Фартук (бывший карман) из тента по нижней кромке: утяжитель заводится
  /// в его полость. У скрина фартук образуется верхним/нижним подворотом.
  ///
  /// Имя поля `pocket` сохранено ради JSON-совместимости со старыми заказами.
  final bool pocket;

  /// Фартук (бывший карман) по верхней кромке — зеркально нижнему.
  final bool pocketTop;

  /// Готовая ширина фартука, мм (рулон 200 мм складывается пополам).
  ///
  /// Поле по-прежнему называется `pocketWidth` — это имя в JSON заказов.
  final double pocketWidth;

  final bool drainHoles;
  final double drainCount;

  /// Усадка ПВХ, % — плёнка кроится больше на эту величину.
  ///
  /// Значение применяется, только когда включён [shrinkageEnabled]
  /// (см. [effectiveShrinkagePercent]). По умолчанию усадка выключена,
  /// поэтому и процент по умолчанию 0.
  final double shrinkagePercent;

  /// Учитывать усадку ПВХ при раскрое.
  ///
  /// По умолчанию **выключено**: заготовка равна расчётной, а поле процента в
  /// панели скрыто. Включает технолог, если партия плёнки даёт усадку; тогда
  /// применяется [shrinkagePercent] (типовое значение
  /// [defaultShrinkagePercent]).
  final bool shrinkageEnabled;

  bool get hasZipper => zippers.isNotEmpty;

  /// Первая молния — для подписей и совместимости.
  ZipperSpec? get zipper => zippers.isEmpty ? null : zippers.first;

  bool get zipperEnabled => zippers.isNotEmpty;

  bool get zipperCentered => zipper?.centered ?? true;

  double get zipperOffsetMm => zipper?.offsetMm ?? 0;

  double get zipperBandWidth => zipper?.bandWidth ?? defaultZipperBandWidth;

  /// Есть ли припуск на раскрой хотя бы по одной оси — с учётом авто-припуска
  /// ПВХ по высоте ([effectiveAllowanceHeightMm]).
  bool get hasAllowance =>
      allowanceWidthMm != 0 || effectiveAllowanceHeightMm != 0;

  /// Задан ли припуск на раскрой вручную (без авто-припуска ПВХ).
  bool get hasManualAllowance =>
      allowanceWidthMm != 0 || allowanceHeightMm != 0;

  /// Авто-припуск к высоте заготовки, мм: [pvcHeightAllowanceMm] для ПВХ при
  /// включённом [pvcHeightAllowanceEnabled]; у скрина — всегда 0.
  double get autoHeightAllowanceMm =>
      (isPvcFilm && pvcHeightAllowanceEnabled) ? pvcHeightAllowanceMm : 0;

  /// Припуск по высоте, который реально уходит в раскрой: ручной
  /// [allowanceHeightMm] плюс авто-припуск ПВХ ([autoHeightAllowanceMm]).
  double get effectiveAllowanceHeightMm =>
      allowanceHeightMm + autoHeightAllowanceMm;

  /// Есть ли авто-припуск по высоте (для подписей «(авто)»).
  bool get hasAutoHeightAllowance => autoHeightAllowanceMm != 0;

  /// Припуск по ширине в виде «+120» / «−30» / «0».
  String get allowanceWidthLabel => formatSignedMm(allowanceWidthMm);

  /// Фактический припуск по высоте («авто + вручную») в виде «+10» / «0».
  String get allowanceHeightLabel => formatSignedMm(effectiveAllowanceHeightMm);

  /// Ручной припуск по высоте в виде «+80» / «0» — для разбивки в панели.
  String get manualAllowanceHeightLabel => formatSignedMm(allowanceHeightMm);

  /// Разбивка припуска по высоте для панели и документов:
  /// «Припуск по высоте: 10 мм (авто) + 0 мм (вручную) = 10 мм».
  String get heightAllowanceBreakdownLabel =>
      'Припуск по высоте: ${formatMm(autoHeightAllowanceMm)} ${unitSuffix()} (авто) + '
      '${formatMm(allowanceHeightMm)} ${unitSuffix()} (вручную) = '
      '${formatMm(effectiveAllowanceHeightMm)} ${unitSuffix()}';

  /// Подпись припуска для документов: «припуск +120/+10 мм».
  String get allowanceLabel => hasAllowance
      ? 'припуск $allowanceWidthLabel/$allowanceHeightLabel ${unitSuffix()}'
      : 'припуск 0/0 мм';

  // Размеры заготовки плёнки с припуском на раскрой. Изделие при этом
  // остаётся размером замера: геометрия и все расчёты идут по основным
  // размерам, а припуск добавляется только в раскрое плёнки.
  // По высоте берётся фактический припуск: ручной плюс авто-припуск ПВХ.
  double get effectiveBottomWidth => bottomWidth + allowanceWidthMm;
  double get effectiveTopWidth => topWidth + allowanceWidthMm;
  double get effectiveLeftHeight => leftHeight + effectiveAllowanceHeightMm;
  double get effectiveRightHeight => rightHeight + effectiveAllowanceHeightMm;

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

  /// Полотно из ПВХ: обычный ПВХ, тонированный ПВХ и москитная сетка.
  ///
  /// Все три кроятся по одной технологии — заготовка с напайкой под
  /// окантовку, — поэтому авто-припуск [pvcHeightAllowanceMm] к высоте
  /// действует и на москитную сетку (это тоже ПВХ-полотно, просто сетчатое).
  /// Скрин — отдельная технология с подворотом: авто-припуска у него нет.
  bool get isPvcFilm => !isScreen;

  /// Усадка, которая реально применяется к раскрою.
  ///
  /// У скрина усадки нет (ткань не тянется, как плёнка ПВХ). У ПВХ усадка
  /// берётся из [shrinkagePercent], но только когда тумблер
  /// [shrinkageEnabled] включён: при выключенном тумблере заготовка кроится
  /// ровно по расчёту, а поле процента в панели скрыто.
  double get effectiveShrinkagePercent =>
      (isScreen || !shrinkageEnabled) ? 0 : shrinkagePercent;

  /// Применяется ли усадка к раскрою ([effectiveShrinkagePercent] > 0).
  bool get hasShrinkage => effectiveShrinkagePercent > 0;

  /// Количество подъёмных ремней: 2 при ширине до 2 м, далее +1 на каждый метр.
  int get liftStrapCount {
    // Скрин крепится только люверсами: ремней у него нет.
    if (!isLifting || isScreen) return 0;
    final width = bottomWidth.isFinite && bottomWidth > 0 ? bottomWidth : 0.0;
    if (width <= 2000) return 2;
    return 2 + ((width - 2000) / 1000).ceil();
  }

  bool get isLifting => windowType == WindowType.lifting;

  /// Т-образное окно: основное полотно плюс приставка.
  bool get isTShape => windowType == WindowType.tShape;

  /// Треугольное окно.
  bool get isTriangle => windowType == WindowType.triangle;

  /// Домик: стена + крыша.
  bool get isHouse => windowType == WindowType.house;

  /// Треугольник или домик — особая форма с многоугольным контуром.
  bool get isSpecialShape => isTriangle || isHouse;

  bool get hasCrossbars => crossbars.isNotEmpty;

  WindowParams withCrossbars(List<CrossbarSpec> value) =>
      copyWith(crossbars: value);

  WindowParams addCrossbar([CrossbarSpec? value]) =>
      withCrossbars([...crossbars, value ?? const CrossbarSpec()]);

  WindowParams updateCrossbar(int index, CrossbarSpec value) {
    if (index < 0 || index >= crossbars.length) return this;
    final next = List<CrossbarSpec>.of(crossbars);
    next[index] = value;
    return withCrossbars(next);
  }

  WindowParams removeCrossbar(int index) {
    if (index < 0 || index >= crossbars.length) return this;
    final next = List<CrossbarSpec>.of(crossbars)..removeAt(index);
    return withCrossbars(next);
  }

  /// Составное окно: ПВХ-полотно плюс второй материал по общему шву.
  bool get isComposite => windowType == WindowType.composite;

  /// Составное окно с диагональным швом.
  bool get hasDiagonalSeam => isComposite && composite.isDiagonal;

  /// Глухое окно: обычное глухое или Т-образное (обе части стоят на месте).
  bool get isFixedShape => !isLifting;

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
  List<double> get hemWidths => [hemBottomMm, hemRightMm, hemTopMm, hemLeftMm];

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
  /// В расчёт ЗАГОТОВКИ она не входит: там работает половина подворота
  /// каждой стороны (см. [hemAxisBottomTopIncrease]).
  double get hemTotalMm => hemBottomMm + hemRightMm + hemTopMm + hemLeftMm;

  /// Половина подворота снизу, мм — именно она идёт в заготовку.
  double get hemBottomHalfMm => hemBottomMm / 2;

  /// Половина подворота справа, мм.
  double get hemRightHalfMm => hemRightMm / 2;

  /// Половина подворота сверху, мм.
  double get hemTopHalfMm => hemTopMm / 2;

  /// Половина подворота слева, мм.
  double get hemLeftHalfMm => hemLeftMm / 2;

  /// Прибавка к заготовке скрина по горизонтали, мм.
  ///
  /// Ширина заготовки = ширина изделия +
  /// `hemLeftMm / 2 + hemRightMm / 2`. Подвороты 80/80 дают 80 мм (по 40 на
  /// кромку), 120/120 — 120 мм. Добавки [screenHemAxisExtraMm] по ширине НЕТ:
  /// +20 мм идёт только к высоте.
  ///
  /// Это правило заказчика (пример: скрин 1000 × 1000, подвороты
  /// 80/80/120/80 → ширина 1000 + 40 + 40 = 1080, высота
  /// 1000 + 40 + 60 + 20 = 1120). ПВХ эта прибавка не касается: у него своя
  /// напайка под окантовку.
  double get hemAxisLeftRightIncrease => hemLeftHalfMm + hemRightHalfMm;

  /// Прибавка к заготовке скрина по вертикали, мм.
  ///
  /// Высота заготовки = высота изделия +
  /// `hemBottomMm / 2 + hemTopMm / 2 + screenHemAxisExtraMm`: при подворотах
  /// 80/120 на изделии 1000 мм получается 1000 + 40 + 60 + 20 = 1120 мм.
  /// +20 мм — постоянная добавка на шов и запас, только к высоте. Смысл
  /// остального правила — в [hemAxisLeftRightIncrease].
  double get hemAxisBottomTopIncrease =>
      hemBottomHalfMm + hemTopHalfMm + screenHemAxisExtraMm;

  /// Все четыре подворота одинаковы — тогда старые версии приложения
  /// поймут заказ по одиночному полю `hemMm` в JSON.
  bool get hasUniformHem =>
      hemBottomMm == hemRightMm &&
      hemRightMm == hemTopMm &&
      hemTopMm == hemLeftMm;

  /// Подпись подворотов по сторонам: «низ 40, право 50, верх 60, лево 40 мм».
  String get hemBySideLabel =>
      'низ ${formatMm(hemBottomMm)}, '
      'право ${formatMm(hemRightMm)}, верх ${formatMm(hemTopMm)}, '
      'лево ${formatMm(hemLeftMm)} ${unitSuffix()}';

  /// Короткая подпись подворотов по сторонам: «40/50/60/40 мм»
  /// (низ/право/верх/лево).
  String get hemBySideShortLabel =>
      '${formatMm(hemBottomMm)}/${formatMm(hemRightMm)}/'
      '${formatMm(hemTopMm)}/${formatMm(hemLeftMm)} ${unitSuffix()}';

  WindowParams copyWith({
    String? projectName,
    String? customer,
    String? drawingNumber,
    String? screenColor,
    double? apexOffsetMm,
    double? roofHeightMm,
    double? roofOverhangMm,
    double? wallHeightMm,
    List<CrossbarSpec>? crossbars,
    Map<EdgeSide, double>? fastenerOffsets,
    WindowType? windowType,
    double? bottomWidth,
    double? topWidth,
    double? leftHeight,
    double? rightHeight,
    double? allowanceWidthMm,
    double? allowanceHeightMm,
    TopAlign? topAlign,
    double? topOffsetMm,
    LevelEdge? levelEdge,
    TShapeSide? tSide,
    double? tWidth,
    double? tHeight,
    double? tOffset,
    bool? tWelded,
    bool? tEnabled,
    bool? t2Enabled,
    TShapeSide? t2Side,
    double? t2Width,
    double? t2Height,
    double? t2Offset,
    bool? t2Welded,
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
    bool? roundEyeletsEnabled,
    FastenerType? fastenerType,
    List<ZipperSpec>? zippers,
    bool? zipperSegments,
    double? zipperTentOverlap,
    List<double>? liftStrapOffsets,
    List<Cutout>? cutouts,
    List<EyeletPosition>? eyeletPositions,
    List<EdgeSide>? manualEyeletSides,
    CompositeSpec? composite,
    bool? noEyeletsTop,
    bool? noEyeletsBottom,
    bool? pocket,
    bool? pocketTop,
    double? pocketWidth,
    bool? drainHoles,
    double? drainCount,
    bool? shrinkageEnabled,
    double? shrinkagePercent,
    bool? pvcHeightAllowanceEnabled,
  }) {
    return WindowParams(
      projectName: projectName ?? this.projectName,
      customer: customer ?? this.customer,
      drawingNumber: drawingNumber ?? this.drawingNumber,
    screenColor: screenColor ?? this.screenColor,
    apexOffsetMm: apexOffsetMm ?? this.apexOffsetMm,
    roofHeightMm: roofHeightMm ?? this.roofHeightMm,
    roofOverhangMm: roofOverhangMm ?? this.roofOverhangMm,
    wallHeightMm: wallHeightMm ?? this.wallHeightMm,
    crossbars: crossbars ?? this.crossbars,
    fastenerOffsets: fastenerOffsets ?? this.fastenerOffsets,
      windowType: windowType ?? this.windowType,
      bottomWidth: bottomWidth ?? this.bottomWidth,
      topWidth: topWidth ?? this.topWidth,
      leftHeight: leftHeight ?? this.leftHeight,
      rightHeight: rightHeight ?? this.rightHeight,
      allowanceWidthMm: allowanceWidthMm ?? this.allowanceWidthMm,
      allowanceHeightMm: allowanceHeightMm ?? this.allowanceHeightMm,
      topAlign: topAlign ?? this.topAlign,
      topOffsetMm: topOffsetMm ?? this.topOffsetMm,
      levelEdge: levelEdge ?? this.levelEdge,
      tSide: tSide ?? this.tSide,
      tWidth: tWidth ?? this.tWidth,
      tHeight: tHeight ?? this.tHeight,
      tOffset: tOffset ?? this.tOffset,
      tWelded: tWelded ?? this.tWelded,
      tEnabled: tEnabled ?? this.tEnabled,
      t2Enabled: t2Enabled ?? this.t2Enabled,
      t2Side: t2Side ?? this.t2Side,
      t2Width: t2Width ?? this.t2Width,
      t2Height: t2Height ?? this.t2Height,
      t2Offset: t2Offset ?? this.t2Offset,
      t2Welded: t2Welded ?? this.t2Welded,
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
      roundEyeletsEnabled: roundEyeletsEnabled ?? this.roundEyeletsEnabled,
      fastenerType: fastenerType ?? this.fastenerType,
      zippers: zippers ?? this.zippers,
      zipperSegments: zipperSegments ?? this.zipperSegments,
      zipperTentOverlap: zipperTentOverlap ?? this.zipperTentOverlap,
      liftStrapOffsets: liftStrapOffsets ?? this.liftStrapOffsets,
      cutouts: cutouts ?? this.cutouts,
      eyeletPositions: eyeletPositions ?? this.eyeletPositions,
      manualEyeletSides: manualEyeletSides ?? this.manualEyeletSides,
      composite: composite ?? this.composite,
      noEyeletsTop: noEyeletsTop ?? this.noEyeletsTop,
      noEyeletsBottom: noEyeletsBottom ?? this.noEyeletsBottom,
      pocket: pocket ?? this.pocket,
      pocketTop: pocketTop ?? this.pocketTop,
      pocketWidth: pocketWidth ?? this.pocketWidth,
      drainHoles: drainHoles ?? this.drainHoles,
      drainCount: drainCount ?? this.drainCount,
      shrinkageEnabled: shrinkageEnabled ?? this.shrinkageEnabled,
      shrinkagePercent: shrinkagePercent ?? this.shrinkagePercent,
      pvcHeightAllowanceEnabled:
          pvcHeightAllowanceEnabled ?? this.pvcHeightAllowanceEnabled,
    );
  }

  /// Поставить ручные точки одной стороны, сохранив остальные стороны.
  WindowParams withManualPoints(
    EdgeSide side,
    List<EyeletPosition> points,
  ) => copyWith(
    eyeletPositions: [
      for (final position in eyeletPositions)
        if (position.side != side) position,
      for (final point in points)
        EyeletPosition(
          side: side,
          fraction: point.fraction.clamp(0.0, 1.0),
          kind: point.kind,
        ),
    ],
    manualEyeletSides: [
      for (final manual in manualEyeletSides)
        if (manual != side) manual,
      side,
    ],
  );

  /// Короткая запись: поставить доли одной стороны (тип — обычный люверс).
  WindowParams withEyeletPositions(
    EdgeSide side,
    List<double> fractions,
  ) => withManualPoints(
    side,
    [for (final fraction in fractions) EyeletPosition(
      side: side,
      fraction: fraction,
    )],
  );

  /// Вернуть автоматическую расстановку люверсов на всех сторонах.
  WindowParams clearEyeletPositions() =>
      copyWith(eyeletPositions: const [], manualEyeletSides: const []);

  /// Сторона расставлена вручную (в том числе пустым списком).
  bool hasManualEyelets(EdgeSide side) => manualEyeletSides.contains(side);

  /// Добавить подъёмный ремешок с центром [offsetMm] от левого края.
  WindowParams addLiftStrap(double offsetMm) => copyWith(
    liftStrapOffsets: [...liftStrapOffsets, offsetMm],
  );

  WindowParams removeLiftStrap(int index) {
    if (index < 0 || index >= liftStrapOffsets.length) return this;
    final next = [...liftStrapOffsets]..removeAt(index);
    return copyWith(liftStrapOffsets: next);
  }

  WindowParams updateLiftStrap(int index, double offsetMm) {
    if (index < 0 || index >= liftStrapOffsets.length) return this;
    final next = [...liftStrapOffsets];
    next[index] = offsetMm;
    return copyWith(liftStrapOffsets: next);
  }

  /// Включить/выключить «доп. настройку молнии».
  ///
  /// Ширина полосы больше не задаётся вручную: она считается из ширины
  /// молнии, тента и напайки (см. [ZipperSpec]).
  WindowParams withZipperSegments(bool enabled) =>
      copyWith(zipperSegments: enabled);

  /// Добавить молнию.
  ///
  /// Первая — по центру полотна. Вторая — разносим обе по трети ширины,
  /// чтобы полосы спайки не совпали и между ними осталось полотно.
  WindowParams addZipper() {
    if (zippers.length >= maxZippers) return this;
    if (zippers.isEmpty) {
      return copyWith(
        zippers: [
          const ZipperSpec(centered: true),
        ],
      );
    }
    // До 5 молний: каждая следующая встаёт в самый широкий свободный
    // промежуток, существующие положения не сдвигаются.
    final width = math.max(bottomWidth, 200.0);
    final positions = [
      for (final zipper in zippers)
        zipper.centered ? width / 2 : zipper.offsetMm,
    ]..sort();
    final edges = <double>[0, ...positions, width];
    var bestStart = 0.0;
    var bestEnd = width;
    var bestGap = -1.0;
    for (var i = 0; i < edges.length - 1; i++) {
      final gap = edges[i + 1] - edges[i];
      if (gap > bestGap) {
        bestGap = gap;
        bestStart = edges[i];
        bestEnd = edges[i + 1];
      }
    }
    return copyWith(
      zippers: [
        ...zippers,
        ZipperSpec(
          centered: false,
          offsetMm: ((bestStart + bestEnd) / 2).clamp(0.0, width),
          zipWidthMm: zippers.first.zipWidthMm,
          tentWidthMm: zippers.first.tentWidthMm,
          weldMm: zippers.first.weldMm,
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
        Cutout(centerXMm: bottomWidth / 2, centerYMm: 400 + index * 450.0),
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

  WindowParams withField(ParamField field, double value) => switch (field) {
    ParamField.bottomWidth => copyWith(bottomWidth: value),
    ParamField.topWidth => copyWith(topWidth: value),
    ParamField.leftHeight => copyWith(leftHeight: value),
    ParamField.rightHeight => copyWith(rightHeight: value),
    ParamField.topOffset => copyWith(topOffsetMm: value),
    ParamField.tWidth => copyWith(tWidth: value),
    ParamField.tHeight => copyWith(tHeight: value),
    ParamField.tOffset => copyWith(tOffset: value),
    ParamField.t2Width => copyWith(t2Width: value),
    ParamField.t2Height => copyWith(t2Height: value),
    ParamField.t2Offset => copyWith(t2Offset: value),
    ParamField.compositeWidth =>
      copyWith(composite: composite.copyWith(width: value)),
    ParamField.compositeDepth =>
      copyWith(composite: composite.copyWith(depth: value)),
    ParamField.compositeOffset =>
      copyWith(composite: composite.copyWith(offset: value)),
    ParamField.compositeAngle =>
      copyWith(composite: composite.copyWith(seamAngleDeg: value)),
    ParamField.zipperTentOverlap => copyWith(zipperTentOverlap: value),
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
    ParamField.tWidth => tWidth,
    ParamField.tHeight => tHeight,
    ParamField.tOffset => tOffset,
    ParamField.t2Width => t2Width,
    ParamField.t2Height => t2Height,
    ParamField.t2Offset => t2Offset,
    ParamField.compositeWidth => composite.width,
    ParamField.compositeDepth => composite.depth,
    ParamField.compositeOffset => composite.offset,
    ParamField.compositeAngle => composite.seamAngleDeg,
    ParamField.zipperTentOverlap => zipperTentOverlap,
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
  ///
  /// ВАЖНО: здесь должны быть ВСЕ поля, влияющие на чертёж. Пропущенное поле
  /// означает, что его изменение не перерисует лист: именно так переход
  /// «Ровно» низ → верх выглядел как «ничего не происходит» — галочка в панели
  /// переезжала, а чертёж оставался прежним, потому что
  /// `WindowDrawingPainter.shouldRepaint` сравнивает эту подпись.
  String get signature => [
    projectName,
    customer,
    drawingNumber,
    windowType.name,
    // Какая кромка горизонтальна: меняет координаты углов, а габарит и
    // масштаб у режимов совпадают — без этого поля перерисовки не было.
    levelEdge.name,
    bottomWidth,
    topWidth,
    leftHeight,
    rightHeight,
    apexOffsetMm,
    roofHeightMm,
    roofOverhangMm,
    wallHeightMm,
    [for (final crossbar in crossbars)
      '${crossbar.axis.name}:${crossbar.positionMm}:${crossbar.widthMm}:'
          '${crossbar.weldMm}:${crossbar.fullSpan}:${crossbar.lengthMm}'],
    allowanceWidthMm,
    allowanceHeightMm,
    topAlign.name,
    topOffsetMm,
    tSide.name,
    tWidth,
    tHeight,
    tOffset,
    tWelded,
    tEnabled,
    t2Enabled,
    t2Side.name,
    t2Width,
    t2Height,
    t2Offset,
    t2Welded,
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
    roundEyeletsEnabled,
    material.name,
    hemBottomMm,
    hemRightMm,
    hemTopMm,
    hemLeftMm,
    fastenerType.name,
    for (final zipper in zippers)
      '${zipper.centered}:${zipper.offsetMm}:${zipper.bandWidth}',
    zipperSegments,
    zipperTentOverlap,
    for (final offset in liftStrapOffsets) offset,
    for (final cutout in cutouts)
      '${cutout.shape.name}:${cutout.width}:${cutout.height}:'
          '${cutout.centerXMm}:${cutout.centerYMm}',
    for (final side in manualEyeletSides) side.name,
    for (final eyelet in eyeletPositions)
      '${eyelet.side.name}:${eyelet.fraction.toStringAsFixed(5)}:${eyelet.kind.name}',
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
    shrinkageEnabled,
    shrinkagePercent,
    pvcHeightAllowanceEnabled,
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

/// Форматирует длину в ТЕКУЩЕЙ единице отображения: «3 000» или «300,0».
///
/// В миллиметрах сохраняется прежнее поведение (0 знаков по умолчанию),
/// в сантиметрах — не меньше одного знака. Рядом с числом подпись единицы
/// ставится через [unitSuffix]: «${formatMm(x)} ${unitSuffix()}».
String formatMm(double value, {int decimals = 0}) =>
    DisplayUnits.formatNumber(value, decimals: decimals);

/// Длина с дробной частью только когда она есть: «40» или «40,5».
///
/// Нужна для половин подворота: 80 → «40», 81 → «40,5». В сантиметрах
/// показывается один знак после запятой, как у остальных длин.
String formatMmTrimmed(double value) {
  if (!value.isFinite) return '—';
  final rounded = value.roundToDouble();
  final digits = (value - rounded).abs() < 1e-9 ? 0 : 1;
  return DisplayUnits.formatNumber(value, decimals: digits);
}

/// Сантиметры из миллиметров: «654». Не зависит от переключателя единиц.
String formatCm(double millimeters) =>
    formatDecimal(millimeters / 10, decimals: 0);

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

/// Разбирает ввод пользователя: поддерживает запятую и точку как разделитель.
double? parseMm(String raw) {
  final normalized = raw
      .trim()
      .replaceAll('\u202F', '')
      .replaceAll(' ', '')
      .replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final parsed = double.tryParse(normalized);
  if (parsed == null) return null;
  // Ввод идёт в текущей единице: в сантиметрах число сразу переводим в мм,
  // чтобы модель и все формулы остались миллиметровыми.
  return DisplayUnits.unit == LengthUnit.cm ? parsed * 10 : parsed;
}
