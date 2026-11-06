import 'orders_backup_stub.dart'
    if (dart.library.io) 'orders_backup_io.dart' as impl;

/// Создаёт резервную копию папки заказов. Возвращает путь к копии.
///
/// В браузере файловой папки нет — вернётся null.
Future<String?> backupOrdersFolder() => impl.backupOrdersFolderImpl();
