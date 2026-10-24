// Ассеты документов на десктопе: файлы рядом с заказами.
//
// В общем JSON документа хранятся только ссылки (имя файла), а сами PNG/PDF
// лежат здесь. Так JSON остаётся маленьким и читаемым, а картинки не
// раздувают shared_preferences.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Каталог ассетов документов по умолчанию:
/// <Домашняя>/Downloads/Мягкие окна/Документы/ассеты.
Directory documentAssetsDirectory([String? directoryPath]) {
  if (directoryPath != null && directoryPath.isNotEmpty) {
    return Directory(directoryPath);
  }
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (home.isEmpty) {
    return Directory('${Directory.current.path}/Мягкие окна/Документы/ассеты');
  }
  return Directory('$home/Downloads/Мягкие окна/Документы/ассеты');
}

/// Подпись места хранения ассетов для интерфейса.
String documentAssetsFolderDescription([String? directoryPath]) =>
    documentAssetsDirectory(directoryPath).path;

/// Файловое хранилище ассетов документа.
class DocumentAssetBackend {
  DocumentAssetBackend({this.directoryPath});

  final String? directoryPath;

  Directory get _directory => documentAssetsDirectory(directoryPath);

  /// Сохраняет байты и возвращает ссылку (имя файла).
  Future<String> put(String fileName, Uint8List bytes) async {
    final directory = _directory;
    await directory.create(recursive: true);
    final safe = _safeName(fileName);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final ref = '${stamp}_$safe';
    final file = File('${directory.path}${Platform.pathSeparator}$ref');
    await file.writeAsBytes(bytes, flush: true);
    return ref;
  }

  /// Читает ассет по ссылке; null — файла нет или он битый.
  Future<Uint8List?> read(String ref) async {
    try {
      final file = File('${_directory.path}${Platform.pathSeparator}${_baseName(ref)}');
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> delete(String ref) async {
    try {
      final file = File('${_directory.path}${Platform.pathSeparator}${_baseName(ref)}');
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Битый ассет не должен мешать удалить документ.
    }
  }
}

/// Читает произвольный файл с диска для вложения/картинки.
///
/// Возвращает null, если путь пустой или файла нет — интерфейс покажет
/// понятное сообщение, а не упадёт.
Future<Uint8List?> readLocalFileBytes(String path) async {
  final cleaned = path.trim().replaceAll('"', '').replaceAll("'", '');
  if (cleaned.isEmpty) return null;
  try {
    final file = File(cleaned);
    if (!file.existsSync()) return null;
    return await file.readAsBytes();
  } catch (_) {
    return null;
  }
}

/// Извлекает текст из DOCX без новых зависимостей.
///
/// DOCX — это ZIP; `word/document.xml` распаковывается `ZLibDecoder(raw: true)`.
/// Разбор best-effort: из XML остаются абзацы, ячейки и разрывы строк. Если
/// файл не DOCX/ZIP или сжат нестандартно — возвращается null, вызывающий код
/// сохраняет файл как обычное вложение и показывает сообщение.
Future<String?> extractDocxText(Uint8List bytes) async {
  try {
    final xml = _readZipEntry(bytes, 'word/document.xml');
    if (xml == null) return null;
    return _docxXmlToText(utf8.decode(xml, allowMalformed: true));
  } catch (_) {
    return null;
  }
}

/// Читает один файл из ZIP по центральному каталогу.
///
/// Центральный каталог надёжнее локальных заголовков: в DOCX размеры часто
/// лежат в data descriptor, и локальный заголовок содержит нули.
Uint8List? _readZipEntry(Uint8List bytes, String entryName) {
  final eocd = _findEocd(bytes);
  if (eocd < 0) return null;
  final data = ByteData.sublistView(bytes);
  final entries = data.getUint16(eocd + 10, Endian.little);
  var offset = data.getUint32(eocd + 16, Endian.little);
  for (var i = 0; i < entries; i++) {
    if (offset + 46 > bytes.length) return null;
    if (data.getUint32(offset, Endian.little) != 0x02014b50) return null;
    final method = data.getUint16(offset + 10, Endian.little);
    final compressedSize = data.getUint32(offset + 20, Endian.little);
    final nameLength = data.getUint16(offset + 28, Endian.little);
    final extraLength = data.getUint16(offset + 30, Endian.little);
    final commentLength = data.getUint16(offset + 32, Endian.little);
    final localOffset = data.getUint32(offset + 42, Endian.little);
    final nameStart = offset + 46;
    if (nameStart + nameLength > bytes.length) return null;
    final name = utf8.decode(
      bytes.sublist(nameStart, nameStart + nameLength),
      allowMalformed: true,
    );
    if (name == entryName) {
      return _readLocalEntry(
        bytes,
        localOffset,
        method,
        compressedSize,
      );
    }
    offset = nameStart + nameLength + extraLength + commentLength;
  }
  return null;
}

Uint8List? _readLocalEntry(
  Uint8List bytes,
  int localOffset,
  int method,
  int compressedSize,
) {
  final data = ByteData.sublistView(bytes);
  if (localOffset + 30 > bytes.length) return null;
  if (data.getUint32(localOffset, Endian.little) != 0x04034b50) return null;
  final nameLength = data.getUint16(localOffset + 26, Endian.little);
  final extraLength = data.getUint16(localOffset + 28, Endian.little);
  final start = localOffset + 30 + nameLength + extraLength;
  final end = start + compressedSize;
  if (end > bytes.length) return null;
  final payload = bytes.sublist(start, end);
  if (method == 0) return Uint8List.fromList(payload);
  if (method == 8) {
    return Uint8List.fromList(ZLibDecoder(raw: true).convert(payload));
  }
  return null;
}

int _findEocd(Uint8List bytes) {
  final end = bytes.length - 22;
  final start = end - 65535 < 0 ? 0 : end - 65535;
  for (var i = end; i >= start; i--) {
    if (bytes[i] == 0x50 &&
        bytes[i + 1] == 0x4b &&
        bytes[i + 2] == 0x05 &&
        bytes[i + 3] == 0x06) {
      return i;
    }
  }
  return -1;
}

/// Достаёт читаемый текст из `word/document.xml`.
String _docxXmlToText(String xml) {
  var text = xml;
  text = text.replaceAll(RegExp(r'<w:tab[^>]*/>'), '\t');
  text = text.replaceAll(RegExp(r'<w:br[^>]*/>'), '\n');
  text = text.replaceAll('</w:tc>', '\t');
  text = text.replaceAll('</w:tr>', '\n');
  text = text.replaceAll('</w:p>', '\n');
  text = text.replaceAll(RegExp(r'<[^>]+>'), '');
  text = text
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
  text = text.replaceAll(RegExp(r'&#(\d+);'), '');
  text = text
      .split('\n')
      .map((line) => line.replaceAll(RegExp(r'[ \t]+'), ' ').trim())
      .where((line) => line.isNotEmpty)
      .join('\n');
  return text.trim();
}

String _baseName(String ref) => ref.split(RegExp(r'[/\\]')).last;

String _safeName(String fileName) {
  final base = _baseName(fileName);
  final cleaned = base
      .replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9._-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'asset.bin' : cleaned;
}
