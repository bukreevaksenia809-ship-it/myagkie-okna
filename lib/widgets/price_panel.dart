import 'package:flutter/material.dart';

import '../models/price_list.dart';

/// Раздел «Прайс-лист»: цены материалов, фурнитуры и работ для сметы.
///
/// Значения живут в [PriceList] и используются листом «Смета». Поля
/// синхронизируются мягко: текст переписывается только если распарсенное
/// число отличается от модельного, поэтому набор с клавиатуры не сбивается.
class PricePanel extends StatefulWidget {
  const PricePanel({
    super.key,
    required this.prices,
    required this.onChanged,
  });

  final PriceList prices;
  final ValueChanged<PriceList> onChanged;

  @override
  State<PricePanel> createState() => _PricePanelState();
}

class _PricePanelState extends State<PricePanel> {
  final _controllers = <String, TextEditingController>{};
  bool _open = false;

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prices = widget.prices;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'ПРАЙС-ЛИСТ',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.9,
                      color: Color(0xFF66748A),
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: const Color(0xFF8A93A0),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Цены уходят в смету: заказ считается автоматически. '
            'Всё в рублях за единицу.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          if (_open) ...[
            const SizedBox(height: 10),
            _group('Полотно, ₽/м²', [
              _row(
                'Обычный ПВХ',
                prices.film(PriceField.filmClear),
                (value) => _set(prices.copyWith(
                  filmClearPerM2: value,
                )),
              ),
              _row(
                'Тонированный',
                prices.film(PriceField.filmTinted),
                (value) => _set(prices.copyWith(
                  filmTintedPerM2: value,
                )),
              ),
              _row(
                'Москитная сетка',
                prices.film(PriceField.filmMesh),
                (value) => _set(prices.copyWith(
                  filmMeshPerM2: value,
                )),
              ),
            ]),
            _group('Окантовка, ₽/м', [
              _row(
                'Тент 100 мм',
                prices.edge(PriceField.edge100),
                (value) => _set(prices.copyWith(edge100PerM: value)),
              ),
              _row(
                'Тент 200 мм',
                prices.edge(PriceField.edge200),
                (value) => _set(prices.copyWith(edge200PerM: value)),
              ),
              _row(
                'Тент 240 мм',
                prices.edge(PriceField.edge240),
                (value) => _set(prices.copyWith(edge240PerM: value)),
              ),
            ]),
            _group('Фурнитура', [
              _row(
                'Люверс, ₽/шт',
                prices.eyeletPrice,
                (value) => _set(prices.copyWith(eyeletPrice: value)),
              ),
              _row(
                'Молния, ₽/м',
                prices.zipperPerM,
                (value) => _set(prices.copyWith(zipperPerM: value)),
              ),
              _row(
                'Спайка, ₽/м',
                prices.weldPerM,
                (value) => _set(prices.copyWith(weldPerM: value)),
              ),
              _row(
                'Карман, ₽/м',
                prices.pocketPerM,
                (value) => _set(prices.copyWith(pocketPerM: value)),
              ),
              _row(
                'Ремень, ₽/шт',
                prices.strapPrice,
                (value) => _set(prices.copyWith(strapPrice: value)),
              ),
              _row(
                'Дренаж, ₽/шт',
                prices.drainPrice,
                (value) => _set(prices.copyWith(drainPrice: value)),
              ),
              _row(
                'Вырез, ₽/шт',
                prices.cutoutPrice,
                (value) => _set(prices.copyWith(cutoutPrice: value)),
              ),
            ]),
            _group('Работы и итог', [
              _row(
                'Сборка, ₽/м² изделия',
                prices.laborPerM2,
                (value) => _set(prices.copyWith(laborPerM2: value)),
              ),
              _row(
                'Наценка, %',
                prices.markupPercent,
                (value) => _set(prices.copyWith(markupPercent: value)),
              ),
              _row(
                'Скидка, %',
                prices.discountPercent,
                (value) => _set(prices.copyWith(discountPercent: value)),
              ),
              _row(
                'НДС, %',
                prices.vatPercent,
                (value) => _set(prices.copyWith(vatPercent: value)),
              ),
            ]),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(
                  () => widget.onChanged(const PriceList.defaults()),
                ),
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Вернуть цены по умолчанию'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _set(PriceList prices) => widget.onChanged(prices);

  Widget _group(String title, List<Widget> children) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title.toUpperCase(),
            style: const TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: Color(0xFF7C8798),
            ),
          ),
          const SizedBox(height: 4),
          ...children,
        ],
      ),
    );
  }

  Widget _row(String label, double value, ValueChanged<double> onChanged) {
    final controller = _controllers.putIfAbsent(
      label,
      () => TextEditingController(text: _format(value)),
    );
    final parsed = parsePrice(controller.text);
    if (parsed == null || (parsed - value).abs() > 1e-9) {
      final text = _format(value);
      if (controller.text != text) {
        controller.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontSize: 12, color: Color(0xFF2B3440)),
            ),
          ),
          SizedBox(
            width: 96,
            child: TextField(
              controller: controller,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              style: const TextStyle(fontSize: 12.5),
              onChanged: (text) {
                final number = parsePrice(text);
                if (number != null) onChanged(number);
              },
            ),
          ),
        ],
      ),
    );
  }

  String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }
}
