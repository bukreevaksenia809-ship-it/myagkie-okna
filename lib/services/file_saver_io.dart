import 'dart:io';
import 'dart:typed_data';

/// Куда сохранён файл: человекочитаемое место и путь на диске.
class SavedFile {
  const SavedFile({required this.destination, this.path});

  /// Текст для сообщения пользователю.
  final String destination;

  /// Путь на диске (в браузере — null).
  final String? path;
}

/// Каталог готовых чертежей по умолчанию: <Домашняя>/Downloads/Мягкие окна.
///
/// На Windows переменной HOME обычно нет — там домашний каталог в USERPROFILE.
/// Разделитель '/' понимают и Windows, и macOS.
Directory exportDirectory() {
  final home = Platform.environment['HOME'] ??
      Platform.environment['USERPROFILE'] ??
      '';
  if (home.isEmpty) {
    return Directory('${Directory.current.path}/Мягкие окна');
  }
  return Directory('$home/Downloads/Мягкие окна');
}

/// Сохраняет файл на диск.
Future<SavedFile> saveBytes(
  Uint8List bytes,
  String fileName, {
  String? directoryPath,
}) async {
  final directory = (directoryPath != null && directoryPath.isNotEmpty)
      ? Directory(directoryPath)
      : exportDirectory();
  await directory.create(recursive: true);
  final file = File('${directory.path}/$fileName');
  await file.writeAsBytes(bytes, flush: true);
  return SavedFile(destination: file.path, path: file.path);
}

/// Подпись каталога для интерфейса.
String exportFolderDescription() => exportDirectory().path;
