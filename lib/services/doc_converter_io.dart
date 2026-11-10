import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'doc_converter_stub.dart' show DocConversionResult;

/// Таймаут конвертации: LibreOffice на большом файле может думать долго, но
/// больше минуты ждать бессмысленно — лучше показать понятную ошибку.
const Duration _conversionTimeout = Duration(seconds: 60);

/// Конвертирует `.doc` → `.docx` через LibreOffice в headless-режиме.
///
/// Ищет `soffice`/`libreoffice` в PATH и типовых местах установки (macOS,
/// Windows, Linux), пишет временный файл, ждёт завершения и читает результат.
/// Временные файлы удаляются в `finally`.
Future<DocConversionResult> convertDocToDocx(
  Uint8List bytes, {
  required String fileName,
}) async {
  if (bytes.isEmpty) {
    return const DocConversionResult.failure('Файл .doc пустой или повреждён.');
  }
  final executable = _findLibreOffice();
  if (executable == null) {
    return const DocConversionResult.failure(
      'Для .doc нужен LibreOffice. Установите его или сохраните файл как '
      '.docx в Word.',
    );
  }
  final temp = await Directory.systemTemp.createTemp('soft_window_doc_');
  try {
    final input = File(p.join(temp.path, 'input.doc'));
    await input.writeAsBytes(bytes, flush: true);
    final profile = Directory(p.join(temp.path, 'profile'));
    await profile.create(recursive: true);
    final args = <String>[
      '--headless',
      '--norestore',
      '--convert-to',
      'docx',
      '--outdir',
      temp.path,
      '-env:UserInstallation=${Uri.directory(profile.path)}',
      input.path,
    ];
    final process = await Process.start(
      executable,
      args,
      runInShell: Platform.isWindows,
    );
    final stdoutFuture = process.stdout.transform(utf8.decoder).join();
    final stderrFuture = process.stderr.transform(utf8.decoder).join();
    var timedOut = false;
    int code;
    try {
      code = await process.exitCode.timeout(_conversionTimeout);
    } on TimeoutException {
      timedOut = true;
      process.kill();
      code = await process.exitCode.timeout(
        const Duration(seconds: 5),
        onTimeout: () => -1,
      );
    }
    final stdoutText = await stdoutFuture;
    final stderrText = await stderrFuture;
    if (timedOut) {
      return const DocConversionResult.failure(
        'LibreOffice не ответил за 60 секунд. Попробуйте ещё раз или '
        'сохраните файл как .docx в Word.',
      );
    }
    final output = File(p.join(temp.path, 'input.docx'));
    if (output.existsSync()) {
      final converted = await output.readAsBytes();
      if (converted.isNotEmpty) {
        return DocConversionResult.success(converted);
      }
    }
    final details = _tail('$stderrText $stdoutText');
    return DocConversionResult.failure(
      'LibreOffice не смог открыть .doc (код $code). '
      '${details.isEmpty ? '' : '$details. '}'
      'Сохраните файл как .docx в Word.',
    );
  } catch (error) {
    return DocConversionResult.failure(
      'Не удалось конвертировать .doc через LibreOffice: $error. '
      'Сохраните файл как .docx в Word.',
    );
  } finally {
    try {
      await temp.delete(recursive: true);
    } catch (_) {
      // Временная папка не должна мешать импорту.
    }
  }
}

/// Ищет LibreOffice: сначала PATH (soffice/libreoffice), затем типовые пути.
String? _findLibreOffice() {
  final names = Platform.isWindows
      ? const ['soffice.exe', 'soffice.com', 'libreoffice.exe']
      : const ['soffice', 'libreoffice'];
  final path = Platform.environment['PATH'] ?? '';
  final separator = Platform.isWindows ? ';' : ':';
  for (final directory in path.split(separator)) {
    final trimmed = directory.trim();
    if (trimmed.isEmpty) continue;
    for (final name in names) {
      final candidate = File(p.join(trimmed, name));
      if (candidate.existsSync()) return candidate.path;
    }
  }
  for (final candidate in _typicalPaths()) {
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

List<String> _typicalPaths() {
  if (Platform.isMacOS) {
    return const [
      '/Applications/LibreOffice.app/Contents/MacOS/soffice',
      '/opt/homebrew/bin/soffice',
      '/usr/local/bin/soffice',
    ];
  }
  if (Platform.isWindows) {
    return const [
      r'C:\Program Files\LibreOffice\program\soffice.exe',
      r'C:\Program Files (x86)\LibreOffice\program\soffice.exe',
      r'C:\Program Files\LibreOffice\program\soffice.com',
      r'C:\Program Files (x86)\LibreOffice\program\soffice.com',
    ];
  }
  return const [
    '/usr/bin/soffice',
    '/usr/bin/libreoffice',
    '/snap/bin/libreoffice',
    '/opt/libreoffice/program/soffice',
  ];
}

String _tail(String value) {
  final text = value.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.length <= 240) return text;
  return '…${text.substring(text.length - 240)}';
}
