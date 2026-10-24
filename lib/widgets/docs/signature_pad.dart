// Подпись от руки: рисуем мышью/пальцем и отдаём PNG.
//
// Байты подписи уходят в отдельное хранилище ассетов (DocumentStore.putAsset),
// а в JSON документа остаётся только ссылка. Здесь же можно загрузить готовый
// PNG подписи или печати — он попадёт в документ как картинка.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'file_path_dialog.dart';

/// Результат диалога подписи.
class SignatureResult {
  const SignatureResult({required this.bytes, required this.fileName});

  final Uint8List bytes;
  final String fileName;
}

/// Чтение файла с диска — в браузере вернёт null.
typedef SignatureFileReader = Future<Uint8List?> Function(String path);

/// Полотно для подписи.
class SignaturePad extends StatefulWidget {
  const SignaturePad({super.key});

  @override
  State<SignaturePad> createState() => SignaturePadState();
}

class SignaturePadState extends State<SignaturePad> {
  final GlobalKey _boundaryKey = GlobalKey();
  final List<List<Offset>> _strokes = <List<Offset>>[];
  List<Offset>? _active;

  /// Есть ли хотя бы один штрих.
  bool get isEmpty => _strokes.every((stroke) => stroke.isEmpty);

  /// Очищает полотно.
  void clear() {
    setState(() {
      _strokes.clear();
      _active = null;
    });
  }

  /// Снимает полотно в PNG (прозрачный фон). null — снимать нечего.
  Future<Uint8List?> exportPng({double pixelRatio = 2}) async {
    if (isEmpty) return null;
    final object = _boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return null;
    final image = await object.toImage(pixelRatio: pixelRatio);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFCDD5E1)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanStart: (details) {
            setState(() {
              _active = <Offset>[details.localPosition];
              _strokes.add(_active!);
            });
          },
          onPanUpdate: (details) {
            final stroke = _active;
            if (stroke == null) return;
            setState(() => stroke.add(details.localPosition));
          },
          onPanEnd: (_) => _active = null,
          onPanCancel: () => _active = null,
          child: RepaintBoundary(
            key: _boundaryKey,
            child: CustomPaint(
              painter: _SignaturePainter(strokes: _strokes),
              child: const SizedBox.expand(),
            ),
          ),
        ),
      ),
    );
  }
}

class _SignaturePainter extends CustomPainter {
  _SignaturePainter({required this.strokes});

  final List<List<Offset>> strokes;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF111827)
      ..strokeWidth = 2.4
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;
    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, 1.2, paint..style = PaintingStyle.fill);
        paint.style = PaintingStyle.stroke;
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (var i = 1; i < stroke.length; i++) {
        path.lineTo(stroke[i].dx, stroke[i].dy);
      }
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _SignaturePainter oldDelegate) => true;
}

/// Диалог «нарисовать подпись / загрузить PNG».
Future<SignatureResult?> showSignatureDialog(
  BuildContext context, {
  required SignatureFileReader readFile,
}) {
  return showDialog<SignatureResult>(
    context: context,
    builder: (context) => _SignatureDialog(readFile: readFile),
  );
}

class _SignatureDialog extends StatefulWidget {
  const _SignatureDialog({required this.readFile});

  final SignatureFileReader readFile;

  @override
  State<_SignatureDialog> createState() => _SignatureDialogState();
}

class _SignatureDialogState extends State<_SignatureDialog> {
  final GlobalKey<SignaturePadState> _padKey = GlobalKey<SignaturePadState>();
  String? _error;
  bool _busy = false;

  Future<void> _insertDrawn() async {
    final bytes = await _padKey.currentState?.exportPng();
    if (bytes == null) {
      setState(() => _error = 'Сначала распишитесь на полотне');
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(
      SignatureResult(
        bytes: bytes,
        fileName: 'подпись-${DateTime.now().millisecondsSinceEpoch}.png',
      ),
    );
  }

  Future<void> _upload() async {
    final path = await askFilePath(
      context,
      title: 'PNG подписи или печати',
      hint: 'Путь к PNG',
      note: 'Файл будет сохранён в хранилище ассетов документа.',
    );
    if (path == null || !mounted) return;
    setState(() => _busy = true);
    final bytes = await widget.readFile(path);
    if (!mounted) return;
    if (bytes == null) {
      setState(() {
        _busy = false;
        _error = 'Не удалось прочитать файл по этому пути';
      });
      return;
    }
    Navigator.of(context).pop(
      SignatureResult(bytes: bytes, fileName: _baseName(path)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Подпись'),
      content: SizedBox(
        width: 560,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                TextButton.icon(
                  onPressed: _busy ? null : () => _padKey.currentState?.clear(),
                  icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                  label: const Text('Очистить'),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: _busy ? null : _upload,
                  icon: const Icon(Icons.upload_file_outlined, size: 18),
                  label: const Text('Загрузить PNG'),
                ),
                const Spacer(),
                if (_busy)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: SignaturePad(key: _padKey),
            ),
            const SizedBox(height: 6),
            Text(
              _error ?? 'Распишитесь мышью или пальцем — подпись вставится PNG.',
              style: TextStyle(
                fontSize: 12,
                color: _error == null
                    ? const Color(0xFF66748A)
                    : const Color(0xFFB42318),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _insertDrawn,
          child: const Text('Вставить'),
        ),
      ],
    );
  }
}

String _baseName(String path) =>
    path.split(RegExp(r'[/\\]')).last.replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9._-]+'), '_');
