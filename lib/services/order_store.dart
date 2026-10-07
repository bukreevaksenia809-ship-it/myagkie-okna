/// Хранилище заказов: на десктопе — файлы, в браузере — локальное хранилище.
library;
export 'order_store_io.dart' if (dart.library.js_interop) 'order_store_web.dart';
