// Редактор документа «как в Word» на своих блоках.
//
// Без flutter_quill: блок — это заголовок, абзац, список, таблица, картинка,
// подпись или разрыв страницы. Внутри текста поддерживается inline-разметка
// **жирный** / *курсив* / __подчёркивание__, выравнивание — у блока. Таблицы
// редактируются по ячейкам, картинки и подписи вставляются как ассеты.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../../models/document.dart';
import '../../services/document_store.dart';
import 'document_page.dart';
import 'file_path_dialog.dart';
import 'inline_markup.dart';
import 'signature_pad.dart';

/// Редактор одного документа.
class DocumentEditor extends StatefulWidget {
  const DocumentEditor({
    super.key,
    required this.document,
    required this.store,
    required this.assets,
    required this.onChanged,
  });

  final OrderDocument document;
  final DocumentStore store;
  final DocumentAssetReader assets;
  final ValueChanged<OrderDocument> onChanged;

  @override
  State<DocumentEditor> createState() => DocumentEditorState();
}

class DocumentEditorState extends State<DocumentEditor> {
  late OrderDocument _document = widget.document;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, FocusNode> _focusNodes = {};
  TextEditingController? _numberController;

  String? _activeBlockId;
  TextEditingController? _activeController;

  @override
  void didUpdateWidget(covariant DocumentEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    _document = widget.document;
    _syncControllers();
  }

  @override
  void dispose() {
    _numberController?.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncControllers() {
    for (final block in _document.blocks) {
      final controller = _controllers[block.id];
      if (controller != null &&
          !(_focusNodes[block.id]?.hasFocus ?? false) &&
          controller.text != block.text) {
        controller.text = block.text;
      }
      if (block.type == DocBlockType.table) {
        final columns = _columns(block);
        for (var r = 0; r < block.rows.length; r++) {
          for (var c = 0; c < columns; c++) {
            final key = _cellKey(block.id, r, c);
            final cellController = _controllers[key];
            final value = c < block.rows[r].length ? block.rows[r][c] : '';
            if (cellController != null &&
                !(_focusNodes[key]?.hasFocus ?? false) &&
                cellController.text != value) {
              cellController.text = value;
            }
          }
        }
      }
    }
    final numberController = _numberController;
    if (numberController != null &&
        _document.number != numberController.text &&
        !(_focusNodes['doc-number']?.hasFocus ?? false)) {
      numberController.text = _document.number;
    }
  }

  TextEditingController _controllerFor(String key, String text) =>
      _controllers.putIfAbsent(key, () => MarkupEditingController(text: text));

  TextEditingController _plainControllerFor(String key, String text) =>
      _controllers.putIfAbsent(key, () => TextEditingController(text: text));

  FocusNode _focusFor(String key) =>
      _focusNodes.putIfAbsent(key, () => FocusNode());

  String _cellKey(String blockId, int row, int column) =>
      '$blockId:$row:$column';

  void _updateDocument(OrderDocument document) {
    setState(() => _document = document);
    widget.onChanged(document);
  }

  void _updateBlock(int index, DocBlock block) {
    if (index < 0 || index >= _document.blocks.length) return;
    _updateDocument(_document.replaceBlock(index, block));
  }

  int get _activeIndex {
    final id = _activeBlockId;
    if (id == null) return -1;
    return _document.blocks.indexWhere((block) => block.id == id);
  }

  void _activate(String blockId, TextEditingController controller) {
    _activeBlockId = blockId;
    _activeController = controller;
  }

  /// Блок выбран, но inline-разметка к нему не применяется (таблицы).
  void _activateBlockOnly(String blockId) {
    _activeBlockId = blockId;
    _activeController = null;
  }

  void _toast(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger?.showSnackBar(SnackBar(content: Text(message)));
  }

  void _wrapSelection(String marker) {
    final controller = _activeController;
    final index = _activeIndex;
    if (controller == null || index < 0) {
      _toast('Сначала поставьте курсор в текст');
      return;
    }
    final value = wrapSelection(controller.value, marker);
    controller.value = value;
    _updateBlock(index, _document.blocks[index].copyWith(text: value.text));
  }

  void _setActiveType(DocBlockType type) {
    final index = _activeIndex;
    if (index < 0) {
      _toast('Сначала выберите блок');
      return;
    }
    final block = _document.blocks[index];
    // Картинку/подпись/таблицу не превращаем в заголовок: вставляем новый
    // текстовый блок после текущего.
    if (!block.type.isText) {
      _insertAfterActive(DocBlock(id: newBlockId(), type: type));
      return;
    }
    _updateBlock(index, block.copyWith(type: type));
  }

  void _setActiveAlign(DocAlign align) {
    final index = _activeIndex;
    if (index < 0) {
      _toast('Сначала выберите блок');
      return;
    }
    _updateBlock(index, _document.blocks[index].copyWith(align: align));
  }

  void _insertAfterActive(DocBlock block) {
    final index = _activeIndex;
    final at = index < 0 ? _document.blocks.length : index + 1;
    _updateDocument(_document.insertBlock(at, block));
    _activeBlockId = block.id;
  }

  void _addParagraph([DocBlockType type = DocBlockType.paragraph]) {
    _insertAfterActive(DocBlock(id: newBlockId(), type: type));
  }

  void _deleteBlock(int index) {
    _updateDocument(_document.removeBlock(index));
    if (_document.blocks.isEmpty) _activeBlockId = null;
  }

  void _moveBlock(int index, int delta) {
    _updateDocument(_document.moveBlock(index, delta));
  }

  void _duplicateBlock(int index) {
    final source = _document.blocks[index];
    final copy = source.copyWith(id: newBlockId());
    _updateDocument(_document.insertBlock(index + 1, copy));
  }

  Future<void> _insertTable() async {
    final size = await showDialog<(int, int)>(
      context: context,
      builder: (context) => const _TableSizeDialog(),
    );
    if (size == null) return;
    _insertAfterActive(
      DocBlock.emptyTable(columns: size.$1, rows: size.$2),
    );
  }

  Future<void> _insertImage() async {
    final path = await askFilePath(
      context,
      title: 'Вставить изображение',
      hint: 'Путь к PNG/JPG',
      note: 'Картинка сохранится в отдельном хранилище ассетов, '
          'в JSON документа останется ссылка.',
    );
    if (path == null || !mounted) return;
    await insertImageFromPath(path);
  }

  /// Вставляет картинку по пути к файлу. Публичный метод нужен тестам и
  /// будущему drag&drop: диалог пути — только один из способов.
  Future<void> insertImageFromPath(String path) async {
    final bytes = await widget.store.readLocalFile(path);
    if (!mounted) return;
    if (bytes == null) {
      _toast('Не удалось прочитать файл. В браузере путь к файлу недоступен.');
      return;
    }
    await insertImageBytes(_baseName(path), bytes);
  }

  /// Вставляет картинку из уже прочитанных байтов.
  ///
  /// Отдельный вход нужен тестам, вставке из буфера и будущему drag&drop:
  /// здесь нет файловых операций, кроме сохранения ассета.
  Future<void> insertImageBytes(String fileName, Uint8List bytes) async {
    if (AttachmentKind.fromFileName(fileName) != AttachmentKind.image) {
      _toast('Это не изображение. Для PDF/DOCX используйте «Вложить файл».');
      return;
    }
    final ref = await widget.store.putAsset(fileName, bytes);
    if (!mounted) return;
    _insertAfterActive(
      DocBlock(
        id: newBlockId(),
        type: DocBlockType.image,
        assetRef: ref,
        align: DocAlign.center,
        widthMm: 90,
      ),
    );
  }

  Future<void> _insertSignature() async {
    final result = await showSignatureDialog(
      context,
      readFile: widget.store.readLocalFile,
    );
    if (result == null || !mounted) return;
    final ref = await widget.store.putAsset(result.fileName, result.bytes);
    if (!mounted) return;
    _insertAfterActive(
      DocBlock(
        id: newBlockId(),
        type: DocBlockType.signature,
        assetRef: ref,
        align: DocAlign.left,
        widthMm: 60,
        isSignature: true,
      ),
    );
  }

  Future<void> _addAttachment() async {
    final path = await askFilePath(
      context,
      title: 'Вложить файл',
      hint: 'Путь к PDF, картинке, DOCX или TXT',
      note: 'Файл сохранится как вложение; DOCX попробуем превратить в текст.',
    );
    if (path == null || !mounted) return;
    final bytes = await widget.store.readLocalFile(path);
    if (!mounted) return;
    if (bytes == null) {
      _toast('Не удалось прочитать файл. В браузере путь к файлу недоступен.');
      return;
    }
    final name = _baseName(path);
    final kind = AttachmentKind.fromFileName(name);
    final ref = await widget.store.putAsset(name, bytes);
    String? extracted;
    if (kind == AttachmentKind.docx) {
      extracted = await widget.store.extractDocx(bytes);
    } else if (kind == AttachmentKind.text) {
      extracted = utf8.decode(bytes, allowMalformed: true);
    }
    if (!mounted) return;
    final attachment = DocAttachment(
      id: newBlockId(),
      fileName: name,
      assetRef: ref,
      kind: kind,
      sizeBytes: bytes.length,
      extractedText: extracted,
    );
    _updateDocument(_document.addAttachment(attachment));
    if (kind == AttachmentKind.docx && (extracted ?? '').trim().isEmpty) {
      _toast(
        'Файл сохранён как вложение. Текст из DOCX извлечь не удалось — '
        'в веб-версии это ограничение, в настольной попробуйте ещё раз.',
      );
    }
  }

  void _insertAttachmentText(DocAttachment attachment) {
    final text = (attachment.extractedText ?? '').trim();
    if (text.isEmpty) {
      _toast('В этом вложении нет извлечённого текста');
      return;
    }
    final lines = text
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .take(200)
        .toList();
    var document = _document;
    var at = _document.blocks.length;
    for (final line in lines) {
      document = document.insertBlock(
        at,
        DocBlock(id: newBlockId(), type: DocBlockType.paragraph, text: line),
      );
      at++;
    }
    _updateDocument(document);
    _toast('Вставлено строк: ${lines.length}');
  }

  void _removeAttachment(DocAttachment attachment) {
    _updateDocument(_document.removeAttachment(attachment.id));
    widget.store.deleteAsset(attachment.assetRef);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _toolbar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = (constraints.maxWidth - 32).clamp(280.0, 794.0);
              return ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                children: [
                  Center(
                    child: Container(
                      width: width,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border.all(color: const Color(0xFFC3CCDA)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x22000000),
                            blurRadius: 12,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      padding: EdgeInsets.fromLTRB(
                        width < 420 ? 18 : 34,
                        width < 420 ? 18 : 30,
                        width < 420 ? 18 : 34,
                        30,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _pageHeader(),
                          const Divider(height: 24),
                          for (var i = 0; i < _document.blocks.length; i++)
                            _buildBlock(i),
                          const SizedBox(height: 8),
                          _addBlockRow(),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Center(
                    child: SizedBox(
                      width: width,
                      child: _attachmentsSection(),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _pageHeader() {
    final numberController = _numberController ??= TextEditingController(
      text: _document.number,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            _document.title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Color(0xFF111827),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 132,
          child: TextField(
            controller: numberController,
            focusNode: _focusFor('doc-number'),
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: Color(0xFF41506A)),
            decoration: const InputDecoration(
              isDense: true,
              labelText: 'Номер',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            ),
            onChanged: (value) {
              _updateDocument(
                _document.copyWith(number: value, updatedAt: DateTime.now()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _toolbar() {
    return Container(
      color: const Color(0xFFF2F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _toolButton(
              icon: Icons.format_bold,
              tooltip: 'Жирный',
              onPressed: () => _wrapSelection('**'),
            ),
            _toolButton(
              icon: Icons.format_italic,
              tooltip: 'Курсив',
              onPressed: () => _wrapSelection('*'),
            ),
            _toolButton(
              icon: Icons.format_underlined,
              tooltip: 'Подчёркнутый',
              onPressed: () => _wrapSelection('__'),
            ),
            const _ToolDivider(),
            _toolButton(
              icon: Icons.format_align_left,
              tooltip: 'По левому краю',
              onPressed: () => _setActiveAlign(DocAlign.left),
            ),
            _toolButton(
              icon: Icons.format_align_center,
              tooltip: 'По центру',
              onPressed: () => _setActiveAlign(DocAlign.center),
            ),
            _toolButton(
              icon: Icons.format_align_right,
              tooltip: 'По правому краю',
              onPressed: () => _setActiveAlign(DocAlign.right),
            ),
            _toolButton(
              icon: Icons.format_align_justify,
              tooltip: 'По ширине',
              onPressed: () => _setActiveAlign(DocAlign.justify),
            ),
            const _ToolDivider(),
            PopupMenuButton<DocBlockType>(
              tooltip: 'Стиль блока',
              icon: const Icon(Icons.format_size, size: 20),
              onSelected: _setActiveType,
              itemBuilder: (context) => [
                for (final type in const [
                  DocBlockType.heading1,
                  DocBlockType.heading2,
                  DocBlockType.heading3,
                  DocBlockType.paragraph,
                  DocBlockType.bulletList,
                  DocBlockType.numberedList,
                ])
                  PopupMenuItem(value: type, child: Text(type.label)),
              ],
            ),
            _toolButton(
              icon: Icons.format_list_bulleted,
              tooltip: 'Маркированный список',
              onPressed: () => _setActiveType(DocBlockType.bulletList),
            ),
            _toolButton(
              icon: Icons.format_list_numbered,
              tooltip: 'Нумерованный список',
              onPressed: () => _setActiveType(DocBlockType.numberedList),
            ),
            const _ToolDivider(),
            _toolButton(
              key: const Key('docs-insert-table'),
              icon: Icons.table_chart_outlined,
              tooltip: 'Вставить таблицу',
              onPressed: _insertTable,
            ),
            _toolButton(
              key: const Key('docs-insert-image'),
              icon: Icons.image_outlined,
              tooltip: 'Вставить изображение',
              onPressed: _insertImage,
            ),
            _toolButton(
              key: const Key('docs-insert-signature'),
              icon: Icons.draw_outlined,
              tooltip: 'Вставить подпись',
              onPressed: _insertSignature,
            ),
            _toolButton(
              key: const Key('docs-add-attachment'),
              icon: Icons.attach_file,
              tooltip: 'Вложить файл',
              onPressed: _addAttachment,
            ),
            _toolButton(
              icon: Icons.horizontal_rule,
              tooltip: 'Разрыв страницы',
              onPressed: () => _insertAfterActive(
                DocBlock(
                  id: newBlockId(),
                  type: DocBlockType.pageBreak,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolButton({
    Key? key,
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
  }) {
    return IconButton(
      key: key,
      icon: Icon(icon, size: 20),
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      onPressed: onPressed,
    );
  }

  Widget _buildBlock(int index) {
    final block = _document.blocks[index];
    return Container(
      key: ValueKey('docs-block-${block.id}'),
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.only(bottom: 4),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFEDF1F6))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  block.type.label,
                  style: const TextStyle(
                    fontSize: 9,
                    color: Color(0xFF9AA5B5),
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              _blockMenu(index),
            ],
          ),
          _blockContent(index, block),
        ],
      ),
    );
  }

  Widget _blockMenu(int index) {
    return PopupMenuButton<String>(
      tooltip: 'Действия с блоком',
      icon: const Icon(Icons.more_vert, size: 18),
      padding: EdgeInsets.zero,
      onSelected: (value) {
        switch (value) {
          case 'up':
            _moveBlock(index, -1);
          case 'down':
            _moveBlock(index, 1);
          case 'duplicate':
            _duplicateBlock(index);
          case 'delete':
            _deleteBlock(index);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(value: 'up', child: Text('Выше')),
        PopupMenuItem(value: 'down', child: Text('Ниже')),
        PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
        PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
  }

  Widget _blockContent(int index, DocBlock block) {
    switch (block.type) {
      case DocBlockType.heading1:
      case DocBlockType.heading2:
      case DocBlockType.heading3:
      case DocBlockType.paragraph:
      case DocBlockType.bulletList:
      case DocBlockType.numberedList:
        return _textBlock(index, block);
      case DocBlockType.table:
        return _tableBlock(index, block);
      case DocBlockType.image:
        return _imageBlock(index, block);
      case DocBlockType.signature:
        return _signatureBlock(index, block);
      case DocBlockType.pageBreak:
        return Row(
          children: [
            const Expanded(
              child: Divider(color: Color(0xFFB8C2D2), thickness: 1),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Разрыв страницы',
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.blueGrey.shade400,
                ),
              ),
            ),
            const Expanded(
              child: Divider(color: Color(0xFFB8C2D2), thickness: 1),
            ),
          ],
        );
    }
  }

  Widget _textBlock(int index, DocBlock block) {
    final controller = _controllerFor(block.id, block.text);
    final focus = _focusFor(block.id);
    final style = switch (block.type) {
      DocBlockType.heading1 => docH1Style.copyWith(fontSize: 18),
      DocBlockType.heading2 => docH2Style.copyWith(fontSize: 15),
      DocBlockType.heading3 => docH3Style.copyWith(fontSize: 13),
      _ => docBodyStyle.copyWith(fontSize: 13),
    };
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) _activate(block.id, controller);
      },
      child: TextField(
        controller: controller,
        focusNode: focus,
        maxLines: null,
        style: style,
        textAlign: _textAlignOf(block.align),
        onTap: () => _activate(block.id, controller),
        onChanged: (value) {
          _updateBlock(index, block.copyWith(text: value));
        },
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          hintText: block.type.isList
              ? 'Каждый пункт с новой строки'
              : 'Текст блока…',
          contentPadding: const EdgeInsets.symmetric(vertical: 3),
        ),
      ),
    );
  }

  Widget _tableBlock(int index, DocBlock block) {
    final columns = _columns(block);
    final rows = _normalizedRows(block, columns);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Table(
          border: TableBorder.all(color: const Color(0xFFCDD5E1), width: 0.7),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          columnWidths: {
            for (var c = 0; c < columns; c++) c: const FlexColumnWidth(),
          },
          children: [
            for (var r = 0; r < rows.length; r++)
              TableRow(
                decoration: BoxDecoration(
                  color: r == 0 ? const Color(0xFFF2F6FB) : Colors.white,
                ),
                children: [
                  for (var c = 0; c < columns; c++)
                    _tableCell(index, block, r, c, rows[r][c]),
                ],
              ),
          ],
        ),
        Wrap(
          spacing: 4,
          children: [
            _miniButton('+ строка', () => _addTableRow(index, block, false)),
            _miniButton('− строка', () => _removeTableRow(index, block)),
            _miniButton('+ столбец', () => _addTableColumn(index, block)),
            _miniButton('− столбец', () => _removeTableColumn(index, block)),
          ],
        ),
      ],
    );
  }

  Widget _tableCell(
    int blockIndex,
    DocBlock block,
    int row,
    int column,
    String text,
  ) {
    final key = _cellKey(block.id, row, column);
    final controller = _plainControllerFor(key, text);
    final focus = _focusFor(key);
    return Focus(
      onFocusChange: (hasFocus) {
        if (hasFocus) _activateBlockOnly(block.id);
      },
      child: TextField(
        controller: controller,
        focusNode: focus,
        maxLines: null,
        style: TextStyle(
          fontSize: 11,
          fontWeight: row == 0 ? FontWeight.w700 : FontWeight.w400,
          color: const Color(0xFF1F2937),
        ),
        onTap: () => _activateBlockOnly(block.id),
        onChanged: (value) => _setTableCell(blockIndex, row, column, value),
        decoration: const InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: EdgeInsets.symmetric(horizontal: 5, vertical: 5),
        ),
      ),
    );
  }

  void _setTableCell(int blockIndex, int row, int column, String value) {
    final block = _document.blocks[blockIndex];
    final columns = _columns(block);
    final rows = _normalizedRows(block, columns);
    while (rows.length <= row) {
      rows.add(List<String>.filled(columns, ''));
    }
    while (rows[row].length <= column) {
      rows[row].add('');
    }
    rows[row][column] = value;
    _updateBlock(blockIndex, block.copyWith(rows: rows));
  }

  void _addTableRow(int index, DocBlock block, bool header) {
    final columns = _columns(block);
    final rows = _normalizedRows(block, columns);
    rows.add(List<String>.filled(columns, ''));
    _updateBlock(index, block.copyWith(rows: rows));
  }

  void _removeTableRow(int index, DocBlock block) {
    if (block.rows.length <= 1) return;
    final rows = [for (final row in block.rows) [...row]]..removeLast();
    _updateBlock(index, block.copyWith(rows: rows));
  }

  void _addTableColumn(int index, DocBlock block) {
    final rows = [for (final row in block.rows) [...row, '']];
    _updateBlock(index, block.copyWith(rows: rows));
  }

  void _removeTableColumn(int index, DocBlock block) {
    final columns = _columns(block);
    if (columns <= 1) return;
    final rows = [
      for (final row in block.rows)
        row.length > 1 ? row.sublist(0, row.length - 1) : row,
    ];
    _updateBlock(index, block.copyWith(rows: rows));
  }

  Widget _imageBlock(int index, DocBlock block) {
    final controller = _controllerFor('${block.id}:caption', block.text);
    final focus = _focusFor('${block.id}:caption');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 150,
          child: FutureBuilder<Uint8List?>(
            future: widget.assets(block.assetRef),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return const Center(
                  child: Text('Изображение недоступно или ещё грузится'),
                );
              }
              return Image.memory(bytes, fit: BoxFit.contain);
            },
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: 'Уже',
              icon: const Icon(Icons.remove_circle_outline, size: 18),
              onPressed: () => _updateBlock(
                index,
                block.copyWith(
                  widthMm: (block.widthMm - 10).clamp(20, 190).toDouble(),
                ),
              ),
            ),
            Text('${block.widthMm.round()} мм'),
            IconButton(
              tooltip: 'Шире',
              icon: const Icon(Icons.add_circle_outline, size: 18),
              onPressed: () => _updateBlock(
                index,
                block.copyWith(
                  widthMm: (block.widthMm + 10).clamp(20, 190).toDouble(),
                ),
              ),
            ),
            Expanded(
              child: Focus(
                onFocusChange: (hasFocus) {
                  if (hasFocus) _activate(block.id, controller);
                },
                child: TextField(
                  controller: controller,
                  focusNode: focus,
                  style: const TextStyle(fontSize: 11),
                  decoration: const InputDecoration(
                    isDense: true,
                    hintText: 'Подпись к изображению',
                    border: InputBorder.none,
                  ),
                  onChanged: (value) =>
                      _updateBlock(index, block.copyWith(text: value)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _signatureBlock(int index, DocBlock block) {
    return Row(
      children: [
        SizedBox(
          width: 200,
          height: 84,
          child: FutureBuilder<Uint8List?>(
            future: widget.assets(block.assetRef),
            builder: (context, snapshot) {
              final bytes = snapshot.data;
              if (bytes == null) {
                return const Center(child: Text('Подпись недоступна'));
              }
              return Image.memory(bytes, fit: BoxFit.contain);
            },
          ),
        ),
        const Spacer(),
        Text(
          'подпись/печать',
          style: TextStyle(fontSize: 10, color: Colors.blueGrey.shade400),
        ),
      ],
    );
  }

  Widget _addBlockRow() {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        _miniButton('+ Абзац', () => _addParagraph()),
        _miniButton('+ H1', () => _addParagraph(DocBlockType.heading1)),
        _miniButton('+ H2', () => _addParagraph(DocBlockType.heading2)),
        _miniButton('+ H3', () => _addParagraph(DocBlockType.heading3)),
        _miniButton(
          '+ Список',
          () => _addParagraph(DocBlockType.bulletList),
        ),
        _miniButton('+ Таблица', _insertTable),
        _miniButton('+ Разрыв', () {
          _insertAfterActive(
            DocBlock(id: newBlockId(), type: DocBlockType.pageBreak),
          );
        }),
      ],
    );
  }

  Widget _miniButton(String label, VoidCallback onPressed) => TextButton(
    onPressed: onPressed,
    style: TextButton.styleFrom(
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      minimumSize: Size.zero,
      textStyle: const TextStyle(fontSize: 11),
    ),
    child: Text(label),
  );

  Widget _attachmentsSection() {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Вложения (${_document.attachments.length})',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton.icon(
                  key: const Key('docs-attach-file'),
                  onPressed: _addAttachment,
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Вложить файл'),
                ),
              ],
            ),
            if (_document.attachments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  'PDF, скан, картинка или DOCX. Файлы хранятся отдельно от '
                  'JSON документа.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
              ),
            for (final attachment in _document.attachments)
              _AttachmentTile(
                attachment: attachment,
                assets: widget.assets,
                onInsertText: attachment.hasText
                    ? () => _insertAttachmentText(attachment)
                    : null,
                onDelete: () => _removeAttachment(attachment),
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatefulWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.assets,
    required this.onDelete,
    this.onInsertText,
  });

  final DocAttachment attachment;
  final DocumentAssetReader assets;
  final VoidCallback onDelete;
  final VoidCallback? onInsertText;

  @override
  State<_AttachmentTile> createState() => _AttachmentTileState();
}

class _AttachmentTileState extends State<_AttachmentTile> {
  Future<Uint8List?>? _pdfPreview;

  @override
  void initState() {
    super.initState();
    _preparePreview();
  }

  @override
  void didUpdateWidget(covariant _AttachmentTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachment.assetRef != widget.attachment.assetRef) {
      _pdfPreview = null;
      _preparePreview();
    }
  }

  void _preparePreview() {
    if (widget.attachment.kind == AttachmentKind.pdf) {
      _pdfPreview = _loadPdfPreview();
    }
  }

  /// Первая страница PDF как картинка. `printing` умеет растеризовать PDF
  /// на десктопе и в браузере; если платформа не поддерживает — вернём null
  /// и покажем понятную заглушку, а не упадём.
  Future<Uint8List?> _loadPdfPreview() async {
    try {
      final bytes = await widget.assets(widget.attachment.assetRef);
      if (bytes == null || bytes.isEmpty) return null;
      final raster = await Printing.raster(bytes, pages: [0], dpi: 96).first;
      return raster.toPng();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final attachment = widget.attachment;
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        switch (attachment.kind) {
          AttachmentKind.pdf => Icons.picture_as_pdf_outlined,
          AttachmentKind.image => Icons.image_outlined,
          AttachmentKind.docx => Icons.description_outlined,
          AttachmentKind.text => Icons.notes_outlined,
          AttachmentKind.other => Icons.insert_drive_file_outlined,
        },
        size: 20,
      ),
      title: Text(
        attachment.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      subtitle: Text(
        '${attachment.kind.label} · ${attachment.sizeLabel}',
        style: const TextStyle(fontSize: 10, color: Color(0xFF66748A)),
      ),
      children: [
        if (attachment.kind == AttachmentKind.pdf)
          SizedBox(
            height: 200,
            child: FutureBuilder<Uint8List?>(
              future: _pdfPreview,
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return const Center(
                    child: Text('Предпросмотр PDF недоступен на этой платформе'),
                  );
                }
                return Image.memory(bytes, fit: BoxFit.contain);
              },
            ),
          )
        else if (attachment.kind.isImage)
          SizedBox(
            height: 180,
            child: FutureBuilder<Uint8List?>(
              future: widget.assets(attachment.assetRef),
              builder: (context, snapshot) {
                final bytes = snapshot.data;
                if (bytes == null) {
                  return const Center(child: Text('Предпросмотр недоступен'));
                }
                return Image.memory(bytes, fit: BoxFit.contain);
              },
            ),
          )
        else if (attachment.hasText)
          Container(
            width: double.infinity,
            constraints: const BoxConstraints(maxHeight: 180),
            padding: const EdgeInsets.all(8),
            color: const Color(0xFFF7F9FC),
            child: SingleChildScrollView(
              child: Text(
                attachment.extractedText!,
                style: const TextStyle(fontSize: 11, height: 1.35),
              ),
            ),
          )
        else
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text(
              'Предпросмотр этого формата недоступен — файл сохранён '
              'как вложение.',
              style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
            ),
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (widget.onInsertText != null)
              TextButton(
                onPressed: widget.onInsertText,
                child: const Text('Вставить текст'),
              ),
            TextButton(
              onPressed: widget.onDelete,
              child: const Text('Удалить'),
            ),
          ],
        ),
      ],
    );
  }
}

class _TableSizeDialog extends StatefulWidget {
  const _TableSizeDialog();

  @override
  State<_TableSizeDialog> createState() => _TableSizeDialogState();
}

class _TableSizeDialogState extends State<_TableSizeDialog> {
  final _columns = TextEditingController(text: '3');
  final _rows = TextEditingController(text: '3');

  @override
  void dispose() {
    _columns.dispose();
    _rows.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Размер таблицы'),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 90,
            child: TextField(
              controller: _columns,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Столбцов'),
            ),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 90,
            child: TextField(
              controller: _rows,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Строк'),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () {
            final columns = int.tryParse(_columns.text.trim()) ?? 3;
            final rows = int.tryParse(_rows.text.trim()) ?? 3;
            Navigator.of(context).pop((
              columns.clamp(1, 8).toInt(),
              rows.clamp(1, 200).toInt(),
            ));
          },
          child: const Text('Вставить'),
        ),
      ],
    );
  }
}

class _ToolDivider extends StatelessWidget {
  const _ToolDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 22,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: const Color(0xFFCDD5E1),
    );
  }
}

TextAlign _textAlignOf(DocAlign align) => switch (align) {
  DocAlign.left => TextAlign.left,
  DocAlign.center => TextAlign.center,
  DocAlign.right => TextAlign.right,
  DocAlign.justify => TextAlign.justify,
};

int _columns(DocBlock block) =>
    block.rows.map((row) => row.length).fold<int>(1, (a, b) => a > b ? a : b);

List<List<String>> _normalizedRows(DocBlock block, int columns) => [
  for (final row in block.rows)
    [
      for (var c = 0; c < columns; c++) c < row.length ? row[c] : '',
    ],
];

String _baseName(String path) => path
    .split(RegExp(r'[/\\]'))
    .last
    .replaceAll(RegExp(r'[^\wА-Яа-яЁё0-9._-]+'), '_');
