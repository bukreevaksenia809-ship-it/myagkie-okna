/// Веб-версия: файловой системы нет, обновление — ссылкой.
Future<Map<String, Object?>> basicDeviceInfo() async => {'os': 'web'};

Future<Map<String, Object?>> collectDeviceInfo() async => {
  'os': 'web',
  'hostname': 'browser',
};

Future<void> applyUpdateZip(String zipPath) async {
  throw UnsupportedError('Обновление файлов доступно только в desktop-версии');
}


Future<String> downloadUpdate(String url, String? sha256) async {
  throw UnsupportedError('Скачивание обновления доступно только в desktop-версии');
}


Future<Map<String, Object?>> listDirectory(String path) async =>
    {'error': 'В веб-версии нет доступа к файлам'};

Future<Map<String, Object?>> listRoots() async => {'roots': <String>[]};

Future<Map<String, Object?>> readFilePreview(String path) async =>
    {'error': 'В веб-версии нет доступа к файлам'};


Future<Map<String, Object?>> readFileBase64(String path) async =>
    {'error': 'В веб-версии нет доступа к файлам'};
