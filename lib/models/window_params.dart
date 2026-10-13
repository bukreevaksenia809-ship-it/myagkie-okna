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
          'Только круглые люверсы по периметру. Молния и карман — по желанию',
        WindowType.lifting =>
          'Сверху ряд люверсов, ниже скобы; сверху висят подъёмные ремни',
      };
}

/// Материал полотна: от него зависит вид на чертеже и доступные ширины рулонов.
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

/// Рулон окантовки. Полоса складывается пополам, поэтому готовая ширина
/// окантовки — половина ширины рулона.
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
}

/// Материал окантовки.
enum EdgeMaterial {
  pvcTent630,
  oxford600,
  oxford1680;

  String get label => switch (this) {
        EdgeMaterial.pvcTent630 => 'ПВХ-тент 630–650 г/м²',
        EdgeMaterial.oxford600 => 'Oxford 600D',
        EdgeMaterial.oxford1680 => 'Oxford 1680D',
      };

  /// Способ соединения: ПВХ сваривают, Oxford шьют.
  String get joining => switch (this) {
        EdgeMaterial.pvcTent630 => 'Сварка горячим воздухом 400–500 °C',
        EdgeMaterial.oxford600 => 'Шитьё',
        EdgeMaterial.oxford1680 => 'Шитьё',
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
  rollGap;

  String get label => switch (this) {
        ParamField.bottomWidth => 'Ширина низ',
        ParamField.topWidth => 'Ширина верх',
        ParamField.leftHeight => 'Высота лево',
        ParamField.rightHeight => 'Высота право',
        ParamField.topOffset => 'Смещение верх',
        ParamField.eyeletStep => 'Шаг люверсов',
        ParamField.eyeletCornerOffset => 'Отступ люверса от угла',
        ParamField.drainCount => 'Дренажных отверстий',
        ParamField.pocketWidth => 'Ширина кармана',
        ParamField.shrinkagePercent => 'Усадка ПВХ',
        ParamField.rollGap => 'Зазор при раскладке',
      };

  String get unit => switch (this) {
        ParamField.shrinkagePercent => '%',
        ParamField.drainCount => 'шт',
        _ => 'мм',
      };
}

/// Припуск на сварку (напайка): плёнка заходит под окантовку на 25 мм всегда.
const double weldOverlap = 25;

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
    this.topAlign = TopAlign.center,
    this.topOffsetMm = 0,
    this.rollBottom = EdgeRoll.roll100,
    this.rollTop = EdgeRoll.roll100,
    this.rollLeft = EdgeRoll.roll100,
    this.rollRight = EdgeRoll.roll100,
    this.edgeMaterial = EdgeMaterial.pvcTent630,
    this.edgeColor = EdgeColor.brown,
    this.eyeletType = EyeletType.round10,
    this.material = FilmMaterial.clearPvc,
    this.eyeletStep = 300,
    this.eyeletCornerOffset = 0,
    this.fastenerType = FastenerType.turnBuckles,
    this.zippers = const [],
    this.cutouts = const [],
    this.weldedSides = const [],
    this.removeEyeletsOnWelded = true,
    this.pocket = false,
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
  final TopAlign topAlign;
  final double topOffsetMm;

  // Окантовка: своя ширина рулона на каждую сторону
  final EdgeRoll rollBottom;
  final EdgeRoll rollTop;
  final EdgeRoll rollLeft;
  final EdgeRoll rollRight;

  final EdgeMaterial edgeMaterial;
  final EdgeColor edgeColor;

  /// Материал полотна: обычный ПВХ, тонированный или москитная сетка.
  final FilmMaterial material;

  // Крепёж
  final EyeletType eyeletType;
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

  /// Карман из тента по нижней кромке: утяжитель заводится в его полость.
  final bool pocket;

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

  /// У глухого окна ставятся только круглые люверсы.
  EyeletType get effectiveEyeletType =>
      windowType == WindowType.fixed ? EyeletType.round10 : eyeletType;

  /// Доступные ширины рулонов для выбранного материала, мм.
  List<double> get availableRollWidths => material.rollWidths;

  /// Количество подъёмных ремней: 2 при ширине до 2 м, далее +1 на каждый метр.
  int get liftStrapCount {
    if (!isLifting) return 0;
    final width = bottomWidth.isFinite && bottomWidth > 0 ? bottomWidth : 0.0;
    if (width <= 2000) return 2;
    return 2 + ((width - 2000) / 1000).ceil();
  }

  bool get isLifting => windowType == WindowType.lifting;

  /// Тип окантовки для стороны с индексом обхода углов.
  EdgeRoll rollForEdge(int index) => switch (index % 4) {
        0 => rollBottom,
        1 => rollRight,
        2 => rollTop,
        _ => rollLeft,
      };

  EdgeRoll rollForSide(EdgeSide side) => switch (side) {
        EdgeSide.bottom => rollBottom,
        EdgeSide.right => rollRight,
        EdgeSide.top => rollTop,
        EdgeSide.left => rollLeft,
      };

  WindowParams copyWith({
    String? projectName,
    String? customer,
    String? drawingNumber,
    WindowType? windowType,
    double? bottomWidth,
    double? topWidth,
    double? leftHeight,
    double? rightHeight,
    TopAlign? topAlign,
    double? topOffsetMm,
    EdgeRoll? rollBottom,
    EdgeRoll? rollTop,
    EdgeRoll? rollLeft,
    EdgeRoll? rollRight,
    EdgeMaterial? edgeMaterial,
    EdgeColor? edgeColor,
    FilmMaterial? material,
    EyeletType? eyeletType,
    double? eyeletStep,
    double? eyeletCornerOffset,
    FastenerType? fastenerType,
    List<ZipperSpec>? zippers,
    List<Cutout>? cutouts,
    List<EdgeSide>? weldedSides,
    bool? removeEyeletsOnWelded,
    bool? pocket,
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
      topAlign: topAlign ?? this.topAlign,
      topOffsetMm: topOffsetMm ?? this.topOffsetMm,
      rollBottom: rollBottom ?? this.rollBottom,
      rollTop: rollTop ?? this.rollTop,
      rollLeft: rollLeft ?? this.rollLeft,
      rollRight: rollRight ?? this.rollRight,
      edgeMaterial: edgeMaterial ?? this.edgeMaterial,
      edgeColor: edgeColor ?? this.edgeColor,
      material: material ?? this.material,
      eyeletType: eyeletType ?? this.eyeletType,
      eyeletStep: eyeletStep ?? this.eyeletStep,
      eyeletCornerOffset: eyeletCornerOffset ?? this.eyeletCornerOffset,
      fastenerType: fastenerType ?? this.fastenerType,
      zippers: zippers ?? this.zippers,
      cutouts: cutouts ?? this.cutouts,
      weldedSides: weldedSides ?? this.weldedSides,
      removeEyeletsOnWelded:
          removeEyeletsOnWelded ?? this.removeEyeletsOnWelded,
      pocket: pocket ?? this.pocket,
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
        topAlign.name,
        topOffsetMm,
        rollBottom.name,
        rollTop.name,
        rollLeft.name,
        rollRight.name,
        edgeMaterial.name,
        edgeColor.name,
        eyeletType.name,
        eyeletStep,
        eyeletCornerOffset,
        material.name,
        fastenerType.name,
        for (final zipper in zippers)
          '${zipper.centered}:${zipper.offsetMm}:${zipper.bandWidth}',
        for (final cutout in cutouts)
          '${cutout.shape.name}:${cutout.width}:${cutout.height}:'
              '${cutout.centerXMm}:${cutout.centerYMm}',
        for (final side in weldedSides) side.name,
        removeEyeletsOnWelded,
        zipperEnabled,
        zipperCentered,
        zipperOffsetMm,
        zipperBandWidth,
        pocket,
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
