import '../models/order_project.dart';
import '../models/window_params.dart';

// --------------------------------------------------------------- сериализация

/// Заказ → JSON.
Map<String, dynamic> orderToJson(OrderProject project) => {
      'sheetMode': project.sheetMode.name,
      'gridColumns': project.gridColumns,
      'rollGap': project.rollGap,
      'rollWidths': {
        for (final entry in project.rollWidths.entries)
          entry.key.name: entry.value,
      },
      'options': {
        'showDimensions': project.options.showDimensions,
        'showGrid': project.options.showGrid,
        'showEdgeLengths': project.options.showEdgeLengths,
        'showCallouts': project.options.showCallouts,
      },
      'windows': [for (final window in project.windows) windowToJson(window)],
    };

/// Заказ ← JSON.
OrderProject orderFromJson(Map<String, dynamic> json) {
  final windowsJson = json['windows'];
  final windows = <WindowParams>[];
  if (windowsJson is List) {
    for (final item in windowsJson) {
      if (item is Map<String, dynamic>) {
        windows.add(windowFromJson(item));
      } else if (item is Map) {
        windows.add(windowFromJson(item.cast<String, dynamic>()));
      }
    }
  }
  final optionsJson = json['options'];
  final options = optionsJson is Map
      ? DrawingOptions(
          showDimensions: _bool(optionsJson['showDimensions'], true),
          showGrid: _bool(optionsJson['showGrid'], true),
          showEdgeLengths: _bool(optionsJson['showEdgeLengths'], true),
          showCallouts: _bool(optionsJson['showCallouts'], true),
        )
      : const DrawingOptions();

  final rollWidths = <FilmMaterial, double>{};
  final rollWidthsJson = json['rollWidths'];
  if (rollWidthsJson is Map) {
    for (final material in FilmMaterial.values) {
      final value = rollWidthsJson[material.name];
      if (value is num) rollWidths[material] = value.toDouble();
    }
  }

  return OrderProject(
    windows: windows.isEmpty ? const [WindowParams()] : windows,
    rollWidths: rollWidths,
    rollGap: _double(json['rollGap'], 20),
    options: options,
    sheetMode: _enumByName(SheetMode.values, json['sheetMode'], SheetMode.single),
    gridColumns: _int(json['gridColumns'], 0).clamp(0, 4),
  );
}

/// Окно → JSON.
Map<String, dynamic> windowToJson(WindowParams p) => {
      'projectName': p.projectName,
      'customer': p.customer,
      'drawingNumber': p.drawingNumber,
      'windowType': p.windowType.name,
      'material': p.material.name,
      'bottomWidth': p.bottomWidth,
      'topWidth': p.topWidth,
      'leftHeight': p.leftHeight,
      'rightHeight': p.rightHeight,
      // Припуск на раскрой, мм: замер + припуск = фактический размер.
      'allowanceWidthMm': p.allowanceWidthMm,
      'allowanceHeightMm': p.allowanceHeightMm,
      'topAlign': p.topAlign.name,
      'topOffsetMm': p.topOffsetMm,
      // Какая кромка горизонтальна: bottom / top / none.
      'levelEdge': p.levelEdge.name,
      // Т-образное окно: сторона, размеры приставки, смещение и спайка.
      'tSide': p.tSide.name,
      'tWidth': p.tWidth,
      'tHeight': p.tHeight,
      'tOffset': p.tOffset,
      'tWelded': p.tWelded,
      // Включена ли первая пристройка (старые заказы читаются как включённая).
      'tEnabled': p.tEnabled,
      // Вторая пристройка Т-окна (угловая форма). У старых заказов её нет,
      // поэтому поле пишется всегда, а читается с выключенным значением.
      't2Enabled': p.t2Enabled,
      't2Side': p.t2Side.name,
      't2Width': p.t2Width,
      't2Height': p.t2Height,
      't2Offset': p.t2Offset,
      't2Welded': p.t2Welded,
      // Ширина рулона окантовки — число миллиметров на каждую сторону.
      'rollBottom': p.rollBottom,
      'rollTop': p.rollTop,
      'rollLeft': p.rollLeft,
      'rollRight': p.rollRight,
      'edgeMaterial': p.edgeMaterial.name,
      'edgeColor': p.edgeColor.name,
      // Запайка плёнки под окантовку (5…60 мм) — вводится руками.
      'weldOverlapMm': p.weldOverlapMm,
      // Подворот скрина по сторонам (10…200 мм на каждую сторону).
      'hemBottomMm': p.hemBottomMm,
      'hemRightMm': p.hemRightMm,
      'hemTopMm': p.hemTopMm,
      'hemLeftMm': p.hemLeftMm,
      // Старое одиночное поле пишем, только когда все подвороты равны: так
      // заказ по-прежнему читается старыми версиями приложения.
      if (p.hasUniformHem) 'hemMm': p.hemBottomMm,
      'eyeletType': p.eyeletType.name,
      'eyeletStep': p.eyeletStep,
      'eyeletCornerOffset': p.eyeletCornerOffset,
      // Тумблер «Круглые люверсы в углах» (по умолчанию включён).
      'roundEyeletsEnabled': p.roundEyeletsEnabled,
      'fastenerType': p.fastenerType.name,
      'zippers': [for (final zipper in p.zippers) zipper.toJson()],
      // «Доп. настройка молнии»: деление полотна на сегменты.
      'zipperSegments': p.zipperSegments,
      'zipperTentOverlap': p.zipperTentOverlap,
      // Ручные положения подъёмных ремней, мм от левого края.
      'liftStrapOffsets': p.liftStrapOffsets,
      'cutouts': [for (final cutout in p.cutouts) cutout.toJson()],
      // Ручные положения люверсов (перетащены на чертеже).
      'eyeletPositions': [
        for (final position in p.eyeletPositions) position.toJson(),
      ],
      'manualEyeletSides': [
        for (final side in p.manualEyeletSides) side.name,
      ],
      // Второй сегмент составного окна. Пишем только для составного окна:
      // у остальных типов поле отсутствует, и старые заказы не меняются.
      if (p.isComposite) 'composite': _compositeToJson(p.composite),
      // Кнопки «не ставить люверсы сверху/снизу».
      'noEyeletsTop': p.noEyeletsTop,
      'noEyeletsBottom': p.noEyeletsBottom,
      // Старые поля оставлены, чтобы заказы читались старыми версиями.
      'zipperEnabled': p.zipperEnabled,
      'zipperCentered': p.zipperCentered,
      'zipperOffsetMm': p.zipperOffsetMm,
      'zipperBandWidth': p.zipperBandWidth,
      'pocket': p.pocket,
      'pocketTop': p.pocketTop,
      'pocketWidth': p.pocketWidth,
      'drainHoles': p.drainHoles,
      'drainCount': p.drainCount,
      // Тумблер усадки и её процент: по умолчанию усадка выключена, поэтому
      // старый заказ без флага читается как «включена, если процент > 0».
      'shrinkageEnabled': p.shrinkageEnabled,
      'shrinkagePercent': p.shrinkagePercent,
      // Тумблер авто-припуска +10 мм к высоте ПВХ (по умолчанию включён).
      'pvcHeightAllowanceEnabled': p.pvcHeightAllowanceEnabled,
    };

/// Окно ← JSON.
WindowParams windowFromJson(Map<String, dynamic> json) {
  const fallback = WindowParams();
  // Старые заказы хранят один подворот на все стороны: читаем его как общий,
  // а новые четыре поля имеют приоритет над ним.
  final legacyHem = _double(json['hemMm'], fallback.hemBottomMm);
  return WindowParams(
    projectName: _string(json['projectName'], fallback.projectName),
    customer: _string(json['customer'], fallback.customer),
    drawingNumber: _string(json['drawingNumber'], fallback.drawingNumber),
    windowType:
        _enumByName(WindowType.values, json['windowType'], fallback.windowType),
    material:
        _enumByName(FilmMaterial.values, json['material'], fallback.material),
    bottomWidth: _double(json['bottomWidth'], fallback.bottomWidth),
    topWidth: _double(json['topWidth'], fallback.topWidth),
    leftHeight: _double(json['leftHeight'], fallback.leftHeight),
    rightHeight: _double(json['rightHeight'], fallback.rightHeight),
    allowanceWidthMm:
        _double(json['allowanceWidthMm'], fallback.allowanceWidthMm),
    allowanceHeightMm:
        _double(json['allowanceHeightMm'], fallback.allowanceHeightMm),
    topAlign: _enumByName(TopAlign.values, json['topAlign'], fallback.topAlign),
    topOffsetMm: _double(json['topOffsetMm'], fallback.topOffsetMm),
    // Старые заказы без поля читаются как bottom: это в точности прежняя
    // геометрия (низ горизонтален, верх наклонён), поэтому расчёты не меняются.
    levelEdge: _enumByName(
      LevelEdge.values,
      json['levelEdge'],
      LevelEdge.bottom,
    ),
    tSide: _enumByName(TShapeSide.values, json['tSide'], fallback.tSide),
    tWidth: _double(json['tWidth'], fallback.tWidth),
    tHeight: _double(json['tHeight'], fallback.tHeight),
    tOffset: _double(json['tOffset'], fallback.tOffset),
    tWelded: _bool(json['tWelded'], fallback.tWelded),
    // Старый заказ без поля — пристройка включена (прежнее поведение).
    tEnabled: _bool(json['tEnabled'], true),
    // Вторая пристройка по умолчанию выключена: старый заказ читается как
    // ровно прежнее Т-окно с одной пристройкой.
    t2Enabled: _bool(json['t2Enabled'], false),
    t2Side: _enumByName(TShapeSide.values, json['t2Side'], fallback.t2Side),
    t2Width: _double(json['t2Width'], fallback.t2Width),
    t2Height: _double(json['t2Height'], fallback.t2Height),
    t2Offset: _double(json['t2Offset'], fallback.t2Offset),
    t2Welded: _bool(json['t2Welded'], fallback.t2Welded),
    rollBottom: _edgeWidthFromJson(json['rollBottom'], fallback.rollBottom),
    rollTop: _edgeWidthFromJson(json['rollTop'], fallback.rollTop),
    rollLeft: _edgeWidthFromJson(json['rollLeft'], fallback.rollLeft),
    rollRight: _edgeWidthFromJson(json['rollRight'], fallback.rollRight),
    edgeMaterial: _enumByName(
        EdgeMaterial.values, json['edgeMaterial'], fallback.edgeMaterial),
    edgeColor:
        _enumByName(EdgeColor.values, json['edgeColor'], fallback.edgeColor),
    weldOverlapMm:
        _double(json['weldOverlapMm'], fallback.weldOverlapMm),
    hemBottomMm: _double(json['hemBottomMm'], legacyHem),
    hemRightMm: _double(json['hemRightMm'], legacyHem),
    hemTopMm: _double(json['hemTopMm'], legacyHem),
    hemLeftMm: _double(json['hemLeftMm'], legacyHem),
    eyeletType:
        _enumByName(EyeletType.values, json['eyeletType'], fallback.eyeletType),
    eyeletStep: _eyeletStepFromJson(json['eyeletStep'], fallback.eyeletStep),
    eyeletCornerOffset:
        _double(json['eyeletCornerOffset'], fallback.eyeletCornerOffset),
    roundEyeletsEnabled:
        _bool(json['roundEyeletsEnabled'], fallback.roundEyeletsEnabled),
    fastenerType: _enumByName(
        FastenerType.values, json['fastenerType'], fallback.fastenerType),
    zippers: _zippersFromJson(json),
    zipperSegments: _bool(json['zipperSegments'], false),
    zipperTentOverlap: _double(
      json['zipperTentOverlap'],
      defaultZipperTentOverlapMm,
    ),
    liftStrapOffsets: _doubleList(json['liftStrapOffsets']),
    cutouts: _cutoutsFromJson(json['cutouts']),
    eyeletPositions: _eyeletPositionsFromJson(json['eyeletPositions']),
    manualEyeletSides: _sidesFromJson(json['manualEyeletSides']),
    composite: _compositeFromJson(json['composite']),
    // Старое поле `weldedSides` намеренно игнорируется: спайка с соседним
    // окном удалена, заказ открывается без падений и без шва.
    noEyeletsTop: _bool(json['noEyeletsTop'], fallback.noEyeletsTop),
    noEyeletsBottom: _bool(json['noEyeletsBottom'], fallback.noEyeletsBottom),
    pocket: _bool(json['pocket'], fallback.pocket),
    pocketTop: _bool(json['pocketTop'], fallback.pocketTop),
    pocketWidth: _double(json['pocketWidth'], fallback.pocketWidth),
    drainHoles: _bool(json['drainHoles'], fallback.drainHoles),
    drainCount: _double(json['drainCount'], fallback.drainCount),
    shrinkageEnabled: _shrinkageEnabledFromJson(json),
    shrinkagePercent:
        _double(json['shrinkagePercent'], fallback.shrinkagePercent),
    pvcHeightAllowanceEnabled: _bool(
      json['pvcHeightAllowanceEnabled'],
      fallback.pvcHeightAllowanceEnabled,
    ),
  );
}

/// Тумблер усадки из JSON.
///
/// Новые заказы пишут флаг [shrinkageEnabled] явно. В старых заказах поля нет,
/// а сама усадка тогда применялась всегда: читаем флаг как «процент > 0».
/// Поэтому старый заказ с 1,5 % открывается как «усадка включена», а с 0 % —
/// как выключенная. Обратная совместимость: размеры раскроя не «прыгают».
bool _shrinkageEnabledFromJson(Map<String, dynamic> json) {
  final flag = json['shrinkageEnabled'];
  if (flag is bool) return flag;
  final percent = json['shrinkagePercent'];
  final value = percent is num ? percent.toDouble() : 0.0;
  return value.isFinite && value > 0;
}

T _enumByName<T extends Enum>(List<T> values, Object? name, T fallback) {
  if (name is String) {
    for (final value in values) {
      if (value.name == name) return value;
    }
  }
  return fallback;
}

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

/// Интервал люверсов из JSON.
///
/// Новые заказы пишут число миллиметров («280»), но встречаются и строки
/// («280» или «280,0») — читаем оба варианта. Битое значение заменяется
/// [fallback] (по умолчанию 300 мм), чтобы старые заказы открывались.
double _eyeletStepFromJson(Object? value, double fallback) {
  if (value is num) {
    final step = value.toDouble();
    return step.isFinite && step > 0 ? step : fallback;
  }
  if (value is String) {
    final parsed = double.tryParse(value.trim().replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite && parsed > 0) return parsed;
  }
  return fallback;
}

/// Ширина рулона окантовки из JSON.
///
/// Новые заказы пишут число миллиметров («150»), старые — имя пресета
/// («roll200»). Принимаем оба варианта: имя разбираем через
/// [EdgeRoll.presetRawWidth], остальное — как число. Битые значения
/// заменяются [fallback] (по умолчанию 100 мм).
double _edgeWidthFromJson(Object? value, double fallback) {
  if (value is num) {
    final width = value.toDouble();
    return width.isFinite && width > 0 ? width : fallback;
  }
  if (value is String) {
    final preset = EdgeRoll.presetRawWidth(value);
    if (preset != null) return preset;
    final parsed = double.tryParse(value.replaceAll(',', '.'));
    if (parsed != null && parsed.isFinite && parsed > 0) return parsed;
  }
  return fallback;
}

int _int(Object? value, int fallback) => value is num ? value.toInt() : fallback;

bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;

String _string(Object? value, String fallback) =>
    value is String ? value : fallback;


/// Молнии из JSON. Понимает и новый список, и старые одиночные поля.
List<ZipperSpec> _zippersFromJson(Map<String, dynamic> json) {
  final raw = json['zippers'];
  if (raw is List && raw.isNotEmpty) {
    return [
      for (final item in raw)
        if (item is Map)
          ZipperSpec(
            centered: _bool(item['centered'], true),
            offsetMm: _double(item['offsetMm'], 0),
            bandWidth: _double(item['bandWidth'], defaultZipperBandWidth),
          ),
    ];
  }
  if (_bool(json['zipperEnabled'], false)) {
    return [
      ZipperSpec(
        centered: _bool(json['zipperCentered'], true),
        offsetMm: _double(json['zipperOffsetMm'], 0),
        bandWidth: _double(json['zipperBandWidth'], defaultZipperBandWidth),
      ),
    ];
  }
  return const [];
}

List<Cutout> _cutoutsFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map)
        Cutout(
          shape: _enumByName(
            CutoutShape.values,
            item['shape'],
            CutoutShape.rect,
          ),
          width: _double(item['width'], 300),
          height: _double(item['height'], 300),
          centerXMm: _double(item['centerXMm'], 0),
          centerYMm: _double(item['centerYMm'], 400),
        ),
  ];
}

List<EdgeSide> _sidesFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String)
        for (final side in EdgeSide.values)
          if (side.name == item) side,
  ];
}

List<EyeletPosition> _eyeletPositionsFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is Map) EyeletPosition.fromJson(item.cast<String, dynamic>()),
  ];
}

List<double> _doubleList(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is num && item.isFinite) item.toDouble(),
  ];
}

Map<String, dynamic> _compositeToJson(CompositeSpec spec) => {
      'side': spec.side.name,
      'material': spec.material.name,
      'width': spec.width,
      'depth': spec.depth,
      'offset': spec.offset,
      'seam': spec.seam.name,
      'seamOffset': spec.seamOffset,
      'seamAngleDeg': spec.seamAngleDeg,
    };

CompositeSpec _compositeFromJson(Object? raw) {
  const fallback = CompositeSpec();
  if (raw is! Map) return fallback;
  final json = raw.cast<String, dynamic>();
  return CompositeSpec(
    side: _enumByName(EdgeSide.values, json['side'], fallback.side),
    material:
        _enumByName(FilmMaterial.values, json['material'], fallback.material),
    width: _double(json['width'], fallback.width),
    depth: _double(json['depth'], fallback.depth),
    offset: _double(json['offset'], fallback.offset),
    seam: _enumByName(CompositeSeam.values, json['seam'], fallback.seam),
    seamOffset: _double(json['seamOffset'], fallback.seamOffset),
    seamAngleDeg: _double(json['seamAngleDeg'], fallback.seamAngleDeg),
  );
}
