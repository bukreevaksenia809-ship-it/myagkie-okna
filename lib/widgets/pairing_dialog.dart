import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/order_project.dart';
import '../services/pairing.dart';

/// Связь с замерщиком: код компьютера, подключение телефона и входящие заказы.
Future<void> showPairingDialog(
  BuildContext context, {
  required OrderProject project,
  required ValueChanged<IncomingOrder> onOpenOrder,
}) {
  return showDialog<void>(
    context: context,
    builder: (context) => PairingDialog(
      project: project,
      onOpenOrder: onOpenOrder,
    ),
  );
}

class PairingDialog extends StatefulWidget {
  const PairingDialog({
    super.key,
    required this.project,
    required this.onOpenOrder,
  });

  final OrderProject project;
  final ValueChanged<IncomingOrder> onOpenOrder;

  @override
  State<PairingDialog> createState() => _PairingDialogState();
}

class _PairingDialogState extends State<PairingDialog> {
  final _codeController = TextEditingController();
  PairingCode? _desktopCode;
  String? _pairedCode;
  String? _pairedName;
  List<IncomingOrder> _incoming = const [];
  List<PairingDevice> _devices = const [];
  Timer? _poll;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
    _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _poll?.cancel();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _busy = true);
    final code = await Pairing.currentCode();
    final paired = await Pairing.pairedCode();
    final incoming = await Pairing.listIncoming();
    final devices = await Pairing.listDevices();
    if (!mounted) return;
    setState(() {
      _desktopCode = code;
      _pairedCode = paired;
      _incoming = incoming;
      _devices = devices;
      if (!silent) _busy = false;
      if (incoming.isEmpty && Pairing.lastError != null) {
        _message = Pairing.lastError;
      }
    });
  }

  Future<void> _createCode() async {
    setState(() => _busy = true);
    final code = await Pairing.createCode();
    if (!mounted) return;
    setState(() {
      _desktopCode = code;
      _busy = false;
      _message = code == null ? Pairing.lastError ?? 'Не удалось создать код' : null;
    });
  }

  Future<void> _join() async {
    setState(() => _busy = true);
    final result = await Pairing.join(_codeController.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = result.ok
          ? 'Подключено к ${result.desktopName.isEmpty ? result.code : result.desktopName}'
          : result.message;
      if (result.ok) {
        _pairedCode = result.code;
        _pairedName = result.desktopName;
      }
    });
  }

  Future<void> _send() async {
    setState(() => _busy = true);
    final id = await Pairing.sendOrder(widget.project);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = id == null
          ? Pairing.lastError ?? 'Не удалось отправить заказ'
          : 'Заказ отправлен на производство';
    });
  }

  Future<void> _open(IncomingOrder order) async {
    await Pairing.markImported(order.id);
    if (!mounted) return;
    Navigator.of(context).pop();
    widget.onOpenOrder(order);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final code = _desktopCode;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 580, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.phone_iphone, color: theme.colorScheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Связь с замерщиком',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _card(
                        title: 'Код этого компьютера',
                        child: code == null
                            ? Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'Создайте код и передайте его замерщику.',
                                    ),
                                  ),
                                  FilledButton(
                                    onPressed: _busy ? null : _createCode,
                                    child: const Text('Создать код'),
                                  ),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      SelectableText(
                                        code.code,
                                        style: const TextStyle(
                                          fontSize: 30,
                                          fontWeight: FontWeight.w800,
                                          letterSpacing: 6,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      IconButton(
                                        tooltip: 'Скопировать',
                                        onPressed: () {
                                          Clipboard.setData(
                                            ClipboardData(text: code.code),
                                          );
                                          setState(
                                            () => _message = 'Код скопирован',
                                          );
                                        },
                                        icon: const Icon(Icons.copy, size: 20),
                                      ),
                                      const Spacer(),
                                      TextButton(
                                        onPressed: _busy ? null : _createCode,
                                        child: const Text('Новый код'),
                                      ),
                                    ],
                                  ),
                                  const Text(
                                    'Замерщик вводит эти 6 цифр в мобильном '
                                    'приложении — и заказы приходят сюда.',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                  if (_devices.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      'Подключены: '
                                      '${_devices.map((device) => device.name.isEmpty ? device.installId : device.name).join(', ')}',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF2E7D32),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        title: 'Подключиться к компьютеру',
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    key: const Key('pairing-code'),
                                    controller: _codeController,
                                    keyboardType: TextInputType.number,
                                    inputFormatters: [
                                      FilteringTextInputFormatter.digitsOnly,
                                      LengthLimitingTextInputFormatter(6),
                                    ],
                                    decoration: const InputDecoration(
                                      labelText: '6 цифр',
                                      hintText: '000000',
                                      border: OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                FilledButton(
                                  key: const Key('pairing-join'),
                                  onPressed: _busy ? null : _join,
                                  child: const Text('Подключиться'),
                                ),
                              ],
                            ),
                            if (_pairedCode != null) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Телефон подключён к ${_pairedName?.isNotEmpty == true ? _pairedName : _pairedCode}',
                                style: const TextStyle(fontSize: 12),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      _card(
                        title: 'Передать заказ на производство',
                        child: Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Отправит текущий заказ на подключённый ПК.',
                                style: TextStyle(fontSize: 12),
                              ),
                            ),
                            FilledButton.icon(
                              onPressed: _busy ? null : _send,
                              icon: const Icon(Icons.upload, size: 18),
                              label: const Text('Передать'),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Заказы от замерщика',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Обновить',
                            onPressed: _busy ? null : _load,
                            icon: const Icon(Icons.refresh),
                          ),
                        ],
                      ),
                      if (_busy) const LinearProgressIndicator(),
                      if (_incoming.isEmpty && !_busy)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 10),
                          child: Text(
                            'Пока нет входящих заказов.',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                      for (final order in _incoming)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(order.name.isEmpty ? 'Заказ с телефона' : order.name),
                          subtitle: Text(
                            '${order.summary} · ${_date(order.createdAt)}',
                            style: const TextStyle(fontSize: 11),
                          ),
                          trailing: FilledButton(
                            onPressed: _busy ? null : () => _open(order),
                            child: const Text('Открыть'),
                          ),
                        ),
                      if (_message != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _message!,
                          style: TextStyle(
                            color: theme.colorScheme.error,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF6F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFDCE3ED)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
          ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(local.day)}.${two(local.month)} ${two(local.hour)}:${two(local.minute)}';
  }
}
