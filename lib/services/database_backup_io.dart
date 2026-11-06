import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'legacy_data_migrator.dart';

/// Ежедневная автоматическая копия базы (только на устройствах с файлами).
class DailyDatabaseBackup {
  DailyDatabaseBackup._();

  static Future<String?> run() async {
    try {
      final directory = await getApplicationSupportDirectory();
      final backups = Directory(p.join(directory.path, 'Backups'));
      if (!backups.existsSync()) {
        backups.createSync(recursive: true);
      }
      final now = DateTime.now();
      final name = 'db-${now.year}-'
          '${now.month.toString().padLeft(2, '0')}-'
          '${now.day.toString().padLeft(2, '0')}.json';
      final file = File(p.join(backups.path, name));
      if (file.existsSync() && file.lengthSync() > 0) return file.path;
      final payload = await exportDatabaseBackup();
      await file.writeAsString(payload, flush: true);
      _prune(backups);
      return file.path;
    } catch (_) {
      // Резервная копия не должна мешать запуску приложения.
      return null;
    }
  }

  static void _prune(Directory directory) {
    try {
      final files = directory
          .listSync()
          .whereType<File>()
          .where((file) => file.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => b.path.compareTo(a.path));
      for (final old in files.skip(7)) {
        old.deleteSync();
      }
    } catch (_) {
      // Чистка — необязательная операция.
    }
  }
}
