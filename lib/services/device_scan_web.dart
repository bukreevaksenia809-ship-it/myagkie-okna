/// Веб-версия: файловой системы нет, обновление — ссылкой.
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
