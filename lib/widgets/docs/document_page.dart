// A4-предпросмотр документа: пагинация и страницы «как в Word».
//
// Документ режется на страницы по высоте A4: абзацы, заголовки и списки
// измеряются TextPainter'ом, таблицы делятся по строкам с повтором шапки,
// разрыв страницы уважается. Страницы — настоящие A4 (794 × 1123 логических
// пикселя), поэтому PDF и печать совпадают с экраном.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/document.dart';
import '../../services/document_pdf.dart';
import 'inline_markup.dart';

/// Ширина полей A4-страницы, логические пиксели (~14 мм).
const double docPagePadding = 52;

/// Высота колонтитула внизу страницы.
const double docPageFooterHeight = 22;

/// Доступная ширина содержимого страницы.
const double docPageContentWidth = documentA4Width - docPagePadding * 2;

/// Доступная высота содержимого страницы.
const double docPageContentHeight =
    documentA4Height - docPagePadding * 2 - docPageFooterHeight;

/// Базовый стиль абзаца.
const TextStyle docBodyStyle = TextStyle(
  fontSize: 11.5,
  height: 1.45,
  color: Color(0xFF1F2937),
);

const TextStyle docH1Style = TextStyle(
  fontSize: 19,
  height: 1.25,
  fontWeight: FontWeight.w800,
  color: Color(0xFF111827),
);

const TextStyle docH2Style = TextStyle(
  fontSize: 14.5,
  height: 1.3,
  fontWeight: FontWeight.w700,
  color: Color(0xFF111827),
);

const TextStyle docH3Style = TextStyle(
  fontSize: 12.5,
  height: 1.3,
  fontWeight: FontWeight.w700,
  color: Color(0xFF111827),
);

const TextStyle docTableStyle = TextStyle(
  fontSize: 9,
  height: 1.3,
  color: Color(0xFF1F2937),
);

/// Читатель ассетов: ссылка из JSON → байты из отдельного хранилища.
typedef DocumentAssetReader = Future<Uint8List?> Function(String? ref);

/// Разбивает блоки документа на страницы A4.
List<List<DocBlock>> paginateDocument(List<DocBlock> blocks) {
  final pages = <List<DocBlock>>[];
  var current = <DocBlock>[];
  var used = 0.0;

  void newPage() {
    if (current.isEmpty) return;
    pages.add(current);
    current = <DocBlock>[];
    used = 0;
  }

  for (final block in blocks) {
    if (block.type == DocBlockType.pageBreak) {
      newPage();
      continue;
    }
    if (block.type == DocBlockType.table && block.rows.isNotEmpty) {
      final rows = block.rows;
      final columns = rows.map((row) => row.length).fold<int>(1, _maxInt);
      final rowHeights = [
        for (final row in rows) _tableRowHeight(row, columns),
      ];
      final headerHeight = rowHeights.first;
      var start = 1;
      if (rows.length == 1) {
        if (used + headerHeight + 8 > docPageContentHeight && current.isNotEmpty) {
          newPage();
        }
        current.add(block);
        used += headerHeight + 8;
        continue;
      }
      while (start < rows.length) {
        var available = docPageContentHeight - used - headerHeight;
        if (available < rowHeights[start] && current.isNotEmpty) {
          newPage();
          available = docPageContentHeight - headerHeight;
        }
        final chunk = <List<String>>[rows.first];
        var chunkHeight = headerHeight;
        while (start < rows.length && chunkHeight + rowHeights[start] <= available) {
          chunk.add(rows[start]);
          chunkHeight += rowHeights[start];
          start++;
        }
        // Даже самое высокое содержимое должно попасть хоть на одну страницу.
        if (chunk.length == 1) {
          chunk.add(rows[start]);
          chunkHeight += rowHeights[start];
          start++;
        }
        current.add(block.copyWith(rows: chunk));
        used += chunkHeight + 8;
        if (start < rows.length) newPage();
      }
      if (start >= rows.length && current.isNotEmpty) {
        // Таблица закончилась — следующему блоку нужен отступ.
        used += 6;
      }
      continue;
    }
    final height = blockHeight(block);
    if (used + height > docPageContentHeight && current.isNotEmpty) {
      newPage();
    }
    current.add(block);
    used += height;
  }
  if (current.isNotEmpty) pages.add(current);
  if (pages.isEmpty) pages.add(const <DocBlock>[]);
  return pages;
}

/// Высота блока на странице — приблизительная, но достаточная, чтобы не
/// разрывать таблицу и не выпускать абзац за край A4.
double blockHeight(DocBlock block) {
  final width = docPageContentWidth;
  switch (block.type) {
    case DocBlockType.heading1:
      return _textHeight(block.text, docH1Style, width) + 14;
    case DocBlockType.heading2:
      return _textHeight(block.text, docH2Style, width) + 12;
    case DocBlockType.heading3:
      return _textHeight(block.text, docH3Style, width) + 10;
    case DocBlockType.paragraph:
      return _textHeight(block.text, docBodyStyle, width) + 8;
    case DocBlockType.bulletList:
    case DocBlockType.numberedList:
      final lines = block.text
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList();
      if (lines.isEmpty) return 26;
      var height = 8.0;
      for (final line in lines) {
        height += _textHeight(line, docBodyStyle, width - 20) + 2;
      }
      return height;
    case DocBlockType.table:
      if (block.rows.isEmpty) return 48;
      final columns = block.rows.map((row) => row.length).fold<int>(1, _maxInt);
      final sum = block.rows
          .map((row) => _tableRowHeight(row, columns))
          .fold<double>(0, (total, height) => total + height);
      return sum + 14;
    case DocBlockType.image:
      return (block.isSignature ? 92 : 150) + 8;
    case DocBlockType.signature:
      return 92;
    case DocBlockType.pageBreak:
      return 0;
  }
}

double _tableRowHeight(List<String> row, int columns) {
  final columnWidth = docPageContentWidth / columns;
  var height = 12.0;
  for (final cell in row) {
    height = height < _textHeight(cell, docTableStyle, columnWidth - 8)
        ? _textHeight(cell, docTableStyle, columnWidth - 8)
        : height;
  }
  return height + 6;
}

double _textHeight(String text, TextStyle style, double maxWidth) {
  if (text.trim().isEmpty) return (style.fontSize ?? 12) * (style.height ?? 1.3);
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: maxWidth);
  final height = painter.height;
  painter.dispose();
  return height;
}

int _maxInt(int a, int b) => a > b ? a : b;

/// Колонки A4-предпросмотра. Держит ключи страниц для PDF/печати.
class DocumentPages extends StatefulWidget {
  const DocumentPages({
    super.key,
    required this.document,
    required this.assets,
    this.showFrame = true,
  });

  final OrderDocument document;
  final DocumentAssetReader assets;
  final bool showFrame;

  @override
  State<DocumentPages> createState() => DocumentPagesState();
}

class DocumentPagesState extends State<DocumentPages> {
  final List<GlobalKey> _pageKeys = <GlobalKey>[];
  final Map<String, Future<Uint8List?>> _assetFutures = {};

  /// Ключи `RepaintBoundary` страниц — их снимает PDF-экспорт.
  List<GlobalKey> get pageKeys => List.unmodifiable(_pageKeys);

  @override
  void didUpdateWidget(covariant DocumentPages oldWidget) {
    super.didUpdateWidget(oldWidget);
    _assetFutures.removeWhere(
      (ref, _) =>
          !widget.document.blocks.any((block) => block.assetRef == ref),
    );
  }

  /// Догружает картинки и ждёт кадр — перед PDF, чтобы подписи попали в файл.
  Future<void> ensureAssetsLoaded() async {
    final futures = <Future<Uint8List?>>[];
    for (final block in widget.document.blocks) {
      final ref = block.assetRef;
      if (ref == null || ref.isEmpty) continue;
      futures.add(_assetFutures.putIfAbsent(ref, () => widget.assets(ref)));
    }
    if (futures.isNotEmpty) {
      await Future.wait(futures);
      if (mounted) setState(() {});
    }
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<Uint8List?> _assetFuture(String? ref) {
    if (ref == null || ref.isEmpty) return Future.value(null);
    return _assetFutures.putIfAbsent(ref, () => widget.assets(ref));
  }

  @override
  Widget build(BuildContext context) {
    final pages = paginateDocument(widget.document.blocks);
    while (_pageKeys.length < pages.length) {
      _pageKeys.add(GlobalKey());
    }
    if (_pageKeys.length > pages.length) {
      _pageKeys.removeRange(pages.length, _pageKeys.length);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : documentA4Width;
        final scale = ((available - 32) / documentA4Width).clamp(0.25, 1.0);
        return ColoredBox(
          color: const Color(0xFFDDE3EC),
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              children: [
                for (var i = 0; i < pages.length; i++) ...[
                  SizedBox(
                    width: documentA4Width * scale,
                    height: documentA4Height * scale,
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: DocumentPage(
                        captureKey: _pageKeys[i],
                        document: widget.document,
                        blocks: pages[i],
                        assets: _assetFuture,
                        pageNumber: i + 1,
                        pageCount: pages.length,
                        showFrame: widget.showFrame,
                      ),
                    ),
                  ),
                  if (i != pages.length - 1) const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Одна A4-страница документа в режиме чтения.
class DocumentPage extends StatelessWidget {
  const DocumentPage({
    super.key,
    required this.document,
    required this.blocks,
    required this.assets,
    required this.pageNumber,
    required this.pageCount,
    this.captureKey,
    this.showFrame = true,
  });

  final OrderDocument document;
  final List<DocBlock> blocks;
  final DocumentAssetReader assets;
  final int pageNumber;
  final int pageCount;
  final GlobalKey? captureKey;
  final bool showFrame;

  @override
  Widget build(BuildContext context) {
    final page = Container(
      width: documentA4Width,
      height: documentA4Height,
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(
        docPagePadding,
        docPagePadding,
        docPagePadding,
        docPagePadding,
      ),
      child: Column(
        children: [
          Expanded(
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final block in blocks) _ReadBlock(block: block, assets: assets),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  document.number.trim().isEmpty
                      ? document.title
                      : '${document.title} · ${document.number}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 8,
                    color: Color(0xFF8A94A6),
                  ),
                ),
              ),
              Text(
                'стр. $pageNumber из $pageCount',
                style: const TextStyle(fontSize: 8, color: Color(0xFF8A94A6)),
              ),
            ],
          ),
        ],
      ),
    );
    final decorated = showFrame
        ? DecoratedBox(
            decoration: BoxDecoration(
              boxShadow: const [
                BoxShadow(
                  color: Color(0x33000000),
                  blurRadius: 14,
                  offset: Offset(0, 5),
                ),
              ],
              border: Border.all(color: const Color(0xFFC3CCDA)),
            ),
            child: page,
          )
        : page;
    if (captureKey == null) return decorated;
    return RepaintBoundary(key: captureKey, child: decorated);
  }
}

class _ReadBlock extends StatelessWidget {
  const _ReadBlock({required this.block, required this.assets});

  final DocBlock block;
  final DocumentAssetReader assets;

  @override
  Widget build(BuildContext context) {
    switch (block.type) {
      case DocBlockType.heading1:
        return _rich(block.text, docH1Style, block.align, paddingBottom: 10);
      case DocBlockType.heading2:
        return _rich(block.text, docH2Style, block.align, paddingBottom: 8);
      case DocBlockType.heading3:
        return _rich(block.text, docH3Style, block.align, paddingBottom: 6);
      case DocBlockType.paragraph:
        return _rich(block.text, docBodyStyle, block.align, paddingBottom: 7);
      case DocBlockType.bulletList:
        return _list(numbered: false);
      case DocBlockType.numberedList:
        return _list(numbered: true);
      case DocBlockType.table:
        return _table();
      case DocBlockType.image:
      case DocBlockType.signature:
        return _image(context);
      case DocBlockType.pageBreak:
        return const SizedBox.shrink();
    }
  }

  Widget _rich(
    String text,
    TextStyle style,
    DocAlign align, {
    double paddingBottom = 0,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: paddingBottom),
      child: RichText(
        textAlign: _textAlign(align),
        text: TextSpan(style: style, children: inlineSpans(text, base: style)),
      ),
    );
  }

  Widget _list({required bool numbered}) {
    final lines = block.text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < lines.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 20,
                    child: Text(
                      numbered ? '${i + 1}.' : '•',
                      style: docBodyStyle,
                    ),
                  ),
                  Expanded(
                    child: RichText(
                      textAlign: _textAlign(block.align),
                      text: TextSpan(
                        style: docBodyStyle,
                        children: inlineSpans(lines[i], base: docBodyStyle),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _table() {
    if (block.rows.isEmpty) return const SizedBox.shrink();
    final columns = _maxColumns(block.rows);
    final widths = _columnWidths(columns);
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Table(
        border: TableBorder.all(color: const Color(0xFFB8C2D2), width: 0.6),
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: {
          for (var c = 0; c < columns; c++)
            c: FlexColumnWidth(widths[c]),
        },
        children: [
          for (var r = 0; r < block.rows.length; r++)
            TableRow(
              decoration: BoxDecoration(
                color: r == 0 ? const Color(0xFFEDF2F9) : Colors.white,
              ),
              children: [
                for (var c = 0; c < columns; c++)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 4,
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: r == 0
                            ? docTableStyle.copyWith(fontWeight: FontWeight.w700)
                            : docTableStyle,
                        children: inlineSpans(
                          c < block.rows[r].length ? block.rows[r][c] : '',
                          base: docTableStyle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _image(BuildContext context) {
    final ref = block.assetRef;
    final height = block.isSignature ? 78.0 : 136.0;
    final width = block.widthMm * documentA4Width / 210;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Align(
        alignment: _alignment(block.align),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: width,
              height: height,
              child: ref == null
                  ? const _MissingAsset()
                  : FutureBuilder<Uint8List?>(
                      future: assets(ref),
                      builder: (context, snapshot) {
                        final bytes = snapshot.data;
                        if (bytes == null) return const _MissingAsset();
                        return Image.memory(
                          bytes,
                          fit: BoxFit.contain,
                          filterQuality: FilterQuality.medium,
                        );
                      },
                    ),
            ),
            if (block.text.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  stripInlineMarkup(block.text),
                  style: const TextStyle(
                    fontSize: 8.5,
                    color: Color(0xFF66748A),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _MissingAsset extends StatelessWidget {
  const _MissingAsset();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F4F8),
        border: Border.all(color: const Color(0xFFCDD5E1)),
      ),
      child: const Center(
        child: Text(
          'изображение недоступно',
          style: TextStyle(fontSize: 8, color: Color(0xFF8A94A6)),
        ),
      ),
    );
  }
}

TextAlign _textAlign(DocAlign align) => switch (align) {
  DocAlign.left => TextAlign.left,
  DocAlign.center => TextAlign.center,
  DocAlign.right => TextAlign.right,
  DocAlign.justify => TextAlign.justify,
};

Alignment _alignment(DocAlign align) => switch (align) {
  DocAlign.left => Alignment.centerLeft,
  DocAlign.center => Alignment.center,
  DocAlign.right => Alignment.centerRight,
  DocAlign.justify => Alignment.centerLeft,
};

int _maxColumns(List<List<String>> rows) =>
    rows.map((row) => row.length).fold<int>(1, _maxInt);

List<double> _columnWidths(int columns) {
  if (columns == 6) return const [0.4, 3.1, 0.9, 0.7, 1.1, 1.2];
  if (columns == 4) return const [0.5, 3.0, 1.3, 0.8];
  return List<double>.filled(columns, 1);
}
