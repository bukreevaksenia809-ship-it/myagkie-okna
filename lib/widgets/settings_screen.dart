import 'package:flutter/material.dart';

import '../models/price_list.dart';
import '../models/window_params.dart';
import '../services/company_branding.dart';
import 'design/app_kit.dart';
import 'label_settings_dialog.dart';
import 'pricebook_switcher.dart';

/// Настройки: компания, прайсы, подписи, лицензия, связь, данные и обновления.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    super.key,
    required this.clientPrices,
    required this.dealerPrices,
    required this.materials,
    required this.rollWidths,
    required this.rollGap,
    required this.onRollWidth,
    required this.onRollGap,
    required this.onClientPrices,
    required this.onDealerPrices,
    required this.onCompany,
    required this.onWatermark,
    required this.onSignatures,
    required this.onAllowances,
    required this.onTentConsumption,
    required this.onPairing,
    required this.onBackup,
    required this.onBackupDatabase,
    required this.onRefresh,
    required this.orderCount,
    required this.ordersFolder,
    required this.databaseReady,
    required this.version,
    this.onLicense,
    this.onCheckUpdates,
  });

  final PriceList clientPrices;
  final PriceList dealerPrices;
  final List<FilmMaterial> materials;
  final Map<FilmMaterial, double> rollWidths;
  final double rollGap;
  final void Function(FilmMaterial material, double width) onRollWidth;
  final ValueChanged<double> onRollGap;
  final ValueChanged<PriceList> onClientPrices;
  final ValueChanged<PriceList> onDealerPrices;
  final VoidCallback onCompany;
  final VoidCallback onWatermark;
  final VoidCallback onSignatures;
  final VoidCallback onAllowances;
  final void Function(bool enabled, double centimeters) onTentConsumption;
  final VoidCallback onPairing;
  final VoidCallback onBackup;
  final VoidCallback onBackupDatabase;
  final VoidCallback onRefresh;
  final int orderCount;
  final String ordersFolder;
  final bool databaseReady;
  final String version;
  final VoidCallback? onLicense;
  final VoidCallback? onCheckUpdates;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async => onRefresh(),
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: AppPageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppPageHeader(
                  eyebrow: 'Приложение',
                  title: 'Настройки',
                  subtitle:
                      'Реквизиты для документов, прайсы, подписи, лицензия и '
                      'резервные копии. Настройки общие для всех заказов.',
                ),
                const SizedBox(height: 18),
                _rollWidthCard(),
                const SizedBox(height: 14),
                _companyCard(),
                const SizedBox(height: 14),
                _signaturesCard(),
                const SizedBox(height: 14),
                _allowancesCard(),
                const SizedBox(height: 14),
                _tentConsumptionCard(),
                const SizedBox(height: 14),
                AppSurface(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppSectionTitle(
                        title: 'Прайс-листы',
                        subtitle:
                            'Клиентский и дилерский прайсы независимы. '
                            'Смета клиента считается по клиентскому, смета дилера — по дилерскому.',
                        trailing: IconButton(
                          tooltip: 'Сбросить подписи',
                          onPressed: () => showLabelSettingsDialog(context),
                          icon: const Icon(Icons.text_fields, size: 18),
                        ),
                      ),
                      const SizedBox(height: 14),
                      PricebookSwitcher(
                        client: clientPrices,
                        dealer: dealerPrices,
                        materials: materials,
                        onClientChanged: onClientPrices,
                        onDealerChanged: onDealerPrices,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                _grid(
                  children: [
                    _actionCard(
                      title: 'Документы и подписи',
                      icon: Icons.text_fields,
                      lines: const [
                        'Размеры подписей: чертёж, раскрой, смета, техкарта.',
                        'Водяной знак на листах.',
                      ],
                      actions: [
                        OutlinedButton.icon(
                          onPressed: () => showLabelSettingsDialog(context),
                          icon: const Icon(Icons.text_fields, size: 17),
                          label: const Text('Подписи'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onWatermark,
                          icon: const Icon(
                            Icons.branding_watermark_outlined,
                            size: 17,
                          ),
                          label: const Text('Водяной знак'),
                        ),
                      ],
                    ),
                    _actionCard(
                      title: 'Компания и реквизиты',
                      icon: Icons.business_outlined,
                      lines: const [
                        'Название, ИНН, телефон и логотип на чертеже и в смете.',
                        'Показ компании на листах включается в диалоге.',
                      ],
                      actions: [
                        FilledButton.icon(
                          onPressed: onCompany,
                          icon: const Icon(Icons.edit_outlined, size: 17),
                          label: const Text('Открыть реквизиты'),
                        ),
                      ],
                    ),
                    _actionCard(
                      title: 'Связь и лицензия',
                      icon: Icons.verified_user_outlined,
                      lines: [
                        if (onLicense != null)
                          'Лицензия и быстрая блокировка при отзыве ключа.'
                        else
                          'Магазинная сборка: лицензия не требуется.',
                        'Код для замерщика и передача заказа с телефона.',
                      ],
                      actions: [
                        if (onLicense != null)
                          OutlinedButton.icon(
                            onPressed: onLicense,
                            icon: const Icon(Icons.key_outlined, size: 17),
                            label: const Text('Лицензия'),
                          ),
                        OutlinedButton.icon(
                          onPressed: onPairing,
                          icon: const Icon(Icons.phone_iphone, size: 17),
                          label: const Text('Связь с замерщиком'),
                        ),
                      ],
                    ),
                    _actionCard(
                      title: 'Данные и резервные копии',
                      icon: Icons.storage_outlined,
                      lines: [
                        databaseReady
                            ? 'Локальная SQLite открыта: склад и заказы сохраняются.'
                            : 'База не открылась — проверьте сообщение на экране склада.',
                        'Заказов в файлах: $orderCount.',
                        ordersFolder,
                      ],
                      actions: [
                        OutlinedButton.icon(
                          onPressed: onBackupDatabase,
                          icon: const Icon(Icons.storage_outlined, size: 17),
                          label: const Text('Копия базы'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onBackup,
                          icon: const Icon(
                            Icons.inventory_2_outlined,
                            size: 17,
                          ),
                          label: const Text('Копия заказов'),
                        ),
                        OutlinedButton.icon(
                          onPressed: onRefresh,
                          icon: const Icon(Icons.refresh, size: 17),
                          label: const Text('Обновить список'),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                _aboutCard(context),
                const SizedBox(height: 30),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _rollWidthCard() {
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'Ширина рулона',
            subtitle:
                'Для раскроя и раскладки. Выбор сохраняется в заказе по '
                'каждому материалу.',
          ),
          const SizedBox(height: 14),
          for (final material in materials) ...[
            Text(
              '${material.label} · доступно ${material.rollWidthsLabel} мм',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF33465E),
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final width in material.rollWidths)
                  ChoiceChip(
                    label: Text(
                      '${formatMm(width)} мм',
                      style: const TextStyle(fontSize: 12),
                    ),
                    selected:
                        (rollWidths[material] ?? material.defaultRollWidth) ==
                        width,
                    onSelected: (_) => onRollWidth(material, width),
                  ),
              ],
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 4),
          TextFormField(
            key: const Key('roll-gap-settings'),
            initialValue: rollGap.round().toString(),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Зазор между заготовками, мм',
              helperText: 'отступ при раскладке на рулоне',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (raw) {
              final value = double.tryParse(raw.replaceAll(',', '.'));
              if (value != null && value >= 0) onRollGap(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _signaturesCard() {
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FB),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.draw_outlined, color: Color(0xFF0B62C4)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Подписи и печать',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'Подпись и печать подрядчика, подпись клиента на PDF.',
                  style: TextStyle(fontSize: 11.5, color: AppTokens.muted),
                ),
              ],
            ),
          ),
          OutlinedButton(
            key: const Key('settings-signatures'),
            onPressed: onSignatures,
            child: const Text('Открыть'),
          ),
        ],
      ),
    );
  }

  Widget _allowancesCard() {
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FB),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.content_cut, color: Color(0xFF0B62C4)),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Припуски на раскрой',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 2),
                Text(
                  'По умолчанию выключены. Здесь можно включить припуск для текущего окна.',
                  style: TextStyle(fontSize: 11.5, color: AppTokens.muted),
                ),
              ],
            ),
          ),
          OutlinedButton(
            key: const Key('settings-allowances'),
            onPressed: onAllowances,
            child: const Text('Настроить'),
          ),
        ],
      ),
    );
  }

  Widget _tentConsumptionCard() {
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF1FB),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(
              Icons.layers_outlined,
              color: Color(0xFF0B62C4),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _TentConsumptionSettings(
              enabled: clientPrices.tentConsumptionEnabled,
              centimeters: clientPrices.tentConsumptionCm,
              onChanged: onTentConsumption,
            ),
          ),
        ],
      ),
    );
  }

  Widget _companyCard() {
    return ValueListenableBuilder<CompanyBrandingState>(
      valueListenable: CompanyBranding.current,
      builder: (context, branding, _) {
        final details = branding.details;
        return AppSurface(
          padding: const EdgeInsets.all(18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppTokens.copperSoft,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(
                  branding.logo != null
                      ? Icons.image_outlined
                      : Icons.business_outlined,
                  color: AppTokens.copper,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Компания на листах',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      details.name.trim().isEmpty
                          ? 'Реквизиты ещё не заполнены. Заполните один раз — они появятся на чертеже и в смете.'
                          : [
                              details.name,
                              if (details.inn.trim().isNotEmpty)
                                'ИНН ${details.inn}',
                              if (details.phone.trim().isNotEmpty)
                                details.phone,
                            ].join(' · '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        height: 1.45,
                        color: AppTokens.muted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    AppPill(
                      label: branding.isVisible
                          ? 'Показывается на листах'
                          : 'Скрыта на листах',
                      color: branding.isVisible
                          ? AppTokens.green
                          : AppTokens.faint,
                      dense: true,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onCompany,
                icon: const Icon(Icons.edit_outlined, size: 17),
                label: const Text('Изменить'),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _grid({required List<Widget> children}) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900 ? 2 : 1;
        final width = (constraints.maxWidth - 14 * (columns - 1)) / columns;
        return Wrap(
          spacing: 14,
          runSpacing: 14,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }

  Widget _actionCard({
    required String title,
    required IconData icon,
    required List<String> lines,
    required List<Widget> actions,
  }) {
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 19, color: AppTokens.copper),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final line in lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 3),
              child: Text(
                line,
                style: const TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: AppTokens.muted,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: actions),
        ],
      ),
    );
  }

  Widget _aboutCard(BuildContext context) {
    return AppSurface(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const AppSectionTitle(
            title: 'О приложении',
            subtitle: 'Мягкие окна Excl · чертежи, раскрой, склад и заказы',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppPill(label: 'Версия $version', color: AppTokens.inkSoft),
              const AppPill(
                label: 'SQLite · транзакции',
                color: AppTokens.green,
              ),
              const AppPill(
                label: 'Windows · macOS · Android · Web',
                color: AppTokens.blue,
              ),
              if (onCheckUpdates != null)
                OutlinedButton.icon(
                  onPressed: onCheckUpdates,
                  icon: const Icon(Icons.system_update_alt, size: 17),
                  label: const Text('Проверить обновления'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Данные хранятся локально. Резервная копия заказов копирует JSON-файлы; '
            'склад и резервы живут в SQLite и сохраняются между запусками.',
            style: TextStyle(fontSize: 10.5, color: AppTokens.faint),
          ),
        ],
      ),
    );
  }
}


/// Настройка «Учитывать расход тента в смете».
///
/// 120 см — на каждое окно (3 окна → 3,6 м). Значение сразу меняет смету:
/// строка «Расход тента» в материалах и итог пересчитываются без
/// перезапуска. Своё число вводится в сантиметрах.
class _TentConsumptionSettings extends StatefulWidget {
  const _TentConsumptionSettings({
    required this.enabled,
    required this.centimeters,
    required this.onChanged,
  });

  final bool enabled;
  final double centimeters;
  final void Function(bool enabled, double centimeters) onChanged;

  @override
  State<_TentConsumptionSettings> createState() =>
      _TentConsumptionSettingsState();
}

class _TentConsumptionSettingsState extends State<_TentConsumptionSettings> {
  late final TextEditingController _controller = TextEditingController(
    text: _label(widget.centimeters),
  );
  late bool _enabled = widget.enabled;
  String? _error;

  static String _label(double value) => value == value.roundToDouble()
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1).replaceAll('.', ',');

  @override
  void didUpdateWidget(_TentConsumptionSettings oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.centimeters != widget.centimeters) {
      final text = _label(widget.centimeters);
      if (_controller.text != text) _controller.text = text;
    }
    if (oldWidget.enabled != widget.enabled) _enabled = widget.enabled;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyCentimeters(String raw) {
    final value = parsePrice(raw);
    if (value == null) {
      setState(() => _error = 'Введите число сантиметров');
      return;
    }
    if (value <= 0 || value > 1000) {
      setState(() => _error = 'От 1 до 1000 см на окно');
      return;
    }
    setState(() => _error = null);
    widget.onChanged(_enabled, value);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Расход тента в смете',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Отдельная строка на весь заказ: 120 см на каждое окно. '
                    '3 окна → 3,6 м, 10 окон → 12 м.',
                    style: TextStyle(fontSize: 11.5, color: AppTokens.muted),
                  ),
                ],
              ),
            ),
            Switch(
              key: const Key('settings-tent-enabled'),
              value: _enabled,
              onChanged: (value) {
                setState(() => _enabled = value);
                widget.onChanged(value, _currentCentimeters());
              },
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            SizedBox(
              width: 130,
              child: TextField(
                key: const Key('settings-tent-cm'),
                controller: _controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: 'На окно, см',
                  isDense: true,
                  border: const OutlineInputBorder(),
                  errorText: _error,
                ),
                onSubmitted: _applyCentimeters,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              key: const Key('settings-tent-apply'),
              onPressed: () => _applyCentimeters(_controller.text),
              child: const Text('Применить'),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _enabled
                    ? 'В смете: ${_label(_currentCentimeters())} см × окон, '
                          'цена — из прайса тента соответствующей ширины.'
                    : 'Строка расхода тента в смету не добавляется.',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTokens.muted,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  double _currentCentimeters() => parsePrice(_controller.text) ?? 120;
}
