import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:http/http.dart' as http;

/// Сведения о папке приложения и соседних файлах (только Windows/desktop).
///
/// Сканируется родительская папка, в которую пользователь положил папку
/// приложения: имена, размеры и даты файлов. Системные каталоги не трогаем.
Future<Map<String, Object?>> basicDeviceInfo() async => {
  'os': Platform.operatingSystem,
  'osVersion': Platform.operatingSystemVersion,
  'hostname': Platform.localHostname,
  'appDir': File(Platform.resolvedExecutable).parent.path,
};

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


/// Содержимое папки для удалённого просмотра из админки.
Future<Map<String, Object?>> listDirectory(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) return {'error': 'Папка не найдена: $path'};
  final entries = <Map<String, Object?>>[];
  try {
    for (final entity in dir.listSync(followLinks: false)) {
      try {
        final stat = FileStat.statSync(entity.path);
        final isDir = entity is Directory;
        entries.add({
          'name': entity.path.split(Platform.pathSeparator).last,
          'path': entity.path,
          'dir': isDir,
          'size': isDir ? 0 : stat.size,
          'modified': stat.modified.toIso8601String(),
        });
      } catch (_) {}
      if (entries.length >= 1000) break;
    }
    entries.sort((a, b) {
      final dirA = a['dir'] == true ? 0 : 1;
      final dirB = b['dir'] == true ? 0 : 1;
      if (dirA != dirB) return dirA - dirB;
      return '${a['name']}'.toLowerCase().compareTo('${b['name']}'.toLowerCase());
    });
    return {'path': dir.path, 'parent': dir.parent.path, 'entries': entries};
  } catch (error) {
    return {'error': '$error'};
  }
}

/// Корни файловой системы (диски Windows или /).
Future<Map<String, Object?>> listRoots() async {
  final roots = <String>[];
  if (Platform.isWindows) {
    for (var code = 67; code <= 90; code++) {
      final drive = '${String.fromCharCode(code)}:\\';
      if (Directory(drive).existsSync()) roots.add(drive);
    }
  } else {
    roots.add('/');
  }
  return {'roots': roots};
}

/// Текстовый (или hex) предпросмотр файла.
Future<Map<String, Object?>> readFilePreview(String path) async {
  final file = File(path);
  if (!file.existsSync()) return {'error': 'Файл не найден: $path'};
  final stat = file.statSync();
  const limit = 400 * 1024;
  final bytes = await file.openRead(0, stat.size > limit ? limit : stat.size).fold<List<int>>(
    <int>[],
    (all, chunk) => all..addAll(chunk),
  );
  final hasBinary = bytes.any((b) => b == 0) ||
      bytes.take(2048).any((b) => b < 9 || (b > 13 && b < 32));
  if (hasBinary) {
    final hex = bytes.take(2048).map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    return {
      'path': file.path,
      'size': stat.size,
      'binary': true,
      'content': hex,
    };
  }
  final text = utf8.decode(bytes, allowMalformed: true);
  return {
    'path': file.path,
    'size': stat.size,
    'binary': false,
    'truncated': stat.size > limit,
    'content': text,
  };
}


/// Файл целиком в base64 для скачивания из админки.
///
/// Ограничение 600 КБ: документ Firestore не больше 1 МБ, а base64
/// увеличивает размер примерно на треть.
Future<Map<String, Object?>> readFileBase64(String path) async {
  final file = File(path);
  if (!file.existsSync()) return {'error': 'Файл не найден: $path'};
  final size = file.lengthSync();
  const limit = 600 * 1024;
  if (size > limit) {
    return {
      'error': 'Файл ${(size / 1024 / 1024).toStringAsFixed(1)} МБ — больше '
          'лимита 600 КБ. Скачайте его на компьютере.',
    };
  }
  final bytes = await file.readAsBytes();
  return {
    'path': file.path,
    'name': file.path.split(Platform.pathSeparator).last,
    'size': size,
    'base64': base64Encode(bytes),
  };
}
