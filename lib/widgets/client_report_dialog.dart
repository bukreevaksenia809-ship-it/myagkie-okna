import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/order_project.dart';
import '../services/client_report_pdf.dart';
import '../services/company_branding.dart';

/// Диалог данных заказчика: заполняется один раз при сохранении отчёта,
/// чтобы не держать эти поля в основной панели программы.
///
/// Значения запоминаются между отчётами (SharedPreferences): имя, телефон,
/// адрес и исполнители не нужно вводить заново.
Future<ClientReportInfo?> showClientReportDialog(
  BuildContext context, {
  required OrderProject project,
  required CompanyBrandingState company,
}) {
  return showDialog<ClientReportInfo>(
    context: context,
    barrierDismissible: true,
    builder: (context) =>
        ClientReportDialog(project: project, company: company),
  );
}

class ClientReportDialog extends StatefulWidget {
  const ClientReportDialog({
    super.key,
    required this.project,
    required this.company,
  });

  final OrderProject project;
  final CompanyBrandingState company;

  @override
  State<ClientReportDialog> createState() => _ClientReportDialogState();
}

class _ClientReportDialogState extends State<ClientReportDialog> {
  static const _storageKey = 'client_report_info_v1';

  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _address = TextEditingController();
  final _comment = TextEditingController();
  final _manager = TextEditingController();
  final _surveyor = TextEditingController(text: 'Замер клиента');
  final _installer = TextEditingController(text: 'Без установки');
  String? _nameError;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    final window = widget.project.selected;
    final customer = window.customer.trim();
    final phoneMatch = RegExp(r'[+\d][\d\s()\-]{6,}').firstMatch(customer);
    _name.text = customer
        .replaceAll(RegExp(r'[+\d][\d\s()\-]{6,}'), '')
        .trim()
        .replaceAll(RegExp(r'[,;]+$'), '');
    _phone.text = phoneMatch?.group(0)?.trim() ?? '';
    _comment.text = window.projectName;
    final signer = widget.company.details.signer.trim();
    if (signer.isNotEmpty && signer != '—') _manager.text = signer;
    _restore();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw == null || raw.isEmpty) return;
      final json = jsonDecode(raw);
      if (json is! Map) return;
      String read(String key) => json[key] is String ? json[key] as String : '';
      if (!mounted) return;
      setState(() {
        if (read('name').isNotEmpty) _name.text = read('name');
        if (read('phone').isNotEmpty) _phone.text = read('phone');
        if (read('address').isNotEmpty) _address.text = read('address');
        if (read('comment').isNotEmpty) _comment.text = read('comment');
        if (read('manager').isNotEmpty) _manager.text = read('manager');
        if (read('surveyor').isNotEmpty) _surveyor.text = read('surveyor');
        if (read('installer').isNotEmpty) _installer.text = read('installer');
        _loaded = true;
      });
    } catch (_) {
      // Запоминание — приятный бонус, без него диалог тоже работает.
    }
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _nameError = 'Укажите имя клиента');
      return;
    }
    final info = ClientReportInfo(
      name: _name.text.trim(),
      phone: _phone.text.trim(),
      address: _address.text.trim(),
      comment: _comment.text.trim(),
      manager: _manager.text.trim(),
      surveyor: _surveyor.text.trim(),
      installer: _installer.text.trim(),
    );
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _storageKey,
        jsonEncode({
          'name': info.name,
          'phone': info.phone,
          'address': info.address,
          'comment': info.comment,
          'manager': info.manager,
          'surveyor': info.surveyor,
          'installer': info.installer,
        }),
      );
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pop(info);
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _phone,
      _address,
      _comment,
      _manager,
      _surveyor,
      _installer,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final narrow = MediaQuery.sizeOf(context).width < 620;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 640, maxHeight: narrow ? 700 : 760),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.badge_outlined,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Отчёт для клиента',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            'Заказ $_orderNumber · данные попадут на обложку. '
                            'Заполняется только здесь, в панели программы их нет.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      key: const Key('client-report-close'),
                      tooltip: 'Закрыть',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _section(theme, 'Клиент'),
                const SizedBox(height: 8),
                _field(
                  key: const Key('client-report-name'),
                  controller: _name,
                  label: 'ФИО клиента',
                  icon: Icons.person_outline,
                  autofocus: true,
                  errorText: _nameError,
                  onChanged: (_) {
                    if (_nameError != null) setState(() => _nameError = null);
                  },
                ),
                const SizedBox(height: 10),
                _field(
                  key: const Key('client-report-phone'),
                  controller: _phone,
                  label: 'Телефон',
                  icon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                ),
                const SizedBox(height: 10),
                _field(
                  key: const Key('client-report-address'),
                  controller: _address,
                  label: 'Адрес доставки / объекта',
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 10),
                _field(
                  key: const Key('client-report-comment'),
                  controller: _comment,
                  label: 'Комментарий (объект, пожелания)',
                  icon: Icons.notes_outlined,
                  maxLines: 2,
                ),
                const SizedBox(height: 18),
                _section(theme, 'Исполнители'),
                const SizedBox(height: 8),
                if (narrow) ...[
                  _field(
                    key: const Key('client-report-manager'),
                    controller: _manager,
                    label: 'Менеджер',
                    icon: Icons.support_agent_outlined,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    key: const Key('client-report-surveyor'),
                    controller: _surveyor,
                    label: 'Замерщик',
                    icon: Icons.straighten_outlined,
                  ),
                  const SizedBox(height: 10),
                  _field(
                    key: const Key('client-report-installer'),
                    controller: _installer,
                    label: 'Монтажник',
                    icon: Icons.handyman_outlined,
                  ),
                ] else
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: _field(
                          key: const Key('client-report-manager'),
                          controller: _manager,
                          label: 'Менеджер',
                          icon: Icons.support_agent_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          key: const Key('client-report-surveyor'),
                          controller: _surveyor,
                          label: 'Замерщик',
                          icon: Icons.straighten_outlined,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _field(
                          key: const Key('client-report-installer'),
                          controller: _installer,
                          label: 'Монтажник',
                          icon: Icons.handyman_outlined,
                        ),
                      ),
                    ],
                  ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    if (!_loaded)
                      Expanded(
                        child: Text(
                          'Можно заполнить заново — прошлые данные не найдены.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: Row(
                          children: [
                            Icon(
                              Icons.check_circle_outline,
                              size: 16,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                'Данные сохранятся для следующих отчётов',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(width: 12),
                    TextButton(
                      key: const Key('client-report-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      key: const Key('client-report-submit'),
                      onPressed: _save,
                      icon: const Icon(Icons.picture_as_pdf, size: 18),
                      label: const Text('Сформировать PDF'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _orderNumber {
    final number = widget.project.selected.drawingNumber.trim();
    return number.isEmpty ? 'б/н' : number;
  }

  Widget _section(ThemeData theme, String text) => Row(
    children: [
      Text(
        text.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          letterSpacing: 1.4,
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.primary,
        ),
      ),
      const SizedBox(width: 10),
      Expanded(child: Divider(color: theme.dividerColor.withValues(alpha: 0.4))),
    ],
  );

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool autofocus = false,
    int maxLines = 1,
    String? errorText,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      key: key,
      controller: controller,
      autofocus: autofocus,
      maxLines: maxLines,
      keyboardType: keyboardType,
      textInputAction:
          maxLines > 1 ? TextInputAction.newline : TextInputAction.next,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 19),
        errorText: errorText,
        isDense: true,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
