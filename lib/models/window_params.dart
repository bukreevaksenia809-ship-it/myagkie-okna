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
  zipperOffset,
  zipperBandWidth,
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
        ParamField.zipperOffset => 'Положение молнии от левого края',
        ParamField.zipperBandWidth => 'Ширина спайки молнии',
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
    this.zipperEnabled = false,
    this.zipperCentered = true,
    this.zipperOffsetMm = 0,
    this.zipperBandWidth = defaultZipperBandWidth,
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
  /// Молния: ставится отдельной кнопкой, всегда вертикально.
  final bool zipperEnabled;
  final bool zipperCentered;

  /// Положение центра молнии от левого внутреннего края плёнки, мм.
  final double zipperOffsetMm;

  /// Ширина спайки, в которую впаивается молния (молния по её центру).
  final double zipperBandWidth;

  /// Карман из тента по нижней кромке: утяжитель заводится в его полость.
  final bool pocket;

  /// Готовая ширина кармана, мм (рулон 200 мм складывается пополам).
  final double pocketWidth;

  final bool drainHoles;
  final double drainCount;

  /// Усадка ПВХ, % — плёнка кроится больше на эту величину.
  final double shrinkagePercent;

  bool get hasZipper => zipperEnabled;

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
    bool? zipperEnabled,
    bool? zipperCentered,
    double? zipperOffsetMm,
    double? zipperBandWidth,
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
      zipperEnabled: zipperEnabled ?? this.zipperEnabled,
      zipperCentered: zipperCentered ?? this.zipperCentered,
      zipperOffsetMm: zipperOffsetMm ?? this.zipperOffsetMm,
      zipperBandWidth: zipperBandWidth ?? this.zipperBandWidth,
      pocket: pocket ?? this.pocket,
      pocketWidth: pocketWidth ?? this.pocketWidth,
      drainHoles: drainHoles ?? this.drainHoles,
      drainCount: drainCount ?? this.drainCount,
      shrinkagePercent: shrinkagePercent ?? this.shrinkagePercent,
    );
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
        ParamField.zipperOffset => copyWith(zipperOffsetMm: value),
        ParamField.zipperBandWidth => copyWith(zipperBandWidth: value),
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
        ParamField.zipperOffset => zipperOffsetMm,
        ParamField.zipperBandWidth => zipperBandWidth,
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
