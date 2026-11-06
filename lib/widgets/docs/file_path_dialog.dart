// Диалог ввода пути к файлу.
//
// Без пакета выбора файла на десктопе самый честный способ — попросить полный
// путь. В браузере файловая система недоступна: там диалог объясняет, что
// вложение сохраняется через встроенные средства, и возвращает null.
import 'package:flutter/material.dart';

/// Спрашивает у пользователя полный путь к файлу. null — отмена.
Future<String?> askFilePath(
  BuildContext context, {
  String title = 'Файл',
  String hint = 'Полный путь к файлу',
  String? note,
}) {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              autofocus: true,
              decoration: InputDecoration(
                labelText: hint,
                hintText: '/Users/.../файл.png',
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                final path = value.trim();
                if (path.isNotEmpty) Navigator.of(context).pop(path);
              },
            ),
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                note,
                style: const TextStyle(fontSize: 12, color: Color(0xFF66748A)),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final path = controller.text.trim();
            if (path.isEmpty) return;
            Navigator.of(context).pop(path);
          },
          child: const Text('Готово'),
        ),
      ],
    ),
  );
}
