import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Что накладываем на документ.
enum SignatureRole {
  contractorSignature('Подпись подрядчика'),
  contractorStamp('Печать подрядчика'),
  clientSignature('Подпись клиента');

  const SignatureRole(this.label);
  final String label;
}

/// На какой странице PDF ставить подписи.
enum SignaturePageMode {
  last('Последняя'),
  first('Первая'),
  all('Все');

  const SignaturePageMode(this.label);
  final String label;
}

class SignatureItem {
  SignatureItem({
    this.image,
    this.enabled = true,
    this.x = 0.58,
    this.y = 0.78,
    this.width = 0.24,
  });

  Uint8List? image;
  bool enabled;
  double x;
  double y;
  double width;

  bool get ready => enabled && image != null && image!.isNotEmpty;
}

/// Настройки подписей и печати. Хранятся локально, чтобы подрядчик загрузил
/// подпись и печать один раз, а затем подписывал любые PDF.
class SignatureSettings {
  SignatureSettings._();

  static final SignatureSettings instance = SignatureSettings._();
  static const _storageKey = 'pdf_signature_settings_v1';

  bool enabled = false;
  SignaturePageMode pageMode = SignaturePageMode.last;
  final Map<SignatureRole, SignatureItem> items = {
    SignatureRole.contractorSignature: SignatureItem(
      x: 0.58,
      y: 0.80,
      width: 0.24,
    ),
    SignatureRole.contractorStamp: SignatureItem(x: 0.76, y: 0.77, width: 0.17),
    SignatureRole.clientSignature: SignatureItem(x: 0.16, y: 0.80, width: 0.27),
  };

  bool get hasAnything => enabled && items.values.any((item) => item.ready);

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      try {
        final json = jsonDecode(raw);
        if (json is! Map) return;
        enabled = json['enabled'] == true;
        pageMode = SignaturePageMode.values.firstWhere(
          (mode) => mode.name == json['pageMode'],
          orElse: () => SignaturePageMode.last,
        );
        final savedItems = json['items'];
        if (savedItems is Map) {
          for (final role in SignatureRole.values) {
            final rawItem = savedItems[role.name];
            if (rawItem is! Map) continue;
            final item = items[role]!;
            final image = rawItem['image'];
            item.image = image is String && image.isNotEmpty
                ? base64Decode(image)
                : null;
            item.enabled = rawItem['enabled'] != false;
            item.x = _double(rawItem['x'], item.x).clamp(0.0, 0.95);
            item.y = _double(rawItem['y'], item.y).clamp(0.0, 0.95);
            item.width = _double(rawItem['width'], item.width).clamp(0.05, 0.7);
          }
        }
      } catch (_) {
        // Повреждённые настройки не должны мешать сохранению документов.
      }
    } catch (_) {
      // В тестах и на платформах без SharedPreferences просто нет подписей.
    }
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'enabled': enabled,
          'pageMode': pageMode.name,
          'items': {
            for (final entry in items.entries)
              entry.key.name: {
                'image': entry.value.image == null
                    ? ''
                    : base64Encode(entry.value.image!),
                'enabled': entry.value.enabled,
                'x': entry.value.x,
                'y': entry.value.y,
                'width': entry.value.width,
              },
          },
        }),
      );
    } catch (_) {}
  }

  static double _double(Object? raw, double fallback) =>
      raw is num ? raw.toDouble() : fallback;
}

/// Накладывает подписи и печать на готовый PDF.
///
/// PDF сначала растеризуется (150 dpi), затем страницы с подписями собираются
/// заново. Так один и тот же механизм работает для чертежа, сметы, техкарты,
/// документа и отчёта клиенту — не нужно менять каждый генератор PDF.
class PdfSignatureService {
  static Future<Uint8List> applyIfEnabled(Uint8List bytes) async {
    final settings = SignatureSettings.instance;
    await settings.load();
    if (!settings.hasAnything) return bytes;
    try {
      final roles = [
        for (final role in SignatureRole.values)
          if (settings.items[role]!.ready) role,
      ];
      if (roles.isEmpty) return bytes;
      final rasters = await Printing.raster(bytes, dpi: 150).toList();
      if (rasters.isEmpty) return bytes;

      final pageImages = <Uint8List>[];
      final pageSizes = <PdfPageFormat>[];
      for (var index = 0; index < rasters.length; index++) {
        final raster = rasters[index];
        final overlay = await _overlayPage(
          raster,
          roles,
          index,
          rasters.length,
          settings,
        );
        pageImages.add(overlay);
        final widthPoints = raster.width / 150 * 72;
        final heightPoints = raster.height / 150 * 72;
        pageSizes.add(PdfPageFormat(widthPoints, heightPoints));
      }

      final document = pw.Document();
      for (var index = 0; index < pageImages.length; index++) {
        final image = pw.MemoryImage(pageImages[index]);
        document.addPage(
          pw.Page(
            pageFormat: pageSizes[index],
            margin: pw.EdgeInsets.zero,
            build: (_) => pw.Image(image, fit: pw.BoxFit.fill),
          ),
        );
      }
      return await document.save();
    } catch (_) {
      // Если растеризация недоступна, не ломаем сохранение: документ уйдёт
      // без подписи, но пользователь не потеряет работу.
      return bytes;
    }
  }

  static Future<Uint8List> _overlayPage(
    PdfRaster raster,
    List<SignatureRole> roles,
    int index,
    int pageCount,
    SignatureSettings settings,
  ) async {
    final base = await raster.toImage();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final width = raster.width.toDouble();
    final height = raster.height.toDouble();
    canvas.drawImage(base, Offset.zero, Paint());
    final pageEnabled = switch (settings.pageMode) {
      SignaturePageMode.all => true,
      SignaturePageMode.first => index == 0,
      SignaturePageMode.last => index == pageCount - 1,
    };
    if (pageEnabled) {
      for (final role in roles) {
        final item = settings.items[role]!;
        final image = await _decode(item.image!);
        final w = width * item.width;
        final h = w * image.height / image.width;
        final left = width * item.x;
        final top = height * item.y;
        final dst = Rect.fromLTWH(left, top, w, h);
        canvas.drawImageRect(
          image,
          Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
          dst,
          Paint()..filterQuality = FilterQuality.high,
        );
        image.dispose();
      }
    }
    base.dispose();
    final picture = recorder.endRecording();
    final output = await picture.toImage(raster.width, raster.height);
    try {
      final data = await output.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) throw StateError('Не удалось закодировать страницу');
      return data.buffer.asUint8List();
    } finally {
      output.dispose();
      picture.dispose();
    }
  }

  static Future<ui.Image> _decode(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }
}
