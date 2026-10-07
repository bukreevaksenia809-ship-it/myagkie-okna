import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

/// Вырезает из изображения прямоугольную область и возвращает её как PNG.
///
/// Используется для постраничного сохранения длинных листов: каждая страница
/// получает свой собственный кусок картинки, поэтому ничего не пропадает
/// и не остаётся пустых страниц.
Future<Uint8List> cropImageToPng(ui.Image source, Rect region) async {
  final left = region.left.floor().clamp(0, source.width - 1);
  final top = region.top.floor().clamp(0, source.height - 1);
  final right = region.right.ceil().clamp(left + 1, source.width);
  final bottom = region.bottom.ceil().clamp(top + 1, source.height);
  final width = right - left;
  final height = bottom - top;

  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawImageRect(
    source,
    Rect.fromLTWH(left.toDouble(), top.toDouble(), width.toDouble(), height.toDouble()),
    Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
    Paint()..filterQuality = FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final cropped = await picture.toImage(width, height);
  final data = await cropped.toByteData(format: ui.ImageByteFormat.png);
  picture.dispose();
  cropped.dispose();
  if (data == null) {
    throw StateError('Не удалось вырезать часть изображения листа');
  }
  return data.buffer.asUint8List();
}
