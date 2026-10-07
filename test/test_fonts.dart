// Вспомогательный загрузчик системного шрифта для тестов, которые
// рендерят изображение: в тестовом окружении своего шрифта нет, и без этого
// текст превращается в квадратики тестового шрифта.
import 'dart:io';

import 'package:flutter/services.dart';

const _fontCandidates = [
  '/System/Library/Fonts/Supplemental/Arial.ttf',
  '/Library/Fonts/Arial Unicode.ttf',
  '/System/Library/Fonts/Supplemental/Verdana.ttf',
];

/// Семейство, под которым регистрируется системный шрифт в тестах.
const testFontFamily = 'Roboto';

Future<void> loadRealFonts() async {
  for (final path in _fontCandidates) {
    final file = File(path);
    if (!file.existsSync()) continue;
    final bytes = file.readAsBytesSync();
    for (final family in const [
      testFontFamily,
      'Arial',
      '.AppleSystemUIFont',
      'Helvetica',
    ]) {
      final loader = FontLoader(family)
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await loader.load();
    }
    return;
  }
}
