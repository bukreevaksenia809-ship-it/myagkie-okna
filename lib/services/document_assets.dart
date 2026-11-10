import 'dart:typed_data';

import 'document_assets_io.dart'
    if (dart.library.js_interop) 'document_assets_web.dart' as platform;

/// Сохраняет байты картинки в хранилище ассетов документов и возвращает ссылку.
///
/// На десктопе это файл рядом с документами, в браузере — отдельный ключ
/// shared_preferences. Ссылка попадает в [DocBlock.assetRef], поэтому шаблон
/// переживает перезапуск и переносится вместе с документами.
Future<String> saveDocumentAsset(String fileName, Uint8List bytes) =>
    platform.DocumentAssetBackend().put(fileName, bytes);
