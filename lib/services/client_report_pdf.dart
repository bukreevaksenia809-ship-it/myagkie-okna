import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Offset, Rect, Size;

import 'package:flutter/services.dart' show FontLoader, rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/document.dart';
import '../models/fastener_spans.dart';
import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';
import '../services/company_branding.dart';
import '../services/costs_summary.dart';
import '../services/estimate.dart';
import '../widgets/window_painter.dart';
import 'file_saver.dart';

/// Отчёт для клиента: обложка с заказом и комплектацией + по странице на
/// каждое окно (чертёж и раскрой материалов).
///
/// Структура повторяет привычный клиентский PDF: альбомный A4, слева —
/// реквизиты заказа и чертёж, справа — комплектация/раскрой/фурнитура.
/// Печатные (производственные) листы остаются отдельными вкладками.
class ClientReportBuilder {
  ClientReportBuilder({
    required this.project,
    required this.prices,
    required this.company,
    this.info = const ClientReportInfo(),
    this.fontRegular,
    this.fontBold,
  });

  final OrderProject project;
  final PriceList prices;
  final CompanyBrandingState company;

  /// Данные заказчика (ФИО, телефон, адрес, комментарий, исполнители).
  final ClientReportInfo info;

  final pw.Font? fontRegular;
  final pw.Font? fontBold;

  late final pw.Font _font;
  late final pw.Font _bold;
  late final pw.Font _serif;
  late final pw.Font _serifBold;

  static bool _drawingFontLoaded = false;

  static const PdfColor ink = PdfColor.fromInt(0xFF1B1F27);
  static const PdfColor dim = PdfColor.fromInt(0xFF5B6B80);
  static const PdfColor accent = PdfColor.fromInt(0xFF0B7BC4);
  static const PdfColor bandBrown = PdfColor.fromInt(0xFF6B4A3A);
  static const PdfColor filmBlue = PdfColor.fromInt(0xFFDCEBFA);
  static const PdfColor hardware = PdfColor.fromInt(0xFF4C5666);
  static const PdfColor metal = PdfColor.fromInt(0xFF5A6675);
  static const PdfColor bandBrownDark = PdfColor.fromInt(0xFF4A3227);
  static const PdfColor filmGrey = PdfColor.fromInt(0xFFE6E9ED);
  static const PdfColor cardBg = PdfColor.fromInt(0xFFF5F8FC);
  static const PdfColor cardBorder = PdfColor.fromInt(0xFFD7E0EC);
  static const PdfColor accentLight = PdfColor.fromInt(0xFFE8F1FC);

  // Премиальная палитра обложки: тёплый фон, графит и золото.
  static const PdfColor ivory = PdfColor.fromInt(0xFFFAF7F1);
  static const PdfColor charcoal = PdfColor.fromInt(0xFF121A24);
  static const PdfColor gold = PdfColor.fromInt(0xFFB9975B);
  static const PdfColor warmDim = PdfColor.fromInt(0xFF8B8378);
  static const PdfColor warmLine = PdfColor.fromInt(0xFFE3D9C9);

  /// Собирает PDF отчёта.
  /// Шрифт для производственного чертежа: регистрируем PT Sans, чтобы
  /// подписи были одинаковыми в приложении и в тестах (не «квадратики»).
  Future<void> _ensureDrawingFont() async {
    if (_drawingFontLoaded) return;
    final loader = FontLoader('ClientReportDrawing')
      ..addFont(rootBundle.load('assets/fonts/PTSans-Regular.ttf'));
    await loader.load();
    _drawingFontLoaded = true;
  }

  Future<Uint8List> build() async {
    await _ensureDrawingFont();
    final regular =
        fontRegular ?? pw.Font.ttf(await rootBundle.load('assets/fonts/PTSans-Regular.ttf'));
    final bold =
        fontBold ?? pw.Font.ttf(await rootBundle.load('assets/fonts/PTSans-Bold.ttf'));
    pw.Font serif = regular;
    pw.Font serifBold = bold;
    try {
      serif = pw.Font.ttf(await rootBundle.load('assets/fonts/PTSerif-Regular.ttf'));
      serifBold =
          pw.Font.ttf(await rootBundle.load('assets/fonts/PTSerif-Bold.ttf'));
    } catch (_) {
      // Если серифного шрифта нет — заголовки останутся PT Sans.
    }
    _font = regular;
    _bold = bold;
    _serif = serif;
    _serifBold = serifBold;
    final theme = pw.ThemeData.withFont(base: regular, bold: bold);
    final document = pw.Document(
      title: 'Отчёт клиенту $_orderNumber',
      author: company.details.displayName,
    );

    final format = PdfPageFormat.a4.landscape;
    document.addPage(
      pw.Page(
        pageFormat: format,
        theme: theme,
        build: (context) => _coverPage(),
      ),
    );

    final windows = _reportProject.windows;
    // Чертёж на клиентском листе — тот же самый, что программа строит для
    // производства: рендерим производственный painter в картинку и вставляем.
    final drawings = <Uint8List?>[];
    for (final window in windows) {
      drawings.add(await _renderProductionDrawing(WindowSpec.of(window)));
    }
    for (var index = 0; index < windows.length; index++) {
      final spec = WindowSpec.of(windows[index]);
      document.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a4,
          theme: theme,
          build: (context) => _windowPage(
            spec,
            index,
            windows.length,
            context,
            drawings[index],
          ),
        ),
      );
    }
    return document.save();
  }

  /// Окна отчёта — ровно те, что на главном листе чертежа: в режиме
  /// «Все окна» весь заказ, в режиме одного окна — выбранное окно.
  OrderProject get _reportProject {
    if (project.sheetMode == SheetMode.grid && project.isMultiWindow) {
      return project;
    }
    return project.copyWith(windows: [project.selected], selectedIndex: 0);
  }

  String get _orderNumber {
    final number = project.selected.drawingNumber.trim();
    return number.isEmpty ? 'б/н' : number;
  }

  String get _clientName {
    if (info.name.trim().isNotEmpty) return info.name.trim();
    final customer = project.selected.customer.trim();
    if (customer.isEmpty) return '—';
    // Телефон в строке заказчика убираем из ФИО.
    return customer
        .replaceAll(RegExp(r'[+\d][\d\s()\-]{6,}'), '')
        .trim()
        .replaceAll(RegExp(r'[,;]+$'), '');
  }

  String get _clientPhone {
    if (info.phone.trim().isNotEmpty) return info.phone.trim();
    final customer = project.selected.customer;
    final match = RegExp(r'[+\d][\d\s()\-]{6,}').firstMatch(customer);
    return match?.group(0)?.trim() ?? '—';
  }

  String get _screenColor {
    for (final window in project.windows) {
      if (window.isScreen && window.screenColor.trim().isNotEmpty) {
        return window.screenColor.trim();
      }
    }
    return '';
  }

  String _materialLabel(FilmMaterial material) {
    if (material == FilmMaterial.screen && _screenColor.isNotEmpty) {
      return 'Скрин, цвет: $_screenColor';
    }
    return material.label;
  }

  String get _clientComment => info.comment.trim().isNotEmpty
      ? info.comment.trim()
      : project.selected.projectName;

  String _windowsWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'окно';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return 'окна';
    }
    return 'окон';
  }

  String get _date {
    final now = DateTime.now();
    return '${now.day.toString().padLeft(2, '0')}.'
        '${now.month.toString().padLeft(2, '0')}.${now.year}';
  }

  // ------------------------------------------------------------- обложка

  pw.Widget _coverPage() {
    final report = _reportProject;
    final summary = CostsSummary(report);
    final estimate = Estimate.of(report, prices);
    final details = company.details;

    return pw.Stack(
      children: [
        pw.Positioned.fill(
          child: pw.Container(color: ivory),
        ),
        // Тёмная «книжная» панель справа.
        pw.Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: pw.SizedBox(
            width: 300,
            child: pw.Container(color: charcoal),
          ),
        ),
        pw.Positioned.fill(
          child: pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(46, 30, 350, 22),
            child: _premiumLeftColumn(summary, details),
          ),
        ),
        pw.Positioned(
          top: 0,
          bottom: 0,
          right: 0,
          child: pw.SizedBox(
            width: 300,
            child: pw.Padding(
              padding: const pw.EdgeInsets.fromLTRB(24, 34, 24, 22),
              child: _premiumPackage(summary, estimate),
            ),
          ),
        ),
      ],
    );
  }

  pw.Widget _premiumLeftColumn(CostsSummary summary, CompanyDetails details) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        _premiumHeader(details),
        pw.SizedBox(height: 18),
        pw.Container(height: 0.9, color: gold),
        pw.SizedBox(height: 26),
        // Заголовок заказа.
        pw.Text(
          'КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ',
          style: pw.TextStyle(
            font: _font,
            fontSize: 8.5,
            letterSpacing: 3.2,
            color: gold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              'Заказ ',
              style: pw.TextStyle(
                font: _serif,
                fontSize: 30,
                color: ink,
              ),
            ),
            pw.Text(
              '№ $_orderNumber',
              style: pw.TextStyle(
                font: _serifBold,
                fontSize: 30,
                color: ink,
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 6),
        pw.Row(
          children: [
            pw.Text('от $_date', style: _s(9.5, color: warmDim)),
            pw.SizedBox(width: 14),
            pw.Container(width: 22, height: 0.8, color: warmLine),
            pw.SizedBox(width: 14),
            pw.Text(
              '${_reportProject.windowCount} '
              '${_windowsWord(_reportProject.windowCount)} в отчёте',
              style: _s(9.5, color: warmDim),
            ),
          ],
        ),
        pw.SizedBox(height: 24),
        _softDivider(),
        pw.SizedBox(height: 16),
        _label('ЗАКАЗЧИК'),
        pw.SizedBox(height: 8),
        pw.Text(
          _clientName.isEmpty ? '—' : _clientName,
          style: pw.TextStyle(font: _serifBold, fontSize: 19, color: ink),
        ),
        pw.SizedBox(height: 6),
        _contactLine(_clientPhone),
        _contactLine(
          info.address.trim().isEmpty
              ? 'Адрес доставки не указан'
              : info.address.trim(),
        ),
        if (_clientComment.isNotEmpty)
          _contactLine(_clientComment),
        pw.SizedBox(height: 14),
        _softDivider(),
        pw.SizedBox(height: 12),
        pw.Row(
          children: [
            _executor('МЕНЕДЖЕР', info.manager.trim().isEmpty
                ? (details.signer.trim().isEmpty ? '—' : details.signer)
                : info.manager),
            _executor('ЗАМЕРЩИК', info.surveyor),
            _executor('МОНТАЖНИК', info.installer),
          ],
        ),
        pw.Spacer(),
        pw.Container(height: 0.7, color: warmLine),
        pw.SizedBox(height: 8),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  details.displayName,
                  style: _s(9.5, bold: true, color: ink),
                ),
                if (details.inn.trim().isNotEmpty)
                  pw.Text(
                    'ИНН ${details.inn.trim()}'
                    '${details.ogrn.trim().isEmpty ? '' : ' · ОГРН ${details.ogrn.trim()}'}',
                    style: _s(8.5, color: warmDim),
                  ),
                if (details.address.trim().isNotEmpty)
                  pw.Text(
                    details.address.trim(),
                    style: _s(8.5, color: warmDim),
                  ),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              'Площадь изделий  ${_m2(summary.productAreaM2)} м²',
              style: _s(9, color: warmDim),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _premiumHeader(CompanyDetails details) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        if (company.logo != null) ...[
          pw.Container(
            height: 54,
            constraints: const pw.BoxConstraints(maxWidth: 140),
            child: pw.Image(pw.MemoryImage(company.logo!), fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 16),
        ],
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                details.displayName,
                maxLines: 2,
                style: pw.TextStyle(font: _serifBold, fontSize: 19, color: ink),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'мягкие окна · производство и монтаж',
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  letterSpacing: 1.4,
                  color: warmDim,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              details.phone.trim().isEmpty ? '—' : details.phone.trim(),
              style: pw.TextStyle(font: _serifBold, fontSize: 15, color: ink),
            ),
            pw.SizedBox(height: 3),
            pw.Text(
              'звонок по России бесплатный',
              style: _s(7.5, color: warmDim),
            ),
          ],
        ),
      ],
    );
  }

  pw.Widget _premiumPackage(CostsSummary summary, Estimate estimate) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Text(
          'КОМПЛЕКТАЦИЯ',
          style: pw.TextStyle(
            font: _font,
            fontSize: 8.5,
            letterSpacing: 3,
            color: gold,
          ),
        ),
        pw.SizedBox(height: 10),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              _m2(summary.productAreaM2),
              style: pw.TextStyle(
                font: _serifBold,
                fontSize: 34,
                color: PdfColors.white,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 6, left: 6),
              child: pw.Text(
                'м²',
                style: pw.TextStyle(font: _font, fontSize: 11, color: gold),
              ),
            ),
            pw.Spacer(),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 8),
              child: pw.Text(
                'общая площадь',
                style: pw.TextStyle(
                  font: _font,
                  fontSize: 7.5,
                  letterSpacing: 1,
                  color: PdfColor.fromInt(0xFF8E9AAA),
                ),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 12),
        _darkDivider(),
        pw.SizedBox(height: 12),
        _darkLabel('МАТЕРИАЛЫ'),
        for (final entry in summary.filmAreaByMaterialWithShrinkage.entries)
          if (entry.value > 0)
            _darkRow(_materialLabel(entry.key), '${_m2(entry.value)} м²'),
        if (_screenColor.isNotEmpty)
          _darkRow('Цвет скрина', _screenColor),
        pw.SizedBox(height: 10),
        _darkLabel('ФУРНИТУРА'),
        for (final entry in summary.eyeletsByType.entries)
          if (entry.value > 0)
            _darkRow(entry.key.displayLabel, '${entry.value} шт.'),
        for (final entry in summary.fastenerCount.entries)
          if (entry.value > 0)
            _darkRow(entry.key.itemTitle, '${entry.value} шт.'),
        if (summary.zipperBandLengthMm > 0)
          _darkRow('Молния', '${_meters(summary.zipperBandLengthMm)} пог.м'),
        if (summary.screenHemLengthMm > 0)
          _darkRow(
            'Подворот скрина',
            '${_meters(summary.screenHemLengthMm)} пог.м',
          ),
        pw.Spacer(),
        _darkDivider(),
        pw.SizedBox(height: 12),
        pw.Text(
          'ИТОГО ПО ЗАКАЗУ',
          style: pw.TextStyle(
            font: _font,
            fontSize: 8,
            letterSpacing: 2.4,
            color: gold,
          ),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            pw.Text(
              _rub(estimate.total).replaceAll('₽', '').trim(),
              style: pw.TextStyle(
                font: _serifBold,
                fontSize: 27,
                color: PdfColors.white,
              ),
            ),
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 4, left: 5),
              child: pw.Text(
                '₽',
                style: pw.TextStyle(font: _font, fontSize: 14, color: gold),
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 8),
        pw.Text(
          'Стоимость актуальна в течение 3-х календарных дней '
          'с даты расчёта.',
          style: pw.TextStyle(
            font: _font,
            fontSize: 7.5,
            height: 1.35,
            color: const PdfColor.fromInt(0xFF8E9AAA),
          ),
        ),
      ],
    );
  }

  pw.TextStyle _s(
    double size, {
    bool bold = false,
    PdfColor? color,
  }) =>
      pw.TextStyle(
        font: bold ? _bold : _font,
        fontSize: size,
        color: color,
      );

  pw.Widget _darkLabel(String text) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 6),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font: _font,
        fontSize: 7.5,
        letterSpacing: 2,
        color: gold,
      ),
    ),
  );

  pw.Widget _darkRow(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(bottom: 5),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: _font,
              fontSize: 9,
              color: const PdfColor.fromInt(0xFFD5DBE3),
            ),
          ),
        ),
        pw.SizedBox(width: 8),
        pw.Text(
          value,
          style: pw.TextStyle(
            font: _font,
            fontSize: 9,
            color: PdfColors.white,
          ),
        ),
      ],
    ),
  );

  pw.Widget _darkDivider() => pw.Container(
    height: 0.5,
    color: const PdfColor.fromInt(0x33FFFFFF),
  );

  pw.Widget _softDivider() => pw.Container(height: 0.6, color: warmLine);

  pw.Widget _label(String text) => pw.Text(
    text,
    style: pw.TextStyle(
      font: _font,
      fontSize: 7.5,
      letterSpacing: 2.6,
      color: gold,
    ),
  );

  pw.Widget _executor(String label, String value) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            label,
            style: pw.TextStyle(
              font: _font,
              fontSize: 6.8,
              letterSpacing: 1.8,
              color: warmDim,
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            value.trim().isEmpty ? '—' : value.trim(),
            style: pw.TextStyle(font: _font, fontSize: 9.5, color: ink),
          ),
        ],
      ),
    );
  }

  /// Строка контакта с маленьким золотым маркером (без иконок: только
  /// типографский акцент — так выглядит дороже).
  pw.Widget _contactLine(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: 14,
            height: 0.7,
            margin: const pw.EdgeInsets.only(top: 6),
            color: gold,
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              text,
              style: pw.TextStyle(
                font: _font,
                fontSize: 9.5,
                height: 1.3,
                color: const PdfColor.fromInt(0xFF4B5360),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --------------------------------------------------------- лист окна

  /// Рисует производственный чертёж тем же painter'ом, что и вкладка
  /// «Чертёж», и отдаёт PNG для вставки в отчёт.
  Future<Uint8List?> _renderProductionDrawing(WindowSpec spec) async {
    try {
      const size = Size(1240, 1754);
      final layout = DrawingLayout(
        size: size,
        geometry: spec.geometry,
        fitExactly: true,
      );
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      final painter = WindowDrawingPainter(
        params: spec.params,
        layout: layout,
        layers: spec.layers,
        options: const DrawingOptions(),
        labelFontFamily: 'ClientReportDrawing',
        showScaleBar: false,
      );
      painter.paint(canvas, size);
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        size.width.toInt(),
        size.height.toInt(),
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      picture.dispose();
      return data?.buffer.asUint8List();
    } catch (_) {
      return null;
    }
  }

  /// Страница окна: производственный чертёж крупно + расход материалов,
  /// параметры и фурнитура на этом же листе.
  pw.Widget _windowPage(
    WindowSpec spec,
    int index,
    int total,
    pw.Context context,
    Uint8List? productionDrawing,
  ) {
    final pdfFont = _font.getFont(context);
    final drawing = productionDrawing != null
        ? pw.FittedBox(
            fit: pw.BoxFit.contain,
            child: pw.Image(pw.MemoryImage(productionDrawing)),
          )
        : pw.CustomPaint(
            size: const PdfPoint(500, 600),
            painter: (canvas, size) => _paintWindow(canvas, size, spec, pdfFont),
          );
    final page = index + 2;
    return pw.Container(
      color: ivory,
      child: pw.Padding(
        padding: const pw.EdgeInsets.fromLTRB(26, 18, 26, 12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'ЧЕРТЁЖ ДЛЯ КЛИЕНТА',
                      style: pw.TextStyle(
                        font: _font,
                        fontSize: 7,
                        letterSpacing: 2.8,
                        color: gold,
                      ),
                    ),
                    pw.SizedBox(height: 4),
                    pw.Text(
                      'Окно №${index + 1} из $total',
                      style: pw.TextStyle(
                        font: _serifBold,
                        fontSize: 21,
                        color: ink,
                      ),
                    ),
                    pw.SizedBox(height: 1),
                    pw.Text(
                      'Заказ $_orderNumber'
                      '${_clientName.isEmpty ? '' : ' · $_clientName'}',
                      style: pw.TextStyle(
                        font: _font,
                        fontSize: 9,
                        color: warmDim,
                      ),
                    ),
                  ],
                ),
                pw.Spacer(),
                pw.Text(
                  '${_cm(spec.geometry.spanX)} × '
                  '${_cm(spec.geometry.overallHeight)} см',
                  style: pw.TextStyle(
                    font: _serif,
                    fontSize: 14,
                    color: ink,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 7),
            pw.Container(height: 0.9, color: gold),
            pw.SizedBox(height: 6),
            pw.Expanded(
              child: pw.Container(
                padding: const pw.EdgeInsets.all(5),
                decoration: pw.BoxDecoration(
                  color: PdfColors.white,
                  border: pw.Border.all(color: warmLine, width: 0.8),
                  borderRadius: pw.BorderRadius.circular(4),
                ),
                child: pw.Center(child: drawing),
              ),
            ),
            pw.SizedBox(height: 7),
            pw.SizedBox(
              height: 174,
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.stretch,
                children: [
                  pw.Expanded(flex: 3, child: _paramsCard(spec)),
                  pw.SizedBox(width: 7),
                  pw.Expanded(flex: 4, child: _cutCard(spec)),
                  pw.SizedBox(width: 7),
                  pw.Expanded(flex: 3, child: _hardwareCard(spec)),
                ],
              ),
            ),
            pw.SizedBox(height: 5),
            pw.Row(
              children: [
                pw.Text(
                  'Чертёж с производства · '
                  '${_materialLabel(spec.params.material)}',
                  style: pw.TextStyle(
                    font: _font,
                    fontSize: 7,
                    color: warmDim,
                  ),
                ),
                pw.Spacer(),
                pw.Text(
                  '$page / ${total + 1}',
                  style: pw.TextStyle(
                    font: _font,
                    fontSize: 7,
                    color: warmDim,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  pw.Widget _paramsCard(WindowSpec spec) {
    final geometry = spec.geometry;
    final edge = spec.layers.finishedWidths
        .where((width) => width > 0)
        .toList();
    final edgeText = edge.isEmpty
        ? 'подворот'
        : '${_trim(edge.reduce((a, b) => a > b ? a : b) / 10)} см';
    final step = spec.params.eyeletStep;
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 10, 12, 9),
      decoration: pw.BoxDecoration(
        color: charcoal,
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'ПАРАМЕТРЫ',
            style: pw.TextStyle(
              font: _font,
              fontSize: 7,
              letterSpacing: 2.2,
              color: gold,
            ),
          ),
          pw.SizedBox(height: 6),
          _darkSpec(
            'Размер',
            '${_cm(geometry.spanX)} × ${_cm(geometry.overallHeight)}',
          ),
          _darkSpec('Площадь', '${_m2(spec.productAreaM2)} м²'),
          _darkSpec('Материал', _materialLabel(spec.params.material)),
          if (spec.params.isScreen && spec.params.screenColor.trim().isNotEmpty)
            _darkSpec('Цвет', spec.params.screenColor.trim()),
          _darkSpec('Окантовка', edgeText),
          _darkSpec('Крепёж', spec.params.fastenerType == FastenerType.eyeletsOnly
              ? 'люверсы'
              : spec.params.fastenerType.itemTitle),
          _darkSpec('Шаг', '${_trim(step / 10)} см'),
          if (spec.layers.zipperBands.isNotEmpty)
            _darkSpec('Молнии', '${spec.layers.zipperBands.length} шт.'),
          if (spec.layers.liftStraps.isNotEmpty)
            _darkSpec('Ремни', '${spec.layers.liftStraps.length} шт.'),
        ],
      ),
    );
  }

  pw.Widget _darkSpec(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 3),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.SizedBox(
          width: 56,
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: _font,
              fontSize: 7.6,
              color: const PdfColor.fromInt(0xFF93A0B1),
            ),
          ),
        ),
        pw.Expanded(
          child: pw.Text(
            value,
            style: pw.TextStyle(
              font: _font,
              fontSize: 8,
              color: PdfColors.white,
            ),
          ),
        ),
      ],
    ),
  );

  pw.Widget _cutCard(WindowSpec spec) {
    final pieces = spec.filmCutPolygonsWithShrinkage;
    final materials = spec.isComposite
        ? [spec.params.material, spec.params.composite.material]
        : [spec.params.material];
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: warmLine, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'РАСКРОЙ',
            style: pw.TextStyle(
              font: _font,
              fontSize: 7,
              letterSpacing: 2.2,
              color: gold,
            ),
          ),
          pw.SizedBox(height: 5),
          for (var index = 0; index < pieces.length; index++)
            _pieceRow(
              pieces[index],
              index < materials.length ? materials[index] : spec.params.material,
              index == 1 && spec.isComposite,
            ),
          if (spec.edgeConsumption.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            for (final entry in (spec.edgeConsumption.entries.toList()
              ..sort((a, b) => a.key.compareTo(b.key))))
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 2),
                child: pw.Row(
                  children: [
                    pw.Container(width: 40, height: 4, color: bandBrown),
                    pw.SizedBox(width: 6),
                    pw.Text(
                      'окантовка ${_trim(entry.key / 10)} см · '
                      '${_meters(entry.value)} м',
                      style: pw.TextStyle(
                        font: _font,
                        fontSize: 7.5,
                        color: warmDim,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  pw.Widget _pieceRow(
    List<Offset> polygon,
    FilmMaterial material,
    bool second,
  ) {
    final bounds = _boundsOf(polygon);
    final width = _min(96.0, 40 + bounds.width / 26);
    final height = _min(54.0, 18 + bounds.height / 44);
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Container(
            width: width,
            height: height,
            decoration: pw.BoxDecoration(
              color: material == FilmMaterial.screen ? filmGrey : filmBlue,
              border: pw.Border.all(
                color: material == FilmMaterial.screen
                    ? metal
                    : const PdfColor.fromInt(0xFF4C9BE8),
                width: 0.7,
              ),
            ),
            alignment: pw.Alignment.center,
            child: pw.Text(
              '${_cm(bounds.width)} × ${_cm(bounds.height)}',
              style: pw.TextStyle(font: _font, fontSize: 7, color: dim),
            ),
          ),
          pw.SizedBox(width: 7),
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  _materialLabel(material),
                  style: pw.TextStyle(
                    font: _bold,
                    fontSize: 7.8,
                    color: ink,
                  ),
                ),
                pw.Text(
                  '${_m2(bounds.width * bounds.height / 1000000)} м²',
                  style: pw.TextStyle(
                    font: _font,
                    fontSize: 7.2,
                    color: warmDim,
                  ),
                ),
                if (second)
                  pw.Text(
                    'второй сегмент',
                    style: pw.TextStyle(
                      font: _font,
                      fontSize: 6.8,
                      color: gold,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _hardwareCard(WindowSpec spec) {
    final eyelets = <String, int>{};
    for (final eyelet in spec.layers.eyelets) {
      final type = spec.layers.typeFor(eyelet);
      eyelets[type.displayLabel] = (eyelets[type.displayLabel] ?? 0) + 1;
    }
    final fasteners = <String, int>{};
    for (final fastener in spec.layers.manualFasteners) {
      final title = fastener.type.itemTitle;
      fasteners[title] = (fasteners[title] ?? 0) + 1;
    }
    if (spec.params.fastenerType != FastenerType.eyeletsOnly) {
      final movable = spec.layers.movableSideEyelets.length;
      if (movable > 0) {
        final title = spec.params.fastenerType.itemTitle;
        fasteners[title] = (fasteners[title] ?? 0) + movable;
      }
    }
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(12, 9, 12, 8),
      decoration: pw.BoxDecoration(
        color: PdfColors.white,
        border: pw.Border.all(color: warmLine, width: 0.8),
        borderRadius: pw.BorderRadius.circular(6),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Text(
            'ФУРНИТУРА',
            style: pw.TextStyle(
              font: _font,
              fontSize: 7,
              letterSpacing: 2.2,
              color: gold,
            ),
          ),
          pw.SizedBox(height: 4),
          for (final entry in eyelets.entries)
            _lightSpec(entry.key, '${entry.value} шт.'),
          for (final entry in fasteners.entries)
            _lightSpec(entry.key, '${entry.value} шт.'),
          if (spec.layers.zipperBands.isNotEmpty)
            _lightSpec(
              'Молния',
              '${_meters(spec.layers.zipperBands.length * spec.layers.filmVisibleBounds.height)} пог.м',
            ),
          // Площадь уже показана в параметрах — не дублируем.
        ],
      ),
    );
  }

  pw.Widget _lightSpec(String label, String value) => pw.Padding(
    padding: const pw.EdgeInsets.only(top: 2),
    child: pw.Row(
      children: [
        pw.Expanded(
          child: pw.Text(
            label,
            style: pw.TextStyle(
              font: _font,
              fontSize: 7.8,
              color: warmDim,
            ),
          ),
        ),
        pw.Text(
          value,
          style: pw.TextStyle(font: _bold, fontSize: 7.8, color: ink),
        ),
      ],
    ),
  );

  // ------------------------------------------------------------- чертёж

  void _paintWindow(
    PdfGraphics canvas,
    PdfPoint size,
    WindowSpec spec,
    PdfFont font,
  ) {
    final geometry = spec.geometry;
    final bounds = _boundsOf(geometry.corners);
    if (bounds.width <= 0 || bounds.height <= 0) return;

    // Поля под размеры и разметку; сам чертёж центрируем в листе.
    const marginX = 62.0;
    const marginY = 54.0;
    final k = _min(
      (size.x - marginX * 2) / bounds.width,
      (size.y - marginY * 2) / bounds.height,
    );
    final offsetX = (size.x - bounds.width * k) / 2;
    final offsetY = (size.y - bounds.height * k) / 2;
    PdfPoint map(Offset point) => PdfPoint(
      offsetX + (point.dx - bounds.left) * k,
      offsetY + (point.dy - bounds.top) * k,
    );

    final parts = spec.layers.partPolygons;
    final inners = spec.layers.edgeInnerPolygons;
    final secondMaterial = spec.isComposite
        ? spec.params.composite.material
        : spec.params.material;
    for (var index = 0; index < parts.length; index++) {
      final part = parts[index];
      final material = index == 1 ? secondMaterial : spec.params.material;
      final isScreen = material == FilmMaterial.screen;
      if (isScreen) {
        _fillPolygon(canvas, part.map(map).toList(), filmGrey);
        canvas
          ..setStrokeColor(metal)
          ..setLineWidth(0.8);
        _strokePolygon(canvas, part.map(map).toList());
        continue;
      }
      _fillPolygon(canvas, part.map(map).toList(), bandBrown);
      final inner = index < inners.length ? inners[index] : part;
      _fillPolygon(canvas, inner.map(map).toList(), filmBlue);
      canvas
        ..setStrokeColor(bandBrownDark)
        ..setLineWidth(0.7);
      _strokePolygon(canvas, part.map(map).toList());
      canvas
        ..setStrokeColor(const PdfColor.fromInt(0xFF9FB4CA))
        ..setLineWidth(0.4);
      _strokePolygon(canvas, inner.map(map).toList());
      canvas
        ..setStrokeColor(const PdfColor.fromInt(0xFFE8D9CF))
        ..setLineWidth(0.4)
        ..setLineDashPattern([2, 2], 0);
      _strokePolygon(
        canvas,
        inner.map((point) => map(point + const Offset(0, 12))).toList(),
      );
      canvas.setLineDashPattern([], 0);
    }

    for (final cutout in spec.layers.cutouts) {
      final rect = _mapRect(cutout.bounds, map);
      canvas
        ..setFillColor(PdfColors.white)
        ..setStrokeColor(metal)
        ..setLineWidth(0.8);
      if (cutout.isCircle) {
        canvas
          ..drawEllipse(
            rect.left + rect.width / 2,
            rect.top + rect.height / 2,
            rect.width / 2,
            rect.height / 2,
          )
          ..fillPath()
          ..strokePath();
      } else {
        canvas
          ..drawRect(rect.left, rect.top, rect.width, rect.height)
          ..fillPath()
          ..strokePath();
      }
    }

    for (final band in spec.layers.zipperBands) {
      final rect = _mapRect(band, map);
      canvas
        ..setFillColor(bandBrown)
        ..setStrokeColor(bandBrownDark)
        ..setLineWidth(0.5)
        ..drawRect(rect.left, rect.top, rect.width, rect.height)
        ..fillPath()
        ..strokePath();
      final cx = rect.left + rect.width / 2;
      canvas
        ..setStrokeColor(const PdfColor.fromInt(0xFF2C2119))
        ..setLineWidth(1)
        ..setLineDashPattern([2, 1.6], 0)
        ..moveTo(cx, rect.top)
        ..lineTo(cx, rect.top + rect.height)
        ..strokePath()
        ..setLineDashPattern([], 0)
        ..setFillColor(const PdfColor.fromInt(0xFFE4B23C))
        ..drawRect(cx - 1.6, rect.top + rect.height * 0.45, 3.2, 6)
        ..fillPath();
    }

    for (final strap in spec.layers.liftStraps) {
      final rect = _mapRect(strap, map);
      canvas
        ..setFillColor(const PdfColor.fromInt(0xFFD9E0E8))
        ..setStrokeColor(metal)
        ..setLineWidth(0.6)
        ..drawRect(rect.left, rect.top, rect.width, rect.height)
        ..fillPath()
        ..strokePath();
      canvas
        ..setStrokeColor(const PdfColor.fromInt(0xFF8B97A6))
        ..setLineWidth(0.5)
        ..moveTo(rect.left + 1, rect.top + rect.height - 4)
        ..lineTo(rect.left + rect.width - 1, rect.top + rect.height - 4)
        ..strokePath();
    }

    for (final side in [WindowSide.bottom, WindowSide.top]) {
      final band = spec.layers.pocketBand(side);
      if (band.length < 3) continue;
      _fillPolygon(
        canvas,
        band.map(map).toList(),
        const PdfColor.fromInt(0xFFC9D3DF),
      );
      canvas
        ..setStrokeColor(const PdfColor.fromInt(0xFF7C8798))
        ..setLineWidth(0.7);
      _strokePolygon(canvas, band.map(map).toList());
    }

    for (final eyelet in spec.layers.eyelets) {
      final center = map(eyelet.center);
      final type = spec.layers.typeFor(eyelet);
      // Как на производственном чертеже: кольцо не мельче 7 pt, иначе
      // вместо люверса получается точка.
      final outerW = _max(type.outerWidth * k, 4.6);
      final outerH = _max(type.outerHeight * k, 4.6);
      final rx = outerW / 2;
      final ry = outerH / 2;
      // Тень.
      canvas
        ..setFillColor(const PdfColor.fromInt(0x22000000))
        ..drawEllipse(center.x + 0.7, center.y - 0.7, rx, ry)
        ..fillPath();
      // Металлическое кольцо.
      canvas
        ..setFillColor(const PdfColor.fromInt(0xFFD8DDE4))
        ..setStrokeColor(const PdfColor.fromInt(0xFF5E6B7B))
        ..setLineWidth(0.7)
        ..drawEllipse(center.x, center.y, rx, ry)
        ..fillPath()
        ..strokePath();
      // Фаска и блеск.
      canvas
        ..setFillColor(const PdfColor.fromInt(0xFFF1F4F8))
        ..drawEllipse(center.x, center.y, rx * 0.68, ry * 0.68)
        ..fillPath()
        ..setFillColor(const PdfColor.fromInt(0xFFFFFFFF))
        ..drawEllipse(center.x, center.y, rx * 0.36, ry * 0.36)
        ..fillPath();
    }

    final autoType = spec.params.fastenerType;
    if (autoType != FastenerType.eyeletsOnly) {
      for (final eyelet in spec.layers.movableSideEyelets) {
        _drawFastener(canvas, map(eyelet.center), autoType);
      }
    }
    for (final fastener in spec.layers.manualFasteners) {
      _drawFastener(canvas, map(fastener.center), fastener.type);
    }

    _dimension(
      canvas,
      map(Offset(bounds.left, bounds.bottom)),
      map(Offset(bounds.right, bounds.bottom)),
      const PdfPoint(0, 30),
      _cm(geometry.spanX),
      font,
    );
    _dimension(
      canvas,
      map(Offset(bounds.left, bounds.top)),
      map(Offset(bounds.right, bounds.top)),
      const PdfPoint(0, -30),
      _cm(geometry.spanX),
      font,
    );
    _dimension(
      canvas,
      map(Offset(bounds.left, bounds.top)),
      map(Offset(bounds.left, bounds.bottom)),
      const PdfPoint(-30, 0),
      _cm(geometry.overallHeight),
      font,
    );
    _dimension(
      canvas,
      map(Offset(bounds.right, bounds.top)),
      map(Offset(bounds.right, bounds.bottom)),
      const PdfPoint(30, 0),
      _cm(geometry.overallHeight),
      font,
    );

    for (final label in fastenerChainLabels(spec)) {
      if (label.side == null) continue;
      final point = map(label.pointMm);
      if (label.text == '0') continue;
      // Боковые стороны уже подписаны габаритом и отступами у углов —
      // вертикальные числа шага только засоряют чертёж.
      if (label.side == WindowSide.left || label.side == WindowSide.right) {
        continue;
      }
      // Числа шага ставим снаружи, между кромкой и габаритным размером.
      final offset = switch (label.side!) {
        WindowSide.bottom => const PdfPoint(0, -12),
        WindowSide.top => const PdfPoint(0, 12),
        WindowSide.left => const PdfPoint(-16, 0),
        WindowSide.right => const PdfPoint(16, 0),
      };
      final textWidth = label.text.length * 3.9;
      canvas.setFillColor(dim);
      canvas.drawString(
        font,
        6.3,
        label.text,
        point.x + offset.x + (offset.x < 0 ? -textWidth : 0),
        point.y + offset.y - 2,
      );
    }

  }

  void _drawFastener(
    PdfGraphics canvas,
    PdfPoint center,
    FastenerType type,
  ) {
    switch (type) {
      case FastenerType.frenchLocks:
        canvas
          ..setFillColor(const PdfColor.fromInt(0xFFEDEFF2))
          ..setStrokeColor(metal)
          ..setLineWidth(0.6)
          ..drawEllipse(center.x, center.y, 5, 4)
          ..fillPath()
          ..strokePath()
          ..setFillColor(metal)
          ..drawEllipse(center.x, center.y, 1.6, 1.6)
          ..fillPath();
      case FastenerType.turnBuckles:
        canvas
          ..setFillColor(const PdfColor.fromInt(0xFFEDEFF2))
          ..setStrokeColor(metal)
          ..setLineWidth(0.6)
          ..drawRect(center.x - 4, center.y - 3, 8, 6)
          ..fillPath()
          ..strokePath()
          ..setStrokeColor(metal)
          ..drawEllipse(center.x + 4, center.y, 2, 2)
          ..strokePath();
      case FastenerType.straps:
        canvas
          ..setFillColor(const PdfColor.fromInt(0xFFCFD7E2))
          ..setStrokeColor(metal)
          ..setLineWidth(0.5)
          ..drawRect(center.x - 2, center.y - 7, 4, 14)
          ..fillPath()
          ..strokePath();
      case FastenerType.eyeletsOnly:
        break;
    }
  }

  void _dimension(
    PdfGraphics canvas,
    PdfPoint a,
    PdfPoint b,
    PdfPoint offset,
    String text,
    PdfFont font,
  ) {
    final start = PdfPoint(a.x + offset.x, a.y + offset.y);
    final end = PdfPoint(b.x + offset.x, b.y + offset.y);
    canvas
      ..setStrokeColor(const PdfColor.fromInt(0xFF7C8798))
      ..setLineWidth(0.7)
      ..moveTo(start.x, start.y)
      ..lineTo(end.x, end.y)
      ..strokePath();
    _arrow(canvas, start, end);
    _arrow(canvas, end, start);

    final middle = PdfPoint((start.x + end.x) / 2, (start.y + end.y) / 2);
    final textWidth = text.length * 5.2;
    final vertical = offset.x.abs() > offset.y.abs();
    canvas.setFillColor(ink);
    canvas.drawString(
      font,
      11,
      text,
      vertical
          ? (offset.x > 0
                ? middle.x + 6
                : middle.x - textWidth - 6)
          : middle.x - textWidth / 2,
      vertical
          ? middle.y - 3
          : middle.y + (offset.y > 0 ? -14 : 5),
    );
  }

  void _arrow(PdfGraphics canvas, PdfPoint from, PdfPoint to) {
    canvas.setFillColor(const PdfColor.fromInt(0xFF7C8798));
    final dx = to.x - from.x;
    final dy = to.y - from.y;
    final length = _sqrt(dx * dx + dy * dy);
    if (length < 0.01) return;
    final ux = dx / length;
    final uy = dy / length;
    final tip = from;
    final bx = tip.x + ux * 5;
    final by = tip.y + uy * 5;
    canvas
      ..moveTo(tip.x, tip.y)
      ..lineTo(bx - uy * 2, by + ux * 2)
      ..lineTo(bx + uy * 2, by - ux * 2)
      ..closePath()
      ..fillPath();
  }

  // ------------------------------------------------------------ служебное

  static double _min(double a, double b) => a < b ? a : b;

  static double _max(double a, double b) => a > b ? a : b;

  static double _sqrt(double value) {
    // Небольшая собственная реализация, чтобы не тянуть dart:math в PDF-слой.
    var x = value;
    if (x <= 0) return 0;
    for (var i = 0; i < 24; i++) {
      x = (x + value / x) / 2;
    }
    return x;
  }

  static Rect _boundsOf(List<Offset> points) {
    var left = double.infinity;
    var right = double.negativeInfinity;
    var top = double.infinity;
    var bottom = double.negativeInfinity;
    for (final point in points) {
      if (point.dx < left) left = point.dx;
      if (point.dx > right) right = point.dx;
      if (point.dy < top) top = point.dy;
      if (point.dy > bottom) bottom = point.dy;
    }
    return Rect.fromLTRB(left, top, right, bottom);
  }

  static PdfRect _mapRect(Rect rect, PdfPoint Function(Offset) map) {
    final a = map(Offset(rect.left, rect.top));
    final b = map(Offset(rect.right, rect.bottom));
    return PdfRect(
      a.x < b.x ? a.x : b.x,
      a.y < b.y ? a.y : b.y,
      (b.x - a.x).abs(),
      (b.y - a.y).abs(),
    );
  }

  static void _fillPolygon(PdfGraphics canvas, List<PdfPoint> points, PdfColor color) {
    if (points.length < 3) return;
    canvas
      ..setFillColor(color)
      ..moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      canvas.lineTo(point.x, point.y);
    }
    canvas
      ..closePath()
      ..fillPath();
  }

  static void _strokePolygon(PdfGraphics canvas, List<PdfPoint> points) {
    if (points.length < 2) return;
    canvas.moveTo(points.first.x, points.first.y);
    for (final point in points.skip(1)) {
      canvas.lineTo(point.x, point.y);
    }
    canvas
      ..closePath()
      ..strokePath();
  }

  String _cm(double mm) => _trim(mm / 10);

  String _trim(double value) {
    final rounded = (value * 10).round() / 10;
    final text = rounded.toStringAsFixed(1);
    return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
  }

  String _m2(double value) => value.toStringAsFixed(2).replaceAll('.', ',');

  String _meters(double mm) => (mm / 1000).toStringAsFixed(2).replaceAll('.', ',');

  String _rub(double value) => formatRubles(value);
}

/// Простой прямоугольник в координатах листа.
class PdfRect {
  const PdfRect(this.left, this.top, this.width, this.height);

  final double left;
  final double top;
  final double width;
  final double height;
}

/// Собирает отчёт и сохраняет его файлом (десктоп — папка, браузер — скачивание).
Future<SavedFile> saveClientReport({
  required OrderProject project,
  required PriceList prices,
  required CompanyBrandingState company,
  ClientReportInfo info = const ClientReportInfo(),
}) async {
  final bytes = await ClientReportBuilder(
    project: project,
    prices: prices,
    company: company,
    info: info,
  ).build();
  final number = project.selected.drawingNumber.trim();
  final name = 'Отчёт клиенту${number.isEmpty ? '' : ' $number'}.pdf';
  return saveBytes(bytes, name);
}


/// Данные заказчика для клиентского отчёта: заполняются в диалоге перед
/// сохранением и подставляются на обложку.
class ClientReportInfo {
  const ClientReportInfo({
    this.name = '',
    this.phone = '',
    this.address = '',
    this.comment = '',
    this.manager = '',
    this.surveyor = 'Замер клиента',
    this.installer = 'Без установки',
  });

  final String name;
  final String phone;
  final String address;
  final String comment;
  final String manager;
  final String surveyor;
  final String installer;
}
