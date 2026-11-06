import 'package:flutter/material.dart';

import '../models/window_params.dart';

class QuickMeasureResult {
  const QuickMeasureResult({required this.windows, required this.makeReport});

  final List<WindowParams> windows;
  final bool makeReport;
}

/// Быстрый замер для телефона: размеры, тип, материал, количество и маркировка
/// в одном коротком листе. Окна создаются пачкой, без длинной панели.
Future<QuickMeasureResult?> showQuickMeasureDialog(
  BuildContext context, {
  required WindowParams base,
}) {
  return showModalBottomSheet<QuickMeasureResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: const Color(0xFFF7F9FC),
    builder: (context) => _QuickMeasureSheet(base: base),
  );
}

class _QuickMeasureSheet extends StatefulWidget {
  const _QuickMeasureSheet({required this.base});

  final WindowParams base;

  @override
  State<_QuickMeasureSheet> createState() => _QuickMeasureSheetState();
}

class _QuickMeasureSheetState extends State<_QuickMeasureSheet> {
  late final TextEditingController _width;
  late final TextEditingController _height;
  late final TextEditingController _marking;
  int _count = 1;
  WindowType _type = WindowType.lifting;
  FilmMaterial _material = FilmMaterial.clearPvc;
  String? _error;

  @override
  void initState() {
    super.initState();
    final base = widget.base;
    _width = TextEditingController(text: base.bottomWidth.round().toString());
    _height = TextEditingController(text: base.leftHeight.round().toString());
    _marking = TextEditingController(text: base.drawingNumber);
    _type = base.isScreen || base.windowType == WindowType.fixed
        ? WindowType.fixed
        : WindowType.lifting;
    _material = base.material;
  }

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _marking.dispose();
    super.dispose();
  }

  double? _number(TextEditingController controller) {
    final value = double.tryParse(controller.text.trim().replaceAll(',', '.'));
    return value != null && value.isFinite && value >= 100 && value <= 20000
        ? value
        : null;
  }

  void _submit({required bool report}) {
    final width = _number(_width);
    final height = _number(_height);
    if (width == null || height == null) {
      setState(() => _error = 'Ширина и высота — от 100 до 20 000 мм');
      return;
    }
    final base = widget.base;
    final marking = _marking.text.trim();
    final windows = [
      for (var i = 0; i < _count; i++)
        base.copyWith(
          windowType: _type,
          material: _material,
          bottomWidth: width,
          topWidth: width,
          leftHeight: height,
          rightHeight: height,
          topOffsetMm: 0,
          topAlign: TopAlign.center,
          projectName: base.projectName,
          customer: base.customer,
          drawingNumber: marking,
        ),
    ];
    Navigator.of(
      context,
    ).pop(QuickMeasureResult(windows: windows, makeReport: report));
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final phone = MediaQuery.sizeOf(context).width < 700;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 4, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Быстрый замер',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                ),
                Text(
                  phone ? 'телефон' : 'быстрое создание',
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF66748A),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 2),
            const Text(
              'Заполните размеры и добавьте сразу несколько одинаковых окон.',
              style: TextStyle(fontSize: 11.5, color: Color(0xFF66748A)),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _numberField(
                    key: 'quick-width',
                    label: 'Ширина, мм',
                    controller: _width,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _numberField(
                    key: 'quick-height',
                    label: 'Высота, мм',
                    controller: _height,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              key: const Key('quick-marking'),
              controller: _marking,
              decoration: const InputDecoration(
                labelText: 'Маркировка окон',
                hintText: 'например МО-014',
                prefixIcon: Icon(Icons.tag, size: 18),
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<WindowType>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: WindowType.fixed,
                    label: Text('Глухое'),
                    icon: Icon(Icons.crop_square, size: 17),
                  ),
                  ButtonSegment(
                    value: WindowType.lifting,
                    label: Text('Подъёмное'),
                    icon: Icon(Icons.vertical_align_top, size: 17),
                  ),
                ],
                selected: {_type},
                onSelectionChanged: (value) =>
                    setState(() => _type = value.first),
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final material in const [
                  FilmMaterial.clearPvc,
                  FilmMaterial.tintedPvc,
                  FilmMaterial.screen,
                ])
                  ChoiceChip(
                    label: Text(
                      material.label,
                      style: const TextStyle(fontSize: 11),
                    ),
                    selected: _material == material,
                    onSelected: (_) => setState(() => _material = material),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Text('Сколько окон:', style: TextStyle(fontSize: 12)),
                const Spacer(),
                IconButton(
                  onPressed: _count > 1 ? () => setState(() => _count--) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                ),
                Text(
                  '$_count',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                IconButton(
                  onPressed: _count < 20
                      ? () => setState(() => _count++)
                      : null,
                  icon: const Icon(Icons.add_circle_outline),
                ),
              ],
            ),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFFB03A3A),
                ),
              ),
              const SizedBox(height: 6),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('quick-add-report'),
                    onPressed: () => _submit(report: true),
                    icon: const Icon(Icons.description_outlined, size: 18),
                    label: const Text('Окна + отчёт'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    key: const Key('quick-add'),
                    onPressed: () => _submit(report: false),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить окна'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _numberField({
    required String key,
    required String label,
    required TextEditingController controller,
  }) {
    return TextField(
      key: Key(key),
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }
}
