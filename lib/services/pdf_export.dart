import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/window_params.dart';
import 'file_saver.dart';
import 'image_slice.dart';

/// Формат страницы PDF для снимка листа.
///
/// У PDF каждая страница может быть своего размера, поэтому в одном документе
/// спокойно соседствуют лист чертежа на A4 и табличная ведомость на A3.
enum SheetPageFormat {
  /// A4 в портретной ориентации (210 × 297 мм).
  ///
  /// Лист чертежа построен ровно в пропорциях A4, поэтому картинка ложится
  /// на страницу без масштабирования и обрезки — так и печатается.
  a4Portrait(widthMm: 210, heightMm: 297),

  /// Широкая страница A3 (420 мм), высота — по пропорциям снимка.
  ///
  /// Так печатаются табличные листы: расходам, смете, техкарте и раскрою
  /// нужна широкая страница.
  a3LandscapeAuto(widthMm: 420, heightMm: 297);

  const SheetPageFormat({required this.widthMm, required this.heightMm});

  /// Ширина страницы в миллиметрах.
  final double widthMm;

  /// Высота страницы в миллиметрах. У [a3LandscapeAuto] это запасное
  /// значение: обычно высота считается по пропорциям снимка.
  final double heightMm;

  /// Высота страницы подстраивается под пропорции снимка.
  bool get autoHeight => this == SheetPageFormat.a3LandscapeAuto;

  /// Ширина страницы в точках PDF.
  double get widthPoints => widthMm * _mmToPoints;

  /// Высота страницы в точках PDF.
  double get heightPoints => heightMm * _mmToPoints;
}

/// Высота страницы A3 — запасной вариант, если пропорции снимка неизвестны.
const double _pageHeightMm = 297.0;

const double _mmToPoints = 72 / 25.4;

/// Предел разрешения снимка листа по большей стороне в браузере.
///
/// В вебе растр стоит заметно дороже, чем на десктопе: кадр снимается и
/// кодируется в главном потоке, отдельного изолята для сборки PDF нет.
/// Поэтому и снимок, и страницы держим меньше — иначе вкладка «зависает».
const double kWebSheetImageMaxSide = 3000;

/// Предел разрешения снимка листа по большей стороне на десктопе.
const double kDesktopSheetImageMaxSide = 4200;

/// Предел разрешения снимка листа по большей стороне для текущей платформы.
double sheetImageMaxSide() =>
    kIsWeb ? kWebSheetImageMaxSide : kDesktopSheetImageMaxSide;

/// Разумный `pixelRatio` снимка по умолчанию.
///
/// В браузере 2, на десктопе 3: в вебе каждый лишний пиксель — это и память,
/// и время блокировки главного потока при кодировании PNG и сборке PDF.
double defaultSheetPixelRatio() => kIsWeb ? 2 : 3;

/// Итоговое разрешение снимка листа.
///
/// Не больше запрошенного [pixelRatio] и не больше [maxSide] пикселей по
/// большей стороне листа. Ниже 0.5 не опускаемся, иначе мелкий текст
/// на длинном листе станет нечитаемым.
double effectiveSheetPixelRatio(
  Size boundarySize, {
  required double pixelRatio,
  double? maxSide,
}) {
  final largest = math.max(boundarySize.width, boundarySize.height);
  if (largest <= 0 || pixelRatio <= 0) return pixelRatio;
  final cap = maxSide ?? sheetImageMaxSide();
  final floor = math.min(0.5, pixelRatio);
  return math.min(pixelRatio, cap / largest).clamp(floor, pixelRatio);
}

/// Снимает лист с экрана и отдаёт его страницы-картинки по одной.
///
/// Одна картинка — одна страница PDF: длинный лист режется последовательно,
/// по возможности по безопасным границам ([safeBreakFractions]), чтобы
/// не разорвать окно пополам. Пустых страниц не бывает.
///
/// [pageFormat] задаёт размер страницы и, значит, шаг нарезки: для чертежа это
/// A4 в портретной ориентации, для табличных листов — широкая страница.
///
/// Главное отличие от [renderSheetPages]: список страниц нигде не копится.
/// Каждая готовая страница сразу уходит в [onPage], поэтому одновременно в
/// памяти живут только снимок листа (самая крупная картинка) и одна
/// страница. Снимок листа освобождается в `finally` — в том числе при ошибке.
///
/// [onPage] можно использовать, чтобы отдать управление интерфейсу: она
/// ожидается перед съёмкой следующей страницы. Возвращает число страниц.
Future<int> renderSheetPagesEach({
  required GlobalKey captureKey,
  required FutureOr<void> Function(Uint8List png, int pageIndex) onPage,
  double? pixelRatio,
  List<double>? safeBreakFractions,
  SheetPageFormat pageFormat = SheetPageFormat.a3LandscapeAuto,
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
  final ratio = pixelRatio ?? defaultSheetPixelRatio();
  final boundarySize = renderObject.size;
  final effectiveRatio =
      effectiveSheetPixelRatio(boundarySize, pixelRatio: ratio);

  // Единственная большая картинка в памяти: снимок всего листа.
  final image = await renderObject.toImage(pixelRatio: effectiveRatio);
  try {
    final imageWidth = image.width.toDouble();
    final imageHeight = image.height.toDouble();

    final pageWidthMm = pageFormat.widthMm;
    final pageHeightMm = pageFormat.heightMm;
    final naturalHeightMm = pageWidthMm * imageHeight / imageWidth;
    // Небольшой запас: почти-страничный лист не режем на две из-за пары мм.
    final singlePage = naturalHeightMm <= pageHeightMm * 1.06;
    final pointsPerImagePixel = (pageWidthMm * _mmToPoints) / imageWidth;
    final pageHeightPixels =
        (pageHeightMm * _mmToPoints) / pointsPerImagePixel;
    // Допуск поиска безопасной границы: погрешность округления и накопленный
    // сдвиг на длинном листе. Меньше процента страницы — на вид не влияет.
    final breakTolerance = math.max(2.0, imageHeight * 0.0008);

    // Границы страниц: режем только там, где это безопасно (по границам
    // страниц листа), иначе — по высоте страницы.
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
              .where((position) =>
                  position > start + 1 &&
                  position <= end + breakTolerance)
              .toList();
          if (candidates.isNotEmpty) end = candidates.last;
        }
        breaks
          ..add(start)
          ..add(end);
        start = end;
      }
    }

    // Каждой странице — свой вырезанный кусок листа; он живёт до конца
    // итерации и отдаётся наружу сразу.
    var pages = 0;
    for (var page = 0; page * 2 + 1 < breaks.length; page++) {
      final start = breaks[page * 2];
      final end = breaks[page * 2 + 1];
      final png = await cropImageToPng(
        image,
        Rect.fromLTRB(0, start, imageWidth, end),
      );
      pages++;
      await onPage(png, page);
    }
    return pages;
  } finally {
    // Снимок листа больше не нужен — отпускаем его при любом исходе.
    image.dispose();
  }
}

/// Снимает лист с экрана и нарезает снимок на страницы-картинки (PNG).
///
/// Собирает все страницы в список, поэтому подходит только для небольших
/// листов. Для печати в браузере и для длинных листов используйте
/// [renderSheetPagesEach] или [SheetPdfBuilder]: там страницы не копятся.
Future<List<Uint8List>> renderSheetPages({
  required GlobalKey captureKey,
  double? pixelRatio,
  List<double>? safeBreakFractions,
  SheetPageFormat pageFormat = SheetPageFormat.a3LandscapeAuto,
}) async {
  final pages = <Uint8List>[];
  await renderSheetPagesEach(
    captureKey: captureKey,
    pixelRatio: pixelRatio,
    safeBreakFractions: safeBreakFractions,
    pageFormat: pageFormat,
    onPage: (png, index) => pages.add(png),
  );
  return pages;
}

/// Собирает PDF по одной странице: документ создаётся один раз, и каждая
/// снятая страница сразу уходит в него.
///
/// Так вместо «списка всех картинок + второй копии при сборке» в памяти
/// живёт один документ. [addPageImage] страницу не копирует, поэтому после
/// возврата из него собственную ссылку на PNG можно отпускать.
///
/// В браузере сборка идёт в главном потоке (изолятов в вебе нет), поэтому
/// [save] и [print] внутри `pw.Document.save()` периодически отдают
/// управление событийному циклу — вкладка не замирает на всё время сборки.
class SheetPdfBuilder {
  SheetPdfBuilder({
    String title = 'Мягкие окна',
    String author = 'Мягкие окна',
    String creator = 'soft_window_drawer',
  }) : _document =
            pw.Document(title: title, author: author, creator: creator);

  pw.Document? _document;

  int _pageCount = 0;

  /// Сколько страниц уже в документе.
  int get pageCount => _pageCount;

  /// Ни одной страницы — печатать нечего.
  bool get isEmpty => _pageCount == 0;

  /// Документ уже собран: добавлять страницы поздно.
  bool get isClosed => _document == null;

  pw.Document get _open {
    final document = _document;
    if (document == null) {
      throw StateError('PDF уже собран: документ закрыт, страницы не добавить');
    }
    return document;
  }

  void _ensureOpen() {
    if (_document == null) {
      throw StateError('PDF уже собран: документ закрыт, страницы не добавить');
    }
  }

  /// Добавляет в PDF готовую страницу-картинку.
  ///
  /// [format] задаёт размер страницы. Для [SheetPageFormat.a3LandscapeAuto]
  /// пропорции берутся из картинки, а ширина страницы — A3, поэтому лист не
  /// растягивается. Для [SheetPageFormat.a4Portrait] страница всегда A4
  /// (210 × 297 мм), а картинка вписывается в неё без искажений: лист чертежа
  /// построен ровно в пропорциях A4 и ложится на страницу один в один.
  void addPageImage(
    Uint8List png, {
    SheetPageFormat format = SheetPageFormat.a3LandscapeAuto,
  }) {
    final document = _open;
    final image = pw.MemoryImage(png);
    final imageWidth = image.width;
    final imageHeight = image.height;
    final hasSize = imageWidth != null &&
        imageWidth > 0 &&
        imageHeight != null &&
        imageHeight > 0;
    final pageWidthPoints = format.widthPoints;
    final pageHeightPoints = format.heightPoints;

    if (format.autoHeight) {
      // Табличный лист: высота страницы — по пропорциям снимка.
      final heightPoints = hasSize
          ? pageWidthPoints * imageHeight! / imageWidth!
          : _pageHeightMm * _mmToPoints;
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            pageWidthPoints,
            heightPoints,
            marginAll: 0,
          ),
          build: (context) => pw.Image(
            image,
            width: pageWidthPoints,
            height: heightPoints,
          ),
        ),
      );
    } else {
      // A4: страница фиксированная, картинку вписываем целиком и по центру.
      var imageWidthPoints = pageWidthPoints;
      var imageHeightPoints = pageHeightPoints;
      if (hasSize) {
        final scale = math.min(
          pageWidthPoints / imageWidth!,
          pageHeightPoints / imageHeight!,
        );
        imageWidthPoints = imageWidth * scale;
        imageHeightPoints = imageHeight * scale;
      }
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(
            pageWidthPoints,
            pageHeightPoints,
            marginAll: 0,
          ),
          build: (context) => pw.Center(
            child: pw.Image(
              image,
              width: imageWidthPoints,
              height: imageHeightPoints,
            ),
          ),
        ),
      );
    }
    _pageCount++;
  }

  /// Снимает лист [captureKey] и добавляет его страницы в PDF по одной.
  ///
  /// Возвращает число добавленных страниц. [onPageAdded] вызывается после
  /// каждой страницы и может отдать управление интерфейсу, чтобы окно
  /// прогресса успело перерисоваться. [pageFormat] задаёт формат страниц:
  /// чертёж печатается на A4, табличные листы — на широкой странице.
  Future<int> addSheet({
    required GlobalKey captureKey,
    double? pixelRatio,
    List<double>? safeBreakFractions,
    SheetPageFormat pageFormat = SheetPageFormat.a3LandscapeAuto,
    FutureOr<void> Function(int pagesInSheet)? onPageAdded,
  }) async {
    _ensureOpen();
    final before = _pageCount;
    await renderSheetPagesEach(
      captureKey: captureKey,
      pixelRatio: pixelRatio,
      safeBreakFractions: safeBreakFractions,
      pageFormat: pageFormat,
      onPage: (png, pageIndex) async {
        // Страница уходит в документ и здесь же отпускается: список
        // готовых картинок снаружи не ведём.
        addPageImage(png, format: pageFormat);
        if (onPageAdded != null) await onPageAdded(_pageCount - before);
      },
    );
    return _pageCount - before;
  }

  /// Собирает документ в байты и закрывает его.
  ///
  /// [balanceEventLoop] — отдавать ли управление во время сборки. По
  /// умолчанию включено в браузере: там `save()` целиком идёт в главном
  /// потоке (декодирование PNG и сжатие страниц), и без этого вкладка
  /// замирает. После сборки документ и все картинки в нём отпускаются,
  /// остаются только готовые байты.
  Future<Uint8List> save({bool? balanceEventLoop}) async {
    final document = _open;
    _document = null;
    return document.save(
      enableEventLoopBalancing: balanceEventLoop ?? kIsWeb,
    );
  }

  /// Собирает PDF и открывает системный диалог печати.
  ///
  /// В браузере [Printing.layoutPdf] открывает диалог печати самой страницы:
  /// если сборка PDF перед этим замораживает вкладку, ожидание особенно
  /// заметно, поэтому и снимки, и сборка идут с отдачей управления.
  Future<bool> print({
    required String jobName,
    bool? balanceEventLoop,
  }) async {
    final bytes = await save(balanceEventLoop: balanceEventLoop);
    return printPdfBytes(bytes: bytes, jobName: jobName);
  }
}

/// Собирает один PDF из готовых страниц-картинок.
///
/// Оставлено для небольших заданий и для кода, которому нужен именно список.
/// Печатать так несколько длинных листов в браузере не стоит: список держит
/// в памяти все страницы сразу. Для инкрементальной сборки — [SheetPdfBuilder].
Future<Uint8List> buildMultiSheetPdf(
  List<Uint8List> pageImages, {
  String title = 'Мягкие окна',
  String author = 'Мягкие окна',
  String creator = 'soft_window_drawer',
  SheetPageFormat format = SheetPageFormat.a3LandscapeAuto,
}) async {
  if (pageImages.isEmpty) {
    throw ArgumentError.value(pageImages, 'pageImages', 'Нет страниц для PDF');
  }

  final builder = SheetPdfBuilder(
    title: title,
    author: author,
    creator: creator,
  );
  for (final png in pageImages) {
    builder.addPageImage(png, format: format);
  }
  return builder.save();
}

/// Отдаёт управление браузеру между страницами одного листа.
///
/// В вебе кодирование PNG и сборка PDF идут в главном потоке: короткая пауза
/// даёт браузеру перерисовать окно. На десктопе ждать нечего — сборка уходит
/// в отдельный изолят, а лишние кадры только замедляют экспорт, поэтому
/// функция сразу возвращает управление (и не ждёт кадр в тестах).
Future<void> _yieldToBrowser() async {
  if (!kIsWeb) return;
  await WidgetsBinding.instance.endOfFrame;
  await Future<void>.delayed(const Duration(milliseconds: 4));
}

/// Снимает лист чертежа и собирает PDF: A3 по ширине, длинный лист режется
/// на страницы A3 последовательно, без «половинок» посередине.
Future<Uint8List> buildSheetPdf({
  required GlobalKey captureKey,
  required WindowParams params,
  double? pixelRatio,
  List<double>? safeBreakFractions,
}) async {
  final builder = SheetPdfBuilder(title: 'Чертёж ${params.drawingNumber}');
  await builder.addSheet(
    captureKey: captureKey,
    pixelRatio: pixelRatio,
    safeBreakFractions: safeBreakFractions,
    // Страницы добавляются по одной, между ними отдаём управление.
    onPageAdded: (pagesInSheet) => _yieldToBrowser(),
  );
  return builder.save();
}

/// Сохраняет лист чертежа в PDF: на десктопе — файлом, в браузере — скачиванием.
Future<SavedFile> exportSheetToPdf({
  required GlobalKey captureKey,
  required WindowParams params,
  double? pixelRatio,
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

/// Открывает системный диалог печати с готовым PDF.
///
/// В браузере это диалог печати самой страницы: вкладка на это время занята,
/// поэтому PDF собирается заранее, а не внутри диалога.
Future<bool> printPdfBytes({
  required Uint8List bytes,
  required String jobName,
}) {
  return Printing.layoutPdf(
    name: jobName,
    onLayout: (format) async => bytes,
  );
}

/// Открывает системный диалог печати с текущим листом.
Future<bool> printSheet({
  required GlobalKey captureKey,
  required WindowParams params,
  required String jobName,
  double? pixelRatio,
  List<double>? safeBreakFractions,
}) async {
  final builder = SheetPdfBuilder(title: 'Чертёж ${params.drawingNumber}');
  await builder.addSheet(
    captureKey: captureKey,
    pixelRatio: pixelRatio,
    safeBreakFractions: safeBreakFractions,
  );
  return builder.print(jobName: jobName);
}

/// Печатает несколько листов одним заданием: страницы идут подряд,
/// на десктопе открывается системный диалог печати.
Future<bool> printSheetPages({
  required List<Uint8List> pageImages,
  required String jobName,
  String? title,
}) async {
  final bytes = await buildMultiSheetPdf(pageImages, title: title ?? jobName);
  return printPdfBytes(bytes: bytes, jobName: jobName);
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
