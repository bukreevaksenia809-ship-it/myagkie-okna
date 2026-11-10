import 'dart:typed_data';

import 'doc_converter_stub.dart' show DocConversionResult;
import 'doc_converter_stub.dart'
    if (dart.library.io) 'doc_converter_io.dart'
    if (dart.library.js_interop) 'doc_converter_web.dart' as platform;

export 'doc_converter_stub.dart' show DocConversionResult;

/// Конвертирует старый `.doc` в `.docx` через LibreOffice (только десктоп).
///
/// В браузере и на платформах без LibreOffice возвращает понятную ошибку:
/// пользователь должен сохранить файл как `.docx` в Word.
Future<DocConversionResult> convertDocToDocx(
  Uint8List bytes, {
  required String fileName,
}) => platform.convertDocToDocx(bytes, fileName: fileName);
