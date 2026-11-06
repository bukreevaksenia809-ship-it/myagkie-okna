import '../data/app_database.dart';
import 'legacy_data_migrator.dart';
import 'database_backup_daily.dart';
import 'price_warehouse_sync.dart';

/// Инициализация локальной базы и перенос старых данных.
///
/// Ошибка базы не должна превращать приложение в серый экран: она
/// запоминается и показывается в интерфейсе, а калькулятор продолжает
/// работать.
class AppBootstrap {
  AppBootstrap._();

  static String? databaseError;
  static bool ready = false;

  static Future<void> initialize() async {
    try {
      await AppDatabase.instance.open();
      await LegacyDataMigrator().run();
      try {
        await PriceWarehouseSync().seedOnce();
      } catch (_) {
        // Склад может быть недоступен — приложение всё равно открывается.
      }
      await DailyDatabaseBackup.run();
      ready = true;
      databaseError = null;
    } catch (error) {
      ready = false;
      databaseError = '$error';
    }
  }
}
