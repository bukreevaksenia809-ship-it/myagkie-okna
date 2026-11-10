import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/document.dart';
import 'package:soft_window_drawer/services/docx_import.dart';
import 'package:soft_window_drawer/services/imported_docx_store.dart';

Uint8List _docx({
  required String documentXml,
  String? numberingXml,
  String? title,
  String? relsXml,
  Map<String, List<int>> media = const {},
  Map<String, List<int>> extraFiles = const {},
}) {
  final archive = Archive();
  final document = utf8.encode(documentXml);
  archive.addFile(
    ArchiveFile('word/document.xml', document.length, document),
  );
  if (numberingXml != null) {
    final numbering = utf8.encode(numberingXml);
    archive.addFile(
      ArchiveFile('word/numbering.xml', numbering.length, numbering),
    );
  }
  if (title != null) {
    final core = utf8.encode(
      '<cp:coreProperties xmlns:cp="cp" xmlns:dc="dc">'
      '<dc:title>$title</dc:title></cp:coreProperties>',
    );
    archive.addFile(ArchiveFile('docProps/core.xml', core.length, core));
  }
  if (relsXml != null) {
    final rels = utf8.encode(relsXml);
    archive.addFile(
      ArchiveFile('word/_rels/document.xml.rels', rels.length, rels),
    );
  }
  for (final entry in media.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  for (final entry in extraFiles.entries) {
    archive.addFile(ArchiveFile(entry.key, entry.value.length, entry.value));
  }
  final encoded = ZipEncoder().encode(archive);
  return Uint8List.fromList(encoded);
}

Uint8List _sample() => _docx(
  title: 'Договор на мягкие окна',
  numberingXml: '''
    <w:numbering xmlns:w="w">
      <w:abstractNum w:abstractNumId="0">
        <w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl>
      </w:abstractNum>
      <w:abstractNum w:abstractNumId="1">
        <w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl>
      </w:abstractNum>
      <w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>
      <w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>
    </w:numbering>
  ''',
  documentXml: '''
    <w:document xmlns:w="w">
      <w:body>
        <w:p>
          <w:pPr><w:pStyle w:val="Heading1"/></w:pPr>
          <w:r><w:rPr><w:b/></w:rPr><w:t>Договор подряда</w:t></w:r>
        </w:p>
        <w:p>
          <w:pPr><w:jc w:val="center"/></w:pPr>
          <w:r><w:t>Заказчик: </w:t></w:r>
          <w:r><w:rPr><w:b/></w:rPr><w:t>{{клиент}}</w:t></w:r>
        </w:p>
        <w:p>
          <w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr>
          <w:r><w:t>Первый пункт</w:t></w:r>
        </w:p>
        <w:p>
          <w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr>
          <w:r><w:t>Второй пункт</w:t></w:r>
        </w:p>
        <w:p>
          <w:pPr><w:numPr><w:numId w:val="2"/></w:numPr></w:pPr>
          <w:r><w:t>Нумерованный пункт</w:t></w:r>
        </w:p>
        <w:tbl>
          <w:tr>
            <w:tc><w:p><w:r><w:t>Товар</w:t></w:r></w:p></w:tc>
            <w:tc><w:p><w:r><w:t>Сумма</w:t></w:r></w:p></w:tc>
          </w:tr>
          <w:tr>
            <w:tc><w:p><w:r><w:t>Мягкое окно</w:t></w:r></w:p></w:tc>
            <w:tc><w:p><w:r><w:t>{{сумма}}</w:t></w:r></w:p></w:tc>
          </w:tr>
        </w:tbl>
        <w:p>
          <w:r><w:br w:type="page"/></w:r>
        </w:p>
        <w:p><w:r><w:t>Подпись: {{номер}}</w:t></w:r></w:p>
      </w:body>
    </w:document>
  ''',
);

void main() {
  test('DOCX: заголовок, абзац, списки, таблица и подстановка', () {
    final bytes = _sample();
    expect(DocxImportService.looksLikeDocx(bytes), isTrue);
    final result = DocxImportService.parse(bytes, fileName: 'договор.docx');
    expect(result.error, isNull);
    expect(result.title, 'Договор на мягкие окна');
    expect(result.blocks.any((b) => b.type == DocBlockType.heading1), isTrue);
    expect(
      result.blocks.any(
        (b) => b.type == DocBlockType.bulletList && b.text.contains('Первый'),
      ),
      isTrue,
    );
    expect(
      result.blocks.any(
        (b) =>
            b.type == DocBlockType.numberedList &&
            b.text.contains('Нумерованный'),
      ),
      isTrue,
    );
    final table = result.blocks.firstWhere(
      (b) => b.type == DocBlockType.table,
    );
    expect(table.rows.first, ['Товар', 'Сумма']);
    expect(table.rows[1].first, 'Мягкое окно');
    expect(
      result.blocks.any((b) => b.type == DocBlockType.pageBreak),
      isTrue,
    );

    final substituted = applyDocxPlaceholdersToBlocks(
      result.blocks,
      const DocxPlaceholderValues(
        client: 'Елена',
        order: 'Веранда',
        date: '10.11.2026',
        amount: '120 000,00 ₽',
        number: 'ДОК-20261110',
      ),
    );
    final text = substituted
        .where((b) => b.type != DocBlockType.table)
        .map((b) => b.text)
        .join('\n');
    expect(text, contains('Елена'));
    expect(text, contains('ДОК-20261110'));
    expect(text, isNot(contains('{{')));
    final filledTable = substituted.firstWhere(
      (b) => b.type == DocBlockType.table,
    );
    expect(filledTable.rows[1][1], '120 000,00 ₽');
  });

  test('Плейсхолдеры терпимы к регистру и пробелам', () {
    const values = DocxPlaceholderValues(client: 'Иван', number: '42');
    expect(applyDocxPlaceholders('{{ КЛИЕНТ }}', values), 'Иван');
    expect(applyDocxPlaceholders('{{номер}}', values), '42');
    expect(
      applyDocxPlaceholders('{{неизвестно}}', values),
      '{{неизвестно}}',
    );
  });

  test('Битый файл возвращает понятную ошибку, а не бросает', () {
    final result = DocxImportService.parse(
      Uint8List.fromList([1, 2, 3, 4, 5]),
      fileName: 'битый.docx',
    );
    expect(result.ok, isFalse);
    expect(result.error, isNotNull);
    expect(result.title, 'битый');
  });

  test('Не DOCX и слишком большой файл отклоняются', () {
    final notDocx = DocxImportService.parse(
      Uint8List.fromList(utf8.encode('просто текст')),
      fileName: 'файл.docx',
    );
    expect(notDocx.ok, isFalse);
    expect(notDocx.error, contains('DOCX'));

    final huge = Uint8List(docxMaxBytes + 1)..[0] = 0x50;
    final tooBig = DocxImportService.parse(huge, fileName: 'большой.docx');
    expect(tooBig.ok, isFalse);
    expect(tooBig.error, contains('МБ'));
  });

  test('Шаблон переживает сохранение в JSON', () {
    final result = DocxImportService.parse(_sample(), fileName: 'a.docx');
    final now = DateTime(2026, 11, 10, 12);
    final template = ImportedDocxTemplate(
      id: 't1',
      title: result.title,
      fileName: 'a.docx',
      importedAt: now,
      updatedAt: now,
      blocks: result.blocks,
      warnings: result.warnings,
      sizeBytes: 1234,
    );
    final restored = ImportedDocxTemplate.fromJson(template.toJson());
    expect(restored.title, template.title);
    expect(restored.blocks.length, template.blocks.length);
    expect(
      restored.blocks.where((b) => b.type == DocBlockType.table).single.rows[0],
      ['Товар', 'Сумма'],
    );
    expect(restored.sizeLabel, '1,2 КБ');
  });

  test('шаблон сохраняется, переименовывается и удаляется', () async {
    SharedPreferences.setMockInitialValues({});
    final store = ImportedDocxStore();
    final now = DateTime(2026, 11, 10, 12);
    final template = ImportedDocxTemplate(
      id: 't1',
      title: 'Договор',
      fileName: 'dogovor.docx',
      importedAt: now,
      updatedAt: now,
      blocks: const [
        DocBlock(id: 'b1', type: DocBlockType.paragraph, text: 'Текст'),
      ],
      sizeBytes: 2048,
    );
    expect(await store.load(), isEmpty);
    await store.upsert(template);
    var loaded = await store.load();
    expect(loaded, hasLength(1));
    expect(loaded.single.title, 'Договор');
    expect(loaded.single.blocks.single.text, 'Текст');

    await store.rename('t1', 'Новый договор');
    loaded = await store.load();
    expect(loaded.single.title, 'Новый договор');

    await store.remove('t1');
    expect(await store.load(), isEmpty);
  });

  test('DOCX с картинкой: логотип на своём месте, ширина из EMU', () {
    // 1×1 PNG — достаточно, чтобы проверить извлечение и размеры.
    const png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    final bytes = _docx(
      relsXml:
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId5" '
          'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
          'Target="media/image1.png"/></Relationships>',
      media: {'word/media/image1.png': png},
      documentXml: '''
        <w:document xmlns:w="w" xmlns:r="r" xmlns:wp="wp" xmlns:a="a" xmlns:pic="pic">
          <w:body>
            <w:p>
              <w:r>
                <w:drawing>
                  <wp:inline>
                    <wp:extent cx="1800000" cy="900000"/>
                    <a:graphic><a:graphicData>
                      <pic:pic><pic:blipFill>
                        <a:blip r:embed="rId5"/>
                      </pic:blipFill></pic:pic>
                    </a:graphicData></a:graphic>
                  </wp:inline>
                </w:drawing>
              </w:r>
            </w:p>
            <w:p><w:r><w:t>Текст после логотипа</w:t></w:r></w:p>
          </w:body>
        </w:document>
      ''',
    );
    final result = DocxImportService.parse(bytes, fileName: 'logo.docx');
    expect(result.error, isNull);
    expect(result.images, hasLength(1));
    expect(result.images.single.widthMm, closeTo(50, 0.01));
    expect(result.images.single.bytes, isNotEmpty);
    final imageBlock = result.blocks.firstWhere(
      (block) => block.type == DocBlockType.image,
    );
    expect(imageBlock.assetRef, startsWith('@docx:'));
    // Картинка стоит до текста: логотип в шапке не уезжает вниз.
    expect(result.blocks.first.type, DocBlockType.image);
    expect(result.blocks.last.text, contains('Текст после логотипа'));

    // После сохранения в ассетах заглушка заменяется реальной ссылкой.
    final assigned = applyDocxImageAssets(result.blocks, {
      imageBlock.assetRef!: 'logo_saved.png',
    });
    expect(
      assigned.firstWhere((block) => block.type == DocBlockType.image).assetRef,
      'logo_saved.png',
    );
  });

  test('логотип из колонтитула Word попадает в начало шаблона', () {
    const png = <int>[
      0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
      0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
      0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
      0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
      0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
      0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
    ];
    final headerXml = utf8.encode('''
      <w:hdr xmlns:w="w" xmlns:r="r" xmlns:wp="wp" xmlns:a="a" xmlns:pic="pic">
        <w:p><w:r><w:drawing><wp:inline>
          <wp:extent cx="720000" cy="720000"/>
          <a:graphic><a:graphicData><pic:pic><pic:blipFill>
            <a:blip r:embed="rId1"/>
          </pic:blipFill></pic:pic></a:graphicData></a:graphic>
        </wp:inline></w:drawing></w:r></w:p>
      </w:hdr>
    ''');
    final headerRels = utf8.encode(
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" '
      'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
      'Target="media/logo.png"/></Relationships>',
    );
    final bytes = _docx(
      documentXml:
          '<w:document xmlns:w="w"><w:body>'
          '<w:p><w:r><w:t>Договор</w:t></w:r></w:p>'
          '</w:body></w:document>',
      extraFiles: {
        'word/header1.xml': headerXml,
        'word/_rels/header1.xml.rels': headerRels,
      },
      media: {'word/media/logo.png': png},
    );
    final result = DocxImportService.parse(bytes, fileName: 'header.docx');
    expect(result.error, isNull);
    expect(result.images, hasLength(1));
    expect(result.images.single.widthMm, closeTo(20, 0.01));
    expect(result.blocks.first.type, DocBlockType.image);
    expect(result.blocks.last.text, contains('Договор'));
  });

  test('DOCX с картинкой переживает сохранение шаблона', () async {
    SharedPreferences.setMockInitialValues({});
    final template = ImportedDocxTemplate(
      id: 'img1',
      title: 'С логотипом',
      fileName: 'logo.docx',
      importedAt: DateTime(2026, 11, 10),
      updatedAt: DateTime(2026, 11, 10),
      blocks: const [
        DocBlock(
          id: 'b-image',
          type: DocBlockType.image,
          assetRef: 'saved-logo.png',
          widthMm: 50,
        ),
        DocBlock(id: 'b-text', type: DocBlockType.paragraph, text: 'Текст'),
      ],
      sizeBytes: 1024,
    );
    await ImportedDocxStore().upsert(template);
    final loaded = await ImportedDocxStore().load();
    expect(loaded.single.blocks.first.assetRef, 'saved-logo.png');
    expect(loaded.single.blocks.first.widthMm, 50);
  });

  test('Пустой документ — ошибка «нет текста»', () {
    final bytes = _docx(
      documentXml:
          '<w:document xmlns:w="w"><w:body>'
          '<w:p><w:r><w:t> </w:t></w:r></w:p>'
          '</w:body></w:document>',
    );
    final result = DocxImportService.parse(bytes);
    expect(result.ok, isFalse);
    expect(result.error, contains('нет текста'));
  });
}
