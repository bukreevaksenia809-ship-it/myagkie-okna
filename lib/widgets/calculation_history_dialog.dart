import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';

/// История вычислений по заказу: размеры, формулы площади, периметра,
/// окантовки, крепежа и заготовки. Не меняет заказ — только показывает,
/// откуда взялись числа на чертеже и в смете.
Future<void> showCalculationHistory(
  BuildContext context,
  OrderProject project,
) {
  return showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 760),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'История вычислений',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'По каждому окну: размеры, формулы и итоговые числа.',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF66748A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.all(14),
                itemCount: project.windows.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _WindowCalculation(
                  index: index,
                  params: project.windows[index],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _WindowCalculation extends StatelessWidget {
  const _WindowCalculation({required this.index, required this.params});

  final int index;
  final WindowParams params;

  @override
  Widget build(BuildContext context) {
    final spec = WindowSpec.of(params);
    final geometry = spec.geometry;
    final edge = spec.edgeConsumption.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final rows = <(String, String)>[
      (
        'Габарит',
        '${formatMm(geometry.spanX)} × ${formatMm(geometry.overallHeight)} мм',
      ),
      (
        'Площадь',
        '${formatMeters(spec.productAreaM2)} м² — площадь контура изделия',
      ),
      (
        'Периметр',
        '${formatMeters(geometry.perimeter / 1000)} м — сумма всех кромок',
      ),
      if (edge.isNotEmpty)
        (
          'Кант',
          edge
              .map(
                (entry) =>
                    '${edgeBandLabel(entry.key)}: '
                    '${formatMeters(entry.value / 1000)} м',
              )
              .join(' · '),
        ),
      (
        'Люверсы',
        '${spec.standaloneEyeletCount} шт, шаг ${spec.eyeletStepLabel}',
      ),
      (
        'Крепёж',
        '${spec.fastenerSummary} · точек ${spec.layers.fastenerPointsCount}',
      ),
      (
        'Заготовка',
        '${formatMm(spec.filmCutWidthWithAllowance)} × '
            '${formatMm(spec.filmCutHeightWithAllowance)} мм '
            '(${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²)',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 14,
                backgroundColor: const Color(0xFF0B62C4),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                params.drawingNumber.trim().isEmpty
                    ? 'Окно №${index + 1}'
                    : 'Окно №${index + 1} · ${params.drawingNumber}',
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF66748A),
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(value, style: const TextStyle(fontSize: 11.5)),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
