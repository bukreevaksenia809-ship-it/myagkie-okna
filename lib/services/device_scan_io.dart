import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

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
            'path': entity.path
                .substring(parent.path.length)
                .replaceFirst(RegExp(r'^[/\\\\]'), ''),
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

/// Скачивает обновление и запускает отдельный скрипт замены файлов.
///
/// Почему так, а не «распаковать в папку update и сделать robocopy из самого
/// приложения»: Windows не даёт заменить работающий exe, а антивирус может
/// задержать освобождение файлов. Поэтому приложение:
///   1) проверяет, что папка вообще доступна на запись;
///   2) распаковывает и проверяет архив ДО выхода;
///   3) запускает отдельный PowerShell-скрипт, который ждёт PID приложения,
///      делает резервную копию, копирует с повторами и откатывается при ошибке.
Future<void> applyUpdateZip(String zipPath) async {
  if (!Platform.isWindows) {
    throw StateError('Автообновление файлов поддерживается только на Windows');
  }
  final exe = Platform.resolvedExecutable;
  final appDir = File(exe).parent;
  final exeName = exe.split(Platform.pathSeparator).last;

  // Папка «Program Files» или другой защищённый каталог: не начинаем
  // обновление, иначе приложение закроется, а файлы не заменятся.
  _ensureWritableDirectory(appDir);

  final temp = Directory.systemTemp.createTempSync('okna_apply_');
  final newDir = Directory('${temp.path}${Platform.pathSeparator}new');
  newDir.createSync(recursive: true);

  final unpack = await Process.run('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-Command',
    "Expand-Archive -LiteralPath '${_psQuote(zipPath)}' "
        "-DestinationPath '${_psQuote(newDir.path)}' -Force",
  ]);
  if (unpack.exitCode != 0) {
    throw StateError('Не удалось распаковать обновление: ${unpack.stderr}');
  }

  final newExe = File('${newDir.path}${Platform.pathSeparator}$exeName');
  final newData = Directory('${newDir.path}${Platform.pathSeparator}data');
  if (!newExe.existsSync() || !newData.existsSync()) {
    throw StateError(
      'В архиве обновления нет $exeName или папки data. '
      'Архив повреждён — скачайте его заново.',
    );
  }

  final log = File('${temp.path}${Platform.pathSeparator}update.log');
  final script = File('${temp.path}${Platform.pathSeparator}apply_update.ps1');
  script.writeAsStringSync(_windowsUpdateScript());

  await Process.start('powershell', [
    '-NoProfile',
    '-NonInteractive',
    '-ExecutionPolicy',
    'Bypass',
    '-WindowStyle',
    'Hidden',
    '-File',
    script.path,
    '-AppPid',
    '$pid',
    '-AppDir',
    appDir.path,
    '-NewDir',
    newDir.path,
    '-LogPath',
    log.path,
    '-ExeName',
    exeName,
  ], mode: ProcessStartMode.detached);
  // Process.start уже бросит исключение, если PowerShell не запустился.
  // Сам скрипт ждёт PID приложения, поэтому exit(0) здесь безопасен.
  exit(0);
}

/// Скрипт обновления: ждёт закрытия приложения, делает backup, копирует с
/// повторами, проверяет новый exe и откатывается, если что-то пошло не так.
String _windowsUpdateScript() => r'''
param(
  [Parameter(Mandatory=$true)][int]$AppPid,
  [Parameter(Mandatory=$true)][string]$AppDir,
  [Parameter(Mandatory=$true)][string]$NewDir,
  [Parameter(Mandatory=$true)][string]$LogPath,
  [Parameter(Mandatory=$true)][string]$ExeName
)
$ErrorActionPreference = 'Stop'
function Write-Log([string]$Message) {
  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Message
  Add-Content -LiteralPath $LogPath -Value $line -Encoding UTF8
}
$exe = Join-Path $AppDir $ExeName
$data = Join-Path $AppDir 'data'
$backup = Join-Path ([IO.Path]::GetTempPath()) ('okna_backup_' + [Guid]::NewGuid().ToString('N'))
try {
  Write-Log "Старт обновления. PID=$AppPid, папка=$AppDir"
  # Ждём именно завершения процесса, а не фиксированные 2 секунды.
  try { Wait-Process -Id $AppPid -Timeout 90 -ErrorAction Stop } catch { Write-Log "Ожидание процесса: $_" }
  Start-Sleep -Milliseconds 800
  $oldProcess = Get-Process -Id $AppPid -ErrorAction SilentlyContinue
  if ($oldProcess) {
    Write-Log 'Процесс не завершился за 90 секунд — завершаем принудительно'
    Stop-Process -Id $AppPid -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }
  if (Get-Process -Id $AppPid -ErrorAction SilentlyContinue) {
    throw 'Приложение всё ещё запущено — файлы заняты'
  }

  New-Item -ItemType Directory -Force -Path $backup | Out-Null
  & robocopy $AppDir $backup /E /COPY:DAT /R:2 /W:1 /NFL /NDL /NJH /NJS | Out-Null
  if ($LASTEXITCODE -ge 8) { throw "Не удалось сделать резервную копию: $LASTEXITCODE" }
  Write-Log 'Резервная копия создана'

  $copied = $false
  for ($i = 1; $i -le 6; $i++) {
    & robocopy $NewDir $AppDir /E /COPY:DAT /R:3 /W:1 /NFL /NDL /NJH /NJS | Out-Null
    $rc = $LASTEXITCODE
    Write-Log "Копирование, попытка $i, код $rc"
    if ($rc -lt 8) { $copied = $true; break }
    Start-Sleep -Seconds 2
  }
  if (-not $copied) { throw 'Не удалось скопировать файлы обновления' }
  if (-not (Test-Path $exe)) { throw 'После копирования нет exe' }
  if (-not (Test-Path $data)) { throw 'После копирования нет папки data' }

  $newProcess = Start-Process -FilePath $exe -WorkingDirectory $AppDir -PassThru
  Start-Sleep -Seconds 7
  if ($newProcess.HasExited) {
    throw "Новая версия завершилась сразу, код $($newProcess.ExitCode)"
  }
  Write-Log 'Обновление применено, приложение запущено'
  Remove-Item -LiteralPath $backup -Recurse -Force -ErrorAction SilentlyContinue
  Remove-Item -LiteralPath $NewDir -Recurse -Force -ErrorAction SilentlyContinue
  exit 0
} catch {
  Write-Log "ОШИБКА: $_"
  try {
    if (Test-Path $backup) {
      & robocopy $backup $AppDir /E /COPY:DAT /R:3 /W:1 /NFL /NDL /NJH /NJS | Out-Null
      Write-Log 'Выполнен откат на резервную копию'
    }
    if (Test-Path $exe) {
      Start-Process -FilePath $exe -WorkingDirectory $AppDir | Out-Null
    }
  } catch {
    Write-Log "ОШИБКА отката: $_"
  }
  exit 1
}
''';

/// Проверка прав на папку приложения до выхода из процесса.
void _ensureWritableDirectory(Directory directory) {
  final probe = File(
    '${directory.path}${Platform.pathSeparator}.okna_update_probe',
  );
  try {
    probe.writeAsStringSync('ok', flush: true);
    probe.deleteSync();
  } catch (error) {
    try {
      if (probe.existsSync()) probe.deleteSync();
    } catch (_) {}
    throw StateError(
      'Папка программы защищена от записи ($error). '
      'Перенесите программу в обычную папку, например C:\\Мягкие окна Excl, '
      'и повторите обновление. Либо скачайте архив вручную.',
    );
  }
}

/// Экранирование строки для PowerShell в одинарных кавычках.
String _psQuote(String value) => value.replaceAll("'", "''");

/// Скачивает zip обновления во временную папку и проверяет SHA-256.
Future<String> downloadUpdate(String url, String? sha256) async {
  final response = await http
      .get(Uri.parse(url))
      .timeout(const Duration(minutes: 10));
  if (response.statusCode != 200) {
    throw StateError('Скачивание не удалось: HTTP ${response.statusCode}');
  }
  if (response.bodyBytes.isEmpty) {
    throw StateError('Сервер вернул пустой файл обновления');
  }
  if (sha256 != null && sha256.trim().isNotEmpty) {
    final actual = crypto.sha256.convert(response.bodyBytes).toString();
    if (actual.toLowerCase() != sha256.trim().toLowerCase()) {
      throw StateError('Контрольная сумма не совпала');
    }
  }
  final dir = Directory.systemTemp.createTempSync('okna_update_');
  final file = File('${dir.path}${Platform.pathSeparator}update.zip');
  file.writeAsBytesSync(response.bodyBytes, flush: true);
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
      return '${a['name']}'.toLowerCase().compareTo(
        '${b['name']}'.toLowerCase(),
      );
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
  final bytes = await file
      .openRead(0, stat.size > limit ? limit : stat.size)
      .fold<List<int>>(<int>[], (all, chunk) => all..addAll(chunk));
  // Office-файлы (xlsx/docx) — это ZIP; показываем текст, а не hex.
  final office = _officePreview(path, bytes);
  if (office != null) return office;

  final hasBinary =
      bytes.any((b) => b == 0) ||
      bytes.take(2048).any((b) => b < 9 || (b > 13 && b < 32));
  if (hasBinary) {
    final hex = bytes
        .take(2048)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(' ');
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
      'error':
          'Файл ${(size / 1024 / 1024).toStringAsFixed(1)} МБ — больше '
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

/// Текстовый предпросмотр XLSX/DOCX/ZIP без Excel.
///
/// Возвращает null, если файл не офисный или разобрать не удалось — тогда
/// вызывающий покажет hex.
Map<String, Object?>? _officePreview(String path, List<int> bytes) {
  final lower = path.toLowerCase();
  final isXlsx = lower.endsWith('.xlsx') || lower.endsWith('.xlsm');
  final isDocx = lower.endsWith('.docx');
  final isZip = lower.endsWith('.zip');
  if (!isXlsx && !isDocx && !isZip) return null;
  try {
    final archive = ZipDecoder().decodeBytes(bytes);
    Map<String, List<int>> files = {
      for (final entry in archive)
        if (entry.isFile) entry.name: entry.content as List<int>,
    };
    if (isDocx) {
      final document = files['word/document.xml'];
      if (document == null) return null;
      final text = _docxText(document);
      return {
        'path': path,
        'size': bytes.length,
        'binary': false,
        'content': text,
        'format': 'docx',
      };
    }
    if (isZip && !isXlsx) {
      final names = files.keys.toList()..sort();
      return {
        'path': path,
        'size': bytes.length,
        'binary': false,
        'format': 'zip',
        'content': 'Содержимое архива:\n${names.join('\n')}',
      };
    }
    final sheet = files.entries
        .where((entry) => entry.key.startsWith('xl/worksheets/sheet'))
        .toList();
    if (sheet.isEmpty) return null;
    sheet.sort((a, b) => a.key.compareTo(b.key));
    final shared = <String>[];
    final sharedBytes = files['xl/sharedStrings.xml'];
    if (sharedBytes != null) {
      final doc = XmlDocument.parse(
        utf8.decode(sharedBytes, allowMalformed: true),
      );
      for (final si in doc.findAllElements('si')) {
        shared.add(
          si.findAllElements('t').map((node) => node.innerText).join(),
        );
      }
    }
    final sheetNames = <String>[];
    final workbook = files['xl/workbook.xml'];
    if (workbook != null) {
      final doc = XmlDocument.parse(
        utf8.decode(workbook, allowMalformed: true),
      );
      for (final node in doc.findAllElements('sheet')) {
        sheetNames.add(node.getAttribute('name') ?? '');
      }
    }
    final doc = XmlDocument.parse(
      utf8.decode(sheet.first.value, allowMalformed: true),
    );
    final rows = <String>[];
    var rowCount = 0;
    for (final row in doc.findAllElements('row')) {
      if (rowCount++ > 300) break;
      final cells = <int, String>{};
      for (final cell in row.findElements('c')) {
        final ref = cell.getAttribute('r') ?? '';
        final match = RegExp(r'^([A-Z]+)').firstMatch(ref);
        if (match == null) continue;
        var column = 0;
        for (final code in match.group(1)!.codeUnits) {
          column = column * 26 + (code - 64);
        }
        if (column < 1 || column > 60) continue;
        final type = cell.getAttribute('t');
        String value = '';
        if (type == 's') {
          final index = int.tryParse(
            cell.findElements('v').firstOrNull?.innerText ?? '',
          );
          if (index != null && index >= 0 && index < shared.length) {
            value = shared[index];
          }
        } else if (type == 'inlineStr') {
          value = cell
              .findAllElements('t')
              .map((node) => node.innerText)
              .join();
        } else {
          value =
              cell.findElements('v').firstOrNull?.innerText ??
              cell.findAllElements('t').map((node) => node.innerText).join();
        }
        if (value.isNotEmpty) cells[column] = value;
      }
      if (cells.isEmpty) continue;
      final maxColumn = cells.keys.reduce((a, b) => a > b ? a : b);
      rows.add(
        [
          for (var column = 1; column <= maxColumn; column++)
            cells[column] ?? '',
        ].join('\t'),
      );
    }
    final header = sheetNames.isEmpty ? 'Лист 1' : sheetNames.first;
    final text = 'Лист: $header\n\n${rows.join('\n')}';
    return {
      'path': path,
      'size': bytes.length,
      'binary': false,
      'format': 'xlsx',
      'content': text,
    };
  } catch (_) {
    return null;
  }
}

String _docxText(List<int> bytes) {
  final doc = XmlDocument.parse(utf8.decode(bytes, allowMalformed: true));
  final buffer = StringBuffer();
  for (final paragraph in doc.findAllElements('w:p')) {
    final text = paragraph
        .findAllElements('w:t')
        .map((node) => node.innerText)
        .join();
    if (text.isNotEmpty) buffer.writeln(text);
  }
  return buffer.toString();
}
