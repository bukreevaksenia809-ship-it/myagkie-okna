import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Папки приложения на телефоне.
///
/// На Android нельзя писать в `HOME`/`Directory.current` — там корень
/// read-only. Используем личную папку приложения во внешнем хранилище
/// (`Android/data/<package>/files`) — она доступна без разрешений.
class StoragePaths {
  StoragePaths._();

  static String? _root;

  static bool get isMobile => Platform.isAndroid || Platform.isIOS;

  /// Вызывается один раз на старте, до чтения заказов.
  static Future<void> init() async {
    if (!isMobile) return;
    try {
      final base = await getExternalStorageDirectory() ??
          await getApplicationDocumentsDirectory();
      _root = '${base.path}/Мягкие окна';
    } catch (_) {
      final base = await getApplicationDocumentsDirectory();
      _root = '${base.path}/Мягкие окна';
    }
  }

  static String? get root => _root;

  static String? get orders => _root == null ? null : '$_root/Заказы';

  static String? get exports => _root;
}
