import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/services/device_scan_io.dart';

void main() {
  test('XLSX читается как таблица, а не hex', () async {
    final files = <String, String>{
      '[Content_Types].xml':
          '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>',
      'xl/workbook.xml':
          '<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheets><sheet name="Прайс" sheetId="1"/></sheets></workbook>',
      'xl/worksheets/sheet1.xml':
          '<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
              '<row r="1"><c r="A1" t="inlineStr"><is><t>Товар</t></is></c>'
              '<c r="B1" t="inlineStr"><is><t>Цена</t></is></c></row>'
              '<row r="2"><c r="A2" t="inlineStr"><is><t>Плёнка</t></is></c>'
              '<c r="B2"><v>1200</v></c></row>'
              '</sheetData></worksheet>',
    };
    final archive = Archive();
    for (final entry in files.entries) {
      final data = utf8.encode(entry.value);
      archive.addFile(ArchiveFile(entry.key, data.length, data));
    }
    final zip = ZipEncoder().encode(archive);
    final file = File(
      '${Directory.systemTemp.path}/office_preview_${DateTime.now().microsecondsSinceEpoch}.xlsx',
    );
    await file.writeAsBytes(zip);
    addTearDown(() => file.deleteSync());

    final result = await readFilePreview(file.path);
    expect(result['format'], 'xlsx');
    expect(result['binary'], isFalse);
    final content = '${result['content']}';
    expect(content, contains('Лист: Прайс'));
    expect(content, contains('Товар'));
    expect(content, contains('Плёнка'));
    expect(content, contains('1200'));
  });
}
