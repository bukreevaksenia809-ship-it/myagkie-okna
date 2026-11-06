import 'package:sqflite_common/sqlite_api.dart';

import 'db_factory_io.dart' if (dart.library.js_interop) 'db_factory_web.dart'
    as platform;

/// Фабрика SQLite для текущей платформы.
///
/// На десктопе/мобильном это `sqflite_common_ffi`, в браузере —
/// `sqflite_common_ffi_web` (SQLite WASM + IndexedDB). Общий код приложения
/// работает с одним и тем же API и транзакциями.
Future<DatabaseFactory> platformDatabaseFactory() =>
    platform.platformDatabaseFactory();

/// Путь к файлу базы (в браузере — имя базы внутри IndexedDB).
Future<String> platformDatabasePath() => platform.platformDatabasePath();
