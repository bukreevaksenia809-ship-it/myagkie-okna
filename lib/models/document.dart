// Документы заказа: блоки «как в Word», шаблоны, вложения и реквизиты.
//
// Модель без Flutter UI: её можно сериализовать в shared_preferences, сравнить
// в тестах и пересобрать на любой платформе. Картинки и подписи здесь НЕ
// хранятся байтами: у блока есть только ссылка [DocBlock.assetRef], а сами
// байты лежат в отдельном хранилище ассетов (см. services/document_store.dart).
//
// Текст блока — обычная строка с inline-разметкой:
//   **жирный**, *курсив*, __подчёркнутый__.
// Разметку разбирает редактор и A4-предпросмотр; сама модель остаётся чистой.

import 'dart:math' as math;

import '../models/order_project.dart';
import '../models/window_params.dart';
import '../services/estimate.dart';

/// Шаблон нового документа. Шесть обязательных клиентских документов плюс
/// пустой документ для ручного творчества.
enum DocumentTemplate {
  act('Акт выполненных работ', 'АКТ', 'Приёмка работ по заказу'),
  contract('Договор подряда', 'ДОГОВОР', 'Подряд и поставка изделий'),
  offer('Коммерческое предложение', 'КП', 'Цены и сроки для клиента'),
  specification('Спецификация', 'СПЕЦ', 'Ведомость изделий и цен'),
  warranty('Гарантийный талон', 'ГАРАНТИЯ', 'Условия гарантии'),
  invoice('Счёт на оплату', 'СЧЁТ', 'Реквизиты и сумма к оплате'),
  custom('Свой документ', 'ДОК', 'Пустой лист с заголовком');

  const DocumentTemplate(this.title, this.code, this.description);

  /// Название документа и шаблона.
  final String title;

  /// Код в номере документа: «АКТ-20261023».
  final String code;

  /// Пояснение в списке шаблонов.
  final String description;
}

/// Выравнивание абзаца. Хранится строкой в JSON, поэтому имя enum стабильно.
enum DocAlign {
  left('Слева'),
  center('По центру'),
  right('Справа'),
  justify('По ширине');

  const DocAlign(this.label);

  final String label;
}

/// Тип блока документа.
enum DocBlockType {
  heading1('Заголовок 1'),
  heading2('Заголовок 2'),
  heading3('Заголовок 3'),
  paragraph('Абзац'),
  bulletList('Маркированный список'),
  numberedList('Нумерованный список'),
  table('Таблица'),
  image('Изображение'),
  signature('Подпись'),
  pageBreak('Разрыв страницы');

  const DocBlockType(this.label);

  final String label;

  bool get isHeading =>
      this == DocBlockType.heading1 ||
      this == DocBlockType.heading2 ||
      this == DocBlockType.heading3;

  bool get isList =>
      this == DocBlockType.bulletList || this == DocBlockType.numberedList;

  bool get isText =>
      this == DocBlockType.paragraph || isHeading || isList;
}

/// Блок документа. Один блок — один абзац, список, таблица, картинка или
/// разрыв страницы. Жирность/курсив/подчёркивание живут внутри [text],
/// выравнивание — в [align].
class DocBlock {
  const DocBlock({
    required this.id,
    required this.type,
    this.text = '',
    this.align = DocAlign.left,
    this.rows = const <List<String>>[],
    this.assetRef,
    this.widthMm = 70,
    this.isSignature = false,
  });

  final String id;
  final DocBlockType type;

  /// Текст блока. У списка пункты разделены переводами строк.
  final String text;

  final DocAlign align;

  /// Строки таблицы. Первая строка — шапка.
  final List<List<String>> rows;

  /// Ссылка на ассет в отдельном хранилище (изображение или подпись).
  final String? assetRef;

  /// Ширина картинки на странице, мм.
  final double widthMm;

  /// Это подпись/печать, а не обычная картинка: подпись рисуется компактнее.
  final bool isSignature;

  bool get isEmptyText => text.trim().isEmpty;

  DocBlock copyWith({
    String? id,
    DocBlockType? type,
    String? text,
    DocAlign? align,
    List<List<String>>? rows,
    String? assetRef,
    bool clearAsset = false,
    double? widthMm,
    bool? isSignature,
  }) =>
      DocBlock(
        id: id ?? this.id,
        type: type ?? this.type,
        text: text ?? this.text,
        align: align ?? this.align,
        rows: rows ?? this.rows,
        assetRef: clearAsset ? null : (assetRef ?? this.assetRef),
        widthMm: widthMm ?? this.widthMm,
        isSignature: isSignature ?? this.isSignature,
      );

  /// Пустая таблица 3 × 3 с шапкой.
  factory DocBlock.emptyTable({String? id, int columns = 3, int rows = 3}) {
    final safeColumns = columns.clamp(1, 8);
    final safeRows = rows.clamp(1, 200);
    return DocBlock(
      id: id ?? newBlockId(),
      type: DocBlockType.table,
      rows: [
        for (var r = 0; r < safeRows; r++)
          [
            for (var c = 0; c < safeColumns; c++)
              r == 0 ? 'Колонка ${c + 1}' : '',
          ],
      ],
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'type': type.name,
    'text': text,
    'align': align.name,
    if (rows.isNotEmpty) 'rows': [for (final row in rows) [...row]],
    if (assetRef != null) 'assetRef': assetRef,
    'widthMm': widthMm,
    if (isSignature) 'isSignature': true,
  };

  factory DocBlock.fromJson(Map<String, dynamic> json) {
    final rawType = json['type'];
    final type = DocBlockType.values
        .where((value) => value.name == rawType)
        .firstOrNull;
    final rawAlign = json['align'];
    final align = DocAlign.values
        .where((value) => value.name == rawAlign)
        .firstOrNull;
    return DocBlock(
      id: _string(json['id']).isEmpty ? newBlockId() : _string(json['id']),
      type: type ?? DocBlockType.paragraph,
      text: _string(json['text']),
      align: align ?? DocAlign.left,
      rows: _rows(json['rows']),
      assetRef: _string(json['assetRef']).isEmpty ? null : _string(json['assetRef']),
      widthMm: _double(json['widthMm'], 70).clamp(10, 190).toDouble(),
      isSignature: json['isSignature'] == true,
    );
  }
}

/// Вложение к документу: PDF, скан, картинка, DOCX или текст.
///
/// [assetRef] — ссылка на отдельное хранилище ассетов, а не base64 в JSON.
/// Для DOCX в [extractedText] лежит best-effort текст (если удалось извлечь).
class DocAttachment {
  const DocAttachment({
    required this.id,
    required this.fileName,
    required this.assetRef,
    required this.kind,
    required this.sizeBytes,
    this.extractedText,
  });

  final String id;
  final String fileName;
  final String assetRef;
  final AttachmentKind kind;
  final int sizeBytes;

  /// Извлечённый текст DOCX (может быть null, если не удалось).
  final String? extractedText;

  String get sizeLabel {
    if (sizeBytes < 1024) return '$sizeBytes Б';
    if (sizeBytes < 1024 * 1024) {
      return '${(sizeBytes / 1024).toStringAsFixed(1)} КБ';
    }
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} МБ';
  }

  bool get hasText => (extractedText ?? '').trim().isNotEmpty;

  DocAttachment copyWith({String? extractedText}) => DocAttachment(
    id: id,
    fileName: fileName,
    assetRef: assetRef,
    kind: kind,
    sizeBytes: sizeBytes,
    extractedText: extractedText ?? this.extractedText,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'assetRef': assetRef,
    'kind': kind.name,
    'sizeBytes': sizeBytes,
    if (hasText) 'extractedText': extractedText,
  };

  factory DocAttachment.fromJson(Map<String, dynamic> json) {
    final name = _string(json['fileName']);
    final rawKind = json['kind'];
    final kind = AttachmentKind.values
        .where((value) => value.name == rawKind)
        .firstOrNull;
    return DocAttachment(
      id: _string(json['id']).isEmpty ? newBlockId() : _string(json['id']),
      fileName: name.isEmpty ? 'файл' : name,
      assetRef: _string(json['assetRef']),
      kind: kind ?? AttachmentKind.fromFileName(name),
      sizeBytes: _int(json['sizeBytes'], 0),
      extractedText: _string(json['extractedText']).isEmpty
          ? null
          : _string(json['extractedText']),
    );
  }
}

/// Вид вложения — от него зависит иконка и способ предпросмотра.
enum AttachmentKind {
  pdf('PDF'),
  image('Изображение'),
  docx('DOCX'),
  text('Текст'),
  other('Файл');

  const AttachmentKind(this.label);

  final String label;

  static AttachmentKind fromFileName(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.pdf')) return AttachmentKind.pdf;
    if (lower.endsWith('.docx')) return AttachmentKind.docx;
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.bmp')) {
      return AttachmentKind.image;
    }
    if (lower.endsWith('.txt') || lower.endsWith('.md')) {
      return AttachmentKind.text;
    }
    return AttachmentKind.other;
  }

  bool get isImage => this == AttachmentKind.image;
}

/// Реквизиты компании-исполнителя. Пустое поле подставляется как прочерк,
/// чтобы документ не выглядел поломанным.
class CompanyDetails {
  const CompanyDetails({
    this.name = '',
    this.inn = '',
    this.ogrn = '',
    this.address = '',
    this.phone = '',
    this.bank = '',
    this.signer = '',
    this.signerPosition = '',
    this.logoAssetRef = '',
  });

  final String name;
  final String inn;
  final String ogrn;
  final String address;
  final String phone;
  final String bank;
  final String signer;
  final String signerPosition;

  /// Ссылка на файл логотипа в хранилище ассетов (пусто — логотипа нет).
  final String logoAssetRef;

  bool get hasLogo => logoAssetRef.trim().isNotEmpty;

  bool get isEmpty =>
      name.trim().isEmpty &&
      inn.trim().isEmpty &&
      address.trim().isEmpty &&
      phone.trim().isEmpty;

  String get displayName => _or(name, 'Исполнитель');

  /// Подпись в документах: «Иванов И. И., директор».
  String get signerLabel {
    final parts = [
      _or(signer, ''),
      _or(signerPosition, ''),
    ].where((part) => part.isNotEmpty).toList();
    return parts.isEmpty ? '—' : parts.join(', ');
  }

  /// Строки реквизитов для договора, счёта и акта.
  List<String> get requisites => [
    'Исполнитель: $displayName',
    if (inn.trim().isNotEmpty) 'ИНН: ${inn.trim()}',
    if (ogrn.trim().isNotEmpty) 'ОГРН: ${ogrn.trim()}',
    if (address.trim().isNotEmpty) 'Адрес: ${address.trim()}',
    if (phone.trim().isNotEmpty) 'Телефон: ${phone.trim()}',
    if (bank.trim().isNotEmpty) 'Банк: ${bank.trim()}',
  ];

  CompanyDetails copyWith({
    String? name,
    String? inn,
    String? ogrn,
    String? address,
    String? phone,
    String? bank,
    String? signer,
    String? signerPosition,
    String? logoAssetRef,
  }) =>
      CompanyDetails(
        name: name ?? this.name,
        inn: inn ?? this.inn,
        ogrn: ogrn ?? this.ogrn,
        address: address ?? this.address,
        phone: phone ?? this.phone,
        bank: bank ?? this.bank,
        signer: signer ?? this.signer,
        signerPosition: signerPosition ?? this.signerPosition,
        logoAssetRef: logoAssetRef ?? this.logoAssetRef,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'inn': inn,
    'ogrn': ogrn,
    'address': address,
    'phone': phone,
    'bank': bank,
    'signer': signer,
    'signerPosition': signerPosition,
    'logoAssetRef': logoAssetRef,
  };

  factory CompanyDetails.fromJson(Map<String, dynamic> json) => CompanyDetails(
    name: _string(json['name']),
    inn: _string(json['inn']),
    ogrn: _string(json['ogrn']),
    address: _string(json['address']),
    phone: _string(json['phone']),
    bank: _string(json['bank']),
    signer: _string(json['signer']),
    signerPosition: _string(json['signerPosition']),
    logoAssetRef: _string(json['logoAssetRef']),
  );
}

/// Клиент и объект заказа. В заказе есть только строка `customer`, поэтому
/// телефон из неё извлекается best-effort и его можно поправить в настройках.
class CustomerDetails {
  const CustomerDetails({
    this.name = '',
    this.phone = '',
    this.address = '',
  });

  final String name;
  final String phone;

  /// Адрес/объект (по умолчанию — projectName заказа).
  final String address;

  String get displayName => _or(name, 'Заказчик');
  String get displayAddress => _or(address, 'объект не указан');
  String get displayPhone => _or(phone, '—');

  factory CustomerDetails.fromProject(OrderProject project) {
    final window = project.windows.isEmpty
        ? const WindowParams()
        : project.windows.first;
    final customer = window.customer.trim();
    final match = RegExp(r'(\+?\d[\d\s\-()]{7,}\d)').firstMatch(customer);
    final phone = match == null ? '' : match.group(1)!.trim();
    final name = phone.isEmpty
        ? customer
        : customer.replaceAll(phone, '').trim().replaceAll(RegExp(r'[,;]+$'), '').trim();
    return CustomerDetails(
      name: name,
      phone: phone,
      address: window.projectName.trim(),
    );
  }

  CustomerDetails copyWith({String? name, String? phone, String? address}) =>
      CustomerDetails(
        name: name ?? this.name,
        phone: phone ?? this.phone,
        address: address ?? this.address,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'phone': phone,
    'address': address,
  };

  factory CustomerDetails.fromJson(Map<String, dynamic> json) =>
      CustomerDetails(
        name: _string(json['name']),
        phone: _string(json['phone']),
        address: _string(json['address']),
      );
}

/// Один документ заказа.
class OrderDocument {
  const OrderDocument({
    required this.id,
    required this.title,
    required this.number,
    required this.template,
    required this.createdAt,
    required this.updatedAt,
    this.blocks = const <DocBlock>[],
    this.attachments = const <DocAttachment>[],
  });

  final String id;
  final String title;
  final String number;
  final DocumentTemplate template;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<DocBlock> blocks;
  final List<DocAttachment> attachments;

  bool get isEmpty => blocks.isEmpty && attachments.isEmpty;

  /// Весь текст документа — для поиска, тестов и вставки в письмо.
  String get plainText => [
    title,
    number,
    for (final block in blocks)
      switch (block.type) {
        DocBlockType.table => block.rows
            .map((row) => row.join(' | '))
            .join('\n'),
        DocBlockType.image ||
        DocBlockType.signature => block.text,
        DocBlockType.pageBreak => '',
        _ => block.text,
      },
    for (final attachment in attachments)
      [attachment.fileName, attachment.extractedText ?? ''].join('\n'),
  ].where((part) => part.trim().isNotEmpty).join('\n');

  OrderDocument copyWith({
    String? id,
    String? title,
    String? number,
    DocumentTemplate? template,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<DocBlock>? blocks,
    List<DocAttachment>? attachments,
  }) =>
      OrderDocument(
        id: id ?? this.id,
        title: title ?? this.title,
        number: number ?? this.number,
        template: template ?? this.template,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        blocks: blocks ?? this.blocks,
        attachments: attachments ?? this.attachments,
      );

  /// Копия документа с новым id и названием «(копия)».
  OrderDocument duplicate({DateTime? now, String? title}) {
    final moment = now ?? DateTime.now();
    return OrderDocument(
      id: newDocumentId(),
      title: title ?? '${this.title} (копия)',
      number: number,
      template: template,
      createdAt: moment,
      updatedAt: moment,
      blocks: [
        for (final block in blocks) block.copyWith(id: newBlockId()),
      ],
      attachments: [
        for (final attachment in attachments)
          DocAttachment(
            id: newBlockId(),
            fileName: attachment.fileName,
            assetRef: attachment.assetRef,
            kind: attachment.kind,
            sizeBytes: attachment.sizeBytes,
            extractedText: attachment.extractedText,
          ),
      ],
    );
  }

  /// Действия с блоками — чтобы редактор не плодил одинаковые списки руками.
  OrderDocument replaceBlock(int index, DocBlock block) {
    if (index < 0 || index >= blocks.length) return this;
    final next = [...blocks];
    next[index] = block;
    return copyWith(blocks: next, updatedAt: DateTime.now());
  }

  OrderDocument insertBlock(int index, DocBlock block) {
    final next = [...blocks];
    next.insert(index.clamp(0, next.length), block);
    return copyWith(blocks: next, updatedAt: DateTime.now());
  }

  OrderDocument removeBlock(int index) {
    if (index < 0 || index >= blocks.length) return this;
    final next = [...blocks]..removeAt(index);
    return copyWith(blocks: next, updatedAt: DateTime.now());
  }

  OrderDocument moveBlock(int index, int delta) {
    final target = index + delta;
    if (index < 0 || index >= blocks.length) return this;
    if (target < 0 || target >= blocks.length) return this;
    final next = [...blocks];
    final block = next.removeAt(index);
    next.insert(target, block);
    return copyWith(blocks: next, updatedAt: DateTime.now());
  }

  OrderDocument addAttachment(DocAttachment attachment) => copyWith(
    attachments: [...attachments, attachment],
    updatedAt: DateTime.now(),
  );

  OrderDocument removeAttachment(String attachmentId) => copyWith(
    attachments: attachments
        .where((attachment) => attachment.id != attachmentId)
        .toList(),
    updatedAt: DateTime.now(),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'number': number,
    'template': template.name,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'blocks': [for (final block in blocks) block.toJson()],
    'attachments': [
      for (final attachment in attachments) attachment.toJson(),
    ],
  };

  factory OrderDocument.fromJson(Map<String, dynamic> json) {
    final rawTemplate = json['template'];
    final template = DocumentTemplate.values
        .where((value) => value.name == rawTemplate)
        .firstOrNull;
    final createdAt = DateTime.tryParse(_string(json['createdAt']));
    return OrderDocument(
      id: _string(json['id']).isEmpty ? newDocumentId() : _string(json['id']),
      title: _string(json['title']).isEmpty
          ? (template ?? DocumentTemplate.custom).title
          : _string(json['title']),
      number: _string(json['number']),
      template: template ?? DocumentTemplate.custom,
      createdAt: createdAt ?? DateTime.now(),
      updatedAt: DateTime.tryParse(_string(json['updatedAt'])) ??
          createdAt ??
          DateTime.now(),
      blocks: [
        for (final item in _mapList(json['blocks']))
          DocBlock.fromJson(item),
      ],
      attachments: [
        for (final item in _mapList(json['attachments']))
          DocAttachment.fromJson(item),
      ],
    );
  }
}

/// Все документы одного заказа + реквизиты компании и клиента.
class DocumentLibrary {
  const DocumentLibrary({
    required this.orderKey,
    required this.documents,
    required this.company,
    required this.customer,
    this.selectedId,
  });

  final String orderKey;
  final List<OrderDocument> documents;
  final CompanyDetails company;
  final CustomerDetails customer;
  final String? selectedId;

  factory DocumentLibrary.empty({
    required String orderKey,
    required CompanyDetails company,
    required CustomerDetails customer,
  }) =>
      DocumentLibrary(
        orderKey: orderKey,
        documents: const [],
        company: company,
        customer: customer,
      );

  OrderDocument? get selected {
    if (documents.isEmpty) return null;
    for (final document in documents) {
      if (document.id == selectedId) return document;
    }
    return documents.first;
  }

  bool get isEmpty => documents.isEmpty;

  DocumentLibrary select(String id) => DocumentLibrary(
    orderKey: orderKey,
    documents: documents,
    company: company,
    customer: customer,
    selectedId: documents.any((document) => document.id == id) ? id : selectedId,
  );

  DocumentLibrary addDocument(OrderDocument document) => DocumentLibrary(
    orderKey: orderKey,
    documents: [...documents, document],
    company: company,
    customer: customer,
    selectedId: document.id,
  );

  DocumentLibrary replaceDocument(OrderDocument document) => DocumentLibrary(
    orderKey: orderKey,
    documents: [
      for (final item in documents)
        if (item.id == document.id) document else item,
    ],
    company: company,
    customer: customer,
    selectedId: selectedId,
  );

  DocumentLibrary duplicateDocument(String id, {DateTime? now}) {
    final index = documents.indexWhere((document) => document.id == id);
    if (index < 0) return this;
    final copy = documents[index].duplicate(now: now);
    final next = [...documents]..insert(index + 1, copy);
    return DocumentLibrary(
      orderKey: orderKey,
      documents: next,
      company: company,
      customer: customer,
      selectedId: copy.id,
    );
  }

  DocumentLibrary renameDocument(String id, String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty) return this;
    return replaceDocument(
      documents
          .firstWhere((document) => document.id == id)
          .copyWith(title: trimmed, updatedAt: DateTime.now()),
    );
  }

  DocumentLibrary removeDocument(String id) {
    final index = documents.indexWhere((document) => document.id == id);
    if (index < 0) return this;
    final next = [...documents]..removeAt(index);
    final nextSelected = selectedId == id
        ? (next.isEmpty
              ? null
              : next[math.min(index, next.length - 1)].id)
        : selectedId;
    return DocumentLibrary(
      orderKey: orderKey,
      documents: next,
      company: company,
      customer: customer,
      selectedId: nextSelected,
    );
  }

  DocumentLibrary withCompany(CompanyDetails company) => DocumentLibrary(
    orderKey: orderKey,
    documents: documents,
    company: company,
    customer: customer,
    selectedId: selectedId,
  );

  DocumentLibrary withCustomer(CustomerDetails customer) => DocumentLibrary(
    orderKey: orderKey,
    documents: documents,
    company: company,
    customer: customer,
    selectedId: selectedId,
  );

  Map<String, dynamic> toJson() => {
    'orderKey': orderKey,
    'selectedId': selectedId,
    'company': company.toJson(),
    'customer': customer.toJson(),
    'documents': [for (final document in documents) document.toJson()],
  };

  factory DocumentLibrary.fromJson(Map<String, dynamic> json) {
    final docs = [
      for (final item in _mapList(json['documents']))
        OrderDocument.fromJson(item),
    ];
    return DocumentLibrary(
      orderKey: _string(json['orderKey']),
      documents: docs,
      company: CompanyDetails.fromJson(_map(json['company'])),
      customer: CustomerDetails.fromJson(_map(json['customer'])),
      selectedId: _string(json['selectedId']).isEmpty
          ? (docs.isEmpty ? null : docs.first.id)
          : _string(json['selectedId']),
    );
  }
}

/// Ключ заказа для хранения документов.
///
/// В заказе нет отдельного id, поэтому берём номер чертежа, а если его нет —
/// название объекта и заказчика. Этого достаточно, чтобы документы разных
/// заказов не смешивались и переживали перезапуск.
String documentOrderKey(OrderProject project) {
  final window = project.windows.isEmpty
      ? const WindowParams()
      : project.windows.first;
  final source = window.drawingNumber.trim().isNotEmpty
      ? window.drawingNumber.trim()
      : '${window.projectName} ${window.customer}'.trim();
  final cleaned = source
      .replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9-]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  return cleaned.isEmpty ? 'заказ' : cleaned;
}

/// Счётчик для id внутри процесса: в тестах два документа, созданные в одну
/// микросекунду, всё равно получают разные id.
int _idCounter = 0;

int _nextId() => ++_idCounter + DateTime.now().microsecondsSinceEpoch;

String newDocumentId() => 'doc_${_nextId()}';

String newBlockId() => 'block_${_nextId()}';

/// Шаблоны документов и автоподстановка из заказа/сметы.
///
/// Один вход [create] — один готовый документ. Все суммы и позиции берутся из
/// [Estimate.of], реквизиты — из [CompanyDetails], клиент/телефон/объект — из
/// [CustomerDetails] (по умолчанию они выводятся из заказа).
class DocumentTemplates {
  DocumentTemplates._();

  /// Гарантия по умолчанию, месяцев.
  static const int warrantyMonths = 12;

  /// Создаёт документ по шаблону.
  static OrderDocument create(
    DocumentTemplate template, {
    required OrderProject project,
    required PriceList prices,
    required CompanyDetails company,
    required CustomerDetails customer,
    DateTime? now,
  }) {
    final moment = now ?? DateTime.now();
    final estimate = Estimate.of(project, prices);
    final number = '${template.code}-${_dateStamp(moment)}';
    final date = formatDocDate(moment);
    final blocks = switch (template) {
      DocumentTemplate.act => _act(
        project: project,
        estimate: estimate,
        company: company,
        customer: customer,
        number: number,
        date: date,
      ),
      DocumentTemplate.contract => _contract(
        project: project,
        estimate: estimate,
        company: company,
        customer: customer,
        number: number,
        date: date,
      ),
      DocumentTemplate.offer => _offer(
        project: project,
        estimate: estimate,
        company: company,
        customer: customer,
        number: number,
        date: date,
      ),
      DocumentTemplate.specification => _specification(
        project: project,
        estimate: estimate,
        company: company,
        customer: customer,
        number: number,
        date: date,
      ),
      DocumentTemplate.warranty => _warranty(
        project: project,
        company: company,
        customer: customer,
        number: number,
        date: date,
      ),
      DocumentTemplate.invoice => _invoice(
        project: project,
        estimate: estimate,
        company: company,
        customer: customer,
        number: number,
        date: date,
      ),
      DocumentTemplate.custom => [
        DocBlock(
          id: newBlockId(),
          type: DocBlockType.heading1,
          text: 'НОВЫЙ ДОКУМЕНТ',
          align: DocAlign.center,
        ),
        DocBlock(
          id: newBlockId(),
          type: DocBlockType.paragraph,
          text: 'Начните печатать здесь.',
        ),
      ],
    };

    return OrderDocument(
      id: newDocumentId(),
      title: template.title,
      number: number,
      template: template,
      createdAt: moment,
      updatedAt: moment,
      blocks: blocks,
    );
  }

  /// Таблица позиций сметы для акта, договора, КП, спецификации и счёта.
  static DocBlock estimateTable(Estimate estimate, {String? id}) => DocBlock(
    id: id ?? newBlockId(),
    type: DocBlockType.table,
    rows: [
      const ['№', 'Наименование', 'Кол-во', 'Ед.', 'Цена', 'Сумма'],
      for (var i = 0; i < estimate.lines.length; i++)
        [
          '${i + 1}',
          estimate.lines[i].title,
          estimate.lines[i].quantityLabel,
          estimate.lines[i].unit,
          estimate.lines[i].unitPriceLabel,
          estimate.lines[i].amountLabel,
        ],
    ],
  );

  /// Строки «Итого / НДС / Всего к оплате» для текста документа.
  static List<String> totalsLines(Estimate estimate) => [
    'Итого: ${formatRubles(estimate.subtotal)}',
    if (estimate.installationAmount > 0)
      'Монтаж: ${formatRubles(estimate.installationAmount)}',
    if (estimate.markupAmount > 0)
      'Наценка: ${formatRubles(estimate.markupAmount)}',
    if (estimate.discountAmount > 0)
      'Скидка: ${formatRubles(estimate.discountAmount)}',
    if (estimate.vatPercent > 0)
      'НДС ${_percent(estimate.vatPercent)} %: '
          '${formatRubles(estimate.vatAmount)}'
    else
      'Без НДС',
    'Всего к оплате: ${formatRubles(estimate.total)}',
  ];

  static List<DocBlock> _act({
    required OrderProject project,
    required Estimate estimate,
    required CompanyDetails company,
    required CustomerDetails customer,
    required String number,
    required String date,
  }) =>
      [
        _h1('АКТ ВЫПОЛНЕННЫХ РАБОТ'),
        _p('№ $number от $date', align: DocAlign.center),
        _p('Заказчик: ${customer.displayName}'),
        _p('Телефон: ${customer.displayPhone}'),
        _p('Объект: ${customer.displayAddress}'),
        _p(company.requisites.join('\n')),
        _p(
          'Настоящий акт составлен о том, что Исполнитель выполнил, а Заказчик '
          'принял следующие работы по изготовлению и установке мягких окон:',
        ),
        estimateTable(estimate),
        _p(totalsLines(estimate).join('\n')),
        _p(
          'Гарантия на изделия — $warrantyMonths месяцев с даты подписания '
          'акта. Претензии по качеству принимаются при предъявлении акта.',
        ),
        _p('Работы выполнены в полном объёме, претензий к качеству нет.'),
        _p('Исполнитель: ${company.signerLabel} ____________________'),
        _p('Заказчик: ${customer.displayName} ____________________'),
        _p('Дата: $date'),
      ];

  static List<DocBlock> _contract({
    required OrderProject project,
    required Estimate estimate,
    required CompanyDetails company,
    required CustomerDetails customer,
    required String number,
    required String date,
  }) =>
      [
        _h1('ДОГОВОР ПОДРЯДА № $number'),
        _p('г. Москва', align: DocAlign.left),
        _p('Дата: $date'),
        _p('Исполнитель: ${company.requisites.join('\n')}'),
        _p(
          'Заказчик: ${customer.displayName}, телефон ${customer.displayPhone}, '
          'объект: ${customer.displayAddress}.',
        ),
        _h2('1. Предмет договора'),
        _p(
          'Исполнитель обязуется изготовить и передать Заказчику мягкие окна '
          '(далее — Изделия) по спецификации ниже, а Заказчик — принять и '
          'оплатить Изделия и работы.',
        ),
        _h2('2. Спецификация и стоимость'),
        estimateTable(estimate),
        _p(totalsLines(estimate).join('\n')),
        _h2('3. Порядок оплаты'),
        _p(
          'Оплата производится в рублях: аванс 50 % после подписания договора, '
          'остаток — после приёмки работ.',
        ),
        _h2('4. Сроки и приёмка'),
        _p(
          'Срок изготовления — 5–10 рабочих дней с момента замера и оплаты '
          'аванса. Приёмка оформляется актом выполненных работ.',
        ),
        _h2('5. Гарантия'),
        _p(
          'Гарантия на Изделия — $warrantyMonths месяцев при соблюдении правил '
          'эксплуатации. Естественный износ, механические повреждения и '
          'самостоятельный ремонт гарантией не покрываются.',
        ),
        _h2('6. Подписи сторон'),
        _p('Исполнитель: ${company.signerLabel} ____________________'),
        _p('Заказчик: ${customer.displayName} ____________________'),
      ];

  static List<DocBlock> _offer({
    required OrderProject project,
    required Estimate estimate,
    required CompanyDetails company,
    required CustomerDetails customer,
    required String number,
    required String date,
  }) =>
      [
        _h1('КОММЕРЧЕСКОЕ ПРЕДЛОЖЕНИЕ № $number'),
        _p('от $date', align: DocAlign.center),
        _p(
          '${company.displayName}\n${company.requisites.skip(1).join('\n')}',
        ),
        _p(
          'Заказчик: ${customer.displayName}\nТелефон: ${customer.displayPhone}\n'
          'Объект: ${customer.displayAddress}',
        ),
        _p(
          'Предлагаем изготовление и монтаж мягких окон по следующей '
          'спецификации:',
        ),
        estimateTable(estimate),
        _p(totalsLines(estimate).join('\n')),
        _p(
          'Срок изготовления — 5–10 рабочих дней. Гарантия — '
          '$warrantyMonths месяцев. Предложение действительно 14 дней.',
        ),
        _p('С уважением, ${company.signerLabel} ____________________'),
      ];

  static List<DocBlock> _specification({
    required OrderProject project,
    required Estimate estimate,
    required CompanyDetails company,
    required CustomerDetails customer,
    required String number,
    required String date,
  }) =>
      [
        _h1('СПЕЦИФИКАЦИЯ № $number'),
        _p('к договору от $date', align: DocAlign.center),
        _p('Заказчик: ${customer.displayName}'),
        _p('Объект: ${customer.displayAddress}'),
        estimateTable(estimate),
        _p(totalsLines(estimate).join('\n')),
        _p('Исполнитель: ${company.signerLabel} ____________________'),
        _p('Заказчик: ${customer.displayName} ____________________'),
      ];

  static List<DocBlock> _warranty({
    required OrderProject project,
    required CompanyDetails company,
    required CustomerDetails customer,
    required String number,
    required String date,
  }) {
    final windows = project.windows;
    return [
      _h1('ГАРАНТИЙНЫЙ ТАЛОН № $number'),
      _p('Дата выдачи: $date', align: DocAlign.center),
      _p('Владелец: ${customer.displayName}'),
      _p('Телефон: ${customer.displayPhone}'),
      _p('Объект: ${customer.displayAddress}'),
      _p('Изготовитель: ${company.displayName}'),
      _p(
        'Гарантийный срок на изделия — $warrantyMonths месяцев с даты '
        'подписания акта выполненных работ.',
      ),
      DocBlock(
        id: newBlockId(),
        type: DocBlockType.table,
        rows: [
          const ['№', 'Изделие', 'Размер', 'Кол-во'],
          for (var i = 0; i < windows.length; i++)
            [
              '${i + 1}',
              windows[i].material.label,
              '${formatMm(windows[i].bottomWidth)} × '
                  '${formatMm(windows[i].leftHeight)} ${unitSuffix()}',
              '1',
            ],
        ],
      ),
      _p(
        'Гарантия не распространяется на повреждения, возникшие из-за '
        'механических ударов, пожара, затопления, самостоятельного ремонта, '
        'а также на естественный износ и загрязнения.',
      ),
      _p(
        'При наступлении гарантийного случая свяжитесь с исполнителем по '
        'телефону ${company.phone.trim().isEmpty ? '—' : company.phone.trim()}.',
      ),
      _p('Подпись владельца: ____________________'),
      _p('Подпись изготовителя: ${company.signerLabel} ____________________'),
    ];
  }

  static List<DocBlock> _invoice({
    required OrderProject project,
    required Estimate estimate,
    required CompanyDetails company,
    required CustomerDetails customer,
    required String number,
    required String date,
  }) =>
      [
        _h1('СЧЁТ НА ОПЛАТУ № $number'),
        _p('от $date', align: DocAlign.center),
        _h2('Поставщик'),
        _p(company.requisites.join('\n')),
        _h2('Покупатель'),
        _p(
          '${customer.displayName}\nТелефон: ${customer.displayPhone}\n'
          'Объект: ${customer.displayAddress}',
        ),
        estimateTable(estimate),
        _p(totalsLines(estimate).join('\n')),
        _p(
          'Всего к оплате: ${formatRubles(estimate.total)}.\n'
          'Оплата означает согласие с условиями поставки. Назначение платежа: '
          'оплата по счёту № $number.',
        ),
        _p('Руководитель: ${company.signerLabel} ____________________'),
        _p('Бухгалтер: ____________________'),
      ];

  static DocBlock _h1(String text) => DocBlock(
    id: newBlockId(),
    type: DocBlockType.heading1,
    text: text,
    align: DocAlign.center,
  );

  static DocBlock _p(String text, {DocAlign align = DocAlign.left}) => DocBlock(
    id: newBlockId(),
    type: DocBlockType.paragraph,
    text: text,
    align: align,
  );

  static DocBlock _h2(String text) => DocBlock(
    id: newBlockId(),
    type: DocBlockType.heading2,
    text: text,
  );
}

/// Дата в документах: «23.10.2026».
String formatDocDate(DateTime moment) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(moment.day)}.${two(moment.month)}.${moment.year}';
}

String _dateStamp(DateTime moment) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${moment.year}${two(moment.month)}${two(moment.day)}';
}

String _percent(double value) {
  if (value == value.roundToDouble()) return value.toStringAsFixed(0);
  return value.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '')
      .replaceAll('.', ',');
}

String _or(String value, String fallback) =>
    value.trim().isEmpty ? fallback : value.trim();

String _string(Object? value) => value is String ? value : '';

int _int(Object? value, int fallback) =>
    value is num ? value.toInt() : fallback;

double _double(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

Map<String, dynamic> _map(Object? value) =>
    value is Map ? value.cast<String, dynamic>() : <String, dynamic>{};

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List) return const [];
  return [
    for (final item in value)
      if (item is Map) item.cast<String, dynamic>(),
  ];
}

List<List<String>> _rows(Object? value) {
  if (value is! List) return const [];
  final rows = <List<String>>[];
  for (final row in value) {
    if (row is! List) continue;
    rows.add([for (final cell in row) cell is String ? cell : '$cell']);
  }
  return rows;
}

// Расширение, чтобы `firstOrNull` работал без пакета collection.
extension<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
