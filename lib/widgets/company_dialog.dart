import 'package:flutter/material.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../models/document.dart';
import '../services/company_branding.dart';
import 'docs/file_path_dialog.dart';

/// Настройки компании: реквизиты и логотип для листов (смета, чертёж).
Future<void> showCompanyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (context) => const _CompanyDialog(),
  );
}

class _CompanyDialog extends StatefulWidget {
  const _CompanyDialog();

  @override
  State<_CompanyDialog> createState() => _CompanyDialogState();
}

class _CompanyDialogState extends State<_CompanyDialog> {
  late final TextEditingController _name;
  late final TextEditingController _inn;
  late final TextEditingController _ogrn;
  late final TextEditingController _address;
  late final TextEditingController _phone;
  late final TextEditingController _bank;
  late final TextEditingController _signer;
  late final TextEditingController _position;
  bool _busy = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    final details = CompanyBranding.current.value.details;
    _name = TextEditingController(text: details.name);
    _inn = TextEditingController(text: details.inn);
    _ogrn = TextEditingController(text: details.ogrn);
    _address = TextEditingController(text: details.address);
    _phone = TextEditingController(text: details.phone);
    _bank = TextEditingController(text: details.bank);
    _signer = TextEditingController(text: details.signer);
    _position = TextEditingController(text: details.signerPosition);
  }

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
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  CompanyDetails _details() => CompanyDetails(
    name: _name.text.trim(),
    inn: _inn.text.trim(),
    ogrn: _ogrn.text.trim(),
    address: _address.text.trim(),
    phone: _phone.text.trim(),
    bank: _bank.text.trim(),
    signer: _signer.text.trim(),
    signerPosition: _position.text.trim(),
    logoAssetRef: CompanyBranding.current.value.details.logoAssetRef,
  );

  Future<void> _pickLogo() async {
    final path = await askFilePath(
      context,
      title: 'Логотип компании',
      hint: 'Путь к PNG/JPG',
      note:
          'Логотип появится на смете и чертеже, если включён тумблер '
          '«Показывать данные компании». В браузере выбор файла недоступен — '
          'используйте настольную версию.',
    );
    if (path == null || path.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final ok = await CompanyBranding.importLogoFromPath(path.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = ok ? null : 'Не удалось прочитать файл по этому пути';
    });
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    await CompanyBranding.saveDetails(_details());
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Компания на листах'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Реквизиты подставляются в шапку сметы и в штамп чертежа. '
                'Логотип — слева от названия: на смете в синей шапке, на '
                'чертеже в штампе.',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder<CompanyBrandingState>(
                valueListenable: CompanyBranding.current,
                builder: (context, branding, _) => SwitchListTile(
                  key: const Key('company-dialog-toggle'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  value: branding.showOnSheets,
                  title: const Text(
                    'Показывать на смете и чертеже',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: const Text(
                    'Выключено — листы выглядят как раньше.',
                    style: TextStyle(fontSize: 11),
                  ),
                  onChanged: (value) => CompanyBranding.setShowOnSheets(value),
                ),
              ),
              const SizedBox(height: 8),
              ValueListenableBuilder<CompanyBrandingState>(
                valueListenable: CompanyBranding.current,
                builder: (context, branding, _) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      DropTarget(
                        onDragDone: (details) async {
                          final files = details.files;
                          if (files.isEmpty) return;
                          final file = files.first;
                          final lower = file.name.toLowerCase();
                          if (!(lower.endsWith('.png') ||
                              lower.endsWith('.jpg') ||
                              lower.endsWith('.jpeg') ||
                              lower.endsWith('.webp'))) {
                            setState(() => _message =
                                'Перетащите PNG, JPG или WEBP');
                            return;
                          }
                          final bytes = await file.readAsBytes();
                          if (!mounted) return;
                          await CompanyBranding.setLogoBytes(
                            bytes,
                            fileName: file.name,
                          );
                          if (!mounted) return;
                          setState(() {
                            _message = null;
                            _busy = false;
                          });
                        },
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F9FC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: const Color(0xFFB9C7D9),
                              style: BorderStyle.solid,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 96,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF1F4F9),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: const Color(0xFFD9E0EA),
                                  ),
                                ),
                                alignment: Alignment.center,
                                child: branding.logo == null
                                    ? const Text(
                                        'перетащите\nлоготип',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: Color(0xFF8A93A0),
                                        ),
                                      )
                                    : Image.memory(
                                        branding.logo!,
                                        fit: BoxFit.contain,
                                      ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Перетащите PNG/JPG сюда или выберите файл',
                                      style: TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    Wrap(
                                      spacing: 6,
                                      children: [
                                        OutlinedButton.icon(
                                          key: const Key('company-logo-load'),
                                          onPressed: _busy ? null : _pickLogo,
                                          icon: const Icon(
                                            Icons.image_outlined,
                                            size: 18,
                                          ),
                                          label: const Text('Выбрать'),
                                        ),
                                        if (branding.logo != null)
                                          TextButton.icon(
                                            key: const Key(
                                              'company-logo-remove',
                                            ),
                                            onPressed: _busy
                                                ? null
                                                : () async {
                                                    await CompanyBranding
                                                        .removeLogo();
                                                  },
                                            icon: const Icon(
                                              Icons.delete_outline,
                                              size: 18,
                                            ),
                                            label: const Text('Удалить'),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        'Положение в шапке документа',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        children: [
                          for (final placement in LogoPlacement.values)
                            ChoiceChip(
                              key: Key('logo-place-${placement.name}'),
                              label: Text(placement.label),
                              selected: branding.logoPlacement == placement,
                              onSelected: (_) =>
                                  CompanyBranding.setLogoPlacement(placement),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Где показывать логотип',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final document in LogoDocument.values)
                            FilterChip(
                              key: Key('logo-doc-${document.name}'),
                              label: Text(document.label),
                              selected: branding.logoDocuments.contains(
                                document,
                              ),
                              onSelected: (selected) {
                                final next = Set<LogoDocument>.of(
                                  branding.logoDocuments,
                                );
                                if (selected) {
                                  next.add(document);
                                } else {
                                  next.remove(document);
                                }
                                CompanyBranding.setLogoDocuments(next);
                              },
                            ),
                        ],
                      ),
                    ],
                  );
                },
              ),
              if (_message != null) ...[
                const SizedBox(height: 6),
                Text(
                  _message!,
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFFB03A3A)),
                ),
              ],
              const SizedBox(height: 12),
              _field(_name, 'Название компании', key: 'company-name'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _field(_inn, 'ИНН', key: 'company-inn')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_ogrn, 'ОГРН', key: 'company-ogrn')),
                ],
              ),
              const SizedBox(height: 8),
              _field(_address, 'Адрес', key: 'company-address'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _field(_phone, 'Телефон', key: 'company-phone')),
                  const SizedBox(width: 10),
                  Expanded(child: _field(_bank, 'Банк / счёт', key: 'company-bank')),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _field(_signer, 'Подписант', key: 'company-signer'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _field(
                      _position,
                      'Должность',
                      key: 'company-position',
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          key: const Key('company-save'),
          onPressed: _busy ? null : _save,
          child: const Text('Сохранить'),
        ),
      ],
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    required String key,
  }) {
    return TextField(
      key: Key(key),
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
