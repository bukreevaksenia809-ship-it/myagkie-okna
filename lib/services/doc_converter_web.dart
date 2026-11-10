import 'dart:typed_data';

import 'doc_converter_stub.dart' show DocConversionResult;

/// В браузере нет доступа к LibreOffice: честно просим сохранить `.docx`.
Future<DocConversionResult> convertDocToDocx(
  Uint8List bytes, {
  required String fileName,
}) async => const DocConversionResult.failure(
  'В браузере старый .doc не открыть. Откройте файл в Word или LibreOffice '
  'и сохраните как .docx — такой файл импортируется с текстом и картинками.',
);
