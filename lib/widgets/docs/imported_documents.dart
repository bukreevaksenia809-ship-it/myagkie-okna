// Импорт пользовательских DOCX в документы заказа.
//
// Здесь только Flutter-часть: выбор файла, предупреждение о частичном
// импорте, список сохранённых шаблонов с открытием/переименованием/удалением.
// Сам разбор — в services/docx_import.dart (чистый Dart, тестируется без
// file_selector).
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../services/doc_converter.dart';
import '../../services/docx_import.dart';
import '../../services/document_assets.dart';
import '../../services/imported_docx_store.dart';

/// Открывает выбор DOCX, разбирает его и сохраняет шаблон.
///
/// Возвращает null, если пользователь отменил выбор, файл битый или больше
/// лимита: причина показывается в SnackBar/диалоге.
Future<ImportedDocxTemplate?> importDocxFromPicker(
  BuildContext context, {
  ImportedDocxStore? store,
}) async {
  XFile? file;
  try {
    file = await openFile(
      acceptedTypeGroups: const [
        XTypeGroup(
          label: 'Документы Word',
          extensions: ['doc', 'docx'],
          mimeTypes: [
            'application/msword',
            'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
          ],
          uniformTypeIdentifiers: [
            'com.microsoft.word.doc',
            'org.openxmlformats.wordprocessingml.document',
          ],
        ),
      ],
    );
  } catch (error) {
    if (context.mounted) {
      _toast(context, 'Не удалось открыть выбор файла: $error');
    }
    return null;
  }
  if (file == null) return null;
  final picked = file;

  var bytes = await picked.readAsBytes();
  final lowerName = picked.name.toLowerCase();
  // Старый .doc конвертируем в .docx через LibreOffice. В браузере и без
  // LibreOffice конвертер вернёт понятное сообщение «сохраните как .docx».
  if (lowerName.endsWith('.doc')) {
    final converted = await convertDocToDocx(bytes, fileName: picked.name);
    if (!converted.ok) {
      if (context.mounted) {
        await _showError(
          context,
          'Не удалось открыть .doc',
          converted.error ?? 'Неизвестная ошибка конвертации.',
        );
      }
      return null;
    }
    bytes = converted.bytes!;
  }
  if (bytes.length > docxMaxBytes) {
    if (context.mounted) {
      _toast(
        context,
        'Файл больше 2 МБ — уменьшите документ или разбейте его на части.',
      );
    }
    return null;
  }
  final result = DocxImportService.parse(bytes, fileName: picked.name);
  if (result.error != null) {
    if (context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Не удалось импортировать Word'),
          content: Text(result.error!),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Понятно'),
            ),
          ],
        ),
      );
    }
    return null;
  }
  if (!result.hasContent) {
    if (context.mounted) _toast(context, 'В документе нет текста или таблиц.');
    return null;
  }
  if (!context.mounted) return null;
  final title = await showDialog<String>(
    context: context,
    builder: (context) => _ImportPreviewDialog(
      result: result,
      initialTitle: _fileNameTitle(picked.name),
    ),
  );
  if (title == null) return null;

  // Картинки сохраняем только после подтверждения, чтобы отмена не оставляла
  // осиротевшие файлы. Блоки уже ссылаются на заглушки — подменяем их.
  final refs = <String, String>{};
  var imageSaveFailed = 0;
  for (final image in result.images) {
    try {
      refs[image.assetRef] = await saveDocumentAsset(
        image.fileName,
        image.bytes,
      );
    } catch (_) {
      imageSaveFailed += 1;
    }
  }
  final blocks = applyDocxImageAssets(result.blocks, refs);
  final warnings = [
    ...result.warnings,
    if (imageSaveFailed > 0)
      DocxImportWarning(
        'image_save',
        'Не удалось сохранить картинку',
        count: imageSaveFailed,
      ),
  ];

  final now = DateTime.now();
  final template = ImportedDocxTemplate(
    id: 'docx_${now.microsecondsSinceEpoch}',
    title: title.trim().isEmpty
        ? 'Импортированный документ'
        : title.trim(),
    fileName: picked.name,
    importedAt: now,
    updatedAt: now,
    blocks: blocks,
    warnings: warnings,
    sizeBytes: bytes.length,
  );
  await (store ?? ImportedDocxStore()).upsert(template);
  if (context.mounted) {
    _toast(context, 'DOCX импортирован: ${template.title}');
  }
  return template;
}

/// Список сохранённых DOCX-шаблонов: открыть, переименовать, удалить.
Future<ImportedDocxTemplate?> showImportedDocxDialog(
  BuildContext context, {
  ImportedDocxStore? store,
}) {
  return showDialog<ImportedDocxTemplate>(
    context: context,
    builder: (context) => _ImportedDocxDialog(store: store),
  );
}

String _fileNameTitle(String fileName) {
  final name = fileName.split('/').last.split('\\').last;
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  final trimmed = base.trim();
  return trimmed.isEmpty ? 'Импортированный документ' : trimmed;
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.maybeOf(context)?.showSnackBar(
    SnackBar(content: Text(message)),
  );
}

Future<void> _showError(
  BuildContext context,
  String title,
  String message,
) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: Text(title),
    content: Text(message),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text('Понятно'),
      ),
    ],
  ),
);

/// Сводка перед сохранением: сколько абзацев/таблиц и что потеряно.
class _ImportPreviewDialog extends StatefulWidget {
  const _ImportPreviewDialog({
    required this.result,
    required this.initialTitle,
  });

  final DocxImportResult result;
  final String initialTitle;

  @override
  State<_ImportPreviewDialog> createState() => _ImportPreviewDialogState();
}

class _ImportPreviewDialogState extends State<_ImportPreviewDialog> {
  late var _title = widget.initialTitle;

  @override
  Widget build(BuildContext context) {
    final result = widget.result;
    final theme = Theme.of(context);
    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.description_outlined),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              result.title.trim().isEmpty
                  ? 'Импорт Word'
                  : result.title.trim(),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Найдено: ${result.paragraphs} абзацев, '
              '${result.headings} заголовков, ${result.tables} таблиц'
              '${result.images.isEmpty ? '' : ', ${result.images.length} картинок'}.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('docx-import-title'),
              initialValue: _title,
              onChanged: (value) => _title = value,
              decoration: const InputDecoration(
                labelText: 'Название шаблона',
                helperText: 'По умолчанию — имя файла без расширения',
                border: OutlineInputBorder(),
              ),
            ),
            if (result.partial) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFF0D9A8)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Частичный импорт',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    for (final warning in result.warnings)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          '• ${warning.label}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    const SizedBox(height: 4),
                    Text(
                      'Текст сохранён, но сложное оформление может '
                      'отличаться от исходного Word.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            Text(
              'Документ попадёт в «Документацию» заказа как свой документ: '
              'его можно открыть, отредактировать, распечатать и сохранить в PDF.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('docx-import-cancel'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton.icon(
          key: const Key('docx-import-save'),
          onPressed: () => Navigator.of(context).pop(_title.trim()),
          icon: const Icon(Icons.download_done, size: 18),
          label: const Text('Импортировать'),
        ),
      ],
    );
  }
}

class _ImportedDocxDialog extends StatefulWidget {
  const _ImportedDocxDialog({this.store});

  final ImportedDocxStore? store;

  @override
  State<_ImportedDocxDialog> createState() => _ImportedDocxDialogState();
}

class _ImportedDocxDialogState extends State<_ImportedDocxDialog> {
  late final ImportedDocxStore _store = widget.store ?? ImportedDocxStore();
  List<ImportedDocxTemplate> _items = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await _store.load();
    if (!mounted) return;
    setState(() {
      _items = items;
      _loading = false;
    });
  }

  Future<void> _rename(ImportedDocxTemplate template) async {
    var value = template.title;
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать шаблон'),
        content: TextFormField(
          key: const Key('docx-rename-field'),
          initialValue: template.title,
          autofocus: true,
          onChanged: (text) => value = text,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('docx-rename-apply'),
            onPressed: () => Navigator.of(context).pop(value.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    if (title == null || title.isEmpty) return;
    final items = await _store.rename(template.id, title);
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _duplicate(ImportedDocxTemplate template) async {
    final items = await _store.duplicate(template.id);
    if (!mounted) return;
    setState(() => _items = items);
    _toast(context, 'Шаблон продублирован');
  }

  Future<void> _delete(ImportedDocxTemplate template) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить шаблон?'),
        content: Text(
          '«${template.title}» будет удалён из списка импортированных. '
          'Уже вставленные в заказы документы останутся.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            key: const Key('docx-delete-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final items = await _store.remove(template.id);
    if (!mounted) return;
    setState(() => _items = items);
  }

  Future<void> _import() async {
    final template = await importDocxFromPicker(context, store: _store);
    if (template == null) return;
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.folder_copy_outlined),
          SizedBox(width: 10),
          Expanded(child: Text('Импортированные Word')),
        ],
      ),
      content: SizedBox(
        width: 620,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Шаблоны хранятся на этом устройстве и переживают '
                    'перезапуск. Их можно вставлять в любой заказ.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  key: const Key('docx-import-more'),
                  onPressed: _import,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: const Text('Импортировать Word'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _items.isEmpty
                  ? Center(
                      child: Text(
                        'Пока нет импортированных документов',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.separated(
                      key: const Key('docx-import-list'),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          leading: const Icon(Icons.description_outlined),
                          title: Text(item.title),
                          subtitle: Text(
                            '${item.fileName} · ${item.sizeLabel}'
                            '${item.warnings.isEmpty ? '' : ' · ${item.warnings.map((warning) => warning.label).join('; ')}'}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Вставить в заказ',
                                key: Key('docx-open-${item.id}'),
                                onPressed: () =>
                                    Navigator.of(context).pop(item),
                                icon: const Icon(Icons.playlist_add),
                              ),
                              IconButton(
                                tooltip: 'Переименовать',
                                key: Key('docx-rename-${item.id}'),
                                onPressed: () => _rename(item),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: 'Дублировать',
                                key: Key('docx-duplicate-${item.id}'),
                                onPressed: () => _duplicate(item),
                                icon: const Icon(Icons.copy_all_outlined),
                              ),
                              IconButton(
                                tooltip: 'Удалить',
                                key: Key('docx-delete-${item.id}'),
                                onPressed: () => _delete(item),
                                icon: const Icon(Icons.delete_outline),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('docx-list-close'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Закрыть'),
        ),
      ],
    );
  }
}
