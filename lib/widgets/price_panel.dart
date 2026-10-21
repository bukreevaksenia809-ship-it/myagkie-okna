import 'package:flutter/material.dart';

import '../models/price_list.dart';
import '../models/window_params.dart';

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
    this.materials = const [],
  });

  final PriceList prices;
  final ValueChanged<PriceList> onChanged;

  /// Материалы заказа: по ним показываем превью ПВХ/скрина и продающие
  /// подписи. Пустой список — панель без превью (так её используют тесты,
  /// которым нужен только прайс).
  final List<FilmMaterial> materials;

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
          const Text(
            'Цены уходят в смету: заказ считается автоматически. '
            'Галочка у строки — учитывать позицию в смете. '
            'Всё в рублях за единицу.',
            style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          _materialsPreview(),
          if (_open) ...[
            const SizedBox(height: 10),
            _group('Полотно, ₽/м²', [
              _row(
                'Обычный ПВХ',
                prices.film(PriceField.filmClear),
                (value) => _set(prices.copyWith(filmClearPerM2: value)),
                itemKey: PriceItemKeys.filmClear,
              ),
              _row(
                'Тонированный',
                prices.film(PriceField.filmTinted),
                (value) => _set(prices.copyWith(filmTintedPerM2: value)),
                itemKey: PriceItemKeys.filmTinted,
              ),
              _row(
                'Москитная сетка',
                prices.film(PriceField.filmMesh),
                (value) => _set(prices.copyWith(filmMeshPerM2: value)),
                itemKey: PriceItemKeys.filmMesh,
              ),
              _row(
                'Скрин, ₽/м²',
                prices.film(PriceField.filmScreen),
                (value) => _set(prices.copyWith(filmScreenPerM2: value)),
                itemKey: PriceItemKeys.filmScreen,
              ),
            ]),
            _group('Окантовка, ₽/м', [
              _row(
                'Тент 80 мм',
                prices.edge(PriceField.edge80),
                (value) => _set(prices.copyWith(edge80PerM: value)),
                itemKey: PriceItemKeys.edge80,
              ),
              _row(
                'Тент 100 мм',
                prices.edge(PriceField.edge100),
                (value) => _set(prices.copyWith(edge100PerM: value)),
                itemKey: PriceItemKeys.edge100,
              ),
              _row(
                'Тент 120 мм',
                prices.edge(PriceField.edge120),
                (value) => _set(prices.copyWith(edge120PerM: value)),
                itemKey: PriceItemKeys.edge120,
              ),
              _row(
                'Тент 200 мм',
                prices.edge(PriceField.edge200),
                (value) => _set(prices.copyWith(edge200PerM: value)),
                itemKey: PriceItemKeys.edge200,
              ),
              _row(
                'Тент 240 мм',
                prices.edge(PriceField.edge240),
                (value) => _set(prices.copyWith(edge240PerM: value)),
                itemKey: PriceItemKeys.edge240,
              ),
            ]),
            _group('Фурнитура', [
              _row(
                'Люверс круглый, ₽/шт',
                prices.eyeletPrice,
                (value) => _set(prices.copyWith(eyeletPrice: value)),
                itemKey: PriceItemKeys.eyeletRound,
              ),
              _row(
                'Люверс овальный, ₽/шт',
                prices.eyeletOvalPrice,
                (value) => _set(prices.copyWith(eyeletOvalPrice: value)),
                itemKey: PriceItemKeys.eyeletOval,
              ),
              _row(
                'Установка люверса, ₽/шт',
                prices.eyeletInstall,
                (value) => _set(prices.copyWith(eyeletInstall: value)),
                itemKey: PriceItemKeys.eyeletInstall,
              ),
              _row(
                'Молния, ₽/м',
                prices.zipperPerM,
                (value) => _set(prices.copyWith(zipperPerM: value)),
                itemKey: PriceItemKeys.zipper,
              ),
              _row(
                'Спайка, ₽/м',
                prices.weldPerM,
                (value) => _set(prices.copyWith(weldPerM: value)),
                itemKey: PriceItemKeys.weld,
              ),
              _row(
                'Фартук, ₽/м',
                prices.pocketPerM,
                (value) => _set(prices.copyWith(pocketPerM: value)),
                itemKey: PriceItemKeys.pocket,
              ),
              _row(
                'Ремень, ₽/шт',
                prices.strapPrice,
                (value) => _set(prices.copyWith(strapPrice: value)),
                itemKey: PriceItemKeys.strap,
              ),
              // Крепёж подвижных сторон: все три типа — за штуку.
              _row(
                'Поворотная скоба, ₽/шт',
                prices.turnBucklePrice,
                (value) => _set(prices.copyWith(turnBucklePrice: value)),
                itemKey: PriceItemKeys.turnBuckle,
              ),
              _row(
                'Французский замок, ₽/шт',
                prices.frenchLockPrice,
                (value) => _set(prices.copyWith(frenchLockPrice: value)),
                itemKey: PriceItemKeys.frenchLock,
              ),
              _row(
                'Саморез верхнего ряда, ₽/шт',
                prices.screwPrice,
                (value) => _set(prices.copyWith(screwPrice: value)),
                itemKey: PriceItemKeys.screw,
              ),
              _row(
                'Дренаж, ₽/шт',
                prices.drainPrice,
                (value) => _set(prices.copyWith(drainPrice: value)),
                itemKey: PriceItemKeys.drain,
              ),
              _row(
                'Вырез, ₽/шт',
                prices.cutoutPrice,
                (value) => _set(prices.copyWith(cutoutPrice: value)),
                itemKey: PriceItemKeys.cutout,
              ),
            ]),
            _group('Работы', [
              _row(
                'Сборка, ₽/м² изделия',
                prices.laborPerM2,
                (value) => _set(prices.copyWith(laborPerM2: value)),
                itemKey: PriceItemKeys.labor,
              ),
              _row(
                'Раскрой, ₽/м² плёнки',
                prices.cuttingPerM2,
                (value) => _set(prices.copyWith(cuttingPerM2: value)),
                itemKey: PriceItemKeys.cutting,
              ),
              _row(
                'Подворот скрина, ₽/м',
                prices.screenHemPerM,
                (value) => _set(prices.copyWith(screenHemPerM: value)),
                itemKey: PriceItemKeys.screenHem,
              ),
            ]),
            // Проценты — не позиции, а условия расчёта: у них нет тумблера,
            // «не считать» выражается нулём.
            _group('Условия расчёта', [
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

  /// Превью материалов заказа: ПВХ, скрин или оба рядом. Рисуются программно,
  /// без новых пакетов и картинок в assets.
  Widget _materialsPreview() {
    final materials = widget.materials;
    if (materials.isEmpty) return const SizedBox.shrink();
    final hasPvc = materials.any((material) => material != FilmMaterial.screen);
    final hasScreen = materials.any(
      (material) => material == FilmMaterial.screen,
    );
    return Column(
      key: const Key('price-material-previews'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        const Text(
          'МАТЕРИАЛЫ ЗАКАЗА',
          style: TextStyle(
            fontSize: 9.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Color(0xFF7C8798),
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (hasPvc)
              _materialCard(
                key: const Key('price-material-pvc'),
                title: 'ПВХ',
                caption:
                    'Лучшее решение в межсезонье — защита от снега и дождя. '
                    'Срок службы 10 лет.',
                screen: false,
              ),
            if (hasScreen)
              _materialCard(
                key: const Key('price-material-screen'),
                title: 'Скрин',
                caption:
                    'Защита от пыли, пуха и насекомых — окно при этом '
                    'проветривается.',
                screen: true,
              ),
          ],
        ),
      ],
    );
  }

  Widget _materialCard({
    required Key key,
    required String title,
    required String caption,
    required bool screen,
  }) {
    return Container(
      key: key,
      width: 165,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 58,
            width: double.infinity,
            child: CustomPaint(painter: _MaterialThumbPainter(screen: screen)),
          ),
          const SizedBox(height: 5),
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2B3440),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            caption,
            style: const TextStyle(
              fontSize: 10,
              height: 1.25,
              color: Color(0xFF66748A),
            ),
          ),
        ],
      ),
    );
  }

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

  /// Строка цены: подпись, тумблер «учитывать в смете» и поле ввода.
  ///
  /// [itemKey] — позиция прайса. У процентов расчёта позиции нет (`null`),
  /// поэтому тумблера у них тоже нет.
  Widget _row(
    String label,
    double value,
    ValueChanged<double> onChanged, {
    String? itemKey,
  }) {
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

    final enabled = itemKey == null || widget.prices.isEnabled(itemKey);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: enabled
                    ? const Color(0xFF2B3440)
                    : const Color(0xFFA3ADBB),
              ),
            ),
          ),
          if (itemKey != null) _toggle(label, itemKey, enabled),
          const SizedBox(width: 4),
          // Выключенная строка приглушена, но цену в ней ещё можно править:
          // включение вернёт её в смету уже с новой ценой.
          SizedBox(
            width: 84,
            child: Opacity(
              opacity: enabled ? 1 : 0.45,
              child: TextField(
                controller: controller,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 8,
                  ),
                ),
                style: const TextStyle(fontSize: 12.5),
                onChanged: (text) {
                  final number = parsePrice(text);
                  if (number != null) onChanged(number);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Компактный тумблер позиции: включена — позиция идёт в смету.
  ///
  /// Ключ `price-toggle-<itemKey>` стабилен, чтобы тесты и панель находили
  /// переключатель по позиции, а не по порядку строк.
  Widget _toggle(String label, String itemKey, bool enabled) {
    return IconButton(
      key: ValueKey('price-toggle-$itemKey'),
      tooltip: enabled
          ? 'Не учитывать в смете: $label'
          : 'Учитывать в смете: $label',
      onPressed: () => _set(widget.prices.withItem(itemKey, enabled: !enabled)),
      icon: Icon(
        enabled ? Icons.check_box : Icons.check_box_outline_blank,
        size: 18,
      ),
      color: enabled ? const Color(0xFF0B62C4) : const Color(0xFF8A93A0),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
      visualDensity: VisualDensity.compact,
      splashRadius: 15,
    );
  }

  String _format(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceAll('.', ',');
  }
}

/// Мини-превью материала: полупрозрачное полотно ПВХ или серая сетка скрина.
class _MaterialThumbPainter extends CustomPainter {
  const _MaterialThumbPainter({required this.screen});

  final bool screen;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0xFF9AA7B8);
    if (screen) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFFE1E6EC));
      final mesh = Paint()
        ..color = const Color(0xFF6D7A8A).withValues(alpha: 0.6)
        ..strokeWidth = 0.7;
      for (var x = 0.0; x <= size.width; x += 5) {
        canvas.drawLine(Offset(x, 0), Offset(x, size.height), mesh);
      }
      for (var y = 0.0; y <= size.height; y += 5) {
        canvas.drawLine(Offset(0, y), Offset(size.width, y), mesh);
      }
      canvas.drawRect(rect.deflate(0.5), border);
      return;
    }
    // ПВХ: голубоватое полупрозрачное полотно с бликом.
    canvas.drawRect(rect, Paint()..color = const Color(0x3359A6D8));
    final sheenRect = Rect.fromLTWH(
      size.width * 0.08,
      0,
      size.width * 0.34,
      size.height,
    );
    final sheen = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0x00FFFFFF), Color(0x99FFFFFF), Color(0x00FFFFFF)],
      ).createShader(sheenRect);
    final path = Path()
      ..moveTo(size.width * 0.08, size.height)
      ..lineTo(size.width * 0.42, 0)
      ..lineTo(size.width * 0.58, 0)
      ..lineTo(size.width * 0.24, size.height)
      ..close();
    canvas.drawPath(path, sheen);
    canvas.drawRect(rect.deflate(0.5), border);
  }

  @override
  bool shouldRepaint(covariant _MaterialThumbPainter oldDelegate) =>
      oldDelegate.screen != screen;
}
