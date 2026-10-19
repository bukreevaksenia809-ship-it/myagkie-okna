// Фотографии крепежа для чертежа.
//
// Заказчик приложил фото французского замка: металлическая овальная
// пластина-окантовка с продетым коричневым ремешком (кожа/пластик). Замок
// теперь рисуется этой картинкой, а не векторной схемой.
//
// Картинка — обычный ассет, без новых пакетов. Декодируем её один раз и
// держим готовый `ui.Image`: пейнтер получает его в конструкторе, поэтому
// повторная сборка листа не пересоздаёт картинку. Пока картинка не
// загрузилась, пейнтер рисует прежний векторный замок (fallback) — пустых
// мест на чертеже не бывает.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Ассеты крепежа и их загрузка в память.
class FastenerArtwork {
  FastenerArtwork._();

  /// Французский замок: фото с овальной пластиной и коричневым ремешком.
  static const String frenchLockAsset = 'assets/fasteners/french_lock.webp';

  /// Готовая картинка французского замка; null — ещё не загружена.
  ///
  /// Слушатель нужен листу чертежа: когда картинка декодирована, лист один
  /// раз перерисовывается — и в снимок RepaintBoundary (печать/PDF) замок
  /// попадает уже фотографией, а не векторным fallback.
  static final ValueNotifier<ui.Image?> frenchLock =
      ValueNotifier<ui.Image?>(null);

  static Future<ui.Image?>? _loading;

  /// Загружает французский замок (один раз), возвращает картинку или null.
  static Future<ui.Image?> ensureFrenchLock() {
    final ready = frenchLock.value;
    if (ready != null) return Future.value(ready);
    return _loading ??= _loadFrenchLock();
  }

  static Future<ui.Image?> _loadFrenchLock() async {
    try {
      final data = await rootBundle.load(frenchLockAsset);
      final codec = await ui.instantiateImageCodec(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      );
      final frame = await codec.getNextFrame();
      frenchLock.value = frame.image;
      return frame.image;
    } catch (error) {
      // Картинки нет или формат не поддержан — остаётся векторный замок.
      debugPrint('Не загрузилась картинка $frenchLockAsset: $error');
      return null;
    }
  }

  /// Сбросить кэш. Только для тестов, чтобы проверить fallback «без фото».
  @visibleForTesting
  static void reset() {
    _loading = null;
    frenchLock.value = null;
  }
}
