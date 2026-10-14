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

/// Ширина страницы PDF: A3 по ширине.
const double _pageWidthMm = 420.0;

/// Высота страницы A3 — запасной вариант, если пропорции снимка неизвестны.
const double _pageHeightMm = 297.0;

const double _mmToPoints = 72 / 25.4;

/// Снимает лист с экрана и нарезает снимок на страницы-картинки (PNG).
///
/// Одна картинка — одна страница PDF: длинный лист режется последовательно,
/// по возможности по безопасным границам ([safeBreakFractions]), чтобы
/// не разорвать окно пополам. Пустых страниц не бывает.
Future<List<Uint8List>> renderSheetPages({
  required GlobalKey captureKey,
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

  final naturalHeightMm = _pageWidthMm * imageHeight / imageWidth;
  // Небольшой запас: почти-A3 лист не режем на две страницы из-за пары мм.
  final singlePage = naturalHeightMm <= _pageHeightMm * 1.06;
  final pointsPerImagePixel = (_pageWidthMm * _mmToPoints) / imageWidth;
  final pageHeightPixels = (_pageHeightMm * _mmToPoints) / pointsPerImagePixel;

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

  // Каждой странице — свой вырезанный кусок листа.
  final pages = <Uint8List>[];
  for (var page = 0; page * 2 + 1 < breaks.length; page++) {
    final start = breaks[page * 2];
    final end = breaks[page * 2 + 1];
    pages.add(
      await cropImageToPng(image, Rect.fromLTRB(0, start, imageWidth, end)),
    );
  }

  image.dispose();
  return pages;
}

/// Собирает один PDF из готовых страниц-картинок.
///
/// Ширина страницы — A3, высота — по пропорциям картинки, поэтому лист
/// не растягивается. Печатать несколько листов одним заданием можно так:
/// снять каждый лист через [renderSheetPages] и сложить страницы сюда.
Future<Uint8List> buildMultiSheetPdf(
  List<Uint8List> pageImages, {
  String title = 'Мягкие окна',
  String author = 'Мягкие окна',
  String creator = 'soft_window_drawer',
}) async {
  if (pageImages.isEmpty) {
    throw ArgumentError.value(pageImages, 'pageImages', 'Нет страниц для PDF');
  }

  final document = pw.Document(title: title, author: author, creator: creator);
  const pageWidthPoints = _pageWidthMm * _mmToPoints;

  for (final png in pageImages) {
    final image = pw.MemoryImage(png);
    final imageWidth = image.width;
    final imageHeight = image.height;
    // Пропорции неизвестны — берём стандартную страницу A3.
    final pageHeightPoints =
        imageWidth == null || imageWidth <= 0 ||
                imageHeight == null || imageHeight <= 0
            ? _pageHeightMm * _mmToPoints
            : pageWidthPoints * imageHeight / imageWidth;
    document.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
          pageWidthPoints,
          pageHeightPoints,
          marginAll: 0,
        ),
        build: (context) => pw.Image(
          image,
          width: pageWidthPoints,
          height: pageHeightPoints,
        ),
      ),
    );
  }

  return document.save();
}

/// Снимает лист чертежа и собирает PDF: A3 по ширине, длинный лист режется
/// на страницы A3 последовательно, без «половинок» посередине.
Future<Uint8List> buildSheetPdf({
  required GlobalKey captureKey,
  required WindowParams params,
  double pixelRatio = 3,
  List<double>? safeBreakFractions,
}) async {
  final pages = await renderSheetPages(
    captureKey: captureKey,
    pixelRatio: pixelRatio,
    safeBreakFractions: safeBreakFractions,
  );
  return buildMultiSheetPdf(pages, title: 'Чертёж ${params.drawingNumber}');
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

/// Печатает несколько листов одним заданием: страницы идут подряд,
/// на десктопе открывается системный диалог печати.
Future<bool> printSheetPages({
  required List<Uint8List> pageImages,
  required String jobName,
  String? title,
}) async {
  final bytes = await buildMultiSheetPdf(pageImages, title: title ?? jobName);
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
