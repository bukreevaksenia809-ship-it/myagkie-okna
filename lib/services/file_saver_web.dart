import 'dart:typed_data';

import 'package:printing/printing.dart';

import 'pdf_signature.dart';

/// Куда сохранён файл: в браузере файл скачивается.
class SavedFile {
  const SavedFile({required this.destination, this.path});

  final String destination;

  /// В браузере пути на диске нет.
  final String? path;
}

/// Отдаёт файл браузеру — он скачивает его как обычный файл.
Future<SavedFile> saveBytes(
  Uint8List bytes,
  String fileName, {
  String? directoryPath,
}) async {
  if (fileName.toLowerCase().endsWith('.pdf')) {
    bytes = await PdfSignatureService.applyIfEnabled(bytes);
  }
  await Printing.sharePdf(bytes: bytes, filename: fileName);
  return SavedFile(destination: 'файл $fileName скачан браузером');
}

/// В браузере файлы хранит сам пользователь.
String exportFolderDescription() => 'папка загрузок браузера';
