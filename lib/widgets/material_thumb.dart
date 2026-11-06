import 'package:flutter/material.dart';

/// Мини-превью материала: полупрозрачное полотно ПВХ или серая сетка скрина.
///
/// Рисуется программно, чтобы картинки одинаково выглядели в панели прайса и
/// в документе сметы, не требуя PNG в assets.
class MaterialThumb extends StatelessWidget {
  const MaterialThumb({super.key, required this.screen});

  final bool screen;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: MaterialThumbPainter(screen: screen));
  }
}

/// Painter мини-превью: ПВХ — голубоватое полотно с бликом, скрин — сетка.
class MaterialThumbPainter extends CustomPainter {
  const MaterialThumbPainter({required this.screen});

  final bool screen;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF9AA7B8);
    if (screen) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFFE1E6EC));
      final mesh = Paint()
        ..color = const Color(0xFF6D7A8A).withValues(alpha: 0.6)
        ..strokeWidth = 0.7;
      for (var x = 0.0; x <= size.width; x += 5) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), mesh);
      }
      for (var y = 0.0; y <= size.height; y += 5) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), mesh);
      }
      canvas.drawRect(rect.deflate(0.5), border);
      return;
    }
    // ПВХ: голубоватое полупрозрачное полотно с бликом.
    canvas.drawRect(rect, Paint()..color = const Color(0x3359A6D8));
    final sheenRect = Rect.fromLTWH(
      size.width * 0.08,
      0,
      size.width * 0.34,
      size.height,
    );
    final sheen = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
      ).createShader(sheenRect);
    final path = Path()
      ..moveTo(size.width * 0.08, size.height)
      ..lineTo(size.width * 0.42, 0)
      ..lineTo(size.width * 0.58, 0)
      ..lineTo(size.width * 0.24, size.height)
      ..close();
    canvas.drawPath(path, sheen);
    canvas.drawRect(rect.deflate(0.5), border);
  }

  @override
  bool shouldRepaint(covariant MaterialThumbPainter oldDelegate) =>
      oldDelegate.screen != screen;
}
