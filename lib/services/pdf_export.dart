import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/window_params.dart';
import 'file_saver.dart';
import 'image_slice.dart';

/// Снимает лист чертежа и собирает PDF: A3 по ширине, длинный лист режется
/// на страницы A3 последовательно, без «половинок» посередине.
Future<Uint8List> buildSheetPdf({
  required GlobalKey captureKey,
  required WindowParams params,
  double pixelRatio = 3,
  List<double>? safeBreakFractions,
}) async {
  final context = captureKey.currentContext;
  if (context == null) {
    throw StateError('Лист чертежа ещё не построен');
  }
  final renderObject = context.findRenderObject();
  if (renderObject is! RenderRepaintBoundary) {
    throw StateError('Не найдена область листа чертежа');
  }

  // Ограничиваем разрешение: длинный подробный лист иначе даёт гигантский растр.
  final boundarySize = renderObject.size;
  final maxSide = math.max(boundarySize.width, boundarySize.height);
  final effectiveRatio = maxSide > 0
      ? math.min(pixelRatio, 4200 / maxSide).clamp(0.5, pixelRatio)
      : pixelRatio;

  final image = await renderObject.toImage(pixelRatio: effectiveRatio);
  final imageWidth = image.width.toDouble();
  final imageHeight = image.height.toDouble();

  const pageWidthMm = 420.0; // A3 по ширине
  const pageHeightMm = 297.0; // A3 по высоте
  const mmToPoints = 72 / 25.4;

  final document = pw.Document(
    title: 'Чертёж ${params.drawingNumber}',
    author: 'Мягкие окна',
    creator: 'soft_window_drawer',
  );

  final naturalHeightMm = pageWidthMm * imageHeight / imageWidth;
  // Небольшой запас: почти-A3 лист не режем на две страницы из-за пары мм.
  final singlePage = naturalHeightMm <= pageHeightMm * 1.06;
  final pointsPerImagePixel =
      (pageWidthMm * mmToPoints) / imageWidth;
  final pageHeightPixels = (pageHeightMm * mmToPoints) / pointsPerImagePixel;

  // Границы страниц: режем только там, где это безопасно (между окнами),
  // иначе — по высоте листа A3.
  final breaks = <double>[];
  if (singlePage) {
    breaks
      ..add(0)
      ..add(imageHeight);
  } else {
    final safeBreaks = <double>[
      for (final fraction in safeBreakFractions ?? const <double>[])
        if (fraction > 0 && fraction < 1) fraction * imageHeight,
    ]..sort();
    var start = 0.0;
    while (start < imageHeight - 1) {
      var end = start + pageHeightPixels;
      if (end >= imageHeight) {
        end = imageHeight;
      } else {
        final candidates = safeBreaks
            .where((position) => position > start + 1 && position <= end + 1)
            .toList();
        if (candidates.isNotEmpty) end = candidates.last;
      }
      breaks
        ..add(start)
        ..add(end);
      start = end;
    }
  }

  // Каждой странице — свой вырезанный кусок листа: пустых страниц не бывает.
  for (var page = 0; page * 2 + 1 < breaks.length; page++) {
    final start = breaks[page * 2];
    final end = breaks[page * 2 + 1];
    final slicePng = await cropImageToPng(
      image,
      Rect.fromLTRB(0, start, imageWidth, end),
    );
    final sliceHeightPoints = (end - start) * pointsPerImagePixel;
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidthMm * mmToPoints,
          sliceHeightPoints,
          marginAll: 0,
        ),
        build: (context) => pw.Image(
          pw.MemoryImage(slicePng),
          width: pageWidthMm * mmToPoints,
          height: sliceHeightPoints,
        ),
      ),
    );
  }

  image.dispose();
  return document.save();
}

/// Сохраняет лист чертежа в PDF: на десктопе — файлом, в браузере — скачиванием.
Future<SavedFile> exportSheetToPdf({
  required GlobalKey captureKey,
  required WindowParams params,
  double pixelRatio = 3,
  String namePrefix = 'Чертёж',
  List<double>? safeBreakFractions,
  String? directoryPath,
}) async {
  final bytes = await buildSheetPdf(
    captureKey: captureKey,
    params: params,
    pixelRatio: pixelRatio,
    safeBreakFractions: safeBreakFractions,
  );
  return saveBytes(
    bytes,
    exportFileName(params, prefix: namePrefix),
    directoryPath: directoryPath,
  );
}

/// Открывает системный диалог печати с текущим листом.
Future<bool> printSheet({
  required GlobalKey captureKey,
  required WindowParams params,
  required String jobName,
  List<double>? safeBreakFractions,
}) async {
  final bytes = await buildSheetPdf(
    captureKey: captureKey,
    params: params,
    safeBreakFractions: safeBreakFractions,
  );
  return Printing.layoutPdf(
    name: jobName,
    onLayout: (format) async => bytes,
  );
}

/// Имя файла: «Чертёж-МО-014-20260930-2115.pdf».
String exportFileName(
  WindowParams params, {
  DateTime? now,
  String prefix = 'Чертёж',
}) {
  final moment = now ?? DateTime.now();
  String two(int value) => value.toString().padLeft(2, '0');
  final stamp = '${moment.year}${two(moment.month)}${two(moment.day)}'
      '-${two(moment.hour)}${two(moment.minute)}';
  final number = params.drawingNumber
      .trim()
      .replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9-]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return '$prefix-${number.isEmpty ? 'без-номера' : number}-$stamp.pdf';
}
