import 'package:flutter/material.dart';

import '../services/watermark.dart';

Future<void> showWatermarkDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const WatermarkDialog(),
  );
}

class WatermarkDialog extends StatefulWidget {
  const WatermarkDialog({super.key});

  @override
  State<WatermarkDialog> createState() => _WatermarkDialogState();
}

class _WatermarkDialogState extends State<WatermarkDialog> {
  final _controller = TextEditingController(text: WatermarkSettings.text.value);
  bool _enabled = WatermarkSettings.enabled.value;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await WatermarkSettings.save(enabled: _enabled, text: _controller.text);
    if (!mounted) return;
    setState(() => _busy = false);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.branding_watermark_outlined,
              color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          const Expanded(child: Text('Водяной знак')),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: const Key('watermark-enabled'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Печатать на всех документах'),
              subtitle: const Text(
                'Диагональный текст поверх каждой страницы PDF',
                style: TextStyle(fontSize: 11),
              ),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('watermark-text'),
              controller: _controller,
              enabled: _enabled,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Текст',
                hintText: 'например, ООО «Мягкие окна»',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const Text(
              'Знак попадёт в PDF-документы, отчёт клиенту и печать. '
              'На экране он не показывается.',
              style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }
}
