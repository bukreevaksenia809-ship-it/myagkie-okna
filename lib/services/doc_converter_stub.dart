import 'dart:typed_data';

/// Результат конвертации старого `.doc` в `.docx`.
class DocConversionResult {
  const DocConversionResult.success(this.bytes)
    : error = null;

  const DocConversionResult.failure(this.error) : bytes = null;

  final Uint8List? bytes;
  final String? error;

  bool get ok => bytes != null && error == null;
}

/// Заглушка для платформ без LibreOffice: конвертация недоступна.
Future<DocConversionResult> convertDocToDocx(
  Uint8List bytes, {
  required String fileName,
}) async => const DocConversionResult.failure(
  'Конвертация .doc недоступна на этой платформе. '
  'Сохраните файл как .docx в Word.',
);
