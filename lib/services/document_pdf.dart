// PDF и печать документа заказа.
//
// Документ уже свёрстан в A4-виджеты (см. widgets/docs/document_page.dart),
// поэтому PDF собирается из снимков страниц — так же, как листы чертежа в
// services/pdf_export.dart. Это даёт точное совпадение экрана и бумаги и не
// требует шрифтов с кириллицей: на странице уже нарисован русский текст.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../models/document.dart';
import 'file_saver.dart';
import 'pdf_export.dart';

/// Ширина A4-страницы документа в логических пикселях (96 dpi).
const double documentA4Width = 794;

/// Высота A4-страницы документа в логических пикселях.
const double documentA4Height = 1123;

/// Пропорции A4: 297 / 210.
const double documentA4Aspect = documentA4Height / documentA4Width;

/// Снимает готовые A4-страницы в PNG по одной.
///
/// [pageKeys] — ключи `RepaintBoundary` страниц в порядке документа. Страницы
/// уже должны быть построены и отрисованы (редактор перед экспортом
/// переключается в предпросмотр и ждёт кадр).
Future<List<Uint8List>> captureDocumentPages({
  required List<GlobalKey> pageKeys,
  double pixelRatio = 2.5,
}) async {
  if (pageKeys.isEmpty) {
    throw StateError('Документ ещё не свёрстан: нет ни одной A4-страницы');
  }
  final pages = <Uint8List>[];
  for (final key in pageKeys) {
    final object = key.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) {
      throw StateError('A4-страница документа ещё не построена');
    }
    final image = await object.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('Не удалось закодировать A4-страницу в PNG');
      }
      pages.add(data.buffer.asUint8List());
    } finally {
      image.dispose();
    }
  }
  return pages;
}

/// Собирает PDF документа: каждая A4-страница — отдельная страница A4.
Future<Uint8List> buildDocumentPdf({
  required List<GlobalKey> pageKeys,
  required String title,
  String? author,
  double pixelRatio = 2.5,
}) async {
  final pages = await captureDocumentPages(
    pageKeys: pageKeys,
    pixelRatio: pixelRatio,
  );
  final builder = SheetPdfBuilder(
    title: title,
    author: author ?? title,
    creator: 'soft_window_drawer',
  );
  for (final png in pages) {
    builder.addPageImage(png, format: SheetPageFormat.a4Portrait);
  }
  return builder.save();
}

/// Имя PDF-файла: «Акт-выполненных-работ-АКТ-20261023-20261023-1530.pdf».
String documentPdfFileName(OrderDocument document, {DateTime? now}) {
  final moment = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp = '${moment.year}${two(moment.month)}${two(moment.day)}'
      '-${two(moment.hour)}${two(moment.minute)}';
  final base = '${document.title}-${document.number}'
      .replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '${base.isEmpty ? 'документ' : base}-$stamp.pdf';
}

/// Сохраняет документ в PDF: на десктопе — файлом, в браузере — скачиванием.
Future<SavedFile> exportDocumentPdf({
  required List<GlobalKey> pageKeys,
  required OrderDocument document,
  String? directoryPath,
  double pixelRatio = 2.5,
}) async {
  final bytes = await buildDocumentPdf(
    pageKeys: pageKeys,
    title: document.title,
    pixelRatio: pixelRatio,
  );
  return saveBytes(
    bytes,
    documentPdfFileName(document),
    directoryPath: directoryPath,
  );
}

/// Открывает системный диалог печати с документом.
Future<bool> printDocument({
  required List<GlobalKey> pageKeys,
  required OrderDocument document,
  double pixelRatio = 2.5,
}) async {
  final bytes = await buildDocumentPdf(
    pageKeys: pageKeys,
    title: document.title,
    pixelRatio: pixelRatio,
  );
  return printPdfBytes(bytes: bytes, jobName: document.title);
}
