// Превью «до/после» для коричневых полос на косом окне.
//
// «До» — реконструкция прежнего алгоритма: полоса каждой стороны резалась
// на сегменты, и на каждом сегменте заново рисовались градиент, фактура и
// строчка. «После» — один четырёхугольник на сторону (edgeBandQuads).
// Картинки нужны, чтобы глазами сравнить: сегментов быть не должно.
//
// Запуск: flutter test test/kosoe_band_preview_test.dart
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/window_geometry.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/widgets/window_painter.dart';

import 'test_fonts.dart';

const _oblique = WindowParams(
  projectName: 'Косое окно, разные высоты',
  drawingNumber: 'КОС-Б',
  bottomWidth: 1200,
  topWidth: 1200,
  leftHeight: 1000,
  rightHeight: 1400,
  rollBottom: 100,
  rollRight: 100,
  rollTop: 100,
  rollLeft: 100,
  weldOverlapMm: 5,
);

/// Только полоса тента: сравнение «сегментами» и «одним четырёхугольником».
class _BandPreviewPainter extends CustomPainter {
  _BandPreviewPainter({
    required this.spec,
    required this.layout,
    required this.segmented,
    required this.title,
    required this.fontFamily,
  });

  final WindowSpec spec;
  final DrawingLayout layout;
  final bool segmented;
  final String title;
  final String? fontFamily;

  static const Color _brown = Color(0xFF8A5A2B);
  static const Color _brownDark = Color(0xFF4C3016);
  static const Color _brownLight = Color(0xFFC08A50);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = Colors.white);

    // Полотно — светлая плёнка, чтобы полоса читалась как на чертеже.
    final film = Path();
    final outer = spec.layers.outer;
    for (var i = 0; i < outer.length; i++) {
      final point = layout.toPxPoint(outer[i]);
      if (i == 0) {
        film.moveTo(point.dx, point.dy);
      } else {
        film.lineTo(point.dx, point.dy);
      }
    }
    film.close();
    canvas.drawPath(film, Paint()..color = const Color(0x335AA7E8));

    for (final band in edgeBandQuads(spec, widths: _widths(spec))) {
      if (segmented) {
        _paintSegmented(canvas, band);
      } else {
        _paintSingle(canvas, band);
      }
    }

    // Наружный контур.
    final outline = Path();
    for (var i = 0; i < outer.length; i++) {
      final point = layout.toPxPoint(outer[i]);
      if (i == 0) {
        outline.moveTo(point.dx, point.dy);
      } else {
        outline.lineTo(point.dx, point.dy);
      }
    }
    outline.close();
    canvas.drawPath(
      outline,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..color = const Color(0xFF1B1F27),
    );

    final painter = TextPainter(
      text: TextSpan(
        text: title,
        style: TextStyle(
          color: const Color(0xFF1B1F27),
          fontSize: 16,
          fontWeight: FontWeight.w700,
          fontFamily: fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    painter.paint(canvas, const Offset(24, 18));
  }

  List<double> _widths(WindowSpec spec) => [
    for (var i = 0; i < spec.layers.outer.length; i++)
      spec.layers.finishedWidthFor(
        spec.layers.sideOfEdge(spec.layers.outer, i),
      ),
  ];

  ({Offset p0, Offset p1, Offset p2, Offset p3, double angle, double length})
  _local(EdgeBandQuad band) {
    final start = layout.toPxPoint(band.outerStart);
    final finish = layout.toPxPoint(band.outerEnd);
    final innerStart = layout.toPxPoint(band.innerStart);
    final innerFinish = layout.toPxPoint(band.innerEnd);
    final direction = finish - start;
    final length = direction.distance;
    final angle = math.atan2(direction.dy, direction.dx);
    final cos = math.cos(angle);
    final sin = math.sin(angle);
    Offset toLocal(Offset screen) {
      final dx = screen.dx - start.dx;
      final dy = screen.dy - start.dy;
      return Offset(dx * cos + dy * sin, -dx * sin + dy * cos);
    }

    return (
      p0: Offset.zero,
      p1: toLocal(finish),
      p2: toLocal(innerFinish),
      p3: toLocal(innerStart),
      angle: angle,
      length: length,
    );
  }

  Path _quadPath(
    Offset p0,
    Offset p1,
    Offset p2,
    Offset p3, {
    double from = 0,
    double to = 1,
  }) {
    final a = Offset.lerp(p0, p1, from)!;
    final b = Offset.lerp(p0, p1, to)!;
    final c = Offset.lerp(p3, p2, to)!;
    final d = Offset.lerp(p3, p2, from)!;
    return Path()
      ..moveTo(a.dx, a.dy)
      ..lineTo(b.dx, b.dy)
      ..lineTo(c.dx, c.dy)
      ..lineTo(d.dx, d.dy)
      ..close();
  }

  void _paintSingle(Canvas canvas, EdgeBandQuad band) {
    final local = _local(band);
    final yMin = math.min(
      math.min(local.p0.dy, local.p1.dy),
      math.min(local.p2.dy, local.p3.dy),
    );
    final yMax = math.max(
      math.max(local.p0.dy, local.p1.dy),
      math.max(local.p2.dy, local.p3.dy),
    );
    final start = layout.toPxPoint(band.outerStart);
    canvas.save();
    canvas.translate(start.dx, start.dy);
    canvas.rotate(local.angle);
    canvas.drawPath(
      _quadPath(local.p0, local.p1, local.p2, local.p3),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: const [_brownDark, _brown, _brownLight, _brown, _brownDark],
          stops: const [0, 0.2, 0.45, 0.75, 1],
        ).createShader(
          Rect.fromLTRB(0, yMin, local.length, math.max(yMax, yMin + 1)),
        ),
    );
    // Одна строчка по сгибу.
    _dashedLine(
      canvas,
      Offset(0, (yMin + yMax) / 2),
      Offset(local.length, (yMin + yMax) / 2),
      Paint()
        ..color = _brownDark.withValues(alpha: 0.6)
        ..strokeWidth = 1.1,
      dash: 8,
      gap: 5,
    );
    canvas.restore();
  }

  void _paintSegmented(Canvas canvas, EdgeBandQuad band) {
    final local = _local(band);
    final yMin = math.min(
      math.min(local.p0.dy, local.p1.dy),
      math.min(local.p2.dy, local.p3.dy),
    );
    final yMax = math.max(
      math.max(local.p0.dy, local.p1.dy),
      math.max(local.p2.dy, local.p3.dy),
    );
    // Именно так «до» и получалось: на каждый кусок — свой градиент и шов.
    final segments = math.max(4, (local.length / 18).round());
    final start = layout.toPxPoint(band.outerStart);
    for (var i = 0; i < segments; i++) {
      final from = i / segments;
      final to = (i + 1) / segments;
      canvas.save();
      canvas.translate(start.dx, start.dy);
      canvas.rotate(local.angle);
      final path = _quadPath(
        local.p0,
        local.p1,
        local.p2,
        local.p3,
        from: from,
        to: to,
      );
      canvas.drawPath(
        path,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [_brownDark, _brown, _brownLight, _brown, _brownDark],
            stops: const [0, 0.2, 0.45, 0.75, 1],
          ).createShader(
            Rect.fromLTRB(
              0,
              yMin,
              math.max(local.length * (to - from), 1),
              math.max(yMax, yMin + 1),
            ),
          ),
      );
      // Поперечная кромка сегмента — «частокол».
      final edge = Offset.lerp(local.p0, local.p1, to)!;
      canvas.drawLine(
        edge,
        Offset.lerp(local.p3, local.p2, to)!,
        Paint()
          ..color = _brownDark.withValues(alpha: 0.7)
          ..strokeWidth = 1,
      );
      // Строчка повторяется на каждом сегменте.
      _dashedLine(
        canvas,
        Offset(local.length * from, (yMin + yMax) / 2),
        Offset(local.length * to, (yMin + yMax) / 2),
        Paint()
          ..color = _brownDark.withValues(alpha: 0.55)
          ..strokeWidth = 1,
        dash: 3,
        gap: 3,
      );
      canvas.restore();
    }
  }

  void _dashedLine(
    Canvas canvas,
    Offset from,
    Offset to,
    Paint paint, {
    required double dash,
    required double gap,
  }) {
    final direction = to - from;
    final length = direction.distance;
    if (length < 0.01) return;
    final unit = direction / length;
    var position = 0.0;
    while (position < length) {
      final end = math.min(position + dash, length);
      canvas.drawLine(from + unit * position, from + unit * end, paint);
      position = end + gap;
    }
  }

  @override
  bool shouldRepaint(covariant _BandPreviewPainter oldDelegate) =>
      oldDelegate.segmented != segmented || oldDelegate.spec != spec;
}

void main() {
  setUpAll(loadRealFonts);

  testWidgets('пишет kosoe-do.png и kosoe-posle.png', (tester) async {
    final spec = WindowSpec.of(_oblique);
    const denominator = 12.5;
    const pixelRatio = 4.0;
    final scale = (96 / 25.4) / denominator;
    final size = Size(
      168 + spec.geometry.spanX * scale,
      136 + spec.geometry.spanY * scale,
    );
    final layout = DrawingLayout.forScaleDenominator(
      size: size,
      geometry: spec.geometry,
      scaleDenominator: denominator,
    );
    final directory = Directory('build/preview')..createSync(recursive: true);

    for (final segmented in [true, false]) {
      final bytes = await tester.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(
          recorder,
          Offset.zero & Size(size.width * pixelRatio, size.height * pixelRatio),
        );
        canvas.scale(pixelRatio);
        _BandPreviewPainter(
          spec: spec,
          layout: layout,
          segmented: segmented,
          title: segmented
              ? 'ДО: полоса собрана из сегментов'
              : 'ПОСЛЕ: один четырёхугольник на сторону',
          fontFamily: testFontFamily,
        ).paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(
          (size.width * pixelRatio).round(),
          (size.height * pixelRatio).round(),
        );
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        image.dispose();
        picture.dispose();
        return data!.buffer.asUint8List();
      });
      final file = File(
        '${directory.path}/${segmented ? 'kosoe-do' : 'kosoe-posle'}.png',
      )..writeAsBytesSync(bytes!);
      expect(file.lengthSync(), greaterThan(5000));
      // ignore: avoid_print
      print('Превью записано: ${file.path} (${file.lengthSync()} байт)');
    }
  });
}
