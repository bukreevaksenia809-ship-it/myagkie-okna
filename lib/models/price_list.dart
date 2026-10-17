// Прайс-лист цеха мягких окон: цены материалов, фурнитуры и работ.
//
// Модель общая для панели цен (`lib/widgets/price_panel.dart`) и для расчёта
// сметы (`lib/services/estimate.dart`). Никаких зависимостей от Flutter UI
// здесь нет — только чистый Dart, чтобы прайс можно было сохранять в JSON.
//
// Все цены — в рублях. Площади — за м², длины окантовки/молнии/спайки —
// за погонный метр, люверсы/ремни/дренаж/вырезы — за штуку.

import 'window_params.dart';

/// Группы цен, которые правит панель цен.
enum PriceField {
  filmClear,
  filmTinted,
  filmMesh,
  filmScreen,
  edge80,
  edge100,
  edge120,
  edge200,
  edge240;

  /// Подпись для поля ввода в панели.
  String get label => switch (this) {
        PriceField.filmClear => 'Плёнка ПВХ прозрачная',
        PriceField.filmTinted => 'Плёнка ПВХ тонированная',
        PriceField.filmMesh => 'Москитная сетка',
        PriceField.filmScreen => 'Скрин (ткань)',
        PriceField.edge80 => 'Окантовка, рулон 80 мм (готово 40)',
        PriceField.edge100 => 'Окантовка, рулон 100 мм (готово 50)',
        PriceField.edge120 => 'Окантовка, рулон 120 мм (готово 60)',
        PriceField.edge200 => 'Окантовка, рулон 200 мм (готово 100)',
        PriceField.edge240 => 'Окантовка, рулон 240 мм (готово 120)',
      };

  /// Короткая подпись — для колонок и итогов.
  String get shortLabel => switch (this) {
        PriceField.filmClear => 'ПВХ прозрачный',
        PriceField.filmTinted => 'ПВХ тонированный',
        PriceField.filmMesh => 'Сетка',
        PriceField.filmScreen => 'Скрин',
        PriceField.edge80 => 'Тент 80',
        PriceField.edge100 => 'Тент 100',
        PriceField.edge120 => 'Тент 120',
        PriceField.edge200 => 'Тент 200',
        PriceField.edge240 => 'Тент 240',
      };

  /// Ключ позиции прайса: имя поля уже совпадает с [PriceItemKeys].
  String get itemKey => name;

  /// Единица измерения цены.
  String get unit => switch (this) {
        PriceField.filmClear ||
        PriceField.filmTinted ||
        PriceField.filmMesh ||
        PriceField.filmScreen =>
          '₽/м²',
        _ => '₽/м',
      };
}

/// Ключи позиций прайса — одно место для модели, панели цен и сметы.
///
/// Ключ — стабильная строка: она лежит в JSON заказа, поэтому имена не
/// переименовываются при рефакторинге. Ключи плёнки и окантовки совпадают с
/// именами [PriceField] (`PriceField.filmClear.name == filmClear`), чтобы
/// лист «Смета» мог показывать выключенные позиции без отдельной таблицы.
///
/// Позиция — это строка прайса с ценой за единицу. Проценты расчёта
/// (наценка, скидка, НДС) — настройки, а не позиции: их не выключают, у них
/// своё значение (0 % = не считать).
class PriceItemKeys {
  PriceItemKeys._();

  // Полотно.
  static const String filmClear = 'filmClear';
  static const String filmTinted = 'filmTinted';
  static const String filmMesh = 'filmMesh';
  static const String filmScreen = 'filmScreen';

  // Окантовка.
  static const String edge80 = 'edge80';
  static const String edge100 = 'edge100';
  static const String edge120 = 'edge120';
  static const String edge200 = 'edge200';
  static const String edge240 = 'edge240';

  // Фурнитура.
  static const String eyeletRound = 'eyeletRound';
  static const String eyeletOval = 'eyeletOval';

  /// Установка люверса: отдельной строки в смете нет (она входит в цену
  /// люверса), поэтому выключение убирает из цены люверса только установку.
  static const String eyeletInstall = 'eyeletInstall';
  static const String zipper = 'zipper';
  static const String weld = 'weld';
  static const String pocket = 'pocket';

  /// Ремень, ₽/шт: одна позиция прайса на подъёмный ремень и на силиконовый
  /// ремень-крепёж — это один и тот же материал ленты.
  static const String strap = 'strap';
  static const String drain = 'drain';
  static const String cutout = 'cutout';

  // Крепёж подвижных сторон: скоба, замок, саморез верхнего ряда.
  static const String turnBuckle = 'turnBuckle';
  static const String frenchLock = 'frenchLock';
  static const String screw = 'screw';

  // Работы.
  static const String labor = 'labor';
  static const String cutting = 'cutting';
  static const String screenHem = 'screenHem';

  /// Все известные ключи. Прайс из JSON фильтруется по этому набору:
  /// неизвестный ключ (из будущей версии) не тащим в модель.
  static const Set<String> all = {
    filmClear,
    filmTinted,
    filmMesh,
    filmScreen,
    edge80,
    edge100,
    edge120,
    edge200,
    edge240,
    eyeletRound,
    eyeletOval,
    eyeletInstall,
    zipper,
    weld,
    pocket,
    strap,
    drain,
    cutout,
    turnBuckle,
    frenchLock,
    screw,
    labor,
    cutting,
    screenHem,
  };
}

/// Цена прозрачного ПВХ 700 мкм, ₽/м².
///
/// Ориентир 2026 года: 700–1200 ₽/м² в зависимости от объёма партии
/// и продавца; 950 — средняя цена небольшого цеха с запасом на отход.
const double defaultFilmClearPerM2 = 950;

/// Цена тонированного ПВХ 700 мкм, ₽/м² (прозрачный + тонировка ~200 ₽).
const double defaultFilmTintedPerM2 = 1150;

/// Цена москитной сетки ПВХ, ₽/м² (сетка дешевле плёнки: 300–500 ₽).
const double defaultFilmMeshPerM2 = 420;

/// Цена скрина (ткань ПВХ под подворот), ₽/м². Ориентир 450–600 ₽/м².
const double defaultFilmScreenPerM2 = 520;

/// Подворот скрина и шов 3 мм — работа, ₽/м по периметру.
const double defaultScreenHemPerM = 180;

/// Окантовка из рулона 80 мм (готовая полоса 40 мм), ₽/м.
///
/// Ориентир: рулон уже 100-го, материала на метр уходит меньше, но раскрой и
/// шов на каждый погонный метр те же, поэтому цена снижается не пропорционально
/// ширине: 120 ₽/м ≈ 0,86 от цены 100-го рулона.
const double defaultEdge80PerM = 120;

/// Окантовка из рулона 100 мм (готовая полоса 50 мм), ₽/м.
///
/// Ориентир: 120–160 ₽/м; тонкий рулон режется вдвое, но требует больше шва.
const double defaultEdge100PerM = 140;

/// Окантовка из рулона 120 мм (готовая полоса 60 мм), ₽/м.
///
/// Между 100-м (140 ₽/м) и 200-м (230 ₽/м) рулонами: линейная интерполяция
/// дала бы 158 ₽/м, берём 165 ₽/м — полоса 60 мм нестандартная, её чаще
/// режут из более широкого рулона, поэтому закладываем небольшой отход.
const double defaultEdge120PerM = 165;

/// Окантовка из рулона 200 мм (готовая 100 мм), ₽/м. Ориентир 200–260 ₽/м.
const double defaultEdge200PerM = 230;

/// Окантовка из рулона 240 мм (готовая 120 мм), ₽/м. Ориентир 240–300 ₽/м.
const double defaultEdge240PerM = 270;

/// Люверс круглый Ø10 мм без установки, ₽/шт (латунь/нерж.: 60–120 ₽).
const double defaultEyeletPrice = 65;

/// Люверс овальный 42×22 мм под скобу без установки, ₽/шт.
const double defaultEyeletOvalPrice = 110;

/// Установка люверса (пробой, запрессовка, инструмент), ₽/шт.
const double defaultEyeletInstall = 25;

/// Молния тракторная с впайкой в полотно (материал + вставка + спайка), ₽/м.
///
/// Ориентир 600–900 ₽/м; берём середину — 780.
const double defaultZipperPerM = 780;

/// Спайка полотен двух соседних окон между собой, ₽/м (горячий воздух).
const double defaultWeldPerM = 450;

/// Фартук (бывший карман) под утяжитель (тент 200 мм, сложенный пополам), ₽/м.
const double defaultPocketPerM = 380;

/// Подъёмный ремень 50 × 500 мм, ₽/шт.
///
/// Эта же цена — для силиконового ремня-крепежа подвижных сторон
/// ([FastenerType.straps]): материал ленты один, различаются длина и способ
/// крепления к раме, а раскрой и установка в цехе одинаковые.
const double defaultStrapPrice = 190;

/// Поворотная скоба (оцинкованная, с шурупом 6×60), ₽/шт.
///
/// Ориентир 2026 года: 180–260 ₽/шт в рознице за скобу в сборе с крепежом.
/// Берём 220 — середину: скоба примерно вдвое дороже овального люверса
/// (110 ₽), через который она ставится, потому что это отдельная деталь
/// с шурупом, а не кольцо.
const double defaultTurnBucklePrice = 220;

/// Французский замок (защёлка с ответной частью и шурупами), ₽/шт.
///
/// Ориентир: 320–500 ₽/шт. 400 — замок с прижимом и ответной планкой дороже
/// скобы (220 ₽) почти вдвое: в комплекте две детали и пружина. Ставится так
/// же через овальный люверс, поэтому люверс считается отдельной строкой.
const double defaultFrenchLockPrice = 400;

/// Саморез верхнего ряда (прессшайба 6×50), ₽/шт.
///
/// Ориентир: 12–30 ₽/шт за саморез с уплотнительной шайбой. 20 ₽ — верхний
/// ряд крепится к раме с тем же шагом, что люверсы, но саморез дешевле
/// люверса с установкой (65 + 25 ₽): это расходник, а не фурнитура.
const double defaultScrewPrice = 20;

/// Дренажное отверстие Ø6 мм в нижней окантовке, ₽/шт.
const double defaultDrainPrice = 90;

/// Вырез в полотне под трубу/вентиляцию с обработкой контура, ₽/шт.
///
/// Окантовка по контуру выреза считается отдельно — она уже входит
/// в расход окантовки в `CostsSummary.edgeByRoll`.
const double defaultCutoutPrice = 350;

/// Сварка и сборка изделия, ₽/м² площади готового изделия.
///
/// Ориентир 500–900 ₽/м²; 700 — средняя ставка цеха.
const double defaultLaborPerM2 = 700;

/// Раскрой плёнки и разметка, ₽/м² площади плёнки в раскрое.
const double defaultCuttingPerM2 = 250;

/// Наценка по умолчанию, %. Ноль — цена прайса уже розничная.
const double defaultMarkupPercent = 0;

/// Скидка по умолчанию, %.
const double defaultDiscountPercent = 0;

/// НДС по умолчанию, %. Считается «сверху» — см. комментарий у [PriceList].
const double defaultVatPercent = 20;

/// Символ валюты.
const String defaultCurrencySymbol = '₽';

/// Прайс-лист: цены за единицу и настройки расчёта сметы.
///
/// Про НДС: выбран режим **«НДС сверху»** — налог начисляется на сумму
/// после наценки и скидки и прибавляется к ИТОГО. Это удобно для частных
/// заказов («итого к оплате»), но если цех работает по «НДС в том числе»,
/// достаточно выставить `vatPercent = 0` и заранее заложить налог в цены:
/// отдельного режима «в том числе» модель не держит, чтобы не было
/// двусмысленности в одном и том же ИТОГО.
class PriceList {
  const PriceList({
    this.filmClearPerM2 = defaultFilmClearPerM2,
    this.filmTintedPerM2 = defaultFilmTintedPerM2,
    this.filmMeshPerM2 = defaultFilmMeshPerM2,
    this.filmScreenPerM2 = defaultFilmScreenPerM2,
    this.screenHemPerM = defaultScreenHemPerM,
    this.edge80PerM = defaultEdge80PerM,
    this.edge100PerM = defaultEdge100PerM,
    this.edge120PerM = defaultEdge120PerM,
    this.edge200PerM = defaultEdge200PerM,
    this.edge240PerM = defaultEdge240PerM,
    this.eyeletPrice = defaultEyeletPrice,
    this.eyeletOvalPrice = defaultEyeletOvalPrice,
    this.eyeletInstall = defaultEyeletInstall,
    this.zipperPerM = defaultZipperPerM,
    this.weldPerM = defaultWeldPerM,
    this.pocketPerM = defaultPocketPerM,
    this.strapPrice = defaultStrapPrice,
    this.turnBucklePrice = defaultTurnBucklePrice,
    this.frenchLockPrice = defaultFrenchLockPrice,
    this.screwPrice = defaultScrewPrice,
    this.drainPrice = defaultDrainPrice,
    this.cutoutPrice = defaultCutoutPrice,
    this.laborPerM2 = defaultLaborPerM2,
    this.cuttingPerM2 = defaultCuttingPerM2,
    this.markupPercent = defaultMarkupPercent,
    this.discountPercent = defaultDiscountPercent,
    this.vatPercent = defaultVatPercent,
    this.currency = defaultCurrencySymbol,
    this.disabledItems = const <String>{},
  });

  /// Цены «как в цехе» — те же, что и в конструкторе по умолчанию.
  const PriceList.defaults() : this();

  // --- Материалы -----------------------------------------------------------
  final double filmClearPerM2;
  final double filmTintedPerM2;
  final double filmMeshPerM2;

  /// Скрин (ткань ПВХ), ₽/м².
  final double filmScreenPerM2;

  /// Подворот скрина и шов, ₽/м периметра.
  final double screenHemPerM;

  final double edge80PerM;
  final double edge100PerM;
  final double edge120PerM;
  final double edge200PerM;
  final double edge240PerM;

  // --- Фурнитура и спецэлементы -------------------------------------------
  /// Люверс круглый Ø10 мм без установки, ₽/шт.
  final double eyeletPrice;

  /// Люверс овальный 42×22 мм без установки, ₽/шт.
  final double eyeletOvalPrice;

  /// Установка люверса (любого типа), ₽/шт.
  final double eyeletInstall;

  final double zipperPerM;
  final double weldPerM;
  final double pocketPerM;
  final double strapPrice;

  /// Поворотная скоба, ₽/шт.
  final double turnBucklePrice;

  /// Французский замок, ₽/шт.
  final double frenchLockPrice;

  /// Саморез верхнего ряда, ₽/шт.
  final double screwPrice;

  final double drainPrice;
  final double cutoutPrice;

  // --- Работы --------------------------------------------------------------
  /// Сварка/сборка за м² готового изделия.
  final double laborPerM2;

  /// Раскрой за м² плёнки.
  final double cuttingPerM2;

  // --- Настройки расчёта ---------------------------------------------------
  final double markupPercent;
  final double discountPercent;

  /// НДС «сверху», %.
  final double vatPercent;

  /// Символ валюты в подписях и смете.
  final String currency;

  /// Выключенные позиции прайса (ключи из [PriceItemKeys]).
  ///
  /// Выключенная позиция — цена есть, но в смету она не идёт: строка просто
  /// не появляется (см. `Estimate`). Так можно быстро прикинуть заказ без
  /// каких-то работ или материалов, не теряя сами цены.
  ///
  /// Набор неизменяемый по договорённости: правится только через [withItem]
  /// и [copyWith], иначе состояние панели и сохранённого заказа разъедется.
  final Set<String> disabledItems;

  /// Учитывать ли позицию [key] в смете. Неизвестный ключ считается
  /// включённым — это безопасный ответ для старого или будущего прайса.
  bool isEnabled(String key) => !disabledItems.contains(key);

  /// Копия прайса с включённой или выключенной позицией [key].
  PriceList withItem(String key, {required bool enabled}) {
    final next = {...disabledItems};
    if (enabled) {
      next.remove(key);
    } else {
      next.add(key);
    }
    return copyWith(disabledItems: next);
  }

  /// Ключ позиции прайса для материала полотна.
  static String filmItemKey(FilmMaterial material) => switch (material) {
        FilmMaterial.clearPvc => PriceItemKeys.filmClear,
        FilmMaterial.tintedPvc => PriceItemKeys.filmTinted,
        FilmMaterial.mosquitoNet => PriceItemKeys.filmMesh,
        FilmMaterial.screen => PriceItemKeys.filmScreen,
      };

  /// Ключ позиции прайса для ширины рулона окантовки.
  ///
  /// Своя ширина (например 150 мм) не имеет отдельной позиции в прайсе: её
  /// цена интерполируется по пресетам, поэтому тумблеры пресетов на неё не
  /// действуют и метод возвращает null — строка всегда считается.
  static String? edgeItemKey(double rawWidthMm) {
    for (final roll in EdgeRoll.values) {
      if ((rawWidthMm - roll.rawWidth).abs() < 1e-9) {
        return switch (roll) {
          EdgeRoll.roll80 => PriceItemKeys.edge80,
          EdgeRoll.roll100 => PriceItemKeys.edge100,
          EdgeRoll.roll120 => PriceItemKeys.edge120,
          EdgeRoll.roll200 => PriceItemKeys.edge200,
          EdgeRoll.roll240 => PriceItemKeys.edge240,
        };
      }
    }
    return null;
  }

  /// Цена плёнки по материалу, ₽/м².
  double filmPerM2(FilmMaterial material) => switch (material) {
        FilmMaterial.clearPvc => filmClearPerM2,
        FilmMaterial.tintedPvc => filmTintedPerM2,
        FilmMaterial.mosquitoNet => filmMeshPerM2,
        FilmMaterial.screen => filmScreenPerM2,
      };

  /// Цена окантовки по типу рулона, ₽/м.
  double edgePerMeter(EdgeRoll roll) => switch (roll) {
        EdgeRoll.roll80 => edge80PerM,
        EdgeRoll.roll100 => edge100PerM,
        EdgeRoll.roll120 => edge120PerM,
        EdgeRoll.roll200 => edge200PerM,
        EdgeRoll.roll240 => edge240PerM,
      };

  /// Цена окантовки для произвольной ширины рулона, ₽/м.
  ///
  /// Пресеты [EdgeRoll.values] (80/100/120/200/240 мм) — опорные точки, у
  /// каждого есть своя цена. Если ширина совпала с пресетом, берём его цену.
  /// Для своей ширины цена линейно интерполируется между двумя соседними
  /// пресетами, а за пределами диапазона — экстраполируется по ближайшему
  /// отрезку: так нестандартная ширина считается плавно и не «прыгает» в цену
  /// соседнего пресета. Старый прайс без цен 80/120 читается с дефолтами
  /// (см. [PriceList.fromJson]), поэтому кривая остаётся непрерывной.
  ///
  /// Деления на ноль нет: знаменатель — разница ширин соседних пресетов,
  /// а она всегда положительна; на всякий случай она проверяется.
  double edgePerMeterForWidth(double rawWidthMm) {
    final points = <(double, double)>[
      for (final roll in EdgeRoll.values) (roll.rawWidth, edgePerMeter(roll)),
    ];
    if (!rawWidthMm.isFinite) return points.first.$2;

    // Точное попадание в пресет — цена пресета.
    for (final point in points) {
      if ((rawWidthMm - point.$1).abs() < 1e-9) return point.$2;
    }

    // Ищем отрезок между соседними пресетами; вне диапазона берём крайний.
    var left = points.first;
    var right = points.last;
    if (rawWidthMm < points.first.$1) {
      left = points[0];
      right = points[1];
    } else if (rawWidthMm > points.last.$1) {
      left = points[points.length - 2];
      right = points.last;
    } else {
      for (var i = 0; i < points.length - 1; i++) {
        if (rawWidthMm >= points[i].$1 && rawWidthMm <= points[i + 1].$1) {
          left = points[i];
          right = points[i + 1];
          break;
        }
      }
    }

    final span = right.$1 - left.$1;
    if (span.abs() < 1e-9) return left.$2;
    final t = (rawWidthMm - left.$1) / span;
    return left.$2 + (right.$2 - left.$2) * t;
  }

  /// Цена люверса с установкой по типу, ₽/шт.
  ///
  /// Установка входит в цену люверса (отдельной строки в смете нет), поэтому
  /// выключенная в прайсе установка убирает из цены только её надбавку.
  double eyeletPerEach(EyeletType type) =>
      (type == EyeletType.round10 ? eyeletPrice : eyeletOvalPrice) +
      (isEnabled(PriceItemKeys.eyeletInstall) ? eyeletInstall : 0);

  /// Цена крепежа подвижных сторон по типу, ₽/шт.
  ///
  /// У «только люверсы» своего крепежа нет — 0: люверс уже посчитан своей
  /// строкой. Силиконовый ремень считается по цене ремня: это одна позиция
  /// прайса на подъёмный и на силиконовый ремень.
  double fastenerPerEach(FastenerType type) => switch (type) {
        FastenerType.eyeletsOnly => 0,
        FastenerType.turnBuckles => turnBucklePrice,
        FastenerType.frenchLocks => frenchLockPrice,
        FastenerType.straps => strapPrice,
      };

  /// Цена позиции панели цен по её полю.
  ///
  /// Чужая группа возвращает 0 — панель не должна падать, если перепутает
  /// поле, а ошибку видно по нулю в смете.
  double film(PriceField field) => switch (field) {
        PriceField.filmClear => filmClearPerM2,
        PriceField.filmTinted => filmTintedPerM2,
        PriceField.filmMesh => filmMeshPerM2,
        PriceField.filmScreen => filmScreenPerM2,
        _ => 0,
      };

  /// Цена окантовки по полю панели цен. См. [film].
  double edge(PriceField field) => switch (field) {
        PriceField.edge80 => edge80PerM,
        PriceField.edge100 => edge100PerM,
        PriceField.edge120 => edge120PerM,
        PriceField.edge200 => edge200PerM,
        PriceField.edge240 => edge240PerM,
        _ => 0,
      };

  /// НДС начисляется сверху (см. комментарий у класса).
  bool get isVatOnTop => vatPercent > 0;

  PriceList copyWith({
    double? filmClearPerM2,
    double? filmTintedPerM2,
    double? filmMeshPerM2,
    double? filmScreenPerM2,
    double? screenHemPerM,
    double? edge80PerM,
    double? edge100PerM,
    double? edge120PerM,
    double? edge200PerM,
    double? edge240PerM,
    double? eyeletPrice,
    double? zipperPerM,
    double? weldPerM,
    double? pocketPerM,
    double? strapPrice,
    double? turnBucklePrice,
    double? frenchLockPrice,
    double? screwPrice,
    double? drainPrice,
    double? cutoutPrice,
    double? laborPerM2,
    double? markupPercent,
    double? discountPercent,
    double? vatPercent,
    // Дополнительные поля модели (панель может их не показывать).
    double? eyeletOvalPrice,
    double? eyeletInstall,
    double? cuttingPerM2,
    String? currency,
    Set<String>? disabledItems,
  }) {
    return PriceList(
      filmClearPerM2: filmClearPerM2 ?? this.filmClearPerM2,
      filmTintedPerM2: filmTintedPerM2 ?? this.filmTintedPerM2,
      filmMeshPerM2: filmMeshPerM2 ?? this.filmMeshPerM2,
      filmScreenPerM2: filmScreenPerM2 ?? this.filmScreenPerM2,
      screenHemPerM: screenHemPerM ?? this.screenHemPerM,
      edge80PerM: edge80PerM ?? this.edge80PerM,
      edge100PerM: edge100PerM ?? this.edge100PerM,
      edge120PerM: edge120PerM ?? this.edge120PerM,
      edge200PerM: edge200PerM ?? this.edge200PerM,
      edge240PerM: edge240PerM ?? this.edge240PerM,
      eyeletPrice: eyeletPrice ?? this.eyeletPrice,
      eyeletOvalPrice: eyeletOvalPrice ?? this.eyeletOvalPrice,
      eyeletInstall: eyeletInstall ?? this.eyeletInstall,
      zipperPerM: zipperPerM ?? this.zipperPerM,
      weldPerM: weldPerM ?? this.weldPerM,
      pocketPerM: pocketPerM ?? this.pocketPerM,
      strapPrice: strapPrice ?? this.strapPrice,
      turnBucklePrice: turnBucklePrice ?? this.turnBucklePrice,
      frenchLockPrice: frenchLockPrice ?? this.frenchLockPrice,
      screwPrice: screwPrice ?? this.screwPrice,
      drainPrice: drainPrice ?? this.drainPrice,
      cutoutPrice: cutoutPrice ?? this.cutoutPrice,
      laborPerM2: laborPerM2 ?? this.laborPerM2,
      cuttingPerM2: cuttingPerM2 ?? this.cuttingPerM2,
      markupPercent: markupPercent ?? this.markupPercent,
      discountPercent: discountPercent ?? this.discountPercent,
      vatPercent: vatPercent ?? this.vatPercent,
      currency: currency ?? this.currency,
      disabledItems: disabledItems ?? this.disabledItems,
    );
  }

  Map<String, dynamic> toJson() => {
        'filmClearPerM2': filmClearPerM2,
        'filmTintedPerM2': filmTintedPerM2,
        'filmMeshPerM2': filmMeshPerM2,
        'filmScreenPerM2': filmScreenPerM2,
        'screenHemPerM': screenHemPerM,
        'edge80PerM': edge80PerM,
        'edge100PerM': edge100PerM,
        'edge120PerM': edge120PerM,
        'edge200PerM': edge200PerM,
        'edge240PerM': edge240PerM,
        'eyeletPrice': eyeletPrice,
        'eyeletOvalPrice': eyeletOvalPrice,
        'eyeletInstall': eyeletInstall,
        'zipperPerM': zipperPerM,
        'weldPerM': weldPerM,
        'pocketPerM': pocketPerM,
        'strapPrice': strapPrice,
        'turnBucklePrice': turnBucklePrice,
        'frenchLockPrice': frenchLockPrice,
        'screwPrice': screwPrice,
        'drainPrice': drainPrice,
        'cutoutPrice': cutoutPrice,
        'laborPerM2': laborPerM2,
        'cuttingPerM2': cuttingPerM2,
        'markupPercent': markupPercent,
        'discountPercent': discountPercent,
        'vatPercent': vatPercent,
        'currency': currency,
        // Пустой набор не пишем: старый формат JSON остаётся прежним, а
        // «нет поля» читается как «всё включено».
        if (disabledItems.isNotEmpty)
          'disabledItems': (disabledItems.toList()..sort()),
      };

  /// Прайс ← JSON. Разбор устойчивый: неизвестные и битые поля заменяются
  /// значениями по умолчанию (как в `order_json.dart`).
  factory PriceList.fromJson(Map<String, dynamic> json) {
    const fallback = PriceList.defaults();
    return PriceList(
      filmClearPerM2: _price(json['filmClearPerM2'], fallback.filmClearPerM2),
      filmTintedPerM2:
          _price(json['filmTintedPerM2'], fallback.filmTintedPerM2),
      filmMeshPerM2: _price(json['filmMeshPerM2'], fallback.filmMeshPerM2),
      filmScreenPerM2:
          _price(json['filmScreenPerM2'], fallback.filmScreenPerM2),
      screenHemPerM: _price(json['screenHemPerM'], fallback.screenHemPerM),
      // Старый прайс без цен 80/120 мм читается с дефолтами: опорные точки
      // кривой цены остаются на месте, а нестандартная ширина интерполируется.
      edge80PerM: _price(json['edge80PerM'], fallback.edge80PerM),
      edge100PerM: _price(json['edge100PerM'], fallback.edge100PerM),
      edge120PerM: _price(json['edge120PerM'], fallback.edge120PerM),
      edge200PerM: _price(json['edge200PerM'], fallback.edge200PerM),
      edge240PerM: _price(json['edge240PerM'], fallback.edge240PerM),
      eyeletPrice: _price(json['eyeletPrice'], fallback.eyeletPrice),
      eyeletOvalPrice:
          _price(json['eyeletOvalPrice'], fallback.eyeletOvalPrice),
      eyeletInstall: _price(json['eyeletInstall'], fallback.eyeletInstall),
      zipperPerM: _price(json['zipperPerM'], fallback.zipperPerM),
      weldPerM: _price(json['weldPerM'], fallback.weldPerM),
      pocketPerM: _price(json['pocketPerM'], fallback.pocketPerM),
      strapPrice: _price(json['strapPrice'], fallback.strapPrice),
      // Старый прайс без цен крепежа читается с дефолтами: строки крепежа
      // в смете считаются, а не пропадают с нулём.
      turnBucklePrice:
          _price(json['turnBucklePrice'], fallback.turnBucklePrice),
      frenchLockPrice:
          _price(json['frenchLockPrice'], fallback.frenchLockPrice),
      screwPrice: _price(json['screwPrice'], fallback.screwPrice),
      drainPrice: _price(json['drainPrice'], fallback.drainPrice),
      cutoutPrice: _price(json['cutoutPrice'], fallback.cutoutPrice),
      laborPerM2: _price(json['laborPerM2'], fallback.laborPerM2),
      cuttingPerM2: _price(json['cuttingPerM2'], fallback.cuttingPerM2),
      markupPercent:
          _percent(json['markupPercent'], fallback.markupPercent, max: 1000),
      discountPercent:
          _percent(json['discountPercent'], fallback.discountPercent, max: 100),
      vatPercent: _percent(json['vatPercent'], fallback.vatPercent, max: 100),
      currency: json['currency'] is String && (json['currency'] as String).isNotEmpty
          ? json['currency'] as String
          : fallback.currency,
      // Старый прайс без поля — всё включено. Неизвестные ключи (из будущих
      // версий) отбрасываем: модель не должна тащить мусор в панель и смету.
      disabledItems: _disabledItems(json['disabledItems']),
    );
  }

  /// Короткая строка условий расчёта для панели и сметы.
  String get termsLabel => [
        if (vatPercent > 0)
          'НДС ${_trim(vatPercent)} % сверху'
        else
          'без НДС',
        if (markupPercent > 0) 'наценка ${_trim(markupPercent)} %',
        if (discountPercent > 0) 'скидка ${_trim(discountPercent)} %',
        'валюта $currency',
      ].join(', ');
}

/// Выключенные позиции из JSON.
///
/// Старый прайс без поля — всё включено. Принимаем только известные ключи
/// из [PriceItemKeys.all]; всё остальное (не список, числа, ключи будущих
/// версий) игнорируем, чтобы модель не тащила мусор в панель и смету.
Set<String> _disabledItems(Object? value) {
  if (value is! List) return const <String>{};
  return {
    for (final key in value)
      if (key is String && PriceItemKeys.all.contains(key)) key,
  };
}

/// Цена из JSON: конечное неотрицательное число, иначе [fallback].
double _price(Object? value, double fallback) {
  if (value is num) {
    final result = value.toDouble();
    if (result.isFinite && result >= 0) return result;
  }
  return fallback;
}

/// Процент из JSON с ограничением сверху.
double _percent(Object? value, double fallback, {required double max}) {
  final result = _price(value, fallback);
  return result.clamp(0, max).toDouble();
}

String _trim(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

/// Разбирает ввод цены: «1 234,56», «1234.56», «1 234 ₽», «−500».
///
/// Возвращает null, если число не распознано; отрицательные значения
/// приводятся к нулю — цены не бывают отрицательными.
double? parsePrice(String text) {
  final normalized = text
      .trim()
      .replaceAll('\u00A0', '')
      .replaceAll('\u202F', '')
      .replaceAll(' ', '')
      .replaceAll('₽', '')
      .replaceAll('р.', '')
      .replaceAll('−', '-')
      .replaceAll(',', '.');
  if (normalized.isEmpty) return null;
  final value = double.tryParse(normalized);
  if (value == null || !value.isFinite) return null;
  return value < 0 ? 0 : value;
}

/// Деньги по-русски: «12 345,67 ₽» — пробел между разрядами, запятая
/// в копейках, округление до копейки.
///
/// Разделитель разрядов — обычный пробел (а не узкий неразрывный, как
/// в `formatMm`), чтобы строка одинаково читалась в PDF, в буфере обмена
/// и в тестах.
String formatRubles(double value, {String currency = defaultCurrencySymbol}) {
  if (!value.isFinite) return '—';
  final negative = value < 0;
  final cents = (value.abs() * 100).round();
  final rubles = cents ~/ 100;
  final kopecks = (cents % 100).toString().padLeft(2, '0');
  return '${negative ? '−' : ''}${groupThousands(rubles.toString())},'
      '$kopecks $currency';
}

/// Группирует цифры по три разряда пробелом: «1234567» → «1 234 567».
String groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(' ');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
