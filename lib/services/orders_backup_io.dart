import 'dart:io';

import 'order_store_io.dart';

/// Копирует папку заказов в соседнюю «Резервные копии/<дата-время>».
Future<String?> backupOrdersFolderImpl() async {
  final source = ordersDirectory();
  if (!source.existsSync()) return null;
  final root = Directory('${source.parent.path}/Резервные копии');
  root.createSync(recursive: true);
  final now = DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp =
      '${now.year}-${two(now.month)}-${two(now.day)}_'
      '${two(now.hour)}-${two(now.minute)}-${two(now.second)}';
  final target = Directory('${root.path}/$stamp');
  await target.create(recursive: true);
  await for (final entity in source.list(followLinks: false)) {
    if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) {
      continue;
    }
    final name = entity.uri.pathSegments.last;
    await entity.copy('${target.path}/$name');
  }
  return target.path;
}
