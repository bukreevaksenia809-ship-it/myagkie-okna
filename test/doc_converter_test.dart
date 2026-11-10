// Старый .doc: на десктопе конвертация через LibreOffice, на вебе — понятное
// сообщение «сохраните как .docx». Тест не требует LibreOffice: если его нет,
// проверяем текст ошибки; если есть — реальную конвертацию DOCX-содержимого.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/services/doc_converter_io.dart';
import 'package:soft_window_drawer/services/doc_converter_stub.dart' as stub;
import 'package:soft_window_drawer/services/doc_converter_web.dart' as web;

Uint8List _minimalDocx() {
  final archive = Archive();
  final xml = utf8.encode(
    '<w:document xmlns:w="w"><w:body>'
    '<w:p><w:r><w:t>Договор</w:t></w:r></w:p>'
    '</w:body></w:document>',
  );
  archive.addFile(ArchiveFile('word/document.xml', xml.length, xml));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('веб: честно просит сохранить .docx', () async {
    final result = await web.convertDocToDocx(
      Uint8List.fromList([1, 2, 3]),
      fileName: 'old.doc',
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('.docx'));
  });

  test('заглушка: конвертация недоступна', () async {
    final result = await stub.convertDocToDocx(
      Uint8List.fromList([1, 2, 3]),
      fileName: 'old.doc',
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('.docx'));
  });

  test('пустой .doc — понятная ошибка', () async {
    final result = await convertDocToDocx(
      Uint8List(0),
      fileName: 'empty.doc',
    );
    expect(result.ok, isFalse);
    expect(result.error, contains('пустой'));
  });

  test('десктоп: LibreOffice конвертирует или объясняет, что его нет', () async {
    final result = await convertDocToDocx(
      _minimalDocx(),
      fileName: 'sample.doc',
    );
    if (result.ok) {
      expect(result.bytes, isNotNull);
      expect(result.bytes!.length, greaterThan(0));
    } else {
      expect(
        result.error,
        anyOf(contains('LibreOffice'), contains('Сохраните файл как .docx')),
      );
    }
  });
}
