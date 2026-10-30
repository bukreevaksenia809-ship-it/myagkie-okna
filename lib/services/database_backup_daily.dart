/// Ежедневная копия базы: на устройствах — файл, в браузере — no-op.
library;

export 'database_backup_io.dart'
    if (dart.library.js_interop) 'database_backup_web.dart';
