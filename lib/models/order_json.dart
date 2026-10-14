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
    gridColumns: _int(json['gridColumns'], 2).clamp(0, 4),
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
      // Ширина рулона окантовки — число миллиметров на каждую сторону.
      'rollBottom': p.rollBottom,
      'rollTop': p.rollTop,
      'rollLeft': p.rollLeft,
      'rollRight': p.rollRight,
      'edgeMaterial': p.edgeMaterial.name,
      'edgeColor': p.edgeColor.name,
      'eyeletType': p.eyeletType.name,
      'eyeletStep': p.eyeletStep,
      'eyeletCornerOffset': p.eyeletCornerOffset,
      'fastenerType': p.fastenerType.name,
      'zippers': [for (final zipper in p.zippers) zipper.toJson()],
      'cutouts': [for (final cutout in p.cutouts) cutout.toJson()],
      'weldedSides': [for (final side in p.weldedSides) side.name],
      // Старые поля оставлены, чтобы заказы читались старыми версиями.
      'zipperEnabled': p.zipperEnabled,
      'zipperCentered': p.zipperCentered,
      'zipperOffsetMm': p.zipperOffsetMm,
      'zipperBandWidth': p.zipperBandWidth,
      'pocket': p.pocket,
      'pocketWidth': p.pocketWidth,
      'drainHoles': p.drainHoles,
      'drainCount': p.drainCount,
      'shrinkagePercent': p.shrinkagePercent,
    };

/// Окно ← JSON.
WindowParams windowFromJson(Map<String, dynamic> json) {
  const fallback = WindowParams();
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
    rollBottom: _edgeWidthFromJson(json['rollBottom'], fallback.rollBottom),
    rollTop: _edgeWidthFromJson(json['rollTop'], fallback.rollTop),
    rollLeft: _edgeWidthFromJson(json['rollLeft'], fallback.rollLeft),
    rollRight: _edgeWidthFromJson(json['rollRight'], fallback.rollRight),
    edgeMaterial: _enumByName(
        EdgeMaterial.values, json['edgeMaterial'], fallback.edgeMaterial),
    edgeColor:
        _enumByName(EdgeColor.values, json['edgeColor'], fallback.edgeColor),
    eyeletType:
        _enumByName(EyeletType.values, json['eyeletType'], fallback.eyeletType),
    eyeletStep: _double(json['eyeletStep'], fallback.eyeletStep),
    eyeletCornerOffset:
        _double(json['eyeletCornerOffset'], fallback.eyeletCornerOffset),
    fastenerType: _enumByName(
        FastenerType.values, json['fastenerType'], fallback.fastenerType),
    zippers: _zippersFromJson(json),
    cutouts: _cutoutsFromJson(json['cutouts']),
    weldedSides: _weldedFromJson(json['weldedSides']),
    pocket: _bool(json['pocket'], fallback.pocket),
    pocketWidth: _double(json['pocketWidth'], fallback.pocketWidth),
    drainHoles: _bool(json['drainHoles'], fallback.drainHoles),
    drainCount: _double(json['drainCount'], fallback.drainCount),
    shrinkagePercent:
        _double(json['shrinkagePercent'], fallback.shrinkagePercent),
  );
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

List<EdgeSide> _weldedFromJson(Object? raw) {
  if (raw is! List) return const [];
  return [
    for (final item in raw)
      if (item is String)
        for (final side in EdgeSide.values)
          if (side.name == item) side,
  ];
}
