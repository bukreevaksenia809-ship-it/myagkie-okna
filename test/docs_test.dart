// Тесты модуля документации: шаблоны, сохранение, PDF, подпись, картинки,
// вложения DOCX и адаптивность вкладки.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/models/document.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/document_pdf.dart';
import 'package:soft_window_drawer/services/document_store.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/widgets/docs/docs_tab.dart';
import 'package:soft_window_drawer/widgets/docs/document_editor.dart';
import 'package:soft_window_drawer/widgets/docs/document_page.dart';
import 'package:soft_window_drawer/widgets/docs/signature_pad.dart';

const _window = WindowParams(
  projectName: 'Мягкое окно веранды',
  customer: 'Иванов Иван Иванович, +7 999 123-45-67',
  drawingNumber: 'МО-014',
  windowType: WindowType.lifting,
  material: FilmMaterial.tintedPvc,
  bottomWidth: 1500,
  topWidth: 1500,
  leftHeight: 2520,
  rightHeight: 2520,
  zippers: [ZipperSpec(centered: false, offsetMm: 400)],
  pocket: true,
);

const _project = OrderProject(windows: [_window]);
const _prices = PriceList.defaults();

const _company = CompanyDetails(
  name: 'ИП Петров Пётр Петрович',
  inn: '770123456789',
  ogrn: '321770000123456',
  address: 'г. Москва, ул. Тёплая, 1',
  phone: '+7 495 000-00-00',
  bank: 'ПАО «Банк», р/с 40802810000000000001',
  signer: 'Петров П. П.',
  signerPosition: 'директор',
);

CustomerDetails get _customer => CustomerDetails.fromProject(_project);

OrderDocument _doc(DocumentTemplate template) => DocumentTemplates.create(
  template,
  project: _project,
  prices: _prices,
  company: _company,
  customer: _customer,
  now: DateTime(2026, 10, 23, 10, 30),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory directory;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    directory = Directory('build/docs_test');
    if (directory.existsSync()) directory.deleteSync(recursive: true);
    directory.createSync(recursive: true);
  });

  test('акт выполненных работ автозаполняется из заказа и сметы', () {
    final document = _doc(DocumentTemplate.act);
    final estimate = Estimate.of(_project, _prices);
    final text = document.plainText;

    expect(document.title, 'Акт выполненных работ');
    expect(document.number, 'АКТ-20261023');
    expect(text, contains('Иванов Иван Иванович'));
    expect(text, contains('+7 999 123-45-67'));
    expect(text, contains('Мягкое окно веранды'));
    expect(text, contains('ИП Петров Пётр Петрович'));
    expect(text, contains('НДС 20'));
    expect(text, contains('12 месяцев'));
    expect(text, contains(formatRubles(estimate.total)));
    expect(text, contains('АКТ-20261023'));

    final table = document.blocks.firstWhere(
      (block) => block.type == DocBlockType.table,
    );
    expect(table.rows.length, greaterThan(1));
    expect(table.rows.first, contains('Наименование'));
    expect(table.rows.first, contains('Сумма'));
    expect(table.rows[1][1], isNotEmpty);
  });

  test('все шесть шаблонов создаются непустыми и с номером', () {
    for (final template in DocumentTemplate.values) {
      final document = _doc(template);
      expect(document.blocks, isNotEmpty, reason: template.name);
      expect(document.number, isNotEmpty, reason: template.name);
      expect(document.plainText.trim(), isNotEmpty, reason: template.name);
    }
    expect(_doc(DocumentTemplate.invoice).plainText, contains('СЧЁТ'));
    expect(_doc(DocumentTemplate.warranty).plainText, contains('ГАРАНТИЙНЫЙ'));
    expect(_doc(DocumentTemplate.contract).plainText, contains('ДОГОВОР'));
    expect(_doc(DocumentTemplate.offer).plainText, contains('КОММЕРЧЕСКОЕ'));
  });

  test('документы сохраняются и восстанавливаются после перезапуска', () async {
    final key = documentOrderKey(_project);
    final document = _doc(DocumentTemplate.specification);
    final store = DocumentStore(assetsDirectory: directory.path);
    final library = DocumentLibrary.empty(
      orderKey: key,
      company: _company,
      customer: _customer,
    ).addDocument(document);
    await store.saveLibrary(library);

    // Новый экземпляр хранилища — как после перезапуска приложения.
    final restored = await DocumentStore(
      assetsDirectory: directory.path,
    ).loadLibrary(key, project: _project);

    expect(restored.documents, hasLength(1));
    expect(restored.selected!.id, document.id);
    expect(restored.selected!.title, document.title);
    expect(restored.selected!.number, document.number);
    expect(restored.selected!.blocks.length, document.blocks.length);
    expect(restored.company.name, _company.name);
    expect(restored.company.inn, _company.inn);
    expect(restored.customer.name, 'Иванов Иван Иванович');
    expect(restored.customer.phone, '+7 999 123-45-67');

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(DocumentStore.librariesKey) ?? '';
    expect(raw, contains(document.id));
    expect(raw, isNot(contains('base64')));
    expect(raw.length, lessThan(80000));
  });

  test('ассеты хранятся отдельно, в JSON остаётся ссылка', () async {
    final store = DocumentStore(assetsDirectory: directory.path);
    final bytes = Uint8List.fromList([137, 80, 78, 71, 1, 2, 3, 4]);
    final ref = await store.putAsset('подпись.png', bytes);
    expect(ref, isNotEmpty);

    final document = _doc(DocumentTemplate.act).copyWith(
      blocks: [
        DocBlock(
          id: newBlockId(),
          type: DocBlockType.signature,
          assetRef: ref,
          isSignature: true,
        ),
      ],
    );
    final library = DocumentLibrary.empty(
      orderKey: documentOrderKey(_project),
      company: _company,
      customer: _customer,
    ).addDocument(document);
    await store.saveLibrary(library);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(DocumentStore.librariesKey) ?? '';
    expect(raw, contains(ref));
    expect(raw, isNot(contains(base64Encode(bytes))));
    expect(await store.readAsset(ref), bytes);
    expect(File('${directory.path}/$ref').existsSync(), isTrue);
  });

  test('дублирование и удаление документа', () {
    final document = _doc(DocumentTemplate.offer);
    final library = DocumentLibrary.empty(
      orderKey: documentOrderKey(_project),
      company: _company,
      customer: _customer,
    ).addDocument(document);

    final duplicated = library.duplicateDocument(document.id);
    expect(duplicated.documents, hasLength(2));
    expect(duplicated.documents[1].title, contains('копия'));
    expect(duplicated.documents[1].id, isNot(document.id));
    expect(duplicated.selectedId, duplicated.documents[1].id);

    final removed = duplicated.removeDocument(duplicated.documents[1].id);
    expect(removed.documents, hasLength(1));
    expect(removed.documents.single.id, document.id);
    expect(removed.selectedId, document.id);
  });

  test('DOCX: текст извлекается best-effort, мусор не роняет', () async {
    final xml = '<w:document><w:body>'
        '<w:p><w:r><w:t>Договор поставки мягких окон</w:t></w:r></w:p>'
        '<w:p><w:r><w:t>Сумма: 100 000 ₽</w:t></w:r></w:p>'
        '<w:tbl><w:tr><w:tc><w:p><w:r><w:t>Окно 1</w:t></w:r></w:p>'
        '</w:tc></w:tr></w:tbl>'
        '</w:body></w:document>';
    final docx = _storedZip('word/document.xml', utf8.encode(xml));

    final text = await DocumentStore().extractDocx(docx);
    expect(text, isNotNull);
    expect(text, contains('Договор поставки'));
    expect(text, contains('100 000'));
    expect(text, contains('Окно 1'));

    expect(await DocumentStore().extractDocx(Uint8List.fromList([1, 2, 3])), isNull);

    // Файл всё равно можно сохранить как вложение — это не ошибка.
    final store = DocumentStore(assetsDirectory: directory.path);
    final ref = await store.putAsset('договор.docx', docx);
    final attachment = DocAttachment(
      id: newBlockId(),
      fileName: 'договор.docx',
      assetRef: ref,
      kind: AttachmentKind.docx,
      sizeBytes: docx.length,
      extractedText: text,
    );
    expect(attachment.kind, AttachmentKind.docx);
    expect(attachment.hasText, isTrue);
    expect(await store.readAsset(ref), docx);
  });

  test('файл с диска читается для вложения', () async {
    final file = File('${directory.path}/скан.png');
    file.writeAsBytesSync([1, 2, 3, 4, 5]);
    final store = DocumentStore(assetsDirectory: directory.path);
    expect(await store.readLocalFile(file.path), [1, 2, 3, 4, 5]);
    expect(await store.readLocalFile('${directory.path}/нет-такого.png'), isNull);
  });

  testWidgets('PDF: байты непустые, страниц 1+ и они A4', (tester) async {
    final document = _doc(DocumentTemplate.act);
    final pagesKey = GlobalKey<DocumentPagesState>();
    tester.view.physicalSize = const Size(1000, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentPages(
            key: pagesKey,
            document: document,
            assets: (ref) async => null,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final state = pagesKey.currentState;
    expect(state, isNotNull);
    expect(state!.pageKeys.length, greaterThanOrEqualTo(1));

    final bytes = await tester.runAsync(
      () => buildDocumentPdf(pageKeys: state.pageKeys, title: document.title),
    );
    expect(bytes, isNotNull);
    expect(bytes!.length, greaterThan(1000));
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');

    final text = String.fromCharCodes(bytes);
    final boxes = RegExp(
      r'/MediaBox\s*\[\s*([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)',
    ).allMatches(text).toList();
    expect(boxes.length, state.pageKeys.length);
    for (final box in boxes) {
      final width = double.parse(box.group(3)!) - double.parse(box.group(1)!);
      final height = double.parse(box.group(4)!) - double.parse(box.group(2)!);
      expect(width, closeTo(210 * 72 / 25.4, 2));
      expect(height, closeTo(297 * 72 / 25.4, 2));
    }
  });

  testWidgets('подпись рисуется и сохраняется ассетом', (tester) async {
    final padKey = GlobalKey<SignaturePadState>();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              height: 180,
              child: SignaturePad(key: padKey),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final center = tester.getCenter(find.byType(SignaturePad));
    final gesture = await tester.startGesture(center - const Offset(60, 10));
    await gesture.moveTo(center - const Offset(20, -20));
    await gesture.moveTo(center + const Offset(20, 20));
    await gesture.moveTo(center + const Offset(60, -10));
    await gesture.up();
    await tester.pump();

    final bytes = await tester.runAsync(() => padKey.currentState!.exportPng());
    expect(bytes, isNotNull);
    final data = bytes!;
    expect(data.length, greaterThan(200));
    expect(data.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);

    // Файловые операции — только через runAsync: тест живёт в fake async.
    final stored = await tester.runAsync(() async {
      final store = DocumentStore(assetsDirectory: directory.path);
      final ref = await store.putAsset('подпись.png', data);
      return store.readAsset(ref);
    });
    expect(stored, data);
    expect(padKey.currentState!.isEmpty, isFalse);
  });

  testWidgets('картинка вставляется в документ и становится ассетом', (
    tester,
  ) async {
    final png = await tester.runAsync(
      () => _solidPng(const Color(0xFF0B62C4)),
    );
    final file = File('${directory.path}/окно.png');
    file.writeAsBytesSync(png!, flush: true);

    final document = _doc(DocumentTemplate.custom);
    var current = document;
    final assetsDir = Directory('${directory.path}/assets');
    final assetStore = DocumentStore(assetsDirectory: assetsDir.path);
    final editorKey = GlobalKey<DocumentEditorState>();

        await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DocumentEditor(
            key: editorKey,
            document: document,
            store: assetStore,
            assets: assetStore.readAsset,
            onChanged: (value) => current = value,
          ),
        ),
      ),
    );
        await tester.pumpAndSettle();
        await tester.runAsync(
      () => editorKey.currentState!.insertImageBytes('окно.png', png),
    );
        await tester.pumpAndSettle();
    
    final imageBlocks = current.blocks
        .where((block) => block.type == DocBlockType.image)
        .toList();
    expect(imageBlocks, hasLength(1));
    expect(imageBlocks.single.assetRef, isNotNull);
    final stored = await tester.runAsync(
      () => assetStore.readAsset(imageBlocks.single.assetRef),
    );
    expect(stored, isNotNull);
    expect(stored!.take(4).toList(), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('пустая вкладка создаёт акт по шаблону с автоподстановкой', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(home: Scaffold(body: DocsTab(project: _project, prices: _prices))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Документы заказа'), findsOneWidget);

    await tester.tap(find.byKey(const Key('docs-create')));
    await tester.pumpAndSettle();
    final actItem = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.text('Акт выполненных работ'),
    );
    expect(actItem, findsOneWidget);
    await tester.tap(actItem);
    await tester.pumpAndSettle();

    expect(find.byType(DocumentEditor), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(find.text('Акт выполненных работ'), findsWidgets);

    // Реквизиты и суммы уже в тексте — проверяем по отрисованным RichText.
    await tester.tap(find.byKey(const Key('docs-preview-toggle')));
    await tester.pumpAndSettle();
    final hasCustomer = find.byWidgetPredicate(
      (widget) =>
          widget is RichText &&
          widget.text.toPlainText().contains('Иванов Иван Иванович'),
    );
    expect(hasCustomer, findsWidgets);
    expect(find.byType(DocumentPage), findsWidgets);
  });

  testWidgets('вкладка документации работает на 360/390/430 и A4', (
    tester,
  ) async {
    final store = DocumentStore();
    final library = DocumentLibrary.empty(
      orderKey: documentOrderKey(_project),
      company: _company,
      customer: _customer,
    ).addDocument(_doc(DocumentTemplate.act));
    await store.saveLibrary(library);

    for (final width in [360.0, 390.0, 430.0]) {
      tester.view.physicalSize = Size(width, 820);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DocsTab(project: _project, prices: _prices),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull, reason: 'ширина $width');

      // Предпросмотр: настоящая A4-страница, вписанная в экран.
      expect(find.byType(DocumentPage), findsWidgets);
      final pageSize = tester.getSize(find.byType(DocumentPage).first);
      expect(pageSize.width, closeTo(documentA4Width, 0.5));
      expect(pageSize.height, closeTo(documentA4Height, 0.5));
      expect(pageSize.width / pageSize.height, closeTo(1 / documentA4Aspect, 0.001));

      // Редактор на узком экране не должен переполняться.
      await tester.tap(find.byKey(const Key('docs-preview-toggle')));
      await tester.pumpAndSettle();
      expect(find.byType(DocumentEditor), findsOneWidget);
      expect(tester.takeException(), isNull, reason: 'редактор $width');

      await tester.tap(find.byKey(const Key('docs-preview-toggle')));
      await tester.pumpAndSettle();
    }

    // Широкий экран: список документов слева, A4 справа.
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: DocsTab(project: _project, prices: _prices)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Документы заказа'), findsOneWidget);
    expect(find.byType(DocumentPage), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<Uint8List> _solidPng(Color color) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(const Rect.fromLTWH(0, 0, 120, 80), Paint()..color = color);
  final picture = recorder.endRecording();
  final image = await picture.toImage(120, 80);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  image.dispose();
  return data!.buffer.asUint8List();
}

/// Собирает ZIP с одним файлом без сжатия (method 0) — как минимальный DOCX.
Uint8List _storedZip(String name, List<int> content) {
  final nameBytes = utf8.encode(name);
  final local = BytesBuilder();
  local.add(_u32(0x04034b50));
  local.add(_u16(20));
  local.add(_u16(0));
  local.add(_u16(0));
  local.add(_u16(0));
  local.add(_u16(0));
  local.add(_u32(0));
  local.add(_u32(content.length));
  local.add(_u32(content.length));
  local.add(_u16(nameBytes.length));
  local.add(_u16(0));
  local.add(nameBytes);
  local.add(content);

  final central = BytesBuilder();
  central.add(_u32(0x02014b50));
  central.add(_u16(20));
  central.add(_u16(20));
  central.add(_u16(0));
  central.add(_u16(0));
  central.add(_u16(0));
  central.add(_u16(0));
  central.add(_u32(0));
  central.add(_u32(content.length));
  central.add(_u32(content.length));
  central.add(_u16(nameBytes.length));
  central.add(_u16(0));
  central.add(_u16(0));
  central.add(_u16(0));
  central.add(_u16(0));
  central.add(_u32(0));
  central.add(_u32(0));
  central.add(nameBytes);

  final localBytes = local.takeBytes();
  final centralBytes = central.takeBytes();
  final end = BytesBuilder();
  end.add(_u32(0x06054b50));
  end.add(_u16(0));
  end.add(_u16(0));
  end.add(_u16(1));
  end.add(_u16(1));
  end.add(_u32(centralBytes.length));
  end.add(_u32(localBytes.length));
  end.add(_u16(0));

  final result = BytesBuilder()
    ..add(localBytes)
    ..add(centralBytes)
    ..add(end.takeBytes());
  return result.takeBytes();
}

Uint8List _u16(int value) => Uint8List(2)..buffer.asByteData().setUint16(0, value, Endian.little);

Uint8List _u32(int value) => Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.little);
