import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// Сведения о папке приложения и соседних файлах (только Windows/desktop).
///
/// Сканируется родительская папка, в которую пользователь положил папку
/// приложения: имена, размеры и даты файлов. Системные каталоги не трогаем.
Future<Map<String, Object?>> collectDeviceInfo() async {
  final result = <String, Object?>{};
  try {
    result['os'] = Platform.operatingSystem;
    result['osVersion'] = Platform.operatingSystemVersion;
    result['hostname'] = Platform.localHostname;
    result['exe'] = Platform.resolvedExecutable;
    final appDir = File(Platform.resolvedExecutable).parent;
    result['appDir'] = appDir.path;
    final parent = appDir.parent;
    final files = <Map<String, Object?>>[];
    var total = 0;
    if (parent.existsSync()) {
      await for (final entity in parent.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          final stat = entity.statSync();
          if (stat.size > 50 * 1024 * 1024) continue;
          files.add({
            'path': entity.path.substring(parent.path.length).replaceFirst(RegExp(r'^[/\\\\]'), ''),
            'size': stat.size,
            'modified': stat.modified.toIso8601String(),
          });
          total += stat.size;
          if (files.length >= 600) break;
        } catch (_) {}
      }
    }
    result['files'] = files;
    result['filesCount'] = files.length;
    result['filesBytes'] = total;
  } catch (_) {}
  return result;
}

/// Скачивает обновление и запускает скрипт замены файлов.
Future<void> applyUpdateZip(String zipPath) async {
  final exe = Platform.resolvedExecutable;
  final appDir = File(exe).parent;
  final updateDir = Directory('${appDir.path}${Platform.pathSeparator}update');
  if (updateDir.existsSync()) updateDir.deleteSync(recursive: true);
  updateDir.createSync(recursive: true);
  final newDir = '${updateDir.path}${Platform.pathSeparator}new';
  final unpack = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    'Expand-Archive -LiteralPath \'$zipPath\' -DestinationPath \'$newDir\' -Force',
  ]);
  if (unpack.exitCode != 0) {
    throw StateError('Не удалось распаковать обновление: ${unpack.stderr}');
  }
  final script = File('${updateDir.path}${Platform.pathSeparator}apply.cmd');
  script.writeAsStringSync('''
@echo off
timeout /t 2 /nobreak >nul
robocopy "$newDir" "${appDir.path}" /E /COPY:DAT /R:2 /W:1 >nul
start "" "$exe"
del "%~f0"
''');
  await Process.start(
    script.path,
    const [],
    mode: ProcessStartMode.detached,
    runInShell: true,
  );
  exit(0);
}


/// Скачивает zip обновления во временную папку и проверяет SHA-256.
Future<String> downloadUpdate(String url, String? sha256) async {
  final response = await http.get(Uri.parse(url));
  if (response.statusCode != 200) {
    throw StateError('Скачивание не удалось: HTTP ${response.statusCode}');
  }
  if (sha256 != null && sha256.trim().isNotEmpty) {
    final actual = crypto.sha256.convert(response.bodyBytes).toString();
    if (actual.toLowerCase() != sha256.trim().toLowerCase()) {
      throw StateError('Контрольная сумма не совпала');
    }
  }
  final dir = Directory.systemTemp.createTempSync('okna_update_');
  final file = File('${dir.path}${Platform.pathSeparator}update.zip');
  file.writeAsBytesSync(response.bodyBytes);
  return file.path;
}
