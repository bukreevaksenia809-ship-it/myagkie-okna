// Импорт пользовательских DOCX в документы заказа.
//
// Чистый Dart без Flutter UI: файл выбирается виджетом, а здесь только
// разбор. DOCX — это ZIP с `word/document.xml`; заголовки, абзацы, списки и
// таблицы превращаются в блоки [DocBlock], которые уже умеют показывать
// A4-предпросмотр и сохранять PDF. Сложное форматирование (картинки,
// колонтитулы, объединённые ячейки) не теряет текст: оно попадает в
// предупреждения «частичного импорта».
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import '../models/document.dart';

/// Максимальный размер DOCX до распаковки — 2 МБ.
///
/// В вебе документы лежат в localStorage (≈5 МБ), а распарсенные блоки
/// сохраняются вместе с библиотекой; 2 МБ — безопасный потолок.
const int docxMaxBytes = 2 * 1024 * 1024;

/// Максимальный размер `word/document.xml` после распаковки — защита от
/// zip-bomb.
const int docxMaxXmlBytes = 12 * 1024 * 1024;

/// Предупреждение частичного импорта: что именно не удалось перенести.
class DocxImportWarning {
  const DocxImportWarning(this.code, this.message, {this.count = 1});

  final String code;
  final String message;
  final int count;

  String get label => count > 1 ? '$message ($count)' : message;

  Map<String, dynamic> toJson() => {
    'code': code,
    'message': message,
    'count': count,
  };

  factory DocxImportWarning.fromJson(Map<String, dynamic> json) =>
      DocxImportWarning(
        json['code'] is String ? json['code'] as String : 'unknown',
        json['message'] is String ? json['message'] as String : '',
        count: json['count'] is num ? (json['count'] as num).toInt() : 1,
      );
}

/// Картинка, извлечённая из DOCX.
///
/// В блоках остаётся только ссылка-заглушка `[assetRef]`, а байты лежат здесь:
/// их сохраняет в хранилище ассетов тот, кто импортирует документ, — сервис
/// разбора остаётся чистым и синхронным.
class DocxImageData {
  const DocxImageData({
    required this.assetRef,
    required this.fileName,
    required this.bytes,
    required this.widthMm,
  });

  /// Ссылка-заглушка в блоке до сохранения (`@docx:...`).
  final String assetRef;

  /// Имя файла внутри DOCX (`image1.png`).
  final String fileName;

  final Uint8List bytes;

  /// Ширина на странице, мм (из EMU, ограничена шириной A4).
  final double widthMm;
}

/// Результат разбора DOCX.
class DocxImportResult {
  const DocxImportResult({
    this.title = '',
    this.blocks = const <DocBlock>[],
    this.warnings = const <DocxImportWarning>[],
    this.error,
    this.paragraphs = 0,
    this.tables = 0,
    this.headings = 0,
    this.images = const <DocxImageData>[],
  });

  final String title;
  final List<DocBlock> blocks;
  final List<DocxImportWarning> warnings;

  /// Текст ошибки; null — импорт удался (возможно, частично).
  final String? error;

  final int paragraphs;
  final int tables;
  final int headings;

  /// Картинки для сохранения в ассетах (блоки уже ссылаются на них).
  final List<DocxImageData> images;

  bool get ok => error == null;
  bool get partial => warnings.isNotEmpty;
  bool get hasContent => blocks.any(
    (block) => block.type == DocBlockType.table
        ? block.rows.isNotEmpty
        : block.type == DocBlockType.pageBreak ||
              block.assetRef != null ||
              block.text.trim().isNotEmpty,
  );
}

/// Значения для подстановки `{{клиент}}`, `{{заказ}}`, `{{дата}}`,
/// `{{сумма}}`, `{{номер}}` при вставке шаблона в заказ.
class DocxPlaceholderValues {
  const DocxPlaceholderValues({
    this.client = '',
    this.order = '',
    this.date = '',
    this.amount = '',
    this.number = '',
  });

  final String client;
  final String order;
  final String date;
  final String amount;
  final String number;

  Map<String, String> get _values => {
    'клиент': client,
    'client': client,
    'заказ': order,
    'order': order,
    'дата': date,
    'date': date,
    'сумма': amount,
    'amount': amount,
    'sum': amount,
    'номер': number,
    'number': number,
  };

  String valueFor(String key) => _values[key.trim().toLowerCase()] ?? '';
}

/// Подставляет значения заказа в текст шаблона.
///
/// Регистр и лишние пробелы внутри `{{ ... }}` не важны. Неизвестные
/// плейсхолдеры остаются как есть — их видно в предпросмотре и можно
/// поправить вручную.
String applyDocxPlaceholders(String text, DocxPlaceholderValues values) {
  if (!text.contains('{{')) return text;
  return text.replaceAllMapped(RegExp(r'\{\{\s*([^{}]+?)\s*\}\}'), (match) {
    final key = match.group(1)?.trim().toLowerCase() ?? '';
    final value = values.valueFor(key);
    return value.isEmpty ? match.group(0)! : value;
  });
}

/// Применяет подстановку ко всем текстовым блокам и ячейкам таблиц.
List<DocBlock> applyDocxPlaceholdersToBlocks(
  List<DocBlock> blocks,
  DocxPlaceholderValues values,
) => [
  for (final block in blocks)
    block.copyWith(
      text: applyDocxPlaceholders(block.text, values),
      rows: block.rows.isEmpty
          ? block.rows
          : [
              for (final row in block.rows)
                [for (final cell in row) applyDocxPlaceholders(cell, values)],
            ],
    ),
];

/// Подставляет реальные ссылки ассетов вместо заглушек `@docx:...`.
///
/// [refs] — карта «заглушка → сохранённый ассет». Блоки без соответствия
/// остаются с заглушкой: предпросмотр покажет «нет картинки», а текст и
/// таблицы не пострадают.
List<DocBlock> applyDocxImageAssets(
  List<DocBlock> blocks,
  Map<String, String> refs,
) => [
  for (final block in blocks)
    block.assetRef != null && refs.containsKey(block.assetRef)
        ? block.copyWith(assetRef: refs[block.assetRef])
        : block,
];

/// Сохранённый импортированный шаблон DOCX.
///
/// Хранится в shared_preferences вместе с библиотекой документов, но под
/// отдельным ключом: сырые байты не пишем, только блоки и предупреждения.
class ImportedDocxTemplate {
  const ImportedDocxTemplate({
    required this.id,
    required this.title,
    required this.fileName,
    required this.importedAt,
    required this.updatedAt,
    required this.blocks,
    this.warnings = const <DocxImportWarning>[],
    this.sizeBytes = 0,
  });

  final String id;
  final String title;
  final String fileName;
  final DateTime importedAt;
  final DateTime updatedAt;
  final List<DocBlock> blocks;
  final List<DocxImportWarning> warnings;
  final int sizeBytes;

  String get sizeLabel {
    if (sizeBytes <= 0) return '—';
    if (sizeBytes < 1024) return '$sizeBytes Б';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} КБ';
    }
    return '${(sizeBytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} МБ';
  }

  ImportedDocxTemplate copyWith({
    String? title,
    DateTime? updatedAt,
    List<DocBlock>? blocks,
  }) => ImportedDocxTemplate(
    id: id,
    title: title ?? this.title,
    fileName: fileName,
    importedAt: importedAt,
    updatedAt: updatedAt ?? this.updatedAt,
    blocks: blocks ?? this.blocks,
    warnings: warnings,
    sizeBytes: sizeBytes,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'fileName': fileName,
    'importedAt': importedAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'blocks': [for (final block in blocks) block.toJson()],
    'warnings': [for (final warning in warnings) warning.toJson()],
    'sizeBytes': sizeBytes,
  };

  factory ImportedDocxTemplate.fromJson(Map<String, dynamic> json) {
    final blocks = <DocBlock>[];
    if (json['blocks'] is List) {
      for (final item in json['blocks'] as List) {
        if (item is Map) {
          blocks.add(DocBlock.fromJson(item.cast<String, dynamic>()));
        }
      }
    }
    final warnings = <DocxImportWarning>[];
    if (json['warnings'] is List) {
      for (final item in json['warnings'] as List) {
        if (item is Map) {
          warnings.add(
            DocxImportWarning.fromJson(item.cast<String, dynamic>()),
          );
        }
      }
    }
    DateTime readDate(Object? value, DateTime fallback) {
      if (value is String) return DateTime.tryParse(value) ?? fallback;
      return fallback;
    }

    final now = DateTime.now();
    return ImportedDocxTemplate(
      id: json['id'] is String ? json['id'] as String : newDocumentId(),
      title: json['title'] is String ? json['title'] as String : 'Документ',
      fileName: json['fileName'] is String ? json['fileName'] as String : '',
      importedAt: readDate(json['importedAt'], now),
      updatedAt: readDate(json['updatedAt'], now),
      blocks: blocks,
      warnings: warnings,
      sizeBytes: json['sizeBytes'] is num
          ? (json['sizeBytes'] as num).toInt()
          : 0,
    );
  }
}

/// Разбор DOCX. Никогда не бросает наружу: любая проблема — [error].
class DocxImportService {
  DocxImportService._();

  /// Быстрая проверка сигнатуры ZIP и наличия `word/document.xml`.
  static bool looksLikeDocx(Uint8List bytes) {
    if (bytes.length < 4) return false;
    if (!(bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        (bytes[2] == 0x03 || bytes[2] == 0x05))) {
      return false;
    }
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      return archive.any(
        (entry) => entry.isFile && entry.name == 'word/document.xml',
      );
    } catch (_) {
      return false;
    }
  }

  static Future<DocxImportResult> parseBytes(
    Uint8List bytes, {
    String? fileName,
  }) async => parse(bytes, fileName: fileName);

  /// Разбирает байты DOCX в блоки документа.
  static DocxImportResult parse(Uint8List bytes, {String? fileName}) {
    final fallbackTitle = _titleFromFileName(fileName);
    if (bytes.length < 4) {
      return DocxImportResult(
        title: fallbackTitle,
        error: 'Файл пустой или повреждён.',
      );
    }
    if (bytes.length > docxMaxBytes) {
      return DocxImportResult(
        title: fallbackTitle,
        error:
            'Файл больше ${_mb(docxMaxBytes)} МБ. Сохраните документ меньше '
            'или разбейте его на части.',
      );
    }
    if (!(bytes[0] == 0x50 && bytes[1] == 0x4B)) {
      return DocxImportResult(
        title: fallbackTitle,
        error: 'Это не DOCX. Откройте файл в Word и сохраните как .docx.',
      );
    }
    try {
      final archive = ZipDecoder().decodeBytes(bytes);
      final entries = <String, List<int>>{};
      var headerFooterCount = 0;
      for (final entry in archive) {
        if (!entry.isFile) continue;
        if (entries.length > 5000) break;
        if (entry.name.startsWith('word/header') ||
            entry.name.startsWith('word/footer')) {
          headerFooterCount += 1;
        }
        final isHeaderXml =
            entry.name.startsWith('word/header') &&
            entry.name.endsWith('.xml');
        final isHeaderRels = entry.name.startsWith('word/_rels/header');
        if (entry.name == 'word/document.xml' ||
            entry.name == 'word/numbering.xml' ||
            entry.name == 'word/styles.xml' ||
            entry.name == 'word/_rels/document.xml.rels' ||
            entry.name == 'docProps/core.xml' ||
            isHeaderXml ||
            isHeaderRels ||
            (entry.name.startsWith('word/media/') &&
                _isSupportedImageName(entry.name))) {
          entries[entry.name] = entry.content as List<int>;
        }
      }
      final documentBytes = entries['word/document.xml'];
      if (documentBytes == null) {
        return DocxImportResult(
          title: fallbackTitle,
          error: 'В файле нет word/document.xml — это не документ Word.',
        );
      }
      if (documentBytes.length > docxMaxXmlBytes) {
        return DocxImportResult(
          title: fallbackTitle,
          error: 'Документ слишком большой для импорта.',
        );
      }
      final document = XmlDocument.parse(
        utf8.decode(documentBytes, allowMalformed: true),
      );
      final numbering = _NumberingFormats.parse(
        entries['word/numbering.xml'],
      );
      final warnings = <String, int>{};
      final blocks = <DocBlock>[];
      final counters = _Counters();
      if (headerFooterCount > 0) warnings['headers'] = headerFooterCount;
      final relationships = _parseRelationships(
        entries['word/_rels/document.xml.rels'],
      );
      final media = <String, List<int>>{
        for (final entry in entries.entries)
          if (entry.key.startsWith('word/media/')) entry.key: entry.value,
      };
      final images = <DocxImageData>[];

      final body = _firstByLocal(document.rootElement, 'body');
      if (body == null) {
        return DocxImportResult(
          title: fallbackTitle,
          error: 'Документ Word пуст.',
        );
      }

      _parseContainer(
        body,
        blocks,
        counters,
        warnings,
        numbering,
        relationships: relationships,
        media: media,
        images: images,
      );

      // Логотип часто лежит не в теле, а в колонтитуле Word. Переносим
      // картинки из первого колонтитула в начало документа: текст
      // колонтитулов по-прежнему не поддерживается (предупреждение выше).
      final headerImages = _headerImages(entries, media, warnings);
      if (headerImages.isNotEmpty) {
        images.insertAll(0, headerImages);
        blocks.insertAll(0, [
          for (final image in headerImages)
            DocBlock(
              id: newBlockId(),
              type: DocBlockType.image,
              assetRef: image.assetRef,
              widthMm: image.widthMm,
              align: DocAlign.center,
            ),
        ]);
      }

      if (blocks.isEmpty) {
        return DocxImportResult(
          title: fallbackTitle,
          warnings: _warningList(warnings),
          error: 'В документе нет текста или таблиц.',
        );
      }

      final title = _documentTitle(entries['docProps/core.xml']) ??
          fallbackTitle;
      return DocxImportResult(
        title: title,
        blocks: blocks,
        warnings: _warningList(warnings),
        paragraphs: counters.paragraphs,
        tables: counters.tables,
        headings: counters.headings,
        images: images,
      );
    } catch (error) {
      return DocxImportResult(
        title: fallbackTitle,
        error: 'Не удалось прочитать DOCX: файл повреждён или защищён.',
      );
    }
  }

  /// Картинки из `word/headerN.xml` со своими связями.
  static List<DocxImageData> _headerImages(
    Map<String, List<int>> entries,
    Map<String, List<int>> media,
    Map<String, int> warnings,
  ) {
    final names = entries.keys
        .where(
          (name) =>
              name.startsWith('word/header') && name.endsWith('.xml'),
        )
        .toList()
      ..sort();
    if (names.isEmpty) return const [];
    final result = <DocxImageData>[];
    for (final name in names) {
      try {
        final doc = XmlDocument.parse(
          utf8.decode(entries[name]!, allowMalformed: true),
        );
        final rels = _parseRelationships(
          entries['word/_rels/${name.split('/').last}.rels'],
        );
        for (final paragraph in doc.descendants.whereType<XmlElement>().where(
          (node) => node.name.local == 'p',
        )) {
          result.addAll(
            _extractImages(
              paragraph,
              relationships: rels,
              media: media,
              warnings: warnings,
            ),
          );
        }
      } catch (_) {
        // Битый колонтитул не должен ломать импорт тела.
      }
    }
    return result;
  }

  static void _parseContainer(
    XmlElement container,
    List<DocBlock> blocks,
    _Counters counters,
    Map<String, int> warnings,
    _NumberingFormats numbering, {
    required Map<String, String> relationships,
    required Map<String, List<int>> media,
    required List<DocxImageData> images,
  }) {
    DocBlockType? pendingListType;
    var pendingItems = <String>[];

    void flushList() {
      final type = pendingListType;
      if (type == null || pendingItems.isEmpty) return;
      blocks.add(
        DocBlock(
          id: newBlockId(),
          type: type,
          text: pendingItems.join('\n'),
        ),
      );
      counters.paragraphs += pendingItems.length;
      pendingListType = null;
      pendingItems = <String>[];
    }

    void emitImages(List<DocxImageData> list) {
      for (final image in list) {
        blocks.add(
          DocBlock(
            id: newBlockId(),
            type: DocBlockType.image,
            assetRef: image.assetRef,
            widthMm: image.widthMm,
            align: DocAlign.center,
          ),
        );
      }
    }

    for (final child in container.children.whereType<XmlElement>()) {
      switch (child.name.local) {
        case 'p':
          final parsed = _parseParagraph(
            child,
            numbering,
            relationships: relationships,
            media: media,
            images: images,
            warnings: warnings,
          );
          if (parsed.pageBreakBefore) {
            flushList();
            blocks.add(
              DocBlock(id: newBlockId(), type: DocBlockType.pageBreak),
            );
          }
          // Картинка без текста (логотип/штамп) — не пустой абзац: её надо
          // сохранить на своём месте, иначе логотип из шапки теряется.
          if (parsed.imagesBeforeText && parsed.images.isNotEmpty) {
            flushList();
            emitImages(parsed.images);
          }
          if (parsed.text.trim().isEmpty) {
            flushList();
            if (!parsed.imagesBeforeText && parsed.images.isNotEmpty) {
              emitImages(parsed.images);
            }
            if (parsed.pageBreakAfter) {
              blocks.add(
                DocBlock(id: newBlockId(), type: DocBlockType.pageBreak),
              );
            }
            continue;
          }
          if (parsed.listType != null) {
            if (pendingListType != null && pendingListType != parsed.listType) {
              flushList();
            }
            pendingListType = parsed.listType;
            pendingItems.add(parsed.text);
          } else {
            flushList();
            blocks.add(
              DocBlock(
                id: newBlockId(),
                type: parsed.type,
                text: parsed.text,
                align: parsed.align,
              ),
            );
            counters.paragraphs += 1;
            if (parsed.type.isHeading) counters.headings += 1;
          }
          if (!parsed.imagesBeforeText && parsed.images.isNotEmpty) {
            flushList();
            emitImages(parsed.images);
          }
          if (parsed.pageBreakAfter) {
            flushList();
            blocks.add(
              DocBlock(id: newBlockId(), type: DocBlockType.pageBreak),
            );
          }
        case 'tbl':
          flushList();
          final table = _parseTable(child, warnings);
          if (table != null) {
            blocks.add(table);
            counters.tables += 1;
          }
        case 'sectPr':
          break;
        default:
          // Вложенные контейнеры (например, sdt) обходим рекурсивно.
          if (child.children.whereType<XmlElement>().isNotEmpty &&
              const {'sdt', 'sdtContent', 'customXml', 'smartTag'}.contains(
                child.name.local,
              )) {
            _parseContainer(
              child,
              blocks,
              counters,
              warnings,
              numbering,
              relationships: relationships,
              media: media,
              images: images,
            );
          }
      }
    }
    flushList();
  }

  static _ParsedParagraph _parseParagraph(
    XmlElement paragraph,
    _NumberingFormats numbering, {
    required Map<String, String> relationships,
    required Map<String, List<int>> media,
    required List<DocxImageData> images,
    required Map<String, int> warnings,
  }) {
    final properties = _firstByLocal(paragraph, 'pPr');
    var align = DocAlign.left;
    final jc = properties == null ? null : _firstByLocal(properties, 'jc');
    align = switch (_attr(jc, 'val')) {
      'center' => DocAlign.center,
      'right' || 'end' => DocAlign.right,
      'both' || 'justify' => DocAlign.justify,
      _ => DocAlign.left,
    };

    final styleNode = properties == null
        ? null
        : _firstByLocal(properties, 'pStyle');
    final style = _attr(styleNode, 'val')?.toLowerCase() ?? '';
    final outline = properties == null
        ? null
        : _firstByLocal(properties, 'outlineLvl');
    final outlineLevel = int.tryParse(_attr(outline, 'val') ?? '');
    final type = _paragraphType(style, outlineLevel);

    DocBlockType? listType;
    final numberingProperties = properties == null
        ? null
        : _firstByLocal(properties, 'numPr');
    if (numberingProperties != null) {
      final numIdNode = _firstByLocal(numberingProperties, 'numId');
      final numId = _attr(numIdNode, 'val');
      final format = numbering.formatFor(numId);
      listType = format == null || format == 'bullet'
          ? DocBlockType.bulletList
          : DocBlockType.numberedList;
    }

    final runs = _parseRuns(paragraph);
    final text = runs.text;
    final hasPageBreakBefore = runs.pageBreakBefore;
    final hasPageBreakAfter = runs.pageBreakAfter;

    final paragraphImages = _extractImages(
      paragraph,
      relationships: relationships,
      media: media,
      warnings: warnings,
    );
    images.addAll(paragraphImages);
    // Картинка в начале абзаца (логотип в шапке) должна стоять до текста.
    final descendants = paragraph.descendants.whereType<XmlElement>().toList();
    final firstText = descendants.indexWhere(
      (node) => node.name.local == 't' && node.innerText.trim().isNotEmpty,
    );
    final firstImage = descendants.indexWhere(_isImageNode);
    final imagesBeforeText =
        paragraphImages.isNotEmpty &&
        (firstText < 0 || (firstImage >= 0 && firstImage < firstText));

    return _ParsedParagraph(
      text: text,
      type: listType != null ? DocBlockType.paragraph : type,
      align: align,
      listType: listType,
      pageBreakBefore: hasPageBreakBefore,
      pageBreakAfter: hasPageBreakAfter,
      images: paragraphImages,
      imagesBeforeText: imagesBeforeText,
    );
  }

  static bool _isImageNode(XmlElement node) =>
      node.name.local == 'blip' || node.name.local == 'imagedata';

  /// Собирает inline-картинки абзаца: `r:embed` → rels → `word/media/...`.
  static List<DocxImageData> _extractImages(
    XmlElement paragraph, {
    required Map<String, String> relationships,
    required Map<String, List<int>> media,
    required Map<String, int> warnings,
  }) {
    final result = <DocxImageData>[];
    for (final node in paragraph.descendants.whereType<XmlElement>()) {
      if (!_isImageNode(node)) continue;
      final id =
          _attr(node, 'embed') ?? _attr(node, 'id') ?? _attr(node, 'link');
      if (id == null || id.isEmpty) continue;
      final path = relationships[id];
      final bytes = path == null ? null : media[path];
      if (path == null || bytes == null || bytes.isEmpty) {
        warnings['image_missing'] = (warnings['image_missing'] ?? 0) + 1;
        continue;
      }
      if (result.length >= 100) {
        warnings['image_limit'] = (warnings['image_limit'] ?? 0) + 1;
        break;
      }
      result.add(
        DocxImageData(
          assetRef: '@docx:${newBlockId()}',
          fileName: _baseName(path),
          bytes: Uint8List.fromList(bytes),
          widthMm: _imageWidthMm(node),
        ),
      );
    }
    return result;
  }

  /// Ширина картинки из EMU (1 мм = 36 000 EMU), ограниченная шириной A4.
  static double _imageWidthMm(XmlElement node) {
    XmlElement? container;
    XmlNode? parent = node.parent;
    while (parent != null) {
      if (parent is XmlElement) {
        if (parent.name.local == 'drawing' || parent.name.local == 'pict') {
          container = parent;
          break;
        }
        if (parent.name.local == 'body') break;
      }
      parent = parent.parent;
    }
    final root = container ?? node;
    for (final element in root.descendants.whereType<XmlElement>()) {
      if (element.name.local != 'extent') continue;
      final cx = num.tryParse(_attr(element, 'cx') ?? '');
      if (cx != null && cx > 0) {
        return (cx / 36000).clamp(10.0, 190.0).toDouble();
      }
    }
    return 70;
  }

  /// Связи `rId → word/media/...` из `document.xml.rels`.
  static Map<String, String> _parseRelationships(List<int>? bytes) {
    if (bytes == null) return const <String, String>{};
    try {
      final document = XmlDocument.parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      final result = <String, String>{};
      for (final node in document.descendants.whereType<XmlElement>()) {
        if (node.name.local != 'Relationship') continue;
        if ((_attr(node, 'TargetMode') ?? '').toLowerCase() == 'external') {
          continue;
        }
        final id = _attr(node, 'Id');
        final target = _attr(node, 'Target');
        if (id == null || id.isEmpty || target == null || target.isEmpty) {
          continue;
        }
        final path = _mediaPath(target);
        if (path != null) result[id] = path;
      }
      return result;
    } catch (_) {
      return const <String, String>{};
    }
  }

  /// Нормализует `Target` связи в путь внутри ZIP (`word/media/...`).
  static String? _mediaPath(String target) {
    var value = target.replaceAll('\\', '/').trim();
    if (value.isEmpty) return null;
    if (value.startsWith('http://') || value.startsWith('https://')) {
      return null;
    }
    if (value.contains('%')) {
      try {
        value = Uri.decodeComponent(value);
      } catch (_) {}
    }
    final stack = <String>[];
    for (final segment in value.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (stack.isNotEmpty) stack.removeLast();
        continue;
      }
      stack.add(segment);
    }
    if (stack.isEmpty) return null;
    if (stack.first != 'word') stack.insert(0, 'word');
    final path = stack.join('/');
    return _isSupportedImageName(path) ? path : null;
  }

  static bool _isSupportedImageName(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  static String _baseName(String path) =>
      path.split('/').last.split('\\').last;

  static _RunsText _parseRuns(XmlElement paragraph) {
    final boldParts = <String>[];
    var bold = false;
    var italic = false;
    var underline = false;
    var pageBreakBefore = false;
    var pageBreakAfter = false;
    var sawPageBreak = false;
    final plain = StringBuffer();

    final runs = paragraph.descendants
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'r')
        .where((node) => !_hasAncestor(node, 'txbxContent'));
    for (final run in runs) {
      final text = StringBuffer();
      for (final child in run.children.whereType<XmlElement>()) {
        switch (child.name.local) {
          case 't':
            text.write(child.innerText);
          case 'tab':
            text.write('\t');
          case 'br':
            final isPage = _attr(child, 'type') == 'page';
            text.write(isPage ? ' ' : '\n');
            if (isPage) {
              if (plain.isEmpty) {
                pageBreakBefore = true;
              } else {
                sawPageBreak = true;
              }
            }
          case 'cr':
            text.write('\n');
        }
      }
      final content = text.toString();
      if (content.isEmpty) continue;
      final properties = _firstByLocal(run, 'rPr');
      final isBold = _toggle(properties, 'b');
      final isItalic = _toggle(properties, 'i');
      final isUnderline = _underline(properties);
      if (isBold != bold ||
          isItalic != italic ||
          isUnderline != underline) {
        bold = isBold;
        italic = isItalic;
        underline = isUnderline;
      }
      var marked = content;
      if (underline) marked = '__${marked}__';
      if (italic) marked = '*$marked*';
      if (bold) marked = '**$marked**';
      plain.write(content);
      boldParts.add(marked);
    }
    if (sawPageBreak) pageBreakAfter = true;
    return _RunsText(
      text: boldParts.join().trim(),
      pageBreakBefore: pageBreakBefore,
      pageBreakAfter: pageBreakAfter,
    );
  }

  static DocBlock? _parseTable(XmlElement table, Map<String, int> warnings) {
    final rows = <List<String>>[];
    var maxColumns = 0;
    var merged = 0;
    for (final rowNode in table.children
        .whereType<XmlElement>()
        .where((node) => node.name.local == 'tr')) {
      final row = <String>[];
      for (final cellNode in rowNode.children
          .whereType<XmlElement>()
          .where((node) => node.name.local == 'tc')) {
        final texts = <String>[];
        for (final paragraph in cellNode.descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'p')) {
          final text = _parseRuns(paragraph).text.trim();
          if (text.isNotEmpty) texts.add(text);
        }
        final cellText = texts.join('\n').trim();
        row.add(cellText);
        final properties = _firstByLocal(cellNode, 'tcPr');
        final spanNode = properties == null
            ? null
            : _firstByLocal(properties, 'gridSpan');
        final span = int.tryParse(_attr(spanNode, 'val') ?? '') ?? 1;
        final vertical = properties == null
            ? null
            : _firstByLocal(properties, 'vMerge');
        if (vertical != null) merged += 1;
        if (span > 1) {
          merged += 1;
          for (var i = 1; i < span && i < 20; i++) {
            row.add('');
          }
        }
      }
      if (row.isEmpty) continue;
      maxColumns = row.length > maxColumns ? row.length : maxColumns;
      rows.add(row);
    }
    if (rows.isEmpty) return null;
    if (maxColumns > 8) warnings['columns'] = maxColumns;
    if (merged > 0) warnings['merged'] = merged;
    for (final row in rows) {
      while (row.length < maxColumns) {
        row.add('');
      }
    }
    return DocBlock(
      id: newBlockId(),
      type: DocBlockType.table,
      rows: rows,
    );
  }

  static DocBlockType _paragraphType(String style, int? outlineLevel) {
    final numeric = int.tryParse(style);
    final level = numeric ?? (outlineLevel != null ? outlineLevel + 1 : null);
    final heading = style.contains('heading') ||
        style.contains('заголовок') ||
        style == 'title' ||
        (numeric != null && numeric >= 1 && numeric <= 6) ||
        (outlineLevel != null && outlineLevel >= 0 && outlineLevel <= 5);
    if (!heading) return DocBlockType.paragraph;
    final value = level ?? 1;
    if (value <= 1) return DocBlockType.heading1;
    if (value == 2) return DocBlockType.heading2;
    return DocBlockType.heading3;
  }

  static bool _toggle(XmlElement? properties, String name) {
    if (properties == null) return false;
    final node = _firstByLocal(properties, name);
    if (node == null) return false;
    final value = _attr(node, 'val');
    return value == null || value == '1' || value == 'true' || value == 'on';
  }

  static bool _underline(XmlElement? properties) {
    if (properties == null) return false;
    final node = _firstByLocal(properties, 'u');
    if (node == null) return false;
    final value = _attr(node, 'val');
    return value == null || value != 'none';
  }

  static bool _hasAncestor(XmlElement node, String localName) {
    XmlNode? parent = node.parent;
    while (parent != null) {
      if (parent is XmlElement && parent.name.local == localName) return true;
      parent = parent.parent;
    }
    return false;
  }

  /// Значение атрибута с учётом namespace-префикса: `val`, `w:val`.
  static String? _attr(XmlElement? node, String localName) {
    if (node == null) return null;
    final direct = node.getAttribute(localName);
    if (direct != null) return direct;
    final prefixed = node.getAttribute('w:$localName');
    if (prefixed != null) return prefixed;
    for (final attribute in node.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static XmlElement? _firstByLocal(XmlElement root, String localName) {
    for (final child in root.children.whereType<XmlElement>()) {
      if (child.name.local == localName) return child;
    }
    return null;
  }

  static String? _documentTitle(List<int>? bytes) {
    if (bytes == null) return null;
    try {
      final document = XmlDocument.parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      for (final node in document.descendants.whereType<XmlElement>()) {
        if (node.name.local == 'title') {
          final text = node.innerText.trim();
          if (text.isNotEmpty) return text;
        }
      }
    } catch (_) {}
    return null;
  }

  static String _titleFromFileName(String? fileName) {
    final name = fileName?.split('/').last.split('\\').last ?? '';
    final lower = name.toLowerCase();
    final withoutExtension = lower.endsWith('.docx')
        ? name.substring(0, name.length - 5)
        : lower.endsWith('.doc')
        ? name.substring(0, name.length - 4)
        : name;
    final trimmed = withoutExtension.trim();
    return trimmed.isEmpty ? 'Импортированный документ' : trimmed;
  }

  static String _mb(int bytes) =>
      (bytes / 1024 / 1024).toStringAsFixed(0);

  static List<DocxImportWarning> _warningList(Map<String, int> counts) => [
    if ((counts['merged'] ?? 0) > 0)
      DocxImportWarning(
        'merged',
        'Объединённые ячейки таблиц упрощены',
        count: counts['merged']!,
      ),
    if ((counts['columns'] ?? 0) > 0)
      DocxImportWarning(
        'columns',
        'В таблице больше 8 колонок — проверьте переносы',
        count: counts['columns']!,
      ),
    if ((counts['image_missing'] ?? 0) > 0)
      DocxImportWarning(
        'image_missing',
        'Часть картинок не перенесена: файла нет внутри DOCX',
        count: counts['image_missing']!,
      ),
    if ((counts['image_limit'] ?? 0) > 0)
      DocxImportWarning(
        'image_limit',
        'Слишком много картинок — перенесены первые 100',
        count: counts['image_limit']!,
      ),
    if ((counts['headers'] ?? 0) > 0)
      DocxImportWarning(
        'headers',
        'Колонтитулы не переносятся',
        count: counts['headers']!,
      ),
  ];
}

class _Counters {
  int paragraphs = 0;
  int tables = 0;
  int headings = 0;
}

class _ParsedParagraph {
  const _ParsedParagraph({
    required this.text,
    required this.type,
    required this.align,
    required this.listType,
    required this.pageBreakBefore,
    required this.pageBreakAfter,
    this.images = const <DocxImageData>[],
    this.imagesBeforeText = false,
  });

  final String text;
  final DocBlockType type;
  final DocAlign align;
  final DocBlockType? listType;
  final bool pageBreakBefore;
  final bool pageBreakAfter;
  final List<DocxImageData> images;
  final bool imagesBeforeText;
}

class _RunsText {
  const _RunsText({
    required this.text,
    required this.pageBreakBefore,
    required this.pageBreakAfter,
  });

  final String text;
  final bool pageBreakBefore;
  final bool pageBreakAfter;
}

/// Форматы списков из `word/numbering.xml`: numId → «bullet»/«decimal».
class _NumberingFormats {
  const _NumberingFormats(this._formats);

  final Map<String, String> _formats;

  String? formatFor(String? numId) =>
      numId == null ? null : _formats[numId];

  factory _NumberingFormats.parse(List<int>? bytes) {
    if (bytes == null) return const _NumberingFormats({});
    try {
      final document = XmlDocument.parse(
        utf8.decode(bytes, allowMalformed: true),
      );
      final abstractFormats = <String, String>{};
      for (final node in document.descendants.whereType<XmlElement>()) {
        if (node.name.local != 'abstractNum') continue;
        final id = _attr(node, 'abstractNumId');
        if (id == null) continue;
        final level = _firstLevel(node);
        final format = level == null
            ? ''
            : (_attr(_firstByLocal(level, 'numFmt'), 'val') ?? '');
        abstractFormats[id] = format;
      }
      final formats = <String, String>{};
      for (final node in document.descendants.whereType<XmlElement>()) {
        if (node.name.local != 'num') continue;
        final numId = _attr(node, 'numId');
        final abstractId = _attr(_firstByLocal(node, 'abstractNumId'), 'val');
        if (numId == null || abstractId == null) continue;
        formats[numId] = abstractFormats[abstractId] ?? '';
      }
      return _NumberingFormats(formats);
    } catch (_) {
      return const _NumberingFormats({});
    }
  }

  static XmlElement? _firstLevel(XmlElement node) {
    for (final child in node.children.whereType<XmlElement>()) {
      if (child.name.local == 'lvl') return child;
    }
    return null;
  }

  /// Значение атрибута с учётом namespace-префикса: `val`, `w:val`.
  static String? _attr(XmlElement? node, String localName) {
    if (node == null) return null;
    final direct = node.getAttribute(localName);
    if (direct != null) return direct;
    final prefixed = node.getAttribute('w:$localName');
    if (prefixed != null) return prefixed;
    for (final attribute in node.attributes) {
      if (attribute.name.local == localName) return attribute.value;
    }
    return null;
  }

  static XmlElement? _firstByLocal(XmlElement root, String localName) {
    for (final child in root.children.whereType<XmlElement>()) {
      if (child.name.local == localName) return child;
    }
    return null;
  }
}
