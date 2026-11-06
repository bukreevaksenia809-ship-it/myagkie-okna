import 'package:flutter/material.dart';

import '../models/price_list.dart';
import '../models/window_params.dart';
import 'price_panel.dart';

/// Прайс-лист с переключателем «Клиент / Дилер».
///
/// Оба прайса независимы: дилерские цены начинаются с клиентских (как
/// просил заказчик), дальше их можно менять отдельно — смета для дилера
/// считается по ним.
class PricebookSwitcher extends StatefulWidget {
  const PricebookSwitcher({
    super.key,
    required this.client,
    required this.dealer,
    required this.onClientChanged,
    required this.onDealerChanged,
    this.materials = const [],
  });

  final PriceList client;
  final PriceList dealer;
  final ValueChanged<PriceList> onClientChanged;
  final ValueChanged<PriceList> onDealerChanged;
  final List<FilmMaterial> materials;

  @override
  State<PricebookSwitcher> createState() => _PricebookSwitcherState();
}

class _PricebookSwitcherState extends State<PricebookSwitcher> {
  bool _dealer = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: false, label: Text('Клиент')),
                  ButtonSegment(value: true, label: Text('Дилер')),
                ],
                selected: {_dealer},
                onSelectionChanged: (selection) =>
                    setState(() => _dealer = selection.first),
              ),
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: _dealer
                  ? 'Прайс для дилера: свои цены, в смету дилера'
                  : 'Клиентский прайс',
              child: Icon(
                _dealer ? Icons.handshake_outlined : Icons.person_outline,
                size: 18,
                color: const Color(0xFF66748A),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        PricePanel(
          prices: _dealer ? widget.dealer : widget.client,
          materials: widget.materials,
          onChanged: _dealer ? widget.onDealerChanged : widget.onClientChanged,
        ),
      ],
    );
  }
}
