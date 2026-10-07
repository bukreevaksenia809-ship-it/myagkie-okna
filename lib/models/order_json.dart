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
      'topAlign': p.topAlign.name,
      'topOffsetMm': p.topOffsetMm,
      'rollBottom': p.rollBottom.name,
      'rollTop': p.rollTop.name,
      'rollLeft': p.rollLeft.name,
      'rollRight': p.rollRight.name,
      'edgeMaterial': p.edgeMaterial.name,
      'edgeColor': p.edgeColor.name,
      'eyeletType': p.eyeletType.name,
      'eyeletStep': p.eyeletStep,
      'eyeletCornerOffset': p.eyeletCornerOffset,
      'fastenerType': p.fastenerType.name,
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
    topAlign: _enumByName(TopAlign.values, json['topAlign'], fallback.topAlign),
    topOffsetMm: _double(json['topOffsetMm'], fallback.topOffsetMm),
    rollBottom:
        _enumByName(EdgeRoll.values, json['rollBottom'], fallback.rollBottom),
    rollTop: _enumByName(EdgeRoll.values, json['rollTop'], fallback.rollTop),
    rollLeft: _enumByName(EdgeRoll.values, json['rollLeft'], fallback.rollLeft),
    rollRight:
        _enumByName(EdgeRoll.values, json['rollRight'], fallback.rollRight),
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
    zipperEnabled: _bool(json['zipperEnabled'], fallback.zipperEnabled),
    zipperCentered: _bool(json['zipperCentered'], fallback.zipperCentered),
    zipperOffsetMm: _double(json['zipperOffsetMm'], fallback.zipperOffsetMm),
    zipperBandWidth: _double(json['zipperBandWidth'], fallback.zipperBandWidth),
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

int _int(Object? value, int fallback) => value is num ? value.toInt() : fallback;

bool _bool(Object? value, bool fallback) => value is bool ? value : fallback;

String _string(Object? value, String fallback) =>
    value is String ? value : fallback;
