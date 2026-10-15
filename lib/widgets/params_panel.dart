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
    this.pricesSection,
    this.techSection,
  });

  final OrderProject project;
  final List<ParamIssue> issues;
  final ValueChanged<OrderProject> onChanged;
  final VoidCallback onReset;

  /// Раздел «Заказы» (сохранение и отчётность) — вставляется сверху.
  final Widget? ordersSection;

  /// Раздел «Прайс-лист» — цены для сметы.
  final Widget? pricesSection;

  /// Раздел «Технолог» — производственные проверки.
  final Widget? techSection;

  @override
  State<ParamsPanel> createState() => _ParamsPanelState();
}

/// Числовые поля выреза в полотне.
enum _CutoutField {
  width('Ширина'),
  height('Высота'),
  centerX('Центр от левого края'),
  centerY('Центр от низа');

  const _CutoutField(this.label);

  final String label;
}

/// Припуски на раскрой: добавка к габариту заготовки, мм.
enum _AllowanceField {
  width('Прибавить к ширине, мм'),
  height('Прибавить к высоте, мм');

  const _AllowanceField(this.label);

  final String label;
}

/// Разумный предел припуска на раскрой, мм.
const double _maxAllowanceMm = 500;

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
    // Запайка плёнки под окантовку и подворот скрина: свои поля с ручным
    // вводом и проверкой диапазона. Подворот задаётся на каждую сторону.
    ParamField.weldOverlap,
    ParamField.hemBottom,
    ParamField.hemRight,
    ParamField.hemTop,
    ParamField.hemLeft,
  ];

  final Map<ParamField, TextEditingController> _controllers = {};
  final Map<ParamField, String?> _errors = {};

  /// Поля молний: положение от левого края и ширина спайки (ключ — номер молнии).
  final Map<int, TextEditingController> _zipperOffsetControllers = {};
  final Map<int, TextEditingController> _zipperBandControllers = {};
  final Map<int, String?> _zipperOffsetErrors = {};
  final Map<int, String?> _zipperBandErrors = {};

  /// Поля вырезов: ширина, высота и центры (ключ — номер выреза и поле).
  final Map<(int, _CutoutField), TextEditingController> _cutoutControllers = {};
  final Map<(int, _CutoutField), String?> _cutoutErrors = {};

  /// Поля «своя ширина, мм» окантовки — по одной на каждую сторону окна.
  final Map<EdgeSide, TextEditingController> _edgeControllers = {};
  final Map<EdgeSide, String?> _edgeErrors = {};

  /// Поля припусков на раскрой: добавка к ширине и к высоте, мм.
  final Map<_AllowanceField, TextEditingController> _allowanceControllers = {};
  final Map<_AllowanceField, String?> _allowanceErrors = {};

  /// Раскрыт ли блок припусков на раскрой.
  bool _allowanceExpanded = false;

  late final TextEditingController _nameController;
  late final TextEditingController _customerController;
  late final TextEditingController _drawingController;

  WindowParams get _params => widget.project.selected;

  @override
  void initState() {
    super.initState();
    for (final field in _windowFields) {
      _controllers[field] = TextEditingController(
        text: _textFor(_params.valueOf(field)),
      );
    }
    _controllers[ParamField.rollGap] = TextEditingController(
      text: _textFor(widget.project.rollGap),
    );
    for (final side in EdgeSide.values) {
      _edgeControllers[side] = TextEditingController(
        text: _textFor(_params.rollForSide(side)),
      );
    }
    for (final field in _AllowanceField.values) {
      _allowanceControllers[field] = TextEditingController(
        text: _textFor(_allowanceValue(_params, field)),
      );
    }
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
    final windowChanged =
        oldProject.selectedIndex != project.selectedIndex ||
        oldProject.windows.length != project.windows.length;

    for (final field in _windowFields) {
      _syncField(field, project.selected.valueOf(field), force: windowChanged);
    }
    _syncField(ParamField.rollGap, project.rollGap, force: windowChanged);
    _syncZipperFields(project.selected, force: windowChanged);
    _syncCutoutFields(project.selected, force: windowChanged);
    _syncEdgeFields(project.selected, force: windowChanged);
    _syncAllowanceFields(project.selected, force: windowChanged);

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
    _syncController(controller, value, force: force);
    if (force) _errors[field] = null;
  }

  /// Общая схема синхронизации для полей молний и вырезов: пока пользователь
  /// печатает, распарсенное значение совпадает с модельным, поэтому текст
  /// (а с ним курсор и выделение) не переписывается.
  void _syncController(
    TextEditingController controller,
    double value, {
    bool force = false,
  }) {
    if (!force) {
      final parsed = parseMm(controller.text);
      if (parsed == null) {
        return; // незавершённый или неверный ввод — не трогаем
      }
      if ((parsed - value).abs() < 1e-9) return; // всё совпадает
    }

    final text = _textFor(value);
    if (controller.text == text && !force) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _syncZipperFields(WindowParams params, {bool force = false}) {
    for (var index = 0; index < params.zippers.length; index++) {
      final zipper = params.zippers[index];
      _syncController(
        _zipperOffsetControllers.putIfAbsent(
          index,
          () => TextEditingController(text: _textFor(zipper.offsetMm)),
        ),
        zipper.offsetMm,
        force: force,
      );
      _syncController(
        _zipperBandControllers.putIfAbsent(
          index,
          () => TextEditingController(text: _textFor(zipper.bandWidth)),
        ),
        zipper.bandWidth,
        force: force,
      );
      if (force) {
        _zipperOffsetErrors[index] = null;
        _zipperBandErrors[index] = null;
      }
    }
    _pruneControllers(_zipperOffsetControllers, params.zippers.length);
    _pruneControllers(_zipperBandControllers, params.zippers.length);
    _pruneErrors(_zipperOffsetErrors, params.zippers.length);
    _pruneErrors(_zipperBandErrors, params.zippers.length);
  }

  void _syncCutoutFields(WindowParams params, {bool force = false}) {
    for (var index = 0; index < params.cutouts.length; index++) {
      final cutout = params.cutouts[index];
      for (final field in _CutoutField.values) {
        _syncController(
          _cutoutControllers.putIfAbsent(
            (index, field),
            () => TextEditingController(
              text: _textFor(_cutoutValue(cutout, field)),
            ),
          ),
          _cutoutValue(cutout, field),
          force: force,
        );
        if (force) _cutoutErrors[(index, field)] = null;
      }
    }
    final stale = _cutoutControllers.keys
        .where((key) => key.$1 >= params.cutouts.length)
        .toList(growable: false);
    for (final key in stale) {
      _cutoutControllers.remove(key)?.dispose();
    }
    final staleErrors = _cutoutErrors.keys
        .where((key) => key.$1 >= params.cutouts.length)
        .toList(growable: false);
    for (final key in staleErrors) {
      _cutoutErrors.remove(key);
    }
  }

  void _pruneControllers(
    Map<int, TextEditingController> controllers,
    int keep,
  ) {
    final stale = controllers.keys
        .where((index) => index >= keep)
        .toList(growable: false);
    for (final index in stale) {
      controllers.remove(index)?.dispose();
    }
  }

  void _pruneErrors(Map<int, String?> errors, int keep) {
    final stale = errors.keys
        .where((index) => index >= keep)
        .toList(growable: false);
    for (final index in stale) {
      errors.remove(index);
    }
  }

  double _cutoutValue(Cutout cutout, _CutoutField field) => switch (field) {
    _CutoutField.width => cutout.width,
    _CutoutField.height => cutout.height,
    _CutoutField.centerX => cutout.centerXMm,
    _CutoutField.centerY => cutout.centerYMm,
  };

  /// Синхронизация полей «своя ширина, мм» окантовки: текст переписывается
  /// только если распарсенное значение разошлось с моделью — набор с
  /// клавиатуры не сбивается (та же схема, что у полей молний и вырезов).
  void _syncEdgeFields(WindowParams params, {bool force = false}) {
    for (final side in EdgeSide.values) {
      _syncController(
        _edgeControllers.putIfAbsent(
          side,
          () => TextEditingController(text: _textFor(params.rollForSide(side))),
        ),
        params.rollForSide(side),
        force: force,
      );
      if (force) _edgeErrors[side] = null;
    }
  }

  /// Значение припуска на раскрой из модели.
  double _allowanceValue(WindowParams params, _AllowanceField field) =>
      switch (field) {
        _AllowanceField.width => params.allowanceWidthMm,
        _AllowanceField.height => params.allowanceHeightMm,
      };

  /// Синхронизация полей припусков: текст переписывается только если
  /// распарсенное значение разошлось с моделью (та же схема, что у молний,
  /// вырезов и ширины окантовки) — набор с клавиатуры не сбивается.
  void _syncAllowanceFields(WindowParams params, {bool force = false}) {
    for (final field in _AllowanceField.values) {
      _syncController(
        _allowanceControllers.putIfAbsent(
          field,
          () => TextEditingController(
            text: _textFor(_allowanceValue(params, field)),
          ),
        ),
        _allowanceValue(params, field),
        force: force,
      );
      if (force) _allowanceErrors[field] = null;
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final controller in _zipperOffsetControllers.values) {
      controller.dispose();
    }
    for (final controller in _zipperBandControllers.values) {
      controller.dispose();
    }
    for (final controller in _cutoutControllers.values) {
      controller.dispose();
    }
    for (final controller in _edgeControllers.values) {
      controller.dispose();
    }
    for (final controller in _allowanceControllers.values) {
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

  /// Ввод интервала люверсов: 50…2000 мм.
  ///
  /// Интервал задаёт пользователь, поэтому жёсткого коридора 250–400 больше
  /// нет. Внутри рамок значение уходит в модель как есть; фактический интервал
  /// по сторонам считается в геометрии и показывается рядом.
  void _onEyeletStepChanged(String raw) {
    final value = parseMm(raw);
    if (value == null) {
      setState(
        () => _errors[ParamField.eyeletStep] = 'Введите число, например 280',
      );
      return;
    }
    if (value < minEyeletStepMm || value > maxEyeletStepMm) {
      setState(
        () => _errors[ParamField.eyeletStep] =
            'Интервал от ${formatMm(minEyeletStepMm)} до '
            '${formatMm(maxEyeletStepMm)} мм',
      );
      return;
    }
    setState(() => _errors[ParamField.eyeletStep] = null);
    _updateWindow(_params.copyWith(eyeletStep: value));
  }

  /// Быстрый пресет интервала люверсов.
  void _applyEyeletStep(double value) {
    setState(() => _errors[ParamField.eyeletStep] = null);
    _updateWindow(_params.copyWith(eyeletStep: value));
  }

  String? _errorFor(ParamField field) {
    final local = _errors[field];
    if (local != null) return local;
    for (final issue in widget.issues) {
      if (issue.field == field && issue.isError) return issue.message;
    }
    return null;
  }

  /// Копия параметров с новой шириной рулона окантовки для стороны.
  WindowParams _withEdgeWidth(
    WindowParams params,
    EdgeSide side,
    double value,
  ) => switch (side) {
    EdgeSide.bottom => params.copyWith(rollBottom: value),
    EdgeSide.right => params.copyWith(rollRight: value),
    EdgeSide.top => params.copyWith(rollTop: value),
    EdgeSide.left => params.copyWith(rollLeft: value),
  };

  /// Быстрый пресет ширины окантовки.
  void _applyEdgeWidth(EdgeSide side, double value) {
    setState(() => _edgeErrors[side] = null);
    _updateWindow(_withEdgeWidth(_params, side, value));
  }

  /// Ввод своей ширины рулона окантовки: 40…400 мм.
  void _onEdgeWidthChanged(EdgeSide side, String raw) {
    final value = parseMm(raw);
    if (value == null) {
      setState(() => _edgeErrors[side] = 'Введите число, например 150');
      return;
    }
    if (value < minEdgeRollWidth || value > maxEdgeRollWidth) {
      setState(
        () => _edgeErrors[side] =
            'Ширина от '
            '${formatMm(minEdgeRollWidth)} до ${formatMm(maxEdgeRollWidth)} мм',
      );
      return;
    }
    setState(() => _edgeErrors[side] = null);
    _updateWindow(_withEdgeWidth(_params, side, value));
  }

  /// Ввод припуска на раскрой: 0…500 мм.
  void _onAllowanceChanged(_AllowanceField field, String raw) {
    final value = parseMm(raw);
    if (value == null) {
      setState(() => _allowanceErrors[field] = 'Введите число, например 120');
      return;
    }
    if (value < 0 || value > _maxAllowanceMm) {
      setState(
        () => _allowanceErrors[field] =
            'Припуск 0…${formatMm(_maxAllowanceMm)} мм',
      );
      return;
    }
    setState(() => _allowanceErrors[field] = null);
    _updateWindow(switch (field) {
      _AllowanceField.width => _params.copyWith(allowanceWidthMm: value),
      _AllowanceField.height => _params.copyWith(allowanceHeightMm: value),
    });
  }

  /// Сброс обоих припусков на раскрой.
  void _resetAllowance() {
    setState(() {
      _allowanceErrors[_AllowanceField.width] = null;
      _allowanceErrors[_AllowanceField.height] = null;
    });
    _updateWindow(_params.copyWith(allowanceWidthMm: 0, allowanceHeightMm: 0));
  }

  /// Ввод запайки плёнки под окантовку: 5…60 мм.
  ///
  /// От запайки напрямую зависит заготовка плёнки: каждый миллиметр
  /// добавляет по миллиметру с каждой стороны.
  void _onWeldOverlapChanged(String raw) {
    final value = parseMm(raw);
    if (value == null) {
      setState(
        () => _errors[ParamField.weldOverlap] = 'Введите число, например 25',
      );
      return;
    }
    if (value < minWeldOverlapMm || value > maxWeldOverlapMm) {
      setState(
        () => _errors[ParamField.weldOverlap] =
            'Запайка от ${formatMm(minWeldOverlapMm)} до '
            '${formatMm(maxWeldOverlapMm)} мм',
      );
      return;
    }
    setState(() => _errors[ParamField.weldOverlap] = null);
    _updateWindow(_params.copyWith(weldOverlapMm: value));
  }

  /// Быстрый пресет подворота скрина для стороны.
  void _applyHem(ParamField field, double value) {
    setState(() => _errors[field] = null);
    _updateWindow(_params.withField(field, value));
  }

  /// Ввод подворота скрина: 10…150 мм на каждую сторону.
  ///
  /// Сторона приходит полем [ParamField], поэтому ошибка адресуется ровно
  /// той строке блока «Подворот, мм», где её ввели.
  void _onHemChanged(ParamField field, String raw) {
    final value = parseMm(raw);
    if (value == null) {
      setState(() => _errors[field] = 'Введите число');
      return;
    }
    if (value < minScreenHemMm || value > maxScreenHemMm) {
      setState(
        () => _errors[field] =
            '${formatMm(minScreenHemMm)}…${formatMm(maxScreenHemMm)} мм',
      );
      return;
    }
    setState(() => _errors[field] = null);
    _updateWindow(_params.withField(field, value));
  }

  /// Поле «Запайка плёнки под окантовку, мм» с пресетами 10/25/40.
  Widget _weldOverlapField(WindowParams params) {
    final value = params.weldOverlapMm;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in const [10.0, 25.0, 40.0])
              ChoiceChip(
                label: Text(
                  '${formatMm(preset)} мм',
                  style: const TextStyle(fontSize: 12),
                ),
                selected: (value - preset).abs() < 1e-9,
                visualDensity: VisualDensity.compact,
                onSelected: (_) {
                  setState(() => _errors[ParamField.weldOverlap] = null);
                  _updateWindow(params.copyWith(weldOverlapMm: preset));
                },
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          key: const Key('weld-overlap-field'),
          controller: _controllers[ParamField.weldOverlap],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Запайка плёнки под окантовку, мм',
            suffixText: 'мм',
            helperText: '${formatMm(minWeldOverlapMm)}…'
                '${formatMm(maxWeldOverlapMm)} мм; заготовка плёнки = готовый '
                'размер − 2 × окантовка + 2 × запайка',
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _errorFor(ParamField.weldOverlap),
            errorMaxLines: 2,
          ),
          onChanged: _onWeldOverlapChanged,
        ),
      ],
    );
  }

  /// Блок «Подворот, мм»: четыре строки — низ, право, верх, лево.
  ///
  /// У каждой стороны свои пресеты 40/50/60 и числовое поле (10…150 мм);
  /// панель узкая (420 px), поэтому строка собрана из подписи, компактных
  /// чипов и поля. Внизу — итог: какой получится заготовка.
  Widget _hemSection(WindowSpec spec) {
    final params = spec.params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Подворот, мм — на каждую сторону',
          style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
        ),
        const SizedBox(height: 6),
        for (final side in EdgeSide.values) ...[
          _hemRow(params, side),
          if (side != EdgeSide.left) const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        Text(
          'Заготовка будет '
          '${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} мм: готовый размер '
          'плюс подворот по сторонам. Шов сварки '
          '${formatMm(screenSeamMm)} мм.',
          key: const Key('hem-blank-label'),
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
      ],
    );
  }

  /// Одна строка подворота: сторона, пресеты 40/50/60 и своё число.
  Widget _hemRow(WindowParams params, EdgeSide side) {
    final field = hemFieldForSide(side);
    final value = params.hemForSide(side);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          child: Text(
            side.label,
            style: const TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
          ),
        ),
        Expanded(
          child: Wrap(
            spacing: 4,
            runSpacing: 4,
            children: [
              for (final preset in screenHemPresets)
                ChoiceChip(
                  label: Text(
                    formatMm(preset),
                    style: const TextStyle(fontSize: 11),
                  ),
                  selected: (value - preset).abs() < 1e-9,
                  visualDensity: VisualDensity.compact,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                  onSelected: (_) => _applyHem(field, preset),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 84,
          child: TextField(
            key: Key('hem-${side.name}-field'),
            controller: _controllers[field],
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              suffixText: 'мм',
              suffixStyle: const TextStyle(fontSize: 11),
              border: const OutlineInputBorder(),
              isDense: true,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              errorText: _errorFor(field),
              errorMaxLines: 2,
            ),
            style: const TextStyle(fontSize: 12.5),
            onChanged: (raw) => _onHemChanged(field, raw),
          ),
        ),
      ],
    );
  }

  /// Блок «Припуски на раскрой»: кнопка-переключатель, два поля и итог.
  Widget _allowanceSection(WindowSpec spec) {
    final params = spec.params;
    final width = spec.filmCutWidthWithAllowance;
    final height = spec.filmCutHeightWithAllowance;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () =>
                    setState(() => _allowanceExpanded = !_allowanceExpanded),
                icon: const Icon(Icons.add_box_outlined, size: 18),
                label: const Text('Припуски на раскрой'),
              ),
            ),
            if (params.hasAllowance) ...[
              const SizedBox(width: 8),
              Text(
                '${params.allowanceWidthLabel} / '
                '${params.allowanceHeightLabel} мм',
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B62C4),
                ),
              ),
            ],
          ],
        ),
        if (_allowanceExpanded) ...[
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _allowanceField(
                  _AllowanceField.width,
                  const Key('allowance-width-field'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _allowanceField(
                  _AllowanceField.height,
                  const Key('allowance-height-field'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Припуск добавляется только к заготовке плёнки в раскрое. '
            'Изделие, чертёж, окантовка и люверсы считаются по замеру и '
            'не меняются.',
            style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          const SizedBox(height: 10),
          _panelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Плёнка в раскрое с припуском: ${formatMm(width)} × '
                  '${formatMm(height)} мм',
                  key: const Key('allowance-cut-size'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Изделие остаётся ${formatMm(params.bottomWidth)} × '
                  '${formatMm(params.leftHeight)} мм; площадь изделия и расход '
                  'окантовки не меняются, припуск виден в раскрое плёнки и '
                  'в расходе материала.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF66748A),
                  ),
                ),
                if (params.hasAllowance) ...[
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      key: const Key('allowance-reset'),
                      onPressed: _resetAllowance,
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('Сбросить припуски'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _allowanceField(_AllowanceField field, Key key) {
    return TextField(
      key: key,
      controller: _allowanceControllers[field],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: field.label,
        suffixText: 'мм',
        helperText: '0…${formatMm(_maxAllowanceMm)}, шаг 1',
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _allowanceErrors[field],
        errorMaxLines: 2,
      ),
      onChanged: (raw) => _onAllowanceChanged(field, raw),
    );
  }

  /// Подпись чипа спайки: сторона окна в винительном падеже.
  String _weldedChipLabel(EdgeSide side) => switch (side) {
    EdgeSide.bottom => 'Спаяно снизу',
    EdgeSide.right => 'Спаяно справа',
    EdgeSide.top => 'Спаяно сверху',
    EdgeSide.left => 'Спаяно слева',
  };

  /// Подпись кнопки «добавить окно к спайке»: сторона окна в родительном.
  String _addWeldedLabel(EdgeSide side) => switch (side) {
    EdgeSide.bottom => '+ окно снизу',
    EdgeSide.right => '+ окно справа',
    EdgeSide.top => '+ окно сверху',
    EdgeSide.left => '+ окно слева',
  };

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final params = project.selected;
    final spec = WindowSpec.of(params);
    final warnings = widget.issues
        .where((issue) => !issue.isError)
        .toList(growable: false);

    return Material(
      color: const Color(0xFFF7F9FC),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          _Hint(
            params.isScreen
                ? 'Скрин — самостоятельная технология: серое полотно '
                    'подворачивается по периметру, подворот задаётся на каждую '
                    'сторону (низ, право, верх, лево — обычно 40/50/60 мм), шов '
                    '${formatMm(screenSeamMm)} мм, крепёж — только люверсы по '
                    'линии подворота. Тента и окантовки у скрина нет: '
                    'заготовка равна готовому размеру плюс подворот по сторонам.'
                : 'Каждое окно рисуется слоями: окантовка (складывается '
                    'пополам), запайка плёнки под окантовку, плёнка, люверсы и '
                    'крепёж. Номера окон подписываются на листе, раскладка '
                    'плёнки — на отдельном листе рулона.',
          ),
          const SizedBox(height: 18),
          _sectionHeader(
            'Окна заказа',
            '${project.windowCount} шт · нумерация на листе',
          ),
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
              OutlinedButton.icon(
                onPressed: () => _updateProject(project.duplicateSelected()),
                icon: const Icon(Icons.copy_all_outlined, size: 18),
                label: const Text('Дублировать'),
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
          if (widget.pricesSection != null) ...[
            const SizedBox(height: 12),
            widget.pricesSection!,
          ],
          if (widget.techSection != null) ...[
            const SizedBox(height: 12),
            widget.techSection!,
          ],
          const SizedBox(height: 20),
          const _SectionTitle('Тип окна'),
          const SizedBox(height: 8),
          _chips<WindowType>(
            values: WindowType.values,
            selected: params.windowType,
            labelOf: (value) => value.label,
            onSelected: (value) =>
                _updateWindow(params.copyWith(windowType: value)),
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
            onSelected: (value) =>
                _updateWindow(params.copyWith(topAlign: value)),
          ),
          if (params.topAlign == TopAlign.custom) ...[
            const SizedBox(height: 12),
            _numberField(ParamField.topOffset),
          ],
          const SizedBox(height: 14),
          _allowanceSection(spec),
          const SizedBox(height: 20),
          _expansion(
            title: 'Полотно (плёнка)',
            subtitle:
                '${params.material.label} · рулон ${formatMm(project.rollWidthFor(params.material))} мм',
            children: [
              const Text(
                'Материал',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
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
              const Text(
                'Ширина рулона',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final width in params.availableRollWidths)
                    ChoiceChip(
                      label: Text(
                        '${formatCm(width)} см',
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: project.rollWidthFor(params.material) == width,
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) => _updateProject(
                        project.setRollWidth(params.material, width),
                      ),
                    ),
                ],
              ),
              if (params.isScreen) ...[
                const SizedBox(height: 14),
                _hemSection(spec),
                const SizedBox(height: 8),
                Text(
                  'Усадки у скрина нет; нужен запас — добавьте припуск на '
                  'раскрой в разделе выше. Подворот каждой стороны входит '
                  'в заготовку своей стороны.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF66748A),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          if (!params.isScreen)
            _expansion(
              title: 'Окантовка',
              subtitle: '${spec.edgeBySideSummary} · ${params.edgeColor.label}',
              children: [
              const Text(
                'Ширина рулона на каждую сторону, мм — пресеты или своё '
                'значение (складывается пополам)',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _edgeWidthEditor(params, EdgeSide.bottom)),
                  const SizedBox(width: 12),
                  Expanded(child: _edgeWidthEditor(params, EdgeSide.top)),
                ],
              ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: _edgeWidthEditor(params, EdgeSide.left)),
                  const SizedBox(width: 12),
                  Expanded(child: _edgeWidthEditor(params, EdgeSide.right)),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Готовая полоса — половина рулона. Своя ширина 40…400 мм; '
                'если ширина меньше 100 мм, запайке 2 × '
                '${formatMm(params.weldOverlapMm)} мм может не хватить ленты.',
                style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              const SizedBox(height: 14),
              const Text(
                'Материал',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
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
              const Text(
                'Цвет',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 6),
              _colorChips(params),
              const SizedBox(height: 14),
              const Text(
                'Спайка с соседним окном',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final side in EdgeSide.values)
                    FilterChip(
                      label: Text(
                        _weldedChipLabel(side),
                        style: const TextStyle(fontSize: 12),
                      ),
                      selected: params.isWelded(side),
                      visualDensity: VisualDensity.compact,
                      onSelected: (_) =>
                          _updateWindow(params.toggleWelded(side)),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'На спаянной стороне окантовка не ставится, полотна свариваются; '
                'расход окантовки уменьшается, добавляется спайка 25 мм.',
                style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              const SizedBox(height: 14),
              const Text(
                'Добавить окно к спайке',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final side in EdgeSide.values)
                    OutlinedButton(
                      key: Key('add-welded-${side.name}'),
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () =>
                          _updateProject(project.addWeldedWindow(side)),
                      child: Text(
                        _addWeldedLabel(side),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Добавит копию этого окна с теми же размерами и сразу сваривает '
                'их выбранной стороной.',
                style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              if (params.weldedSides.isNotEmpty) ...[
                const SizedBox(height: 6),
                _panelCard(
                  child: SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: params.removeEyeletsOnWelded,
                    title: const Text(
                      'Убирать люверсы (крепёж) на спаянной стороне',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    subtitle: const Text(
                      'Выключите, если по спайке всё равно нужны люверсы — '
                      'тогда крепёж останется и на сварной стороне.',
                      style: TextStyle(fontSize: 11),
                    ),
                    onChanged: (value) => _updateWindow(
                      params.copyWith(removeEyeletsOnWelded: value),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              _weldOverlapField(params),
            ],
          )
          else
            _panelCard(
              child: Text(
                'Окантовка скрину не нужна: материал подворачивается сам. '
                'Подворот по сторонам (низ, право, верх, лево) и шов '
                '${formatMm(screenSeamMm)} мм — в разделе «Полотно (плёнка)».',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF5B6B80),
                ),
              ),
            ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Крепёж',
            subtitle:
                '${spec.eyeletType.label} · интервал '
                '${formatMm(params.eyeletStep)} мм (факт. '
                '${spec.eyeletStepLabel}) · '
                '${spec.eyeletCount} шт на окно',
            children: [
              const Text(
                'Люверс',
                style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
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
              _eyeletStepField(spec),
              const SizedBox(height: 12),
              _numberField(ParamField.eyeletCornerOffset),
              const SizedBox(height: 6),
              Text(
                params.isScreen
                    ? 'Люверсы ставятся по линии подворота: у скрина других '
                        'креплений нет.'
                    : 'Люверсы ставятся от углов: при 0 мм первый люверс стоит в углу.',
                style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              if (!params.isScreen) ...[
                const SizedBox(height: 14),
                Text(
                  params.windowType == WindowType.fixed
                      ? 'Крепление к каркасу'
                      : 'Крепёж подвижных сторон (низ и бока)',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF5B6B80),
                  ),
                ),
                const SizedBox(height: 6),
                _chips<FastenerType>(
                  values: FastenerType.values,
                  selected: params.fastenerType,
                  labelOf: (value) => value.label,
                  onSelected: (value) =>
                      _updateWindow(params.copyWith(fastenerType: value)),
                ),
              ] else ...[
                const SizedBox(height: 10),
                const Text(
                  'Крепёж скрина — только люверсы: поворотные скобы, '
                  'французские замки и ремни не применяются.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Молния и карман',
            subtitle: _specElementsSummary(params),
            children: [
              if (!params.isScreen) ...[
                if (params.zippers.isEmpty)
                  OutlinedButton.icon(
                    onPressed: () => _updateWindow(params.addZipper()),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Добавить молнию'),
                  )
                else ...[
                  for (var index = 0; index < params.zippers.length; index++)
                    _zipperCard(params, spec, index),
                  if (params.zippers.length == 1 && maxZippers > 1)
                    OutlinedButton.icon(
                      onPressed: () => _updateWindow(params.addZipper()),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('Добавить вторую молнию'),
                    ),
                  const SizedBox(height: 6),
                  Text(
                    'Молния впаивается в полосу тента: на чертеже показаны полоса '
                    'спайки и расстояния до кромок плёнки. Всего до $maxZippers молний.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF66748A),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
              ] else ...[
                const Text(
                  'Молния у скрина не ставится: полотно подворачивается и '
                  'крепится люверсами.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
                const SizedBox(height: 10),
              ],
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Карман снизу (по нижней кромке)'),
                value: params.pocket,
                onChanged: (value) =>
                    _updateWindow(params.copyWith(pocket: value)),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Карман сверху (по верхней кромке)'),
                value: params.pocketTop,
                onChanged: (value) =>
                    _updateWindow(params.copyWith(pocketTop: value)),
              ),
              if (params.pocket || params.pocketTop) ...[
                _numberField(ParamField.pocketWidth),
                const SizedBox(height: 6),
                Text(
                  params.isScreen
                      ? 'У скрина карман образуется подворотом материала '
                          '${formatMm(params.pocketWidth)} мм. Угловые люверсы со '
                          'стороны кармана не ставятся, крайние боковые смещаются '
                          'на ${formatMm(pocketCornerOffset)} мм — чтобы в полость '
                          'кармана заводился утяжитель.'
                      : 'Карман делается из тента 200 мм, складывается пополам — '
                          'получается 100 мм. Угловые люверсы со стороны кармана '
                          'не ставятся: они смещаются на '
                          '${formatMm(pocketCornerOffset)} мм, чтобы в полость '
                          'кармана заводился утяжитель.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF66748A),
                  ),
                ),
              ],
              if (!params.isScreen) ...[
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
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Вырезы в полотне',
            subtitle: _cutoutsSummary(params),
            children: [
              const Text(
                'Отверстие под трубу, вентиляцию или стойку: контур выреза '
                'обводится окантовкой, размеры идут на чертёж и в раскрой.',
                style: TextStyle(fontSize: 11.5, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 10),
              for (var index = 0; index < params.cutouts.length; index++)
                _cutoutCard(params, index),
              OutlinedButton.icon(
                onPressed: params.cutouts.length < maxCutouts
                    ? () => _updateWindow(params.addCutout())
                    : null,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Добавить вырез'),
              ),
              const SizedBox(height: 6),
              Text(
                params.cutouts.length >= maxCutouts
                    ? 'Больше $maxCutouts вырезов на окно не ставится.'
                    : 'На окно можно поставить до $maxCutouts вырезов.',
                style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _expansion(
            title: 'Раскрой',
            subtitle:
                'заготовка ${formatMm(spec.filmCutWidthWithAllowance)} × '
                '${formatMm(spec.filmCutHeightWithAllowance)} мм',
            children: [
              if (params.isScreen) ...[
                const Text(
                  'У скрина усадки нет: заготовка равна готовому размеру плюс '
                  'подворот по сторонам. Нужен запас — добавьте припуск на '
                  'раскрой.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
                const SizedBox(height: 12),
              ] else ...[
                _numberField(ParamField.shrinkagePercent),
                const SizedBox(height: 12),
              ],
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
                onChanged: (value) => _updateProject(
                  project.updateOptions(
                    project.options.copyWith(showDimensions: value),
                  ),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Сетка'),
                value: project.options.showGrid,
                onChanged: (value) => _updateProject(
                  project.updateOptions(
                    project.options.copyWith(showGrid: value),
                  ),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Длины боковых кромок'),
                value: project.options.showEdgeLengths,
                onChanged: (value) => _updateProject(
                  project.updateOptions(
                    project.options.copyWith(showEdgeLengths: value),
                  ),
                ),
              ),
              SwitchListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: const Text('Подписи ширины окантовки'),
                value: project.options.showCallouts,
                onChanged: (value) => _updateProject(
                  project.updateOptions(
                    project.options.copyWith(showCallouts: value),
                  ),
                ),
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
                      child: Icon(
                        Icons.info_outline,
                        size: 16,
                        color: Color(0xFFB26A00),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        issue.message,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF8A5200),
                        ),
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
            onChanged: (value) =>
                _updateWindow(params.copyWith(customer: value)),
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
                onPressed: params.zippers.length < maxZippers
                    ? () => _updateWindow(params.addZipper())
                    : null,
                icon: const Icon(Icons.vertical_split, size: 18),
                label: const Text('Молния по центру'),
              ),
              OutlinedButton.icon(
                onPressed: params.cutouts.length < maxCutouts
                    ? () => _updateWindow(params.addCutout())
                    : null,
                icon: const Icon(Icons.crop_free, size: 18),
                label: const Text('Вырез по центру'),
              ),
              OutlinedButton.icon(
                onPressed: () => _updateWindow(params.copyWith(pocket: true)),
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

  String _specElementsSummary(WindowParams params) {
    final zipperPart = switch (params.zippers.length) {
      0 => null,
      1 => 'молния ${formatMm(params.zippers.first.bandWidth)} мм',
      _ => 'молний ${params.zippers.length}',
    };
    final parts = <String>[
      ?zipperPart,
      if (params.cutouts.isNotEmpty) 'вырезов ${params.cutouts.length}',
      if (params.pocket) 'карман снизу ${formatMm(params.pocketWidth)} мм',
      if (params.pocketTop) 'карман сверху ${formatMm(params.pocketWidth)} мм',
      if (params.drainHoles && !params.isScreen)
        'дренаж ${params.drainCount.round()} шт',
    ];
    return parts.isEmpty ? 'не включены' : parts.join(' · ');
  }

  /// Подпись раздела вырезов: сколько их и сколько окантовки уходит на контуры.
  String _cutoutsSummary(WindowParams params) {
    if (params.cutouts.isEmpty) return 'не заданы';
    final perimeter = params.cutouts.fold<double>(
      0,
      (sum, cutout) => sum + cutout.perimeterMm,
    );
    return '${params.cutouts.length} шт · контур ${formatMm(perimeter)} мм';
  }

  /// Карточка внутри раздела: подложка с рамкой. Прозрачный Material нужен,
  /// чтобы переключатели рисовали чернильные волны поверх заливки.
  Widget _panelCard({required Widget child}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Material(type: MaterialType.transparency, child: child),
    );
  }

  /// Карточка одной молнии: центр или сдвиг, ширина спайки, удаление.
  Widget _zipperCard(WindowParams params, WindowSpec spec, int index) {
    final zipper = params.zippers[index];
    final filmWidth = spec.filmVisibleWidth;
    final maxOffset = filmWidth.isFinite && filmWidth > 0 ? filmWidth : 1.0;
    final offset = zipper.offsetMm.clamp(0.0, maxOffset);
    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Молния ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Удалить молнию',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _updateWindow(params.removeZipper(index)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('По центру полотна'),
            value: zipper.centered,
            onChanged: (value) => _updateWindow(
              params.updateZipper(index, zipper.copyWith(centered: value)),
            ),
          ),
          if (!zipper.centered) ...[
            const SizedBox(height: 4),
            Text(
              'Положение от левого края плёнки: ${formatMm(offset)} мм',
              style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6B80)),
            ),
            Slider(
              value: offset,
              min: 0,
              max: maxOffset,
              divisions: math.max((maxOffset / 10).round(), 1),
              label: formatMm(offset),
              onChanged: (value) => _updateWindow(
                params.updateZipper(
                  index,
                  zipper.copyWith(centered: false, offsetMm: value),
                ),
              ),
            ),
            _zipperOffsetField(index, offset, maxOffset),
            const SizedBox(height: 8),
          ],
          _zipperBandField(index, zipper.bandWidth),
          const SizedBox(height: 6),
          Text(
            'Спайка шириной ${formatMm(zipper.bandWidth)} мм: молния впаивается '
            'в полосу тента и идёт по её середине.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
        ],
      ),
    );
  }

  Widget _zipperOffsetField(int index, double value, double maxOffset) {
    return TextField(
      controller: _zipperOffsetControllers.putIfAbsent(
        index,
        () => TextEditingController(text: _textFor(value)),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Положение от левого края',
        suffixText: 'мм',
        helperText: '0–${formatMm(maxOffset)} мм, шаг 10',
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _zipperOffsetErrors[index],
        errorMaxLines: 2,
      ),
      onChanged: (raw) => _onZipperOffsetChanged(index, raw, maxOffset),
    );
  }

  Widget _zipperBandField(int index, double value) {
    return TextField(
      controller: _zipperBandControllers.putIfAbsent(
        index,
        () => TextEditingController(text: _textFor(value)),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Ширина спайки',
        suffixText: 'мм',
        helperText: '40–120 мм, по умолчанию 50',
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _zipperBandErrors[index],
        errorMaxLines: 2,
      ),
      onChanged: (raw) => _onZipperBandChanged(index, raw),
    );
  }

  void _onZipperOffsetChanged(int index, String raw, double maxOffset) {
    final zippers = _params.zippers;
    if (index < 0 || index >= zippers.length) return;
    final value = parseMm(raw);
    if (value == null) {
      setState(
        () => _zipperOffsetErrors[index] = 'Введите число, например 500',
      );
      return;
    }
    if (value < 0 || value > maxOffset) {
      setState(
        () => _zipperOffsetErrors[index] =
            'Положение от 0 до ${formatMm(maxOffset)} мм',
      );
      return;
    }
    setState(() => _zipperOffsetErrors[index] = null);
    _updateWindow(
      _params.updateZipper(
        index,
        zippers[index].copyWith(centered: false, offsetMm: value),
      ),
    );
  }

  void _onZipperBandChanged(int index, String raw) {
    final zippers = _params.zippers;
    if (index < 0 || index >= zippers.length) return;
    final value = parseMm(raw);
    if (value == null) {
      setState(() => _zipperBandErrors[index] = 'Введите число, например 50');
      return;
    }
    if (value < 40 || value > 120) {
      setState(() => _zipperBandErrors[index] = 'Ширина спайки 40–120 мм');
      return;
    }
    setState(() => _zipperBandErrors[index] = null);
    _updateWindow(
      _params.updateZipper(index, zippers[index].copyWith(bandWidth: value)),
    );
  }

  /// Карточка одного выреза: форма, размеры, положение центра, удаление.
  Widget _cutoutCard(WindowParams params, int index) {
    final cutout = params.cutouts[index];
    final isCircle = cutout.shape == CutoutShape.circle;
    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Вырез ${index + 1}',
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'контур ${formatMm(cutout.perimeterMm)} мм',
                style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              IconButton(
                tooltip: 'Удалить вырез',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                icon: const Icon(Icons.delete_outline, size: 18),
                onPressed: () => _updateWindow(params.removeCutout(index)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          SegmentedButton<CutoutShape>(
            showSelectedIcon: false,
            style: const ButtonStyle(visualDensity: VisualDensity.compact),
            segments: [
              for (final shape in CutoutShape.values)
                ButtonSegment<CutoutShape>(
                  value: shape,
                  label: Text(
                    shape.label,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
            selected: {cutout.shape},
            onSelectionChanged: (selection) => _updateWindow(
              params.updateCutout(
                index,
                cutout.copyWith(shape: selection.first),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _cutoutField(
                  index: index,
                  field: _CutoutField.width,
                  value: cutout.width,
                  label: isCircle ? 'Ширина (диаметр)' : 'Ширина',
                ),
              ),
              if (!isCircle) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _cutoutField(
                    index: index,
                    field: _CutoutField.height,
                    value: cutout.height,
                    label: 'Высота',
                  ),
                ),
              ],
            ],
          ),
          if (isCircle) ...[
            const SizedBox(height: 6),
            const Text(
              'У круглого выреза высота равна диаметру, поле высоты скрыто.',
              style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
            ),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _cutoutField(
                  index: index,
                  field: _CutoutField.centerX,
                  value: cutout.centerXMm,
                  label: 'Центр от левого края',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _cutoutField(
                  index: index,
                  field: _CutoutField.centerY,
                  value: cutout.centerYMm,
                  label: 'Центр от низа',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _cutoutField({
    required int index,
    required _CutoutField field,
    required double value,
    required String label,
  }) {
    return TextField(
      controller: _cutoutControllers.putIfAbsent((
        index,
        field,
      ), () => TextEditingController(text: _textFor(value))),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'мм',
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _cutoutErrors[(index, field)],
        errorMaxLines: 2,
      ),
      onChanged: (raw) => _onCutoutChanged(index, field, raw),
    );
  }

  void _onCutoutChanged(int index, _CutoutField field, String raw) {
    final cutouts = _params.cutouts;
    if (index < 0 || index >= cutouts.length) return;
    final key = (index, field);
    final value = parseMm(raw);
    if (value == null) {
      setState(() => _cutoutErrors[key] = 'Введите число, например 300');
      return;
    }
    final isCenter =
        field == _CutoutField.centerX || field == _CutoutField.centerY;
    if (isCenter && value < 0) {
      setState(
        () => _cutoutErrors[key] = 'Смещение не может быть отрицательным',
      );
      return;
    }
    if (!isCenter && value <= 0) {
      setState(() => _cutoutErrors[key] = 'Размер должен быть больше нуля');
      return;
    }
    setState(() => _cutoutErrors[key] = null);
    final cutout = cutouts[index];
    final updated = switch (field) {
      _CutoutField.width => cutout.copyWith(width: value),
      _CutoutField.height => cutout.copyWith(height: value),
      _CutoutField.centerX => cutout.copyWith(centerXMm: value),
      _CutoutField.centerY => cutout.copyWith(centerYMm: value),
    };
    _updateWindow(_params.updateCutout(index, updated));
  }

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

  /// Ширина окантовки одной стороны: быстрые пресеты 100/200/240 и поле
  /// «своя ширина, мм» (готовая полоса — половина рулона).
  Widget _edgeWidthEditor(WindowParams params, EdgeSide side) {
    final raw = params.rollForSide(side);
    final finished = WindowParams.finishedEdgeWidth(raw);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          side.label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in WindowParams.edgePresets)
              ChoiceChip(
                label: Text(
                  edgeBandLabel(preset, short: true),
                  style: const TextStyle(fontSize: 12),
                ),
                selected: (raw - preset).abs() < 1e-9,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => _applyEdgeWidth(side, preset),
              ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _edgeControllers[side],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'Своя ширина, мм',
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _edgeErrors[side],
            errorMaxLines: 2,
            helperText:
                'готовая полоса ${formatMm(finished)} мм '
                '(складывается пополам)',
            helperMaxLines: 2,
          ),
          onChanged: (value) => _onEdgeWidthChanged(side, value),
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

  /// Интервал люверсов: пресеты, своё число и фактический интервал по сторонам.
  ///
  /// Пользователь задаёт «примерный» интервал, а приложение расставляет
  /// люверсы так, чтобы фактический интервал был НЕ БОЛЬШЕ заданного: число
  /// интервалов по стороне округляется вверх. Поэтому рядом с полем всегда
  /// видно, что получилось на самом деле.
  Widget _eyeletStepField(WindowSpec spec) {
    final params = spec.params;
    final value = params.eyeletStep;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Интервал люверсов, мм',
          style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final preset in eyeletStepPresets)
              ChoiceChip(
                label: Text(
                  formatMm(preset),
                  style: const TextStyle(fontSize: 11),
                ),
                selected: (value - preset).abs() < 1e-9,
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                labelPadding: const EdgeInsets.symmetric(horizontal: 2),
                onSelected: (_) => _applyEyeletStep(preset),
              ),
          ],
        ),
        const SizedBox(height: 6),
        TextField(
          key: const Key('eyelet-step-field'),
          controller: _controllers[ParamField.eyeletStep],
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: ParamField.eyeletStep.label,
            suffixText: 'мм',
            helperText: '${formatMm(minEyeletStepMm)}…'
                '${formatMm(maxEyeletStepMm)} мм; рекомендовано '
                '${formatMm(recommendedEyeletStepMinMm)}–'
                '${formatMm(recommendedEyeletStepMaxMm)}',
            helperMaxLines: 2,
            border: const OutlineInputBorder(),
            isDense: true,
            errorText: _errorFor(ParamField.eyeletStep),
            errorMaxLines: 2,
          ),
          onChanged: _onEyeletStepChanged,
        ),
        const SizedBox(height: 6),
        Text(
          'Задан ${formatMm(value)} мм → фактически '
          '${spec.eyeletStepLabel} по сторонам: число интервалов округляют '
          'вверх, поэтому факт не больше заданного.',
          key: const Key('eyelet-step-actual'),
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
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
        params.isScreen ? 'Полотно скрина видимое' : 'Плёнка видимая',
        '${formatMm(spec.filmVisibleWidth)} × ${formatMm(spec.filmVisibleHeight)} мм',
      ),
      (
        params.isScreen
            ? 'Заготовка: готовый размер + подворот по сторонам '
                '${params.hemBySideShortLabel}'
                '${params.hasAllowance ? ' и припуск' : ''}'
            : 'Заготовка с запайкой ${formatMm(params.weldOverlapMm)} мм'
                '${params.hasAllowance ? ' и припуском' : ''}',
        '${formatMm(spec.filmCutWidthWithAllowance)} × '
            '${formatMm(spec.filmCutHeightWithAllowance)} мм',
      ),
      if (!params.isScreen)
        (
          'С усадкой ${formatPercent(params.effectiveShrinkagePercent)}',
          '${formatMm(spec.filmCutWidthWithShrinkage)} × '
              '${formatMm(spec.filmCutHeightWithShrinkage)} мм',
        )
      else
        ('Усадка', 'нет'),
      // Габарит заготовки и площадь полотна — разные числа: у трапеции
      // заготовка кроится прямоугольником и больше полотна.
      (
        'Площадь заготовки (габарит) без усадки',
        '${formatMeters(spec.filmCutAreaM2)} м²'
      ),
      (
        'Площадь заготовки (габарит) с усадкой',
        '${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²'
      ),
      (
        'Площадь полотна изделия (без припуска)',
        '${formatMeters(spec.filmAreaM2)} м²'
      ),
      if (params.isScreen)
        (
          'Подворот и шов ${formatMm(screenSeamMm)} мм по сторонам '
              '(низ/право/верх/лево)',
          params.hemBySideShortLabel
        ),
      for (final label in spec.edgeConsumptionLabels)
        ('Окантовка ${label.split(' — ').first}', label.split(' — ').last),
      (
        'Люверсов',
        '${spec.eyeletCount} шт, ${spec.eyeletStepLabel}',
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
                        fontSize: 11.5,
                        color: Color(0xFF41506A),
                      ),
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
