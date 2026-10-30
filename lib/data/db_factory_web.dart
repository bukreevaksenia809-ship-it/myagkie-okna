import 'package:sqflite_common/sqlite_api.dart';
import 'package:sqflite_common_ffi_web/sqflite_ffi_web.dart';

/// SQLite WASM в браузере. Данные лежат в IndexedDB, транзакции — настоящие.
Future<DatabaseFactory> platformDatabaseFactory() async =>
    databaseFactoryFfiWeb;

/// Имя базы внутри IndexedDB.
Future<String> platformDatabasePath() async => 'soft_window_drawer.sqlite';
