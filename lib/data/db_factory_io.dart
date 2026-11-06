import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// SQLite на десктопе и мобильных платформах.
Future<DatabaseFactory> platformDatabaseFactory() async {
  sqfliteFfiInit();
  return databaseFactoryFfi;
}

/// Файл базы в каталоге поддержки приложения.
///
/// В тестах и на CI используется подмена через [Directory.systemTemp] и
/// `AppDatabase.configureForTesting`, поэтому сюда попадает только реальный
/// запуск приложения.
Future<String> platformDatabasePath() async {
  Directory directory;
  try {
    directory = await getApplicationSupportDirectory();
  } catch (_) {
    directory = Directory.systemTemp;
  }
  await directory.create(recursive: true);
  return p.join(directory.path, 'soft_window_drawer.sqlite');
}
