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
    required this.onClientPrices,
    required this.onDealerPrices,
    required this.onCompany,
    required this.onWatermark,
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
  final ValueChanged<PriceList> onClientPrices;
  final ValueChanged<PriceList> onDealerPrices;
  final VoidCallback onCompany;
  final VoidCallback onWatermark;
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
                _companyCard(),
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
                          icon: const Icon(Icons.branding_watermark_outlined, size: 17),
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
                          icon: const Icon(Icons.inventory_2_outlined, size: 17),
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
            for (final child in children)
              SizedBox(width: width, child: child),
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
