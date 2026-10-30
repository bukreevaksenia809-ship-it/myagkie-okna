import 'dart:convert';
import 'dart:typed_data';

import 'file_saver.dart';
import 'legacy_data_migrator.dart';

/// Резервные копии локальной базы.
///
/// JSON-копия содержит весь склад, журнал, партии, заказы, историю и
/// привязки материалов. Её можно сохранить вручную из настроек; на
/// десктопе раз в день автоматически пишется копия рядом с базой.
class DatabaseBackup {
  DatabaseBackup._();

  /// Сохраняет копию через обычный механизм файлов (папка/скачивание).
  static Future<String> saveToFile() async {
    final payload = await exportDatabaseBackup();
    final bytes = Uint8List.fromList(
      utf8.encode(_pretty(payload)),
    );
    final stamp = DateTime.now()
        .toIso8601String()
        .replaceAll(RegExp(r'[:.]'), '-')
        .substring(0, 19);
    final saved = await saveBytes(
      bytes,
      'SoftWindowDrawer-backup-$stamp.json',
    );
    return saved.destination;
  }

  static String _pretty(String source) {
    try {
      return const JsonEncoder.withIndent('  ').convert(jsonDecode(source));
    } catch (_) {
      return source;
    }
  }
}
