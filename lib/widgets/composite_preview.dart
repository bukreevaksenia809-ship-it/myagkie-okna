import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/window_params.dart';

/// Наглядная схема составного окна: основной ПВХ и второй сегмент.
///
/// Это не рабочий чертёж, а быстрый предпросмотр в панели: сторона, глубина,
/// прямой/диагональный шов и материал видны сразу, без переключения листа.
class CompositePreview extends StatelessWidget {
  const CompositePreview({super.key, required this.spec});

  final CompositeSpec spec;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 132,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFDCE3ED)),
      ),
      child: CustomPaint(
        painter: _CompositePainter(spec),
        size: Size.infinite,
      ),
    );
  }
}

class _CompositePainter extends CustomPainter {
  _CompositePainter(this.spec);

  final CompositeSpec spec;

  @override
  void paint(Canvas canvas, Size size) {
    final outer = Rect.fromLTWH(
      size.width * 0.12,
      size.height * 0.16,
      size.width * 0.76,
      size.height * 0.68,
    );
    final main = Paint()..color = const Color(0xFFDCEEF9);
    final outline = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = const Color(0xFF52708C);
    final secondColor = spec.material == FilmMaterial.screen
        ? const Color(0xFFC9D2DC)
        : const Color(0xFF9EC9E8);
    final second = Paint()..color = secondColor;

    // Глубина второго сегмента в процентах от короткой стороны — только
    // для наглядности, не для расчёта.
    final depth = (spec.depth / 1200).clamp(0.12, 0.55);
    final band = switch (spec.side) {
      EdgeSide.right => Rect.fromLTRB(
          outer.right - outer.width * depth,
          outer.top,
          outer.right,
          outer.bottom,
        ),
      EdgeSide.left => Rect.fromLTRB(
          outer.left,
          outer.top,
          outer.left + outer.width * depth,
          outer.bottom,
        ),
      EdgeSide.top => Rect.fromLTRB(
          outer.left,
          outer.top,
          outer.right,
          outer.top + outer.height * depth,
        ),
      EdgeSide.bottom => Rect.fromLTRB(
          outer.left,
          outer.bottom - outer.height * depth,
          outer.right,
          outer.bottom,
        ),
    };

    canvas.drawRect(outer, main);
    if (!spec.isDiagonal) {
      canvas.drawRect(band, second);
      // Линия шва — общая кромка.
      final seam = switch (spec.side) {
        EdgeSide.right => band.left,
        EdgeSide.left => band.right,
        EdgeSide.top => band.bottom,
        EdgeSide.bottom => band.top,
      };
      final a = switch (spec.side) {
        EdgeSide.right || EdgeSide.left => Offset(seam, outer.top),
        _ => Offset(outer.left, seam),
      };
      final b = switch (spec.side) {
        EdgeSide.right || EdgeSide.left => Offset(seam, outer.bottom),
        _ => Offset(outer.right, seam),
      };
      _dashed(canvas, a, b);
    } else {
      // Диагональ: второй сегмент — угол у выбранной стороны.
      final pivot = switch (spec.side) {
        EdgeSide.right => Offset(outer.right, outer.top + outer.height * spec.seamOffset),
        EdgeSide.left => Offset(outer.left, outer.top + outer.height * spec.seamOffset),
        EdgeSide.top => Offset(outer.left + outer.width * spec.seamOffset, outer.top),
        EdgeSide.bottom => Offset(outer.left + outer.width * spec.seamOffset, outer.bottom),
      };
      final dir = switch (spec.side) {
        EdgeSide.right => const Offset(-1, 0.9),
        EdgeSide.left => const Offset(1, 0.9),
        EdgeSide.top => const Offset(0.9, 1),
        EdgeSide.bottom => const Offset(0.9, -1),
      };
      final corner = switch (spec.side) {
        EdgeSide.right => outer.topRight,
        EdgeSide.left => outer.topLeft,
        EdgeSide.top => outer.topRight,
        EdgeSide.bottom => outer.bottomRight,
      };
      final end = corner + dir * (outer.longestSide * 1.4);
      final path = Path()
        ..moveTo(pivot.dx, pivot.dy)
        ..lineTo(end.dx, end.dy)
        ..lineTo(corner.dx, corner.dy)
        ..close();
      canvas.save();
      canvas.clipRect(outer);
      canvas.drawPath(path, second);
      canvas.restore();
      _dashed(canvas, pivot, end);
    }
    canvas.drawRect(outer, outline);
    _label(canvas, 'ПВХ', outer.center);
    _label(
      canvas,
      spec.material.label,
      band.center,
      color: const Color(0xFF274257),
    );
  }

  void _dashed(Canvas canvas, Offset a, Offset b) {
    final paint = Paint()
      ..color = const Color(0xFF4D6A84)
      ..strokeWidth = 1.6;
    final total = (b - a).distance;
    if (total < 1) return;
    final unit = (b - a) / total;
    for (var d = 0.0; d < total; d += 8) {
      canvas.drawLine(
        a + unit * d,
        a + unit * math.min(d + 4, total),
        paint,
      );
    }
  }

  void _label(Canvas canvas, String text, Offset center, {Color color = const Color(0xFF274257)}) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 120);
    painter.paint(canvas, center - Offset(painter.width / 2, painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _CompositePainter oldDelegate) =>
      oldDelegate.spec != spec;
}
