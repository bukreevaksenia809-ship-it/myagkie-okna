import 'dart:convert';
import 'dart:io';

/// Ссылка на сохранённый заказ.
class StoredOrderRef {
  const StoredOrderRef({
    required this.id,
    required this.label,
    required this.savedAt,
  });

  final String id;
  final String label;
  final DateTime savedAt;
}

/// Каталог сохранённых заказов: <Домашняя>/Downloads/Мягкие окна/Заказы.
Directory ordersDirectory([String? directoryPath]) {
  if (directoryPath != null && directoryPath.isNotEmpty) {
    return Directory(directoryPath);
  }
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (home.isEmpty) {
    return Directory('${Directory.current.path}/Мягкие окна/Заказы');
  }
  return Directory('$home/Downloads/Мягкие окна/Заказы');
}

/// Подпись места хранения для интерфейса.
String ordersFolderDescriptionImpl([String? directoryPath]) =>
    ordersDirectory(directoryPath).path;

/// Сохраняет заказ в JSON-файл.
Future<StoredOrderRef> storeOrder(
  Map<String, dynamic> payload,
  String fileName, {
  String? directoryPath,
  DateTime? savedAt,
}) async {
  final directory = ordersDirectory(directoryPath);
  await directory.create(recursive: true);
  final file = File('${directory.path}/$fileName');
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(payload),
    flush: true,
  );
  final moment = savedAt ?? file.lastModifiedSync();
  return StoredOrderRef(id: file.path, label: fileName, savedAt: moment);
}

/// Список сохранённых заказов вместе с их JSON.
Future<List<(StoredOrderRef, Map<String, dynamic>)>> readStoredOrders({
  String? directoryPath,
}) async {
  final directory = ordersDirectory(directoryPath);
  if (!directory.existsSync()) return const [];
  final result = <(StoredOrderRef, Map<String, dynamic>)>[];
  for (final file in directory
      .listSync()
      .whereType<File>()
      .where((file) => file.path.endsWith('.json'))) {
    try {
      final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      result.add((
        StoredOrderRef(
          id: file.path,
          label: file.uri.pathSegments.last,
          savedAt: DateTime.tryParse('${json['savedAt']}') ??
              file.lastModifiedSync(),
        ),
        json,
      ));
    } catch (_) {
      // Битый файл пропускаем, чтобы список всегда открывался.
    }
  }
  return result;
}

/// Читает один заказ.
Future<Map<String, dynamic>> readStoredOrder(StoredOrderRef ref) async {
  return jsonDecode(await File(ref.id).readAsString()) as Map<String, dynamic>;
}

/// Удаляет файл заказа.
Future<void> removeStoredOrder(StoredOrderRef ref) async {
  final file = File(ref.id);
  if (file.existsSync()) await file.delete();
}
