import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';

/// Панель параметров: окна заказа, размеры, окантовка по сторонам, раскрой.
class ParamsPanel extends StatefulWidget {
  const ParamsPanel({
    super.key,
    required this.project,
    required this.issues,
    required this.onChanged,
    required this.onReset,
    this.ordersSection,
  });

  final OrderProject project;
  final List<ParamIssue> issues;
  final ValueChanged<OrderProject> onChanged;
  final VoidCallback onReset;

  /// Раздел «Заказы» (сохранение и отчётность) — вставляется сверху.
  final Widget? ordersSection;

  @override
  State<ParamsPanel> createState() => _ParamsPanelState();
}

class _ParamsPanelState extends State<ParamsPanel> {
  static const _windowFields = <ParamField>[
    ParamField.bottomWidth,
    ParamField.topWidth,
    ParamField.leftHeight,
    ParamField.rightHeight,
    ParamField.topOffset,
    ParamField.eyeletStep,
    ParamField.eyeletCornerOffset,
    ParamField.drainCount,
    ParamField.pocketWidth,
    ParamField.shrinkagePercent,
    ParamField.zipperOffset,
    ParamField.zipperBandWidth,
  ];

  final Map<ParamField, TextEditingController> _controllers = {};
  final Map<ParamField, String?> _errors = {};
  late final TextEditingController _nameController;
  late final TextEditingController _customerController;
  late final TextEditingController _drawingController;

  WindowParams get _params => widget.project.selected;

  @override
  void initState() {
    super.initState();
    for (final field in _windowFields) {
      _controllers[field] = TextEditingController(text: _textFor(_params.valueOf(field)));
    }
    _controllers[ParamField.rollGap] =
        TextEditingController(text: _textFor(widget.project.rollGap));
    _nameController = TextEditingController(text: _params.projectName);
    _customerController = TextEditingController(text: _params.customer);
    _drawingController = TextEditingController(text: _params.drawingNumber);
  }

  @override
  void didUpdateWidget(covariant ParamsPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldProject = oldWidget.project;
    final project = widget.project;

    // Сменилось выбранное окно — перечитываем все поля.
    final windowChanged = oldProject.selectedIndex != project.selectedIndex ||
        oldProject.windows.length != project.windows.length;

    for (final field in _windowFields) {
      _syncField(field, project.selected.valueOf(field), force: windowChanged);
    }
    _syncField(ParamField.rollGap, project.rollGap, force: windowChanged);

    // Текстовые поля обновляем только если пользователь их не редактирует:
    // иначе набранное (и область ввода IME) сбрасывается на каждом символе.
    if (_nameController.text != project.selected.projectName) {
      _nameController.text = project.selected.projectName;
    }
    if (_customerController.text != project.selected.customer) {
      _customerController.text = project.selected.customer;
    }
    if (_drawingController.text != project.selected.drawingNumber) {
      _drawingController.text = project.selected.drawingNumber;
    }
  }

  /// Обновляет поле только тогда, когда его текст разошёлся со значением
  /// модели. Пока пользователь печатает, они совпадают, поэтому курсор
  /// и выделение не сбрасываются.
  void _syncField(ParamField field, double value, {bool force = false}) {
    final controller = _controllers[field];
    if (controller == null) return;

    if (!force) {
      final parsed = parseMm(controller.text);
      if (parsed == null) return; // незавершённый или неверный ввод — не трогаем
      if ((parsed - value).abs() < 1e-9) return; // всё совпадает
    }

    final text = _textFor(value);
    if (controller.text == text && !force) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    if (force) _errors[field] = null;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _nameController.dispose();
    _customerController.dispose();
    _drawingController.dispose();
    super.dispose();
  }

  String _textFor(double value) {
    if (!value.isFinite) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toString().replaceAll('.', ',');
  }

  void _updateProject(OrderProject project) => widget.onChanged(project);

  void _updateWindow(WindowParams params) =>
      _updateProject(widget.project.updateSelected(params));

  void _onNumberChanged(ParamField field, String raw) {
    final value = parseMm(raw);
    if (value == null) {
      setState(() => _errors[field] = 'Введите число, например 2500');
      return;
    }
    if (value <= 0) {
      setState(() => _errors[field] = 'Значение должно быть больше нуля');
      return;
    }
    setState(() => _errors[field] = null);

    switch (field) {
      case ParamField.rollGap:
        _updateProject(widget.project.setRollGap(value));
      default:
        _updateWindow(_params.withField(field, value));
    }
  }

  String? _errorFor(ParamField field) {
    final local = _errors[field];
    if (local != null) return local;
    for (final issue in widget.issues) {
      if (issue.field == field && issue.isError) return issue.message;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final params = project.selected;
    final spec = WindowSpec.of(params);
    final warnings =
        widget.issues.where((issue) => !issue.isError).toList(growable: false);

    return Material(
      color: const Color(0xFFF7F9FC),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          const _Hint(
            'Каждое окно рисуется слоями: окантовка (складывается пополам), '
            'напайка 25 мм, плёнка, люверсы и крепёж. Номера окон подписываются '
            'на листе, раскладка плёнки — на отдельном листе рулона.',
          ),
          const SizedBox(height: 18),
          _sectionHeader('Окна заказа', '${project.windowCount} шт · нумерация на листе'),
          const SizedBox(height: 10),
          _windowList(project),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _updateProject(project.addWindow()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить окно'),
              ),
              TextButton.icon(
                onPressed: project.windowCount > 1
                    ? () => _updateProject(project.removeSelected())
                    : null,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('Удалить'),
              ),
            ],
          ),
          if (widget.ordersSection != null) ...[
            const SizedBox(height: 16),
            widget.ordersSection!,
          ],
          const SizedBox(height: 20),
          const _SectionTitle('Тип окна'),
          const SizedBox(height: 8),
          _chips<WindowType>(
            values: WindowType.values,
            selected: params.windowType,
            labelOf: (value) => value.label,
            onSelected: (value) => _updateWindow(params.copyWith(windowType: value)),
          ),
          const SizedBox(height: 8),
          Text(
            params.windowType.hint,
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6B80)),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Размеры полотна, мм'),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(child: _numberField(ParamField.bottomWidth)),
              const SizedBox(width: 12),
              Expanded(child: _numberField(ParamField.topWidth)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _numberField(ParamField.leftHeight)),
              const SizedBox(width: 12),
              Expanded(child: _numberField(ParamField.rightHeight)),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Верхняя кромка',
            style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
          ),
          const SizedBox(height: 6),
          _chips<TopAlign>(
            values: TopAlign.values,
            selected: params.topAlign,
            labelOf: (value) => value.label,
            onSelected: (value) => _updateWindow(params.copyWith(topAlign: value)),
          ),
          if (params.topAlign == TopAlign.custom) ...[
            const SizedBox(height: 12),
            _numberField(ParamField.topOffset),
          ],
          const SizedBox(height: 20),
          _expansion(
            title: 'Полотно (плёнка)',
            subtitle:
                '${params.material.label} · рулон ${formatMm(project.rollWidthFor(params.material))} мм',
            children: [
              const Text('Материал',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80))),
              const SizedBox(height: 6),
              _chips<FilmMaterial>(
                values: FilmMaterial.values,
                selected: params.material,
                labelOf: (value) => value.label,
                onSelected: (value) =>
                    _updateWindow(params.copyWith(material: value)),
              ),
              const SizedBox(height: 6),
              Text(
                '${params.material.thickness}; доступные рулоны: '
                '${params.material.rollWidthsLabel} см',
                style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              const SizedBox(height: 14),
              const Text('Ширина рулона',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80))),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final width in params.availableRollWidths)
                    ChoiceChip(
                      label: Text('${formatCm(width)} см',
                          style: const TextStyle(fontSize: 12)),
                      selected: project.rollWidthFor(params.material) == width,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _updateProject(
                        project.setRollWidth(params.material, width),
                      ),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Окантовка',
            subtitle: '${spec.edgeBySideSummary} · ${params.edgeColor.label}',
            children: [
              const Text(
                'Рулон на каждую сторону (складывается пополам)',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _rollPicker('Низ', params.rollBottom, (roll) => params.copyWith(rollBottom: roll))),
                  const SizedBox(width: 12),
                  Expanded(child: _rollPicker('Верх', params.rollTop, (roll) => params.copyWith(rollTop: roll))),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(child: _rollPicker('Лево', params.rollLeft, (roll) => params.copyWith(rollLeft: roll))),
                  const SizedBox(width: 12),
                  Expanded(child: _rollPicker('Право', params.rollRight, (roll) => params.copyWith(rollRight: roll))),
                ],
              ),
              const SizedBox(height: 14),
              const Text('Материал',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80))),
              const SizedBox(height: 6),
              _chips<EdgeMaterial>(
                values: EdgeMaterial.values,
                selected: params.edgeMaterial,
                labelOf: (value) => value.label,
                onSelected: (value) =>
                    _updateWindow(params.copyWith(edgeMaterial: value)),
              ),
              const SizedBox(height: 6),
              Text(
                params.edgeMaterial.joining,
                style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              const SizedBox(height: 14),
              const Text('Цвет',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80))),
              const SizedBox(height: 6),
              _colorChips(params),
              const SizedBox(height: 12),
              _readOnlyField('Напайка плёнки под окантовку', '${formatMm(weldOverlap)} мм'),
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Крепёж',
            subtitle:
                '${spec.eyeletType.label} · шаг ${formatMm(params.eyeletStep)} мм · '
                '${spec.eyeletCount} шт на окно',
            children: [
              const Text('Люверс',
                  style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80))),
              const SizedBox(height: 6),
              _chips<EyeletType>(
                values: EyeletType.values,
                selected: params.effectiveEyeletType,
                labelOf: (value) => value.label,
                enabledOf: (value) =>
                    params.windowType != WindowType.fixed ||
                    value == EyeletType.round10,
                onSelected: (value) =>
                    _updateWindow(params.copyWith(eyeletType: value)),
              ),
              if (params.windowType == WindowType.fixed) ...[
                const SizedBox(height: 6),
                const Text(
                  'У глухого окна ставятся только круглые люверсы.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: _numberField(ParamField.eyeletStep)),
                  const SizedBox(width: 12),
                  Expanded(child: _numberField(ParamField.eyeletCornerOffset)),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Люверсы ставятся от углов: при 0 мм первый люверс стоит в углу.',
                style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              const SizedBox(height: 14),
              Text(
                params.windowType == WindowType.fixed
                    ? 'Крепление к каркасу'
                    : 'Крепёж подвижных сторон (низ и бока)',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 6),
              _chips<FastenerType>(
                values: FastenerType.values,
                selected: params.fastenerType,
                labelOf: (value) => value.label,
                onSelected: (value) =>
                    _updateWindow(params.copyWith(fastenerType: value)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Молния и карман',
            subtitle: _specElementsSummary(params, spec),
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Добавить молнию (вертикальная)'),
                value: params.hasZipper,
                onChanged: (value) =>
                    _updateWindow(params.copyWith(zipperEnabled: value)),
              ),
              if (params.hasZipper) ...[
                const SizedBox(height: 6),
                Text(
                  'Положение молнии: '
                  '${formatMm(spec.layers.zipperGaps?.left ?? 0)} мм от левого края',
                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6B80)),
                ),
                Slider(
                  value: _zipperCenter(spec).clamp(
                    math.max(params.zipperBandWidth / 2, 1),
                    math.max(spec.filmVisibleWidth - params.zipperBandWidth / 2, 2),
                  ),
                  min: math.max(params.zipperBandWidth / 2, 1),
                  max: math.max(spec.filmVisibleWidth - params.zipperBandWidth / 2, 2),
                  divisions: math.max(
                    ((spec.filmVisibleWidth - params.zipperBandWidth) / 10).round(),
                    1,
                  ),
                  label: formatMm(_zipperCenter(spec)),
                  onChanged: (value) => _updateWindow(
                    params.copyWith(zipperCentered: false, zipperOffsetMm: value),
                  ),
                ),
                const Text(
                  'Двигайте молнию влево-вправо этим ползунком — на чертеже она '
                  'перемещается вместе с размерами спайки.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: _numberField(ParamField.zipperOffset)),
                    const SizedBox(width: 12),
                    Expanded(child: _numberField(ParamField.zipperBandWidth)),
                  ],
                ),
                SwitchListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Молния по центру'),
                  value: params.zipperCentered,
                  onChanged: (value) =>
                      _updateWindow(params.copyWith(zipperCentered: value)),
                ),
                const Text(
                  'Спайка шириной 50 мм: молния впаивается в полосу тента '
                  'и идёт по её середине.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Карман по нижней кромке'),
                value: params.pocket,
                onChanged: (value) =>
                    _updateWindow(params.copyWith(pocket: value)),
              ),
              if (params.pocket) ...[
                _numberField(ParamField.pocketWidth),
                const SizedBox(height: 6),
                const Text(
                  'Карман делается из тента 200 мм, складывается пополам — '
                  'получается 100 мм. Нижние угловые люверсы не ставятся: они '
                  'поднимаются на 50 мм, чтобы в полость кармана заводился утяжитель.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
              ],
              const SizedBox(height: 8),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Дренажные отверстия внизу'),
                value: params.drainHoles,
                onChanged: (value) =>
                    _updateWindow(params.copyWith(drainHoles: value)),
              ),
              if (params.drainHoles) _numberField(ParamField.drainCount),
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Раскрой',
            subtitle:
                'плёнка ${formatMm(spec.filmCutWidth)} × ${formatMm(spec.filmCutHeight)} мм',
            children: [
              _numberField(ParamField.shrinkagePercent),
              const SizedBox(height: 12),
              _CuttingCard(spec: spec),
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Раскладка на рулоне',
            subtitle: _rollSummary(project),
            children: [
              _numberField(ParamField.rollGap),
              const SizedBox(height: 6),
              const Text(
                'Ширина рулона выбирается для каждого материала в разделе '
                '«Полотно». Раскладка строится на вкладке «Раскладка на рулоне».',
                style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Отображение',
            subtitle: 'сетка, размеры, подписи',
            children: [
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Размерные линии'),
                value: project.options.showDimensions,
                onChanged: (value) => _updateProject(project.updateOptions(
                    project.options.copyWith(showDimensions: value))),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Сетка'),
                value: project.options.showGrid,
                onChanged: (value) => _updateProject(
                    project.updateOptions(project.options.copyWith(showGrid: value))),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Длины боковых кромок'),
                value: project.options.showEdgeLengths,
                onChanged: (value) => _updateProject(project.updateOptions(
                    project.options.copyWith(showEdgeLengths: value))),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Подписи ширины окантовки'),
                value: project.options.showCallouts,
                onChanged: (value) => _updateProject(project.updateOptions(
                    project.options.copyWith(showCallouts: value))),
              ),
            ],
          ),
          if (warnings.isNotEmpty) ...[
            const SizedBox(height: 20),
            const _SectionTitle('Проверьте параметры'),
            const SizedBox(height: 8),
            for (final issue in warnings)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Icon(Icons.info_outline,
                          size: 16, color: Color(0xFFB26A00)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: const TextStyle(
                            fontSize: 12, color: Color(0xFF8A5200)),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          const SizedBox(height: 20),
          const _SectionTitle('Маркировка'),
          const SizedBox(height: 10),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Изделие',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                _updateWindow(params.copyWith(projectName: value)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _customerController,
            decoration: const InputDecoration(
              labelText: 'Заказчик',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) => _updateWindow(params.copyWith(customer: value)),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _drawingController,
            decoration: const InputDecoration(
              labelText: 'Маркировка окна (номер заказа)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (value) =>
                _updateWindow(params.copyWith(drawingNumber: value)),
          ),
          const SizedBox(height: 20),
          const _SectionTitle('Пресеты'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                onPressed: () => _updateWindow(
                  params.copyWith(windowType: WindowType.fixed),
                ),
                icon: const Icon(Icons.crop_square, size: 18),
                label: const Text('Глухое'),
              ),
              OutlinedButton.icon(
                onPressed: () => _updateWindow(
                  params.copyWith(
                    windowType: WindowType.lifting,
                    fastenerType: FastenerType.turnBuckles,
                  ),
                ),
                icon: const Icon(Icons.vertical_align_top, size: 18),
                label: const Text('Подъёмное'),
              ),
              OutlinedButton.icon(
                onPressed: () => _updateWindow(
                  params.copyWith(zipperEnabled: true, zipperCentered: true),
                ),
                icon: const Icon(Icons.vertical_split, size: 18),
                label: const Text('Добавить молнию'),
              ),
              OutlinedButton.icon(
                onPressed: () =>
                    _updateWindow(params.copyWith(pocket: true)),
                icon: const Icon(Icons.inbox_outlined, size: 18),
                label: const Text('Добавить карман'),
              ),
              TextButton.icon(
                onPressed: widget.onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Сбросить'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _specElementsSummary(WindowParams params, WindowSpec spec) {
    final parts = <String>[
      if (params.hasZipper) 'молния ${formatMm(params.zipperBandWidth)} мм',
      if (params.pocket) 'карман ${formatMm(params.pocketWidth)} мм',
      if (params.drainHoles) 'дренаж ${params.drainCount.round()} шт',
    ];
    return parts.isEmpty ? 'не включены' : parts.join(' · ');
  }

  /// Центр молнии от левого края плёнки, мм.
  double _zipperCenter(WindowSpec spec) => spec.params.zipperCentered
      ? spec.filmVisibleWidth / 2
      : spec.params.zipperOffsetMm;

  /// Подпись раскладки: рулоны по материалам.
  String _rollSummary(OrderProject project) {
    final parts = [
      for (final material in project.materialsInOrder)
        '${material.label.toLowerCase()}: ${formatCm(project.rollWidthFor(material))} см',
    ];
    return '${parts.join(' · ')} · зазор ${formatMm(project.rollGap)} мм';
  }

  Widget _sectionHeader(String title, String subtitle) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _SectionTitle(title)),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
      ],
    );
  }

  Widget _windowList(OrderProject project) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var index = 0; index < project.windowCount; index++)
          ChoiceChip(
            label: Text(
              '№${index + 1} · ${formatMm(project.windows[index].bottomWidth)}×'
              '${formatMm(project.windows[index].leftHeight)}',
              style: const TextStyle(fontSize: 11.5),
            ),
            selected: index == project.selectedIndex,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => _updateProject(project.select(index)),
          ),
      ],
    );
  }

  Widget _rollPicker(String label, EdgeRoll selected, WindowParams Function(EdgeRoll) apply) {
    return Row(
      children: [
        SizedBox(
          width: 46,
          child: Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF5B6B80))),
        ),
        Expanded(
          child: DropdownButton<EdgeRoll>(
            value: selected,
            isExpanded: true,
            isDense: true,
            style: const TextStyle(fontSize: 12.5, color: Color(0xFF1B1F27)),
            items: [
              for (final roll in EdgeRoll.values)
                DropdownMenuItem(
                  value: roll,
                  child: Text(
                    roll.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
            ],
            onChanged: (roll) {
              if (roll != null) _updateWindow(apply(roll));
            },
          ),
        ),
      ],
    );
  }

  Widget _expansion({
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: ExpansionTile(
        initiallyExpanded: true,
        shape: const Border(),
        collapsedShape: const Border(),
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
        title: Text(
          title,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
        children: children,
      ),
    );
  }

  Widget _chips<T>({
    required List<T> values,
    required T selected,
    required String Function(T) labelOf,
    required ValueChanged<T> onSelected,
    bool Function(T)? enabledOf,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final value in values)
          ChoiceChip(
            label: Text(labelOf(value), style: const TextStyle(fontSize: 12)),
            selected: selected == value,
            visualDensity: VisualDensity.compact,
            onSelected: (enabledOf == null || enabledOf(value))
                ? (_) => onSelected(value)
                : null,
          ),
      ],
    );
  }

  Widget _colorChips(WindowParams params) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final color in EdgeColor.values)
          ChoiceChip(
            avatar: Container(
              decoration: BoxDecoration(
                color: Color(color.value),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF9AA3AD)),
              ),
            ),
            label: Text(color.label, style: const TextStyle(fontSize: 12)),
            selected: params.edgeColor == color,
            visualDensity: VisualDensity.compact,
            onSelected: (_) => _updateWindow(params.copyWith(edgeColor: color)),
          ),
      ],
    );
  }

  Widget _numberField(ParamField field) {
    return TextField(
      controller: _controllers[field],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: field.label,
        suffixText: field.unit,
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _errorFor(field),
        errorMaxLines: 2,
      ),
      onChanged: (value) => _onNumberChanged(field, value),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      child: Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12.5),
      ),
    );
  }
}

/// Карточка раскроя: что и сколько закупать.
class _CuttingCard extends StatelessWidget {
  const _CuttingCard({required this.spec});

  final WindowSpec spec;

  @override
  Widget build(BuildContext context) {
    final params = spec.params;
    final rows = <(String, String)>[
      ('Площадь изделия', '${formatMeters(spec.productAreaM2)} м²'),
      (
        'Плёнка видимая',
        '${formatMm(spec.filmVisibleWidth)} × ${formatMm(spec.filmVisibleHeight)} мм'
      ),
      (
        'Плёнка в раскрое (напайка ${formatMm(weldOverlap)} мм)',
        '${formatMm(spec.filmCutWidth)} × ${formatMm(spec.filmCutHeight)} мм'
      ),
      (
        'С усадкой ${formatPercent(params.shrinkagePercent)}',
        '${formatMm(spec.filmCutWidthWithShrinkage)} × '
            '${formatMm(spec.filmCutHeightWithShrinkage)} мм'
      ),
      ('Площадь плёнки в раскрое', '${formatMeters(spec.filmAreaM2)} м²'),
      for (final label in spec.edgeConsumptionLabels)
        ('Окантовка ${label.split(' — ').first}', label.split(' — ').last),
      (
        'Люверсов',
        '${spec.eyeletCount} шт, шаг ${spec.eyeletStepLabel}'
      ),
    ];

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF3FB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC7DDF6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'РАСКРОЙ И ФУРНИТУРА',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
              color: Color(0xFF4A6A9A),
            ),
          ),
          const SizedBox(height: 8),
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                          fontSize: 11.5, color: Color(0xFF41506A)),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    row.$2,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF16324F),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.9,
        color: Color(0xFF66748A),
      ),
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F1FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFC7DDF6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.layers_outlined, size: 18, color: Color(0xFF0B62C4)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 12.5, color: Color(0xFF1D3F66)),
            ),
          ),
        ],
      ),
    );
  }
}
