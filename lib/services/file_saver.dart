/// Сохранение файлов: на десктопе — в папку, в браузере — скачиванием.
library;
export 'file_saver_io.dart' if (dart.library.js_interop) 'file_saver_web.dart';
