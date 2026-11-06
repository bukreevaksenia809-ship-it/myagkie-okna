// Ассеты документов в браузере: отдельные ключи shared_preferences.
//
// В вебе нет файловой системы, поэтому байты картинок/PDF лежат не в общем
// JSON документа, а под своими ключами. Ссылка в JSON — тот же идентификатор,
// что и на десктопе, поэтому документ переносится между версиями без правок.
import 'dart:convert';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

/// Префикс ключей ассетов в localStorage.
const String documentAssetKeyPrefix = 'soft_window_drawer_doc_asset_v1:';

/// Подпись места хранения ассетов для интерфейса.
String documentAssetsFolderDescription([String? directoryPath]) =>
    'локальное хранилище браузера';

/// Хранилище ассетов на shared_preferences.
class DocumentAssetBackend {
  DocumentAssetBackend({String? directoryPath});

  /// Сохраняет байты отдельным ключом и возвращает ссылку.
  Future<String> put(String fileName, Uint8List bytes) async {
    final prefs = await SharedPreferences.getInstance();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ref = '${stamp}_${_safeName(fileName)}';
    await prefs.setString('$documentAssetKeyPrefix$ref', base64Encode(bytes));
    return ref;
  }

  /// Читает ассет по ссылке; null — ключа нет или он битый.
  Future<Uint8List?> read(String ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$documentAssetKeyPrefix${_baseName(ref)}');
      if (raw == null || raw.isEmpty) return null;
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String ref) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$documentAssetKeyPrefix${_baseName(ref)}');
    } catch (_) {
      // Битый ключ не должен мешать удалить документ.
    }
  }
}

/// В браузере произвольный файл с диска не прочитать без пакета выбора файла.
/// Возвращаем null — интерфейс покажет понятное сообщение.
Future<Uint8List?> readLocalFileBytes(String path) async => null;

/// В браузере DOCX не распаковать средствами dart:io, поэтому извлечения
/// текста нет: файл сохраняется как обычное вложение. Это не ошибка.
Future<String?> extractDocxText(Uint8List bytes) async => null;

String _baseName(String ref) => ref.split(RegExp(r'[/\\]')).last;

String _safeName(String fileName) {
  final base = _baseName(fileName);
  final cleaned = base
      .replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9._-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'asset.bin' : cleaned;
}
