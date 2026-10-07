import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_params.dart';
import '../services/roll_plan.dart';
import 'window_painter.dart' show formatScaleLabel;

/// Лист раскладки заготовок плёнки на рулонах: свой рулон для каждого материала.
class RollSheet extends StatelessWidget {
  const RollSheet({
    super.key,
    required this.project,
    this.captureKey,
    this.labelFontFamily,
  });

  final OrderProject project;
  final GlobalKey? captureKey;
  final String? labelFontFamily;

  static const double titleBlockHeight = 118;
  static const double sidePanelWidth = 250;
  static const double _outerPadding = 20;

  /// Раскладка по материалам заказа.
  List<RollPlan> get plans => buildRollPlans(project);

  @override
  Widget build(BuildContext context) {
    final rollPlans = plans;

    return LayoutBuilder(
      builder: (context, constraints) {
        final sheetWidth =
            math.max(constraints.maxWidth - _outerPadding * 2, 320.0);
        final sheetHeight =
            math.max(constraints.maxHeight - _outerPadding * 2, 320.0);

        return Container(
          color: const Color(0xFFE7EBF2),
          padding: const EdgeInsets.all(_outerPadding),
          child: Center(
            child: RepaintBoundary(
              key: captureKey,
              child: Container(
                width: sheetWidth,
                height: sheetHeight,
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFFC3CCDA)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.10),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(
                            child: CustomPaint(
                              painter: RollLayoutPainter(
                                plans: rollPlans,
                                selectedIndex: project.selectedIndex,
                                labelFontFamily: labelFontFamily,
                              ),
                              size: Size.infinite,
                            ),
                          ),
                          const VerticalDivider(
                            width: 1,
                            thickness: 1,
                            color: Color(0xFFC3CCDA),
                          ),
                          SizedBox(
                            width: sidePanelWidth,
                            child: _RollSidePanel(
                              project: project,
                              plans: rollPlans,
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: titleBlockHeight,
                      child: _RollTitleBlock(
                        project: project,
                        plans: rollPlans,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Отрисовка рулонов: полосы стоят рядом, заготовки уложены полками.
class RollLayoutPainter extends CustomPainter {
  RollLayoutPainter({
    required this.plans,
    required this.selectedIndex,
    this.labelFontFamily,
  });

  final List<RollPlan> plans;
  final int selectedIndex;
  final String? labelFontFamily;

  static const Color _ink = Color(0xFF1B1F27);
  static const Color _filmFill = Color(0x335AA7E8);
  static const Color _filmEdge = Color(0xFF4C9BE8);
  static const Color _accent = Color(0xFF0B62C4);
  static const Color _rollFill = Color(0xFFF4F7FB);
  static const Color _grid = Color(0xFFE8ECF3);

  @override
  void paint(Canvas canvas, Size size) {
    if (plans.isEmpty) {
      _label(
        canvas,
        'Нет заготовок для раскладки',
        Offset(size.width / 2, 60),
      );
      return;
    }

    const padLeft = 96.0;
    const padRight = 40.0;
    const padTop = 96.0;
    const padBottom = 64.0;
    const gapPx = 54.0;

    final totalWidthMm = plans.fold<double>(0, (sum, plan) => sum + plan.rollWidth);
    final maxLengthMm = plans
        .map((plan) => math.max(
              plan.layout.requiredLength,
              plan.layout.placements.fold<double>(
                0,
                (maxY, placement) =>
                    math.max(maxY, placement.y + placement.height),
              ),
            ))
        .reduce(math.max);
    if (maxLengthMm <= 0) {
      _label(canvas, 'Нет заготовок для раскладки', Offset(size.width / 2, 60));
      return;
    }

    final availableWidth = math.max(
      size.width - padLeft - padRight - gapPx * (plans.length - 1),
      40.0,
    );
    final availableHeight = math.max(size.height - padTop - padBottom, 40.0);
    final scale = math.min(availableWidth / totalWidthMm, availableHeight / maxLengthMm);
    if (!scale.isFinite || scale <= 0) return;

    var xPx = padLeft;
    for (final plan in plans) {
      final stripWidth = plan.rollWidth * scale;
      _paintRoll(canvas, plan, xPx, stripWidth, scale, padTop);
      xPx += stripWidth + gapPx;
    }

    _label(
      canvas,
      'Масштаб ${formatScaleLabel(scale)}',
      Offset(padLeft + (xPx - gapPx - padLeft) / 2, size.height - 26),
      small: true,
      color: const Color(0xFF41506A),
    );
  }

  void _paintRoll(
    Canvas canvas,
    RollPlan plan,
    double xPx,
    double stripWidth,
    double scale,
    double topPx,
  ) {
    final rollLength = plan.layout.requiredLength;
    final rollRect = Rect.fromLTWH(xPx, topPx, stripWidth, rollLength * scale);

    canvas.drawRect(rollRect, Paint()..color = _rollFill);

    // Разметка вдоль рулона.
    final gridStep = _gridStep(scale);
    final gridPaint = Paint()
      ..color = _grid
      ..strokeWidth = 1;
    for (var y = gridStep; y < rollLength; y += gridStep) {
      final dy = rollRect.top + y * scale;
      canvas.drawLine(Offset(rollRect.left, dy), Offset(rollRect.right, dy), gridPaint);
      if (identical(plan, plans.first)) {
        _text(
          canvas,
          formatMm(y),
          Offset(rollRect.left - 8, dy),
          alignRight: true,
          small: true,
          color: const Color(0xFF8A93A0),
        );
      }
    }
    for (var x = gridStep; x < plan.rollWidth; x += gridStep) {
      final dx = rollRect.left + x * scale;
      canvas.drawLine(Offset(dx, rollRect.top), Offset(dx, rollRect.bottom), gridPaint);
    }

    // Заготовки.
    for (final placement in plan.layout.placements) {
      final rect = Rect.fromLTWH(
        rollRect.left + placement.x * scale,
        rollRect.top + placement.y * scale,
        placement.width * scale,
        placement.height * scale,
      );
      final index = int.tryParse(placement.piece.id) ?? 0;
      final isSelected = index - 1 == selectedIndex;

      canvas.drawRect(rect, Paint()..color = _filmFill);
      canvas.drawRect(
        rect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = isSelected ? 2.4 : 1.4
          ..color = isSelected ? _accent : _filmEdge,
      );

      final center = rect.center;
      final number = '№${placement.piece.id}';
      if (rect.width > 74 && rect.height > 40) {
        _label(canvas, number, Offset(center.dx, center.dy - 9), color: _ink);
        _label(
          canvas,
          '${formatMm(placement.width)}×${formatMm(placement.height)}'
          '${placement.rotated ? ' ↻' : ''}',
          Offset(center.dx, center.dy + 8),
          small: true,
          color: const Color(0xFF41506A),
        );
      } else if (rect.width > 34 && rect.height > 18) {
        _label(canvas, number, center, small: true, color: _ink);
      }
    }

    canvas.drawRect(
      rollRect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = _ink,
    );

    // Заголовок рулона и размеры.
    _label(
      canvas,
      '${plan.material.label} · рулон ${formatMm(plan.rollWidth)} мм',
      Offset(rollRect.center.dx, rollRect.top - 62),
      small: true,
      color: _accent,
    );
    _dimension(
      canvas,
      Offset(rollRect.left, rollRect.top - 34),
      Offset(rollRect.right, rollRect.top - 34),
      'Ширина ${formatMm(plan.rollWidth)}',
    );
    _verticalDimension(
      canvas,
      Offset(rollRect.left - 30, rollRect.top),
      Offset(rollRect.left - 30, rollRect.top + rollLength * scale),
      'Длина ${formatMm(rollLength)}',
    );

    // Предупреждения по этому рулону.
    if (plan.layout.warnings.isNotEmpty) {
      final text = plan.layout.warnings.join(' · ');
      final painter = _painter(text, color: Colors.white, small: true);
      final width = math.min(painter.width + 22, stripWidth + 120);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(rollRect.left, rollRect.bottom + 10, width, 22),
        const Radius.circular(4),
      );
      canvas.drawRRect(rect, Paint()..color = const Color(0xFFB3261E));
      canvas.save();
      canvas.clipRRect(rect);
      painter.paint(canvas, Offset(rect.left + 10, rect.top + 5));
      canvas.restore();
    }
  }

  double _gridStep(double scale) {
    const candidates = <double>[100, 200, 250, 500, 1000, 2000, 5000];
    for (final candidate in candidates) {
      if (candidate * scale >= 40) return candidate;
    }
    return 10000;
  }

  void _dimension(Canvas canvas, Offset a, Offset b, String text) {
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.1;
    canvas.drawLine(a, b, paint);
    _arrow(canvas, a, const Offset(-1, 0));
    _arrow(canvas, b, const Offset(1, 0));
    canvas.drawLine(a + const Offset(0, 4), a + const Offset(0, 34), paint);
    canvas.drawLine(b + const Offset(0, 4), b + const Offset(0, 34), paint);
    _label(canvas, text, Offset((a.dx + b.dx) / 2, a.dy - 12), small: true);
  }

  void _verticalDimension(Canvas canvas, Offset a, Offset b, String text) {
    final paint = Paint()
      ..color = _ink
      ..strokeWidth = 1.1;
    canvas.drawLine(a, b, paint);
    _arrow(canvas, a, const Offset(0, -1));
    _arrow(canvas, b, const Offset(0, 1));
    _label(
      canvas,
      text,
      Offset(a.dx - 12, (a.dy + b.dy) / 2),
      angle: -math.pi / 2,
      small: true,
    );
  }

  void _arrow(Canvas canvas, Offset tip, Offset direction) {
    const length = 10.0;
    const halfWidth = 3.4;
    final back = tip - direction * length;
    final normal = Offset(-direction.dy, direction.dx) * halfWidth;
    canvas.drawPath(
      Path()
        ..moveTo(tip.dx, tip.dy)
        ..lineTo(back.dx + normal.dx, back.dy + normal.dy)
        ..lineTo(back.dx - normal.dx, back.dy - normal.dy)
        ..close(),
      Paint()..color = _ink,
    );
  }

  TextPainter _painter(
    String text, {
    required Color color,
    bool small = false,
  }) {
    return TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: small ? 10.5 : 12.5,
          fontWeight: small ? FontWeight.w500 : FontWeight.w700,
          fontFamily: labelFontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
  }

  void _text(
    Canvas canvas,
    String text,
    Offset position, {
    bool alignRight = false,
    bool small = false,
    Color color = _ink,
  }) {
    final painter = _painter(text, color: color, small: small);
    painter.paint(
      canvas,
      Offset(
        alignRight ? position.dx - painter.width : position.dx,
        position.dy - painter.height / 2,
      ),
    );
  }

  void _label(
    Canvas canvas,
    String text,
    Offset position, {
    double angle = 0,
    bool small = false,
    Color color = _ink,
  }) {
    final painter = _painter(text, color: color, small: small);
    canvas.save();
    canvas.translate(position.dx, position.dy);
    canvas.rotate(angle);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: painter.width + 8,
      height: painter.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
    painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant RollLayoutPainter oldDelegate) =>
      oldDelegate.plans != plans ||
      oldDelegate.selectedIndex != selectedIndex ||
      oldDelegate.labelFontFamily != labelFontFamily;
}

class _RollSidePanel extends StatelessWidget {
  const _RollSidePanel({required this.project, required this.plans});

  final OrderProject project;
  final List<RollPlan> plans;

  @override
  Widget build(BuildContext context) {
    final totalPiecesArea =
        plans.fold<double>(0, (sum, plan) => sum + plan.piecesArea);
    final totalRollArea =
        plans.fold<double>(0, (sum, plan) => sum + plan.rollArea);
    final waste = totalRollArea > 0
        ? ((totalRollArea - totalPiecesArea) / totalRollArea * 100)
            .clamp(0.0, 100.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'РАСКЛАДКА НА РУЛОНЕ',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF66748A),
            ),
          ),
          const SizedBox(height: 10),
          _row('Рулонов (материалов)', '${plans.length} шт'),
          _row('Площадь заготовок', '${formatMeters(totalPiecesArea / 1000000)} м²'),
          _row('Площадь рулонов', '${formatMeters(totalRollArea / 1000000)} м²'),
          _row('Отход', formatPercent(waste)),
          _row('Зазор между заготовками', '${formatMm(project.rollGap)} мм'),
          const SizedBox(height: 12),
          const Text(
            'РУЛОНЫ',
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF66748A),
            ),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final plan in plans) ...[
                    Text(
                      '${plan.material.label} · ${formatMm(plan.rollWidth)} мм',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16324F),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 8),
                      child: Text(
                        'длина ${formatMm(plan.layout.requiredLength)} мм · '
                        'заготовок ${plan.layout.placements.length} · '
                        'отход ${formatPercent(plan.rollArea > 0 ? ((plan.rollArea - plan.piecesArea) / plan.rollArea * 100).clamp(0.0, 100.0) : 0.0)}',
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF4A5563),
                        ),
                      ),
                    ),
                    for (final placement in plan.layout.placements)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, bottom: 3),
                        child: Text(
                          '${placement.piece.label}: '
                          '${formatMm(placement.width)}×${formatMm(placement.height)} мм'
                          '${placement.rotated ? ' (повёрнуто)' : ''}',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF4A5563),
                          ),
                        ),
                      ),
                  ],
                  for (final plan in plans)
                    if (plan.layout.warnings.isNotEmpty)
                      for (final warning in plan.layout.warnings)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.warning_amber_rounded,
                                  size: 15, color: Color(0xFFB26A00)),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  warning,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF8A5200),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF41506A)),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF16324F),
            ),
          ),
        ],
      ),
    );
  }
}

class _RollTitleBlock extends StatelessWidget {
  const _RollTitleBlock({required this.project, required this.plans});

  final OrderProject project;
  final List<RollPlan> plans;

  @override
  Widget build(BuildContext context) {
    final totalPiecesArea =
        plans.fold<double>(0, (sum, plan) => sum + plan.piecesArea);
    final totalRollArea =
        plans.fold<double>(0, (sum, plan) => sum + plan.rollArea);
    final waste = totalRollArea > 0
        ? ((totalRollArea - totalPiecesArea) / totalRollArea * 100)
            .clamp(0.0, 100.0)
        : 0.0;
    final first = project.windows.first;
    final rollsSummary = plans
        .map((plan) =>
            '${plan.material.label}: ${formatMm(plan.rollWidth)}×${formatMm(plan.layout.requiredLength)}')
        .join(' · ');

    return Container(
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF1B1F27), width: 1.4)),
      ),
      child: Row(
        children: [
          Expanded(flex: 3, child: _cell('Изделие', first.projectName)),
          Expanded(flex: 2, child: _cell('Заказчик', first.customer)),
          Expanded(
            flex: 2,
            child: _cell('Окон в раскладке',
                '${plans.fold<int>(0, (sum, plan) => sum + plan.layout.placements.length)} шт'),
          ),
          Expanded(flex: 4, child: _cell('Рулоны (ширина × длина)', rollsSummary)),
          Expanded(
            flex: 2,
            child: _cell('Площадь заготовок',
                '${formatMeters(totalPiecesArea / 1000000)} м²'),
          ),
          Expanded(
            flex: 2,
            child: _cell('Площадь рулонов',
                '${formatMeters(totalRollArea / 1000000)} м²'),
          ),
          Expanded(flex: 2, child: _cell('Отход', formatPercent(waste))),
        ],
      ),
    );
  }

  Widget _cell(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: const BoxDecoration(
        border: Border(left: BorderSide(color: Color(0xFFC3CCDA))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label.toUpperCase(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 8.5,
              height: 1.15,
              letterSpacing: 0.4,
              color: Color(0xFF7C8798),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value.isEmpty ? '—' : value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 12.5,
              color: Color(0xFF1B1F27),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
