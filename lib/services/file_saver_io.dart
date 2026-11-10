import 'dart:io';
import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'pdf_signature.dart';

import 'storage_paths.dart';

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
  final mobileDir = StoragePaths.exports;
  if (mobileDir != null) return Directory(mobileDir);
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
}
) async {
  if (fileName.toLowerCase().endsWith('.pdf')) {
    bytes = await PdfSignatureService.applyIfEnabled(bytes);
  }
  // На телефоне отдаём файл системному «Поделиться»: пользователь сам
  // выбирает «Загрузки», «Файлы» или отправляет в мессенджер. Это не требует
  // доступа ко всей памяти и работает на Android 8+.
  if (StoragePaths.isMobile) {
    await Printing.sharePdf(bytes: bytes, filename: fileName);
    return SavedFile(destination: 'файл $fileName сохранён через «Поделиться»');
  }
  final directory = (directoryPath != null && directoryPath.isNotEmpty)
      ? Directory(directoryPath)
      : exportDirectory();
  await directory.create(recursive: true);
  // Не перезаписываем чужой файл молча: при совпадении имени добавляем « (2)».
  final file = _uniqueFile(directory, fileName);
  await file.writeAsBytes(bytes, flush: true);
  return SavedFile(destination: file.path, path: file.path);
}

/// Свободное имя в [directory]: `отчёт.pdf` → `отчёт (2).pdf`.
///
/// Сохранение отчёта с тем же именем не должно затирать предыдущий файл без
/// предупреждения, поэтому ищем первый свободный номер.
File _uniqueFile(Directory directory, String fileName) {
  final direct = File('${directory.path}/$fileName');
  if (!direct.existsSync()) return direct;
  final dot = fileName.lastIndexOf('.');
  final hasExtension = dot > 0 && dot < fileName.length - 1;
  final base = hasExtension ? fileName.substring(0, dot) : fileName;
  final extension = hasExtension ? fileName.substring(dot) : '';
  for (var index = 2; index < 1000; index++) {
    final candidate = File('${directory.path}/$base ($index)$extension');
    if (!candidate.existsSync()) return candidate;
  }
  final stamp = DateTime.now().millisecondsSinceEpoch;
  return File('${directory.path}/$base ($stamp)$extension');
}

/// Подпись каталога для интерфейса.
String exportFolderDescription() => exportDirectory().path;
