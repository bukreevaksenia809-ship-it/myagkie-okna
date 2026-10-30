import '../data/app_database.dart';
import 'legacy_data_migrator.dart';
import 'database_backup_daily.dart';

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
      await DailyDatabaseBackup.run();
      ready = true;
      databaseError = null;
    } catch (error) {
      ready = false;
      databaseError = '$error';
    }
  }
}
