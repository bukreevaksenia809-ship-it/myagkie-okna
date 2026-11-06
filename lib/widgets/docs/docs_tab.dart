// Вкладка «Документация»: центр клиентских документов заказа.
//
// Слева (на широком экране) — список документов заказа, справа — редактор или
// A4-предпросмотр. На узком экране список превращается в выпадающий выбор, а
// действия с документом живут в меню. Всё сохраняется в shared_preferences,
// картинки и подписи — в отдельном хранилище ассетов.
import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/document.dart';
import '../../models/order_project.dart';
import '../../models/price_list.dart';
import '../../services/document_pdf.dart';
import '../../services/company_branding.dart';
import '../../services/document_store.dart';
import '../docs/document_editor.dart';
import '../docs/document_page.dart';

/// Вкладка «Документация».
class DocsTab extends StatefulWidget {
  const DocsTab({super.key, required this.project, required this.prices});

  final OrderProject project;
  final PriceList prices;

  @override
  State<DocsTab> createState() => _DocsTabState();
}

class _DocsTabState extends State<DocsTab> {
  final DocumentStore _store = DocumentStore();
  final GlobalKey<DocumentPagesState> _pagesKey = GlobalKey<DocumentPagesState>();

  DocumentLibrary? _library;
  bool _loading = true;
  bool _busy = false;
  bool _preview = true;
  String? _error;
  String _loadedKey = '';
  int _loadToken = 0;
  Timer? _saveTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant DocsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (documentOrderKey(widget.project) != _loadedKey) {
      _load();
    }
  }

  @override
  void dispose() {
    _saveTimer?.cancel();
    // Последнее изменение не должно потеряться при переключении вкладки.
    _saveNow();
    super.dispose();
  }

  Future<void> _load() async {
    final token = ++_loadToken;
    final key = documentOrderKey(widget.project);
    setState(() {
      _loadedKey = key;
      _loading = true;
      _error = null;
    });
    try {
      final library = await _store.loadLibrary(key, project: widget.project);
      if (!mounted || token != _loadToken) return;
      setState(() {
        _library = library;
        _loading = false;
        if (library.isEmpty) _preview = false;
      });
    } catch (error) {
      if (!mounted || token != _loadToken) return;
      setState(() {
        _loading = false;
        _error = 'Не удалось прочитать документы: $error';
      });
    }
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 350), _saveNow);
  }

  Future<void> _saveNow() async {
    final library = _library;
    if (library == null) return;
    try {
      await _store.saveLibrary(library);
      // Реквизиты из настроек документов сразу подхватывают листы (смета,
      // чертёж): обновляем общий кеш брендинга.
      await CompanyBranding.load(store: _store, force: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Не удалось сохранить документы: $error')),
      );
    }
  }

  void _setLibrary(DocumentLibrary library, {bool saveNow = false}) {
    setState(() => _library = library);
    if (saveNow) {
      _saveTimer?.cancel();
      _saveNow();
    } else {
      _scheduleSave();
    }
  }

  void _updateDocument(OrderDocument document) {
    final library = _library;
    if (library == null) return;
    _setLibrary(library.replaceDocument(document));
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _chooseTemplate() async {
    final template = await showDialog<DocumentTemplate>(
      context: context,
      builder: (context) => const _TemplateDialog(),
    );
    if (template == null || !mounted) return;
    final library = _library;
    if (library == null) return;
    final document = DocumentTemplates.create(
      template,
      project: widget.project,
      prices: widget.prices,
      company: library.company,
      customer: library.customer,
    );
    _setLibrary(library.addDocument(document), saveNow: true);
    setState(() => _preview = false);
  }

  void _select(String id) {
    final library = _library;
    if (library == null || library.selectedId == id) return;
    _setLibrary(library.select(id), saveNow: true);
  }

  Future<void> _duplicate(String id) async {
    final library = _library;
    if (library == null) return;
    _setLibrary(library.duplicateDocument(id), saveNow: true);
    _toast('Документ дублирован');
  }

  Future<void> _rename(String id) async {
    final library = _library;
    final document =
        library?.documents.where((item) => item.id == id).firstOrNull;
    if (library == null || document == null) return;
    final controller = TextEditingController(text: document.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Переименовать документ'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Название',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(context).pop(controller.text.trim()),
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (title == null || title.isEmpty) return;
    _setLibrary(library.renameDocument(id, title), saveNow: true);
  }

  Future<void> _delete(String id) async {
    final library = _library;
    final document =
        library?.documents.where((item) => item.id == id).firstOrNull;
    if (library == null || document == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить документ?'),
        content: Text(
          '«${document.title}» будет удалён. Текст документа пропадёт, '
          'вложения останутся в хранилище ассетов.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    _setLibrary(library.removeDocument(id), saveNow: true);
  }

  Future<void> _refreshFromOrder(OrderDocument document) async {
    final library = _library;
    if (library == null || document.template == DocumentTemplate.custom) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Обновить из заказа?'),
        content: const Text(
          'Текст документа будет заменён шаблоном с актуальными реквизитами и '
          'позициями сметы. Ручные правки пропадут.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Обновить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final fresh = DocumentTemplates.create(
      document.template,
      project: widget.project,
      prices: widget.prices,
      company: library.company,
      customer: library.customer,
    );
    _setLibrary(
      library.replaceDocument(
        document.copyWith(
          blocks: fresh.blocks,
          number: fresh.number,
          updatedAt: DateTime.now(),
        ),
      ),
      saveNow: true,
    );
    _toast('Документ обновлён из заказа');
  }

  Future<void> _openSettings() async {
    final library = _library;
    if (library == null) return;
    final result = await showDialog<
      ({CompanyDetails company, CustomerDetails customer})
    >(
      context: context,
      builder: (context) => _SettingsDialog(
        company: library.company,
        customer: library.customer,
      ),
    );
    if (result == null) return;
    _setLibrary(
      library.withCompany(result.company).withCustomer(result.customer),
      saveNow: true,
    );
    _toast('Реквизиты сохранены — новые документы подставят их автоматически');
  }

  Future<void> _ensurePreview() async {
    if (!_preview) {
      setState(() => _preview = true);
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _exportPdf() async {
    final document = _library?.selected;
    if (document == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _ensurePreview();
      final pages = _pagesKey.currentState;
      if (pages == null) {
        _toast('Документ ещё верстается — попробуйте ещё раз');
        return;
      }
      await pages.ensureAssetsLoaded();
      final saved = await exportDocumentPdf(
        pageKeys: pages.pageKeys,
        document: document,
      );
      _toast('PDF сохранён: ${saved.destination}');
    } catch (error) {
      _toast('Не удалось собрать PDF: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print() async {
    final document = _library?.selected;
    if (document == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _ensurePreview();
      final pages = _pagesKey.currentState;
      if (pages == null) {
        _toast('Документ ещё верстается — попробуйте ещё раз');
        return;
      }
      await pages.ensureAssetsLoaded();
      await printDocument(pageKeys: pages.pageKeys, document: document);
    } catch (error) {
      _toast('Не удалось напечатать: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = _library;
    return ColoredBox(
      color: const Color(0xFFDDE3EC),
      child: Column(
        children: [
          _header(),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? _errorView(_error!)
                : library == null
                ? const SizedBox.shrink()
                : library.isEmpty
                ? _EmptyDocs(onPick: _chooseTemplate)
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 900;
                      if (!wide) {
                        return Column(
                          children: [
                            _narrowSelector(library),
                            Expanded(child: _editorArea(library)),
                          ],
                        );
                      }
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(width: 300, child: _docsList(library)),
                          const VerticalDivider(width: 1),
                          Expanded(child: _editorArea(library)),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final library = _library;
    final hasDocs = library != null && library.documents.isNotEmpty;
    return Container(
      color: const Color(0xFFF2F5F9),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            FilledButton.icon(
              key: const Key('docs-create'),
              onPressed: _chooseTemplate,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Документ'),
            ),
            const SizedBox(width: 8),
            if (hasDocs) ...[
              OutlinedButton.icon(
                key: const Key('docs-preview-toggle'),
                onPressed: () => setState(() => _preview = !_preview),
                icon: Icon(
                  _preview ? Icons.edit_outlined : Icons.visibility_outlined,
                  size: 18,
                ),
                label: Text(_preview ? 'Редактировать' : 'Предпросмотр'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('docs-pdf'),
                onPressed: _busy ? null : _exportPdf,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf, size: 18),
                label: const Text('PDF'),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                key: const Key('docs-print'),
                onPressed: _busy ? null : _print,
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Печать'),
              ),
              const SizedBox(width: 8),
            ],
            IconButton(
              key: const Key('docs-settings'),
              tooltip: 'Реквизиты компании и клиента',
              onPressed: _openSettings,
              icon: const Icon(Icons.settings_outlined, size: 20),
            ),
          ],
        ),
      ),
    );
  }

  Widget _docsList(DocumentLibrary library) {
    final selected = library.selected;
    return Container(
      color: const Color(0xFFF7F9FC),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Документы заказа',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '${library.documents.length}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF66748A),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              itemCount: library.documents.length,
              itemBuilder: (context, index) {
                final document = library.documents[index];
                final isSelected = selected?.id == document.id;
                return Material(
                  color: isSelected
                      ? const Color(0xFFE3EEFC)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(8),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => _select(document.id),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 4, 8),
                      child: Row(
                        children: [
                          Icon(
                            _templateIcon(document.template),
                            size: 20,
                            color: isSelected
                                ? const Color(0xFF0B62C4)
                                : const Color(0xFF66748A),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  document.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  [
                                    if (document.number.trim().isNotEmpty)
                                      document.number,
                                    'ред. ${formatDocDate(document.updatedAt)}',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: Color(0xFF66748A),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _docMenu(document),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Клиент',
                  style: TextStyle(fontSize: 10, color: Color(0xFF8A94A6)),
                ),
                const SizedBox(height: 2),
                Text(
                  library.customer.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                Text(
                  library.company.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
                const SizedBox(height: 4),
                TextButton.icon(
                  onPressed: _openSettings,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
                  icon: const Icon(Icons.settings_outlined, size: 16),
                  label: const Text(
                    'Реквизиты',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _narrowSelector(DocumentLibrary library) {
    final selected = library.selected;
    return Container(
      color: const Color(0xFFF7F9FC),
      padding: const EdgeInsets.fromLTRB(10, 4, 6, 4),
      child: Row(
        children: [
          const Icon(Icons.description_outlined, size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: selected?.id,
                isExpanded: true,
                style: const TextStyle(fontSize: 13, color: Color(0xFF1F2937)),
                items: [
                  for (final document in library.documents)
                    DropdownMenuItem(
                      value: document.id,
                      child: Text(
                        document.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (id) {
                  if (id != null) _select(id);
                },
              ),
            ),
          ),
          if (selected != null) _docMenu(selected),
        ],
      ),
    );
  }

  Widget _docMenu(OrderDocument document) {
    return PopupMenuButton<String>(
      tooltip: 'Действия с документом',
      icon: const Icon(Icons.more_vert, size: 18),
      onSelected: (value) {
        switch (value) {
          case 'duplicate':
            _duplicate(document.id);
          case 'rename':
            _rename(document.id);
          case 'refresh':
            _refreshFromOrder(document);
          case 'delete':
            _delete(document.id);
        }
      },
      itemBuilder: (context) => [
        const PopupMenuItem(value: 'duplicate', child: Text('Дублировать')),
        const PopupMenuItem(value: 'rename', child: Text('Переименовать')),
        if (document.template != DocumentTemplate.custom)
          const PopupMenuItem(
            value: 'refresh',
            child: Text('Обновить из заказа'),
          ),
        const PopupMenuItem(value: 'delete', child: Text('Удалить')),
      ],
    );
  }

  Widget _editorArea(DocumentLibrary library) {
    final document = library.selected;
    if (document == null) return const SizedBox.shrink();
    if (_preview) {
      return DocumentPages(
        key: _pagesKey,
        document: document,
        assets: _store.readAsset,
      );
    }
    return DocumentEditor(
      key: ValueKey(document.id),
      document: document,
      store: _store,
      assets: _store.readAsset,
      onChanged: _updateDocument,
    );
  }

  Widget _errorView(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 36, color: Color(0xFFB42318)),
            const SizedBox(height: 10),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: _load, child: const Text('Повторить')),
          ],
        ),
      ),
    );
  }
}

IconData _templateIcon(DocumentTemplate template) => switch (template) {
  DocumentTemplate.act => Icons.task_alt,
  DocumentTemplate.contract => Icons.handshake_outlined,
  DocumentTemplate.offer => Icons.request_quote_outlined,
  DocumentTemplate.specification => Icons.list_alt_outlined,
  DocumentTemplate.warranty => Icons.verified_outlined,
  DocumentTemplate.invoice => Icons.receipt_long_outlined,
  DocumentTemplate.custom => Icons.description_outlined,
};

class _TemplateDialog extends StatelessWidget {
  const _TemplateDialog();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Новый документ'),
      content: SizedBox(
        width: 540,
        height: 430,
        child: ListView(
          children: [
            for (final template in DocumentTemplate.values)
              ListTile(
                leading: Icon(_templateIcon(template)),
                title: Text(template.title),
                subtitle: Text(template.description),
                onTap: () => Navigator.of(context).pop(template),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
      ],
    );
  }
}

class _EmptyDocs extends StatelessWidget {
  const _EmptyDocs({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const Text(
          'Документы заказа',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: Color(0xFF1F2937),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Выберите шаблон — клиент, объект, реквизиты и позиции сметы '
          'подставятся автоматически. Любой текст и таблицу можно править.',
          style: TextStyle(fontSize: 12.5, color: Color(0xFF66748A)),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final template in DocumentTemplate.values)
              SizedBox(
                width: 168,
                child: Card(
                  margin: EdgeInsets.zero,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: onPick,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            _templateIcon(template),
                            color: const Color(0xFF0B62C4),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            template.title,
                            style: const TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            template.description,
                            style: const TextStyle(
                              fontSize: 10.5,
                              color: Color(0xFF66748A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Создать документ'),
          ),
        ),
      ],
    );
  }
}

class _SettingsDialog extends StatefulWidget {
  const _SettingsDialog({required this.company, required this.customer});

  final CompanyDetails company;
  final CustomerDetails customer;

  @override
  State<_SettingsDialog> createState() => _SettingsDialogState();
}

class _SettingsDialogState extends State<_SettingsDialog> {
  late final _name = TextEditingController(text: widget.company.name);
  late final _inn = TextEditingController(text: widget.company.inn);
  late final _ogrn = TextEditingController(text: widget.company.ogrn);
  late final _address = TextEditingController(text: widget.company.address);
  late final _phone = TextEditingController(text: widget.company.phone);
  late final _bank = TextEditingController(text: widget.company.bank);
  late final _signer = TextEditingController(text: widget.company.signer);
  late final _position = TextEditingController(
    text: widget.company.signerPosition,
  );
  late final _customerName = TextEditingController(text: widget.customer.name);
  late final _customerPhone = TextEditingController(
    text: widget.customer.phone,
  );
  late final _customerAddress = TextEditingController(
    text: widget.customer.address,
  );

  @override
  void dispose() {
    for (final controller in [
      _name,
      _inn,
      _ogrn,
      _address,
      _phone,
      _bank,
      _signer,
      _position,
      _customerName,
      _customerPhone,
      _customerAddress,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Реквизиты'),
      content: SizedBox(
        width: 560,
        height: 460,
        child: ListView(
          children: [
            const _SectionLabel('Компания'),
            _field(_name, 'Название'),
            _field(_inn, 'ИНН'),
            _field(_ogrn, 'ОГРН'),
            _field(_address, 'Адрес', maxLines: 2),
            _field(_phone, 'Телефон'),
            _field(_bank, 'Банк, р/с'),
            _field(_signer, 'Подписант (ФИО)'),
            _field(_position, 'Должность подписанта'),
            const SizedBox(height: 10),
            const _SectionLabel('Клиент и объект'),
            _field(_customerName, 'Клиент'),
            _field(_customerPhone, 'Телефон клиента'),
            _field(_customerAddress, 'Объект / адрес', maxLines: 2),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            company: CompanyDetails(
              name: _name.text.trim(),
              inn: _inn.text.trim(),
              ogrn: _ogrn.text.trim(),
              address: _address.text.trim(),
              phone: _phone.text.trim(),
              bank: _bank.text.trim(),
              signer: _signer.text.trim(),
              signerPosition: _position.text.trim(),
            ),
            customer: CustomerDetails(
              name: _customerName.text.trim(),
              phone: _customerPhone.text.trim(),
              address: _customerAddress.text.trim(),
            ),
          )),
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    int maxLines = 1,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          isDense: true,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 10,
          ),
        ),
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: Color(0xFF0B62C4),
        ),
      ),
    );
  }
}
