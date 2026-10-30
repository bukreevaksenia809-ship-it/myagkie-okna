import 'package:flutter/material.dart';

import '../services/label_settings.dart';
import '../theme/app_tokens.dart';

/// Диалог размеров всех типов подписей (5…24 pt).
Future<void> showLabelSettingsDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _LabelSettingsDialog(),
  );
}

class _LabelSettingsDialog extends StatefulWidget {
  const _LabelSettingsDialog();

  @override
  State<_LabelSettingsDialog> createState() => _LabelSettingsDialogState();
}

class _LabelSettingsDialogState extends State<_LabelSettingsDialog> {
  LabelSettings _settings = LabelSettings.value;

  void _set(LabelKind kind, double value) {
    LabelSettings.setSize(kind, value);
    setState(() => _settings = LabelSettings.value);
  }

  Future<void> _reset() async {
    await LabelSettings.resetToDefaults();
    if (!mounted) return;
    setState(() => _settings = LabelSettings.value);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.text_fields, color: AppTokens.copper),
          SizedBox(width: 8),
          Text('Размеры подписей'),
        ],
      ),
      content: SizedBox(
        width: 540,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Размер каждой группы подписей настраивается отдельно, 5…24 pt. '
              'Изменения сразу видны на листах: чертёж, раскрой, расходы, смета, '
              'техкарта, отчёт клиенту.',
              style: TextStyle(fontSize: 12, height: 1.45, color: AppTokens.muted),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: ListView.separated(
                itemCount: LabelKind.values.length,
                separatorBuilder: (_, _) => const Divider(height: 8),
                itemBuilder: (context, index) {
                  final kind = LabelKind.values[index];
                  final value = _settings.ptFor(kind);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              kind.label,
                              style: const TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '${value.toStringAsFixed(1).replaceAll('.', ',')} pt',
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTokens.copper,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      Slider(
                        value: value,
                        min: LabelSettings.minPt,
                        max: LabelSettings.maxPt,
                        divisions:
                            ((LabelSettings.maxPt - LabelSettings.minPt) * 2)
                                .round(),
                        onChanged: (next) => _set(kind, next),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _reset, child: const Text('Сбросить')),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Готово'),
        ),
      ],
    );
  }
}
