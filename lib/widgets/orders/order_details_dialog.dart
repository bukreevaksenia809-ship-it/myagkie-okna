import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/order_repository.dart';
import '../../data/warehouse_repository.dart';
import '../../models/order_project.dart';
import '../../models/order_record.dart';
import '../../models/price_list.dart';
import '../../models/warehouse.dart';
import '../design/app_kit.dart';
import '../docs/docs_tab.dart';
import '../warehouse/order_materials_dialog.dart';

/// Открывает карточку заказа. Возвращает true, если что-то изменилось.
Future<bool> showOrderDetailsDialog(
  BuildContext context,
  OrderRecord order, {
  ValueChanged<OrderRecord>? onOpenProject,
}) async {
  final changed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _OrderDetailsDialog(
      order: order,
      onOpenProject: onOpenProject,
    ),
  );
  return changed == true;
}

enum _OrderTab {
  overview('Обзор', Icons.dashboard_outlined),
  materials('Материалы', Icons.inventory_2_outlined),
  checklist('Чек-лист', Icons.checklist_outlined),
  comments('Комментарии', Icons.forum_outlined),
  history('История', Icons.history),
  files('Файлы', Icons.attach_file),
  documents('Документы', Icons.description_outlined);

  const _OrderTab(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _OrderDetailsDialog extends StatefulWidget {
  const _OrderDetailsDialog({required this.order, this.onOpenProject});

  final OrderRecord order;
  final ValueChanged<OrderRecord>? onOpenProject;

  @override
  State<_OrderDetailsDialog> createState() => _OrderDetailsDialogState();
}

class _OrderDetailsDialogState extends State<_OrderDetailsDialog> {
  final _repo = OrderRepository.instance;
  late OrderRecord _order = widget.order;
  OrderDetails? _details;
  List<OrderMaterial> _materials = const [];
  _OrderTab _tab = _OrderTab.overview;
  bool _loading = true;
  bool _saving = false;
  bool _changed = false;
  String? _message;
  bool _messageError = false;

  late final TextEditingController _title;
  late final TextEditingController _customer;
  late final TextEditingController _phone;
  late final TextEditingController _address;
  late final TextEditingController _assignee;
  late final TextEditingController _labels;
  late final TextEditingController _comment;
  final _checklist = TextEditingController();
  final _newComment = TextEditingController();
  final _linkName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fillControllers();
    _load();
  }

  void _fillControllers() {
    _title = TextEditingController(text: _order.title);
    _customer = TextEditingController(text: _order.customer);
    _phone = TextEditingController(text: _order.phone);
    _address = TextEditingController(text: _order.address);
    _assignee = TextEditingController(text: _order.assignee);
    _labels = TextEditingController(text: _order.labels.join(', '));
    _comment = TextEditingController(text: _order.comment);
  }

  @override
  void dispose() {
    for (final controller in [
      _title,
      _customer,
      _phone,
      _address,
      _assignee,
      _labels,
      _comment,
      _checklist,
      _newComment,
      _linkName,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final details = await _repo.details(_order.id);
      final materials = await WarehouseRepository.instance.orderMaterials(_order.id);
      if (!mounted) return;
      setState(() {
        _details = details;
        _materials = materials;
        _order = details.order;
        _loading = false;
      });
      _title.text = _order.title;
      _customer.text = _order.customer;
      _phone.text = _order.phone;
      _address.text = _order.address;
      _assignee.text = _order.assignee;
      _labels.text = _order.labels.join(', ');
      _comment.text = _order.comment;
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _message = 'Не удалось открыть заказ: $error';
        _messageError = true;
      });
    }
  }

  Future<void> _saveMetadata() async {
    setState(() => _saving = true);
    final next = _order.copyWith(
      title: _title.text.trim(),
      customer: _customer.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      assignee: _assignee.text.trim(),
      labels: _labels.text
          .split(',')
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList(),
      comment: _comment.text.trim(),
    );
    final result = await _repo.updateMetadata(next);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = result.message;
      _messageError = !result.ok;
      if (result.order != null) _order = result.order!;
      _changed = _changed || result.ok;
    });
    if (result.ok) await _load();
  }

  Future<void> _setStatus(OrderStatus status) async {
    final result = await _repo.setStatus(_order.id, status);
    if (!mounted) return;
    setState(() {
      _message = result.message;
      _messageError = !result.ok;
      _changed = _changed || result.ok;
    });
    await _load();
  }

  Future<void> _setPriority(OrderPriority priority) async {
    final result = await _repo.updateMetadata(
      _order.copyWith(priority: priority),
    );
    if (!mounted) return;
    setState(() {
      _message = result.message;
      _messageError = !result.ok;
      _changed = _changed || result.ok;
    });
    await _load();
  }

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 2)),
      initialDate: _order.deadline ?? now.add(const Duration(days: 7)),
    );
    if (picked == null) return;
    final result = await _repo.updateMetadata(
      _order.copyWith(deadline: picked),
    );
    if (!mounted) return;
    setState(() {
      _message = result.message;
      _messageError = !result.ok;
      _changed = _changed || result.ok;
    });
    await _load();
  }

  Future<void> _clearDeadline() async {
    final result = await _repo.updateMetadata(
      _order.copyWith(clearDeadline: true),
    );
    if (!mounted) return;
    setState(() {
      _message = result.message;
      _messageError = !result.ok;
      _changed = _changed || result.ok;
    });
    await _load();
  }

  Future<void> _openMaterials() async {
    final changed = await showOrderMaterialsDialog(context, _order);
    if (!mounted) return;
    _changed = _changed || changed;
    await _load();
  }

  Future<void> _openProject() async {
    final project = _repo.projectOf(_order);
    if (widget.onOpenProject != null) {
      widget.onOpenProject!(_order);
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    // Без внешнего обработчика показываем сводку проекта.
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Окна заказа ${_order.number}'),
        content: Text(
          'Окон: ${project.windowCount}\n'
          'Материалы: ${project.materialsInOrder.map((m) => m.label).join(', ')}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Понятно'),
          ),
        ],
      ),
    );
  }

  Future<void> _addComment() async {
    final text = _newComment.text.trim();
    if (text.isEmpty) return;
    await _repo.addComment(_order.id, text);
    _newComment.clear();
    _changed = true;
    await _load();
  }

  Future<void> _addChecklist() async {
    final text = _checklist.text.trim();
    if (text.isEmpty) return;
    await _repo.addChecklistItem(_order.id, text);
    _checklist.clear();
    await _load();
  }

  Future<void> _pickAttachment() async {
    const typeGroup = XTypeGroup(
      label: 'Фото и документы',
      extensions: ['png', 'jpg', 'jpeg', 'webp', 'gif', 'pdf', 'docx', 'xlsx'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return;
    final bytes = await file.readAsBytes();
    await _repo.addAttachmentBytes(
      _order.id,
      name: file.name,
      bytes: bytes,
      mime: _mimeFor(file.name),
    );
    await _load();
    _changed = true;
    if (mounted) setState(() => _message = 'Файл прикреплён');
  }

  Future<void> _addLink() async {
    final name = _linkName.text.trim();
    if (name.isEmpty) return;
    final url = await showDialog<String>(
      context: context,
      builder: (context) {
        final controller = TextEditingController();
        return AlertDialog(
          title: const Text('Ссылка на файл'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'URL или путь к файлу',
              hintText: 'https://…',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Добавить'),
            ),
          ],
        );
      },
    );
    if (url == null || url.isEmpty) return;
    await _repo.addAttachment(
      _order.id,
      name: name,
      url: url.startsWith('http') ? url : '',
      path: url.startsWith('http') ? '' : url,
    );
    _linkName.clear();
    await _load();
    _changed = true;
  }

  String _mimeFor(String name) {
    final lower = name.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    return 'application/octet-stream';
  }

  Future<void> _duplicate() async {
    final copy = await _repo.duplicateOrder(_order.id);
    if (copy == null) return;
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _archive() async {
    final result = await _repo.archive(_order.id, !_order.archived);
    if (!mounted) return;
    setState(() {
      _message = result.message;
      _messageError = !result.ok;
      _changed = _changed || result.ok;
    });
    await _load();
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить заказ?'),
        content: const Text(
          'Заказ и его история, чек-лист, комментарии и файлы будут удалены. '
          'Материалы, уже списанные на склад, останутся в журнале.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(backgroundColor: AppTokens.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _repo.deleteOrder(_order.id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final narrow = width < 900;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: narrow ? 8 : 28,
        vertical: narrow ? 8 : 20,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1180),
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.92,
          child: Column(
            children: [
              _header(narrow),
              const Divider(height: 1),
              _tabBar(),
              const Divider(height: 1),
              Expanded(
                child: _loading && _details == null
                    ? const Center(child: CircularProgressIndicator())
                    : _body(narrow),
              ),
              if (_message != null) ...[
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                  child: AppBanner(
                    message: _message!,
                    tone: _messageError ? AppTokens.red : AppTokens.green,
                    icon: _messageError
                        ? Icons.error_outline
                        : Icons.check_circle_outline,
                  ),
                ),
              ],
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
                child: Row(
                  children: [
                    Text(
                      'Обновлён ${appDateTime(_order.updatedAt ?? DateTime.now())}',
                      style: const TextStyle(
                        fontSize: 10.5,
                        color: AppTokens.faint,
                      ),
                    ),
                    const Spacer(),
                    if (_tab == _OrderTab.overview)
                      FilledButton.icon(
                        onPressed: _saving ? null : _saveMetadata,
                        icon: _saving
                            ? const SizedBox(
                                width: 15,
                                height: 15,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.save_outlined, size: 17),
                        label: const Text('Сохранить'),
                      ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(_changed),
                      child: const Text('Закрыть'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(bool narrow) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _order.priority.color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Center(
              child: Text(
                _order.priority == OrderPriority.urgent
                    ? '!'
                    : _order.number.replaceAll(RegExp(r'\D'), '').padLeft(2, '0'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                  color: _order.priority.color,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      _order.number,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: AppTokens.copper,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _statusPill(),
                    const SizedBox(width: 6),
                    AppPill(
                      label: _order.priority.label,
                      color: _order.priority.color,
                      dense: true,
                    ),
                    if (_order.archived) ...[
                      const SizedBox(width: 6),
                      const AppPill(
                        label: 'Архив',
                        color: AppTokens.faint,
                        dense: true,
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  _order.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  [
                    if (_order.customer.isNotEmpty) _order.customer,
                    if (_order.phone.isNotEmpty) _order.phone,
                    if (_order.address.isNotEmpty) _order.address,
                  ].join(' · '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: AppTokens.muted,
                  ),
                ),
              ],
            ),
          ),
          if (!narrow) ...[
            OutlinedButton.icon(
              onPressed: _openMaterials,
              icon: const Icon(Icons.inventory_2_outlined, size: 17),
              label: const Text('Материалы'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: _openProject,
              icon: const Icon(Icons.architecture_outlined, size: 17),
              label: const Text('Открыть в конструкторе'),
            ),
            const SizedBox(width: 4),
          ],
          PopupMenuButton<String>(
            tooltip: 'Ещё',
            onSelected: (value) {
              switch (value) {
                case 'materials':
                  _openMaterials();
                case 'project':
                  _openProject();
                case 'duplicate':
                  _duplicate();
                case 'archive':
                  _archive();
                case 'delete':
                  _delete();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'materials',
                child: Text('Материалы склада'),
              ),
              const PopupMenuItem(
                value: 'project',
                child: Text('Открыть в конструкторе'),
              ),
              const PopupMenuItem(
                value: 'duplicate',
                child: Text('Дублировать'),
              ),
              PopupMenuItem(
                value: 'archive',
                child: Text(_order.archived ? 'Вернуть из архива' : 'В архив'),
              ),
              const PopupMenuItem(value: 'delete', child: Text('Удалить')),
            ],
          ),
          IconButton(
            tooltip: 'Закрыть',
            onPressed: () => Navigator.of(context).pop(_changed),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _statusPill() {
    return PopupMenuButton<OrderStatus>(
      tooltip: 'Сменить статус',
      onSelected: _setStatus,
      itemBuilder: (context) => [
        for (final status in OrderStatus.values)
          PopupMenuItem(
            value: status,
            child: Row(
              children: [
                _statusDot(status),
                const SizedBox(width: 8),
                Text(status.label),
                if (status == _order.status) ...[
                  const SizedBox(width: 8),
                  const Icon(Icons.check, size: 15),
                ],
              ],
            ),
          ),
      ],
      child: AppPill(
        label: _order.status.label,
        color: _statusColor(_order.status),
        icon: Icons.circle,
        dense: true,
      ),
    );
  }

  Widget _tabBar() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          for (final tab in _OrderTab.values)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: TextButton.icon(
                onPressed: () => setState(() => _tab = tab),
                style: TextButton.styleFrom(
                  foregroundColor: _tab == tab
                      ? AppTokens.copper
                      : AppTokens.muted,
                  backgroundColor: _tab == tab
                      ? AppTokens.copperSoft
                      : Colors.transparent,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                ),
                icon: Icon(tab.icon, size: 17),
                label: Text(
                  tab.label,
                  style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body(bool narrow) {
    return switch (_tab) {
      _OrderTab.overview => _overview(narrow),
      _OrderTab.materials => _materialsTab(),
      _OrderTab.checklist => _checklistTab(),
      _OrderTab.comments => _commentsTab(),
      _OrderTab.history => _historyTab(),
      _OrderTab.files => _filesTab(),
      _OrderTab.documents => _documentsTab(),
    };
  }

  Widget _overview(bool narrow) {
    final details = _details;
    final left = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSurface(
          padding: const EdgeInsets.all(16),
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const AppSectionTitle(
                title: 'Данные заказа',
                subtitle: 'Клиент, адрес и срок видны на доске и в календаре',
              ),
              const SizedBox(height: 14),
              _two(
                narrow,
                AppField(label: 'Название', controller: _title),
                AppField(label: 'Клиент', controller: _customer),
              ),
              const SizedBox(height: 10),
              _two(
                narrow,
                AppField(
                  label: 'Телефон',
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                ),
                AppField(label: 'Ответственный', controller: _assignee),
              ),
              const SizedBox(height: 10),
              AppField(label: 'Адрес', controller: _address),
              const SizedBox(height: 10),
              _two(narrow, _priorityField(), _deadlineField()),
              const SizedBox(height: 10),
              AppField(
                label: 'Метки',
                controller: _labels,
                hint: 'через запятую',
              ),
              const SizedBox(height: 10),
              AppField(label: 'Комментарий', controller: _comment, maxLines: 4),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AppSurface(
          padding: const EdgeInsets.all(16),
          shadow: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppSectionTitle(
                title: 'Связанные материалы',
                subtitle: details == null
                    ? 'Загрузка…'
                    : 'Резерв и списание — в отдельном окне',
                trailing: OutlinedButton.icon(
                  onPressed: _openMaterials,
                  icon: const Icon(Icons.inventory_2_outlined, size: 16),
                  label: const Text('Открыть'),
                ),
              ),
            ],
          ),
        ),
      ],
    );

    final right = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSurface(
          padding: const EdgeInsets.all(16),
          shadow: false,
          color: AppTokens.cream,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Сумма заказа',
                style: TextStyle(fontSize: 11, color: AppTokens.muted),
              ),
              const SizedBox(height: 4),
              Text(
                appMoney(_order.amount),
                style: const TextStyle(
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'по прайсу на момент сохранения',
                style: TextStyle(fontSize: 10, color: AppTokens.faint),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        AppSurface(
          padding: const EdgeInsets.all(16),
          shadow: false,
          child: Column(
            children: [
              _fact('Срок', _order.deadlineLabel, color: _deadlineColor()),
              _fact('Статус', _order.status.label),
              _fact(
                'Приоритет',
                _order.priority.label,
                color: _order.priority.color,
              ),
              _fact(
                'Ответственный',
                _order.assignee.isEmpty ? '—' : _order.assignee,
              ),
              _fact(
                'Чек-лист',
                details == null
                    ? '—'
                    : '${details.doneCount} из ${details.checklist.length}',
              ),
              _fact('Комментарии', '${details?.comments.length ?? 0}'),
              _fact('Файлы', '${details?.attachments.length ?? 0}'),
              _fact('Создан', appDate(_order.createdAt)),
            ],
          ),
        ),
      ],
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: narrow
          ? Column(children: [left, const SizedBox(height: 12), right])
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: left),
                const SizedBox(width: 14),
                Expanded(flex: 2, child: right),
              ],
            ),
    );
  }

  Widget _priorityField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Приоритет',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        DropdownButtonFormField<OrderPriority>(
          initialValue: _order.priority,
          items: [
            for (final priority in OrderPriority.values)
              DropdownMenuItem(value: priority, child: Text(priority.label)),
          ],
          onChanged: (value) {
            if (value != null) _setPriority(value);
          },
        ),
      ],
    );
  }

  Widget _deadlineField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Срок',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: AppTokens.muted,
          ),
        ),
        const SizedBox(height: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: AppTokens.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTokens.line),
          ),
          child: Row(
            children: [
              const Icon(Icons.event_outlined, size: 18, color: AppTokens.copper),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: _pickDeadline,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Text(
                      _order.deadline == null
                          ? 'Без срока'
                          : appDate(_order.deadline),
                      style: TextStyle(
                        fontSize: 13,
                        color: _order.deadline == null
                            ? AppTokens.faint
                            : AppTokens.ink,
                      ),
                    ),
                  ),
                ),
              ),
              if (_order.deadline != null)
                IconButton(
                  tooltip: 'Убрать срок',
                  visualDensity: VisualDensity.compact,
                  onPressed: _clearDeadline,
                  icon: const Icon(Icons.close, size: 16),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _materialsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppBanner(
            title: 'Материалы заказа',
            message:
                'Потребность считается по смете и раскрою: полотно, окантовка, '
                'люверсы и фурнитура. Резерв запрещает продавать материал '
                'другому заказу, списание идёт по FIFO.',
            tone: AppTokens.blue,
            icon: Icons.info_outline,
            action: FilledButton.icon(
              onPressed: _openMaterials,
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Открыть склад'),
            ),
          ),
          const SizedBox(height: 14),
          AppResponsiveGrid(
            minItemWidth: 180,
            maxColumns: 3,
            children: [
              AppMetricCard(
                label: 'Резерв',
                value: appQty(
                  _materials.fold<double>(0, (s, m) => s + m.reservedQty),
                ),
                icon: Icons.lock_outline,
                tone: AppTokens.copper,
                hint: '${_materials.where((m) => m.reservedQty > 0).length} поз.',
              ),
              AppMetricCard(
                label: 'Списано',
                value: appQty(
                  _materials.fold<double>(0, (s, m) => s + m.issuedQty),
                ),
                icon: Icons.check_circle_outline,
                tone: AppTokens.green,
                hint: '${_materials.where((m) => m.issuedQty > 0).length} поз.',
              ),
              AppMetricCard(
                label: 'Всего связано',
                value: '${_materials.length}',
                icon: Icons.link,
                tone: AppTokens.blue,
                hint: 'Позиций склада',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _checklistTab() {
    final details = _details;
    final items = details?.checklist ?? const <OrderChecklistItem>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSurface(
            padding: const EdgeInsets.all(16),
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppSectionTitle(
                  title: 'Чек-лист производства',
                  subtitle: items.isEmpty
                      ? 'Пока пусто'
                      : '${details!.doneCount} из ${items.length} выполнено',
                  trailing: OutlinedButton.icon(
                    onPressed: () async {
                      await _repo.addDefaultChecklist(_order.id);
                      await _load();
                    },
                    icon: const Icon(Icons.playlist_add, size: 16),
                    label: const Text('Стандартный'),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _checklist,
                        decoration: const InputDecoration(
                          hintText: 'Новый пункт чек-листа',
                        ),
                        onSubmitted: (_) => _addChecklist(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _addChecklist,
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Добавить'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (items.isEmpty)
                  const Text(
                    'Добавьте пункты или нажмите «Стандартный».',
                    style: TextStyle(fontSize: 12, color: AppTokens.muted),
                  )
                else
                  for (final item in items)
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: item.done,
                      onChanged: (_) async {
                        await _repo.toggleChecklistItem(item);
                        await _load();
                      },
                      title: Text(
                        item.text,
                        style: TextStyle(
                          fontSize: 13,
                          decoration: item.done
                              ? TextDecoration.lineThrough
                              : null,
                          color: item.done ? AppTokens.faint : AppTokens.ink,
                        ),
                      ),
                      secondary: IconButton(
                        tooltip: 'Удалить',
                        onPressed: () async {
                          await _repo.deleteChecklistItem(item.id);
                          await _load();
                        },
                        icon: const Icon(Icons.close, size: 16),
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _commentsTab() {
    final comments = _details?.comments ?? const <OrderComment>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSurface(
            padding: const EdgeInsets.all(16),
            shadow: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSectionTitle(
                  title: 'Комментарии',
                  subtitle: 'Внутренние заметки по заказу',
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newComment,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText: 'Написать комментарий…',
                        ),
                        onSubmitted: (_) => _addComment(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _addComment,
                      icon: const Icon(Icons.send, size: 17),
                      label: const Text('Отправить'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (comments.isEmpty)
                  const Text(
                    'Комментариев пока нет.',
                    style: TextStyle(fontSize: 12, color: AppTokens.muted),
                  )
                else
                  for (final comment in comments)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTokens.cream,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            comment.text,
                            style: const TextStyle(
                              fontSize: 12.5,
                              height: 1.45,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Row(
                            children: [
                              Text(
                                appDateTime(comment.at),
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTokens.faint,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Удалить',
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  await _repo.deleteComment(
                                    comment.id,
                                    _order.id,
                                  );
                                  await _load();
                                },
                                icon: const Icon(Icons.close, size: 14),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _historyTab() {
    final events = _details?.events ?? const <OrderEvent>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const AppSectionTitle(
              title: 'История изменений',
              subtitle: 'Кто и когда менял заказ',
            ),
            const SizedBox(height: 12),
            if (events.isEmpty)
              const Text(
                'История пока пуста.',
                style: TextStyle(fontSize: 12, color: AppTokens.muted),
              )
            else
              for (final event in events)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(top: 3),
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: AppTokens.copper,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.text,
                              style: const TextStyle(
                                fontSize: 12.5,
                                color: AppTokens.inkSoft,
                              ),
                            ),
                            Text(
                              appDateTime(event.at),
                              style: const TextStyle(
                                fontSize: 10,
                                color: AppTokens.faint,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _filesTab() {
    final files = _details?.attachments ?? const <OrderAttachment>[];
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: AppSurface(
        padding: const EdgeInsets.all(16),
        shadow: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppSectionTitle(
              title: 'Файлы и фото',
              subtitle: files.isEmpty
                  ? 'Прикрепите фото замера, эскиз или документ'
                  : '${files.length} файлов',
              trailing: Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickAttachment,
                    icon: const Icon(Icons.attach_file, size: 16),
                    label: const Text('Файл'),
                  ),
                  FilledButton.icon(
                    onPressed: _addLink,
                    icon: const Icon(Icons.link, size: 16),
                    label: const Text('Ссылка'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _linkName,
              decoration: const InputDecoration(
                hintText: 'Название ссылки перед добавлением',
              ),
            ),
            const SizedBox(height: 12),
            if (files.isEmpty)
              const Text(
                'Вложений пока нет.',
                style: TextStyle(fontSize: 12, color: AppTokens.muted),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final file in files) _attachmentCard(file),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _attachmentCard(OrderAttachment file) {
    final data = file.data;
    return Container(
      width: 190,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTokens.cream,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTokens.lineSoft),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (data != null && file.mime.startsWith('image/'))
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                data,
                height: 100,
                width: double.infinity,
                fit: BoxFit.cover,
              ),
            )
          else
            Container(
              height: 60,
              decoration: BoxDecoration(
                color: AppTokens.white,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Center(
                child: Icon(
                  file.url.isNotEmpty ? Icons.link : Icons.insert_drive_file,
                  color: AppTokens.copper,
                ),
              ),
            ),
          const SizedBox(height: 7),
          Text(
            file.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            appDate(file.addedAt),
            style: const TextStyle(fontSize: 10, color: AppTokens.faint),
          ),
          Row(
            children: [
              if (file.url.isNotEmpty)
                IconButton(
                  tooltip: 'Открыть ссылку',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => launchUrl(
                    Uri.parse(file.url),
                    mode: LaunchMode.externalApplication,
                  ),
                  icon: const Icon(Icons.open_in_new, size: 16),
                ),
              const Spacer(),
              IconButton(
                tooltip: 'Удалить',
                visualDensity: VisualDensity.compact,
                onPressed: () async {
                  await _repo.deleteAttachment(file.id);
                  await _load();
                },
                icon: const Icon(Icons.close, size: 15),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _documentsTab() {
    return DocsTab(
      project: _repo.projectOf(_order),
      prices: const PriceList.defaults(),
    );
  }

  Widget _fact(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 105,
            child: Text(
              label,
              style: const TextStyle(fontSize: 10.5, color: AppTokens.faint),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: color ?? AppTokens.inkSoft,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _two(bool narrow, Widget left, Widget right) {
    if (narrow) {
      return Column(children: [left, const SizedBox(height: 10), right]);
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: left),
        const SizedBox(width: 12),
        Expanded(child: right),
      ],
    );
  }

  Color _deadlineColor() => switch (_order.deadlineState) {
    DeadlineState.overdue => AppTokens.red,
    DeadlineState.today || DeadlineState.soon => AppTokens.amber,
    _ => AppTokens.inkSoft,
  };

  Widget _statusDot(OrderStatus status) => Container(
    width: 8,
    height: 8,
    decoration: BoxDecoration(
      color: _statusColor(status),
      shape: BoxShape.circle,
    ),
  );

  Color _statusColor(OrderStatus status) => switch (status) {
    OrderStatus.newOrder => AppTokens.blue,
    OrderStatus.measured => const Color(0xFF0B62C4),
    OrderStatus.production => AppTokens.copper,
    OrderStatus.ready => AppTokens.green,
    OrderStatus.installed => AppTokens.inkSoft,
    OrderStatus.cancelled => AppTokens.red,
  };
}
