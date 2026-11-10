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
