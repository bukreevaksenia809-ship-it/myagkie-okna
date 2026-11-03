import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../services/pdf_signature.dart';
import 'docs/signature_pad.dart';

/// Центр подписей: загрузить подпись/печать подрядчика, расписаться клиенту
/// пальцем и расставить всё на A4. Настройки применяются ко всем PDF —
/// чертежам, сметам, техкартам, документам и отчёту клиенту.
Future<bool> showSignatureCenter(BuildContext context) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const SignatureCenterDialog(),
  );
  return result == true;
}

class SignatureCenterDialog extends StatefulWidget {
  const SignatureCenterDialog({super.key});

  @override
  State<SignatureCenterDialog> createState() => _SignatureCenterDialogState();
}

class _SignatureCenterDialogState extends State<SignatureCenterDialog> {
  final SignatureSettings _settings = SignatureSettings.instance;
  SignatureRole _selected = SignatureRole.contractorSignature;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _settings.load().then((_) {
      if (mounted) setState(() => _loading = false);
    });
  }

  Future<Uint8List?> _pickImage() async {
    const group = XTypeGroup(
      label: 'Изображение',
      extensions: ['png', 'jpg', 'jpeg', 'webp'],
    );
    final file = await openFile(acceptedTypeGroups: const [group]);
    if (file == null) return null;
    return file.readAsBytes();
  }

  Future<void> _upload(SignatureRole role) async {
    final bytes = await _pickImage();
    if (!mounted || bytes == null || bytes.isEmpty) return;
    setState(() {
      _settings.items[role]!
        ..image = bytes
        ..enabled = true;
      _selected = role;
      _settings.enabled = true;
    });
  }

  Future<void> _draw(SignatureRole role) async {
    final bytes = await _showPad();
    if (!mounted || bytes == null || bytes.isEmpty) return;
    setState(() {
      _settings.items[role]!
        ..image = bytes
        ..enabled = true;
      _selected = role;
      _settings.enabled = true;
    });
  }

  Future<Uint8List?> _showPad() async {
    final key = GlobalKey<SignaturePadState>();
    final mobile = MediaQuery.sizeOf(context).width < 700;
    return showDialog<Uint8List>(
      context: context,
      barrierDismissible: false,
      builder: (context) => Dialog(
        insetPadding: EdgeInsets.symmetric(
          horizontal: mobile ? 8 : 32,
          vertical: mobile ? 8 : 24,
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Подпись пальцем или мышью',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const Text(
                  'Распишитесь в рамке. На телефоне можно рисовать пальцем.',
                  style: TextStyle(fontSize: 11.5, color: Color(0xFF66748A)),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: mobile ? 240 : 260,
                  child: SignaturePad(key: key),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    TextButton(
                      onPressed: () => key.currentState?.clear(),
                      child: const Text('Очистить'),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Отмена'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      key: const Key('signature-pad-done'),
                      onPressed: () async {
                        final bytes = await key.currentState?.exportPng();
                        if (context.mounted) {
                          Navigator.of(context).pop(bytes);
                        }
                      },
                      child: const Text('Готово'),
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

  Future<void> _save() async {
    await _settings.save();
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final mobile = size.width < 700;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: mobile ? 6 : 28,
        vertical: mobile ? 6 : 20,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 960, maxHeight: size.height - 24),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
              child: Row(
                children: [
                  const Icon(Icons.draw_outlined, color: Color(0xFF0B62C4)),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Подписи и печать',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Подпись и печать подрядчика, подпись клиента — на любой PDF',
                          style: TextStyle(
                            fontSize: 11,
                            color: Color(0xFF66748A),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    key: const Key('signature-enabled'),
                    value: _settings.enabled,
                    onChanged: (value) =>
                        setState(() => _settings.enabled = value),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final role in SignatureRole.values)
                                _roleCard(role),
                            ],
                          ),
                          const SizedBox(height: 14),
                          _placementCard(mobile),
                        ],
                      ),
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Подписи накладываются при сохранении и печати PDF.',
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Color(0xFF66748A),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      setState(() {
                        _settings.enabled = false;
                        for (final item in _settings.items.values) {
                          item.image = null;
                          item.enabled = true;
                        }
                      });
                      await _settings.save();
                    },
                    child: const Text('Очистить всё'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    key: const Key('signature-save'),
                    onPressed: _save,
                    icon: const Icon(Icons.check, size: 18),
                    label: const Text('Сохранить'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _roleCard(SignatureRole role) {
    final item = _settings.items[role]!;
    final isClient = role == SignatureRole.clientSignature;
    final available = item.image != null;
    return Container(
      width: 222,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: _selected == role
            ? const Color(0xFFEAF1FB)
            : const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _selected == role
              ? const Color(0xFF0B62C4)
              : const Color(0xFFD9E0EA),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  role.label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Switch(
                value: item.enabled,
                onChanged: available
                    ? (value) => setState(() => item.enabled = value)
                    : null,
              ),
            ],
          ),
          GestureDetector(
            onTap: available ? () => setState(() => _selected = role) : null,
            child: Container(
              height: 64,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE1E7F0)),
              ),
              child: available
                  ? Padding(
                      padding: const EdgeInsets.all(4),
                      child: Image.memory(
                        item.image!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) =>
                            const Center(child: Text('Не удалось показать')),
                      ),
                    )
                  : const Center(
                      child: Text(
                        'не загружено',
                        style: TextStyle(
                          fontSize: 10.5,
                          color: Color(0xFF8A97AA),
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 4,
            children: [
              TextButton.icon(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                ),
                onPressed: () => _upload(role),
                icon: const Icon(Icons.upload_file, size: 16),
                label: const Text('Файл', style: TextStyle(fontSize: 11)),
              ),
              if (!isClient)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                  ),
                  onPressed: () => _draw(role),
                  icon: const Icon(Icons.gesture, size: 16),
                  label: const Text(
                    'Подписать',
                    style: TextStyle(fontSize: 11),
                  ),
                ),
              if (available)
                IconButton(
                  tooltip: 'Удалить',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => item.image = null),
                  icon: const Icon(Icons.delete_outline, size: 17),
                ),
            ],
          ),
          if (isClient)
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('client-sign-now'),
                onPressed: () => _draw(role),
                icon: const Icon(Icons.fingerprint, size: 17),
                label: const Text('Клиент расписывается'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placementCard(bool mobile) {
    final item = _settings.items[_selected]!;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Размещение на листе',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              DropdownButton<SignaturePageMode>(
                value: _settings.pageMode,
                isDense: true,
                items: [
                  for (final mode in SignaturePageMode.values)
                    DropdownMenuItem(value: mode, child: Text(mode.label)),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _settings.pageMode = value);
                },
              ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            'Перетащите подпись или печать по листу. На телефоне — пальцем.',
            style: TextStyle(fontSize: 10.5, color: Color(0xFF66748A)),
          ),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: mobile ? 260 : 300,
              child: AspectRatio(
                aspectRatio: 210 / 297,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final height = constraints.maxHeight;
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFFDFDFD),
                        border: Border.all(color: const Color(0xFFC9D2DF)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 8,
                            offset: Offset(0, 3),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          Positioned(
                            left: 12,
                            top: 12,
                            child: Text(
                              'A4 · ${_settings.pageMode.label.toLowerCase()} страница',
                              style: const TextStyle(
                                fontSize: 8,
                                color: Color(0xFFA0AABA),
                              ),
                            ),
                          ),
                          for (final role in SignatureRole.values)
                            if (_settings.items[role]!.ready)
                              _draggable(role, width, height),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Text('Размер', style: TextStyle(fontSize: 11)),
              Expanded(
                child: Slider(
                  value: item.width.clamp(0.05, 0.7),
                  min: 0.05,
                  max: 0.7,
                  divisions: 26,
                  onChanged: item.image == null
                      ? null
                      : (value) => setState(() => item.width = value),
                ),
              ),
              Text(
                '${(item.width * 100).round()}%',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _draggable(SignatureRole role, double width, double height) {
    final item = _settings.items[role]!;
    final isSelected = _selected == role;
    final w = width * item.width;
    return Positioned(
      left: width * item.x,
      top: height * item.y,
      width: w,
      child: GestureDetector(
        onTap: () => setState(() => _selected = role),
        onPanUpdate: (details) {
          setState(() {
            _selected = role;
            item.x = (item.x + details.delta.dx / width).clamp(0.0, 0.95);
            item.y = (item.y + details.delta.dy / height).clamp(0.0, 0.95);
          });
        },
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(
              color: isSelected ? const Color(0xFF0B62C4) : Colors.transparent,
              width: 1.2,
            ),
          ),
          child: Image.memory(item.image!, fit: BoxFit.contain),
        ),
      ),
    );
  }
}
