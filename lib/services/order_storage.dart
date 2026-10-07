import '../models/order_json.dart';
import '../models/order_project.dart';
import 'costs_summary.dart';
import 'order_store.dart';

/// Краткая информация о сохранённом заказе — для списка и отчётности.
class SavedOrder {
  const SavedOrder({
    required this.ref,
    required this.name,
    required this.savedAt,
    required this.customer,
    required this.windowCount,
    required this.filmAreaM2,
    required this.eyeletTotal,
    required this.materials,
    required this.edgeSummary,
  });

  /// Ссылка на запись в хранилище (файл или ключ браузера).
  final StoredOrderRef ref;

  final String name;
  final DateTime savedAt;
  final String customer;
  final int windowCount;
  final double filmAreaM2;
  final int eyeletTotal;
  final String materials;
  final String edgeSummary;

  String get title => name.isEmpty ? ref.label : name;
}

/// Подпись места хранения заказов для интерфейса.
String ordersFolderDescription([String? directoryPath]) =>
    ordersFolderDescriptionImpl(directoryPath);

/// Сохраняет заказ для отчётности и подсчёта расходов.
Future<SavedOrder> saveOrder(
  OrderProject project, {
  String? name,
  DateTime? now,
  String? directoryPath,
}) async {
  final moment = now ?? DateTime.now();
  final orderName = (name ?? project.windows.first.projectName).trim();
  final fileName = '${_fileStamp(moment)}-${_safeFileName(orderName)}.json';
  final payload = <String, dynamic>{
    'version': 1,
    'savedAt': moment.toIso8601String(),
    'name': orderName,
    ...orderToJson(project),
    'summary': orderSummaryToJson(project),
  };
  final ref = await storeOrder(
    payload,
    fileName,
    directoryPath: directoryPath,
    savedAt: moment,
  );
  return _savedOrderFromJson(ref, payload);
}

/// Список сохранённых заказов (свежие сверху).
Future<List<SavedOrder>> listSavedOrders({String? directoryPath}) async {
  final stored = await readStoredOrders(directoryPath: directoryPath);
  final orders = [
    for (final entry in stored) _savedOrderFromJson(entry.$1, entry.$2),
  ];
  orders.sort((a, b) => b.savedAt.compareTo(a.savedAt));
  return orders;
}

/// Загружает заказ.
Future<OrderProject> loadOrder(SavedOrder order) async {
  final json = await readStoredOrder(order.ref);
  return orderFromJson(json);
}

/// Удаляет сохранённый заказ.
Future<void> deleteOrder(SavedOrder order) async {
  await removeStoredOrder(order.ref);
}

/// Сводка по заказу для отчётности.
Map<String, dynamic> orderSummaryToJson(OrderProject project) {
  final summary = CostsSummary(project);
  return {
    'windowCount': project.windowCount,
    'productAreaM2': summary.productAreaM2,
    'filmAreaM2': summary.filmAreaM2,
    'filmAreaWithShrinkageM2': summary.filmAreaWithShrinkageM2,
    'eyeletTotal': summary.eyeletTotal,
    'filmByMaterial': summary.filmByMaterialLabels,
    'edgeByRoll': summary.edgeConsumptionLabels,
    'rolls': [
      for (final plan in summary.rollPlans)
        '${plan.material.label}: ${plan.rollWidth} × '
            '${plan.layout.requiredLength} мм, отход '
            '${plan.wastePercent.toStringAsFixed(1)}%',
    ],
    'totalWastePercent': summary.rollWastePercent,
  };
}

SavedOrder _savedOrderFromJson(
  StoredOrderRef ref,
  Map<String, dynamic> json,
) {
  final summary = json['summary'];
  final summaryMap =
      summary is Map ? summary.cast<String, dynamic>() : <String, dynamic>{};
  final windows = json['windows'];
  String customer = '';
  if (windows is List && windows.isNotEmpty && windows.first is Map) {
    customer = _string((windows.first as Map)['customer'], '');
  }
  return SavedOrder(
    ref: ref,
    name: _string(json['name'], ''),
    savedAt: DateTime.tryParse(_string(json['savedAt'], '')) ?? ref.savedAt,
    customer: customer,
    windowCount: _int(summaryMap['windowCount'], 0),
    filmAreaM2: _double(summaryMap['filmAreaM2'], 0),
    eyeletTotal: _int(summaryMap['eyeletTotal'], 0),
    materials:
        (summaryMap['filmByMaterial'] as List?)?.map((item) => '$item').join('; ') ??
            '',
    edgeSummary:
        (summaryMap['edgeByRoll'] as List?)?.map((item) => '$item').join('; ') ??
            '',
  );
}

String _fileStamp(DateTime moment) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${moment.year}${two(moment.month)}${two(moment.day)}'
      '-${two(moment.hour)}${two(moment.minute)}';
}

String _safeFileName(String name) {
  final cleaned = name
      .trim()
      .replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return cleaned.isEmpty ? 'заказ' : cleaned;
}

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

int _int(Object? value, int fallback) => value is num ? value.toInt() : fallback;

String _string(Object? value, String fallback) =>
    value is String ? value : fallback;
