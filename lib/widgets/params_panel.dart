import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../models/order_project.dart';
import '../models/price_list.dart';
import '../models/window_geometry.dart';
import '../models/window_params.dart';
import '../services/company_branding.dart';
import 'company_dialog.dart';

/// Краткая карточка заказа для верхнего списка.
class OrderOverview {
  const OrderOverview({required this.name, required this.windowCount});

  final String name;
  final int windowCount;
}

/// Панель параметров: заказы, материал, тип, размеры, крепёж, окантовка.
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
    this.orderOverviews = const [],
    this.selectedOrderIndex = 0,
    this.onSelectOrder,
    this.onCreateOrder,
    this.onRenameOrder,
    this.onDeleteOrder,
    this.prices,
  });

  final OrderProject project;
  final List<ParamIssue> issues;
  final ValueChanged<OrderProject> onChanged;
  final VoidCallback onReset;

  /// Верхний список заказов: переключение, переименование, удаление.
  final List<OrderOverview> orderOverviews;
  final int selectedOrderIndex;
  final ValueChanged<int>? onSelectOrder;
  final VoidCallback? onCreateOrder;
  final ValueChanged<int>? onRenameOrder;
  final ValueChanged<int>? onDeleteOrder;

  /// Цены для подписей в блоке крепежа.
  final PriceList? prices;

  /// Раздел «Сохранённые заказы» (файлы/отчётность) — вставляется снизу.
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

/// Шаг ползунков положения выреза, мм.
///
/// Вырез двигают мышью по видимой плёнке; шаг 10 мм совпадает с точностью
/// замера и не даёт «дрожащих» дробных чисел в поле.
const double _cutoutSliderStepMm = 10;

class _ParamsPanelState extends State<ParamsPanel> {
  static const _windowFields = <ParamField>[
    ParamField.bottomWidth,
    ParamField.topWidth,
    ParamField.leftHeight,
    ParamField.rightHeight,
    ParamField.topOffset,
    ParamField.tWidth,
    ParamField.tHeight,
    ParamField.tOffset,
    ParamField.t2Width,
    ParamField.t2Height,
    ParamField.t2Offset,
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

  /// Последний выбранный вид ПВХ: при переключении «Скрин → ПВХ» возвращаем
  /// именно его, а не сбрасываем на прозрачный.
  FilmMaterial _lastPvcMaterial = FilmMaterial.clearPvc;

  /// Поля молний: положение от левого края и ширина спайки (ключ — номер молнии).
  final Map<int, TextEditingController> _zipperOffsetControllers = {};
  final Map<int, TextEditingController> _zipperZipControllers = {};
  final Map<int, TextEditingController> _zipperTentControllers = {};
  final Map<int, TextEditingController> _zipperWeldControllers = {};
  final Map<int, TextEditingController> _strapControllers = {};
  final Map<int, String?> _zipperOffsetErrors = {};
  final Map<int, String?> _zipperZipErrors = {};
  final Map<int, String?> _zipperTentErrors = {};
  final Map<int, String?> _zipperWeldErrors = {};

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
    _syncStrapFields(project.selected, force: windowChanged);
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
        _zipperZipControllers.putIfAbsent(
          index,
          () => TextEditingController(text: _textFor(zipper.zipWidthMm)),
        ),
        zipper.zipWidthMm,
        force: force,
      );
      _syncController(
        _zipperTentControllers.putIfAbsent(
          index,
          () => TextEditingController(text: _textFor(zipper.tentWidthMm)),
        ),
        zipper.tentWidthMm,
        force: force,
      );
      _syncController(
        _zipperWeldControllers.putIfAbsent(
          index,
          () => TextEditingController(text: _textFor(zipper.weldMm)),
        ),
        zipper.weldMm,
        force: force,
      );
      if (force) {
        _zipperOffsetErrors[index] = null;
        _zipperZipErrors[index] = null;
        _zipperTentErrors[index] = null;
        _zipperWeldErrors[index] = null;
      }
    }
    _pruneControllers(_zipperOffsetControllers, params.zippers.length);
    _pruneControllers(_zipperZipControllers, params.zippers.length);
    _pruneControllers(_zipperTentControllers, params.zippers.length);
    _pruneControllers(_zipperWeldControllers, params.zippers.length);
    _pruneErrors(_zipperOffsetErrors, params.zippers.length);
    _pruneErrors(_zipperZipErrors, params.zippers.length);
    _pruneErrors(_zipperTentErrors, params.zippers.length);
    _pruneErrors(_zipperWeldErrors, params.zippers.length);
  }

  void _syncStrapFields(WindowParams params, {bool force = false}) {
    final offsets = params.liftStrapOffsets;
    for (var index = 0; index < offsets.length; index++) {
      _syncController(
        _strapControllers.putIfAbsent(
          index,
          () => TextEditingController(text: _textFor(offsets[index])),
        ),
        offsets[index],
        force: force,
      );
    }
    _pruneControllers(_strapControllers, offsets.length);
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

  /// Суффикс ключа поля выреза: w/h/x/y.
  ///
  /// По нему тесты и панель находят поле и ползунок конкретной оси
  /// (`cutout-0-x-field`, `cutout-0-x-slider`).
  String _cutoutAxisName(_CutoutField field) => switch (field) {
    _CutoutField.width => 'w',
    _CutoutField.height => 'h',
    _CutoutField.centerX => 'x',
    _CutoutField.centerY => 'y',
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
    for (final controller in _zipperZipControllers.values) {
      controller.dispose();
    }
    for (final controller in _zipperTentControllers.values) {
      controller.dispose();
    }
    for (final controller in _zipperWeldControllers.values) {
      controller.dispose();
    }
    for (final controller in _strapControllers.values) {
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

  void _updateWindow(WindowParams params) {
    if (params.isPvcFilm) _lastPvcMaterial = params.material;
    _updateProject(widget.project.updateSelected(params));
  }

  void _onNumberChanged(ParamField field, String raw) {
    // Усадка — единственное процентное поле: 0 % допустим (включённый тумблер
    // без запаса), поэтому у него своя проверка диапазона 0…5 %.
    if (field == ParamField.shrinkagePercent) {
      _onShrinkageChanged(raw);
      return;
    }
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
            '${formatMm(maxEyeletStepMm)} ${unitSuffix()}',
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
            '${formatMm(minEdgeRollWidth)} до ${formatMm(maxEdgeRollWidth)} ${unitSuffix()}',
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
            'Припуск 0…${formatMm(_maxAllowanceMm)} ${unitSuffix()}',
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

  /// Тумблер «+10 мм к высоте по умолчанию (ПВХ)».
  ///
  /// Для скрина флаг не действует — у скрина авто-припуска нет никогда,
  /// поэтому кнопку ему и не показываем.
  void _setPvcHeightAllowance(bool value) {
    _updateWindow(_params.copyWith(pvcHeightAllowanceEnabled: value));
  }

  /// Тумблер «Учитывать усадку ПВХ».
  ///
  /// При включении, если процент ещё не задан (0), подставляем типовое
  /// значение [defaultShrinkagePercent] — 1,5 %.
  void _setShrinkageEnabled(bool value) {
    final percent = value && _params.shrinkagePercent == 0
        ? defaultShrinkagePercent
        : _params.shrinkagePercent;
    setState(() => _errors[ParamField.shrinkagePercent] = null);
    _updateWindow(
      _params.copyWith(shrinkageEnabled: value, shrinkagePercent: percent),
    );
  }

  /// Ввод усадки ПВХ: 0…5 %.
  void _onShrinkageChanged(String raw) {
    final value = parseMm(raw);
    if (value == null) {
      setState(
        () => _errors[ParamField.shrinkagePercent] =
            'Введите число, например 1,5',
      );
      return;
    }
    if (value < 0 || value > maxShrinkageFieldPercent) {
      setState(
        () => _errors[ParamField.shrinkagePercent] =
            'Усадка 0…${formatDecimal(maxShrinkageFieldPercent)} %',
      );
      return;
    }
    setState(() => _errors[ParamField.shrinkagePercent] = null);
    _updateWindow(_params.copyWith(shrinkagePercent: value));
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
            '${formatMm(maxWeldOverlapMm)} ${unitSuffix()}',
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

  /// Ввод подворота скрина: 10…200 мм на каждую сторону.
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
            '${formatMm(minScreenHemMm)}…${formatMm(maxScreenHemMm)} ${unitSuffix()}',
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
                  '${formatMm(preset)} ${unitSuffix()}',
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
            helperText:
                '${formatMm(minWeldOverlapMm)}…'
                '${formatMm(maxWeldOverlapMm)} ${unitSuffix()}; заготовка плёнки = готовый '
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

  /// Выбор «Ровно: низ · верх · нет» — какая кромка остаётся горизонтальной
  /// при разных высотах сторон. Заменяет прежние кнопки выравнивания.
  ///
  /// Раньше здесь стоял [SegmentedButton]: он НЕ вызывает обработчик, если
  /// нажали уже выбранный сегмент (при `emptySelectionAllowed == false`), и
  /// вообще не пишет в модель, когда выбранный набор не изменился. Из-за
  /// этого нажатие «иногда не работало». Теперь каждая кнопка — обычный
  /// [OutlinedButton]: нажатие на любой сегмент ВСЕГДА пишет в модель и
  /// перерисовывает панель, даже если значение не поменялось.
  ///
  /// Для Т-образного окна основное полотно — прямоугольник по низу и левой
  /// высоте, поэтому режим на его контур не влияет: контрол заблокирован и
  /// это явно написано с замком, а не просто «серые кнопки».
  Widget _levelEdgeSelector(WindowParams params) {
    final enabled = !params.isTShape;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Ровно',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
              if (!enabled) ...[
                const SizedBox(width: 6),
                const Icon(
                  Icons.lock_outline,
                  key: Key('level-edge-lock'),
                  size: 14,
                  color: Color(0xFF8A5200),
                ),
              ],
              const Spacer(),
              if (!enabled)
                Text(
                  'недоступно',
                  key: const Key('level-edge-locked'),
                  style: const TextStyle(
                    fontSize: 10.5,
                    color: Color(0xFF8A5200),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              for (final edge in LevelEdge.values) ...[
                if (edge != LevelEdge.values.first) const SizedBox(width: 6),
                Expanded(child: _levelEdgeButton(params, edge, enabled)),
              ],
            ],
          ),
          const SizedBox(height: 6),
          Text(
            enabled
                ? 'При разных размерах одна кромка остаётся горизонтальной. '
                      'Нажатие на любой сегмент всегда применяется: «Низ» — низ '
                      'ровно, «Верх» — верх ровно, «Нет» — перепад делится '
                      'поровну.'
                : 'Для Т-образного окна основное полотно прямоугольное — режим '
                      '«Ровно» на контур не влияет, поэтому переключатель '
                      'заблокирован.',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF66748A)),
          ),
        ],
      ),
    );
  }

  /// Одна кнопка переключателя «Ровно».
  ///
  /// Выбранная кнопка залита цветом и помечена галочкой — по этой галочке
  /// видно фактическое состояние модели, а не «нажатость».
  Widget _levelEdgeButton(WindowParams params, LevelEdge edge, bool enabled) {
    final selected = params.levelEdge == edge;
    return OutlinedButton(
      key: Key('level-edge-${edge.name}'),
      onPressed: enabled ? () => _selectLevelEdge(edge) : null,
      style: OutlinedButton.styleFrom(
        backgroundColor: selected && enabled
            ? const Color(0xFF0B62C4)
            : (enabled ? Colors.white : const Color(0xFFEDF0F5)),
        foregroundColor: selected && enabled
            ? Colors.white
            : const Color(0xFF33465E),
        side: BorderSide(
          color: selected && enabled
              ? const Color(0xFF0B62C4)
              : const Color(0xFFC3CCDA),
        ),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 7),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected && enabled) ...[
            const Icon(Icons.check, key: Key('level-edge-check'), size: 14),
            const SizedBox(width: 2),
          ],
          Flexible(
            child: Text(
              edge.shortLabel,
              key: Key('level-edge-${edge.name}-label'),
              style: const TextStyle(fontSize: 11.5),
            ),
          ),
        ],
      ),
    );
  }

  /// Запись режима «Ровно» в модель.
  ///
  /// Пишем ВСЕГДА: даже нажатие на уже выбранный сегмент обновляет модель и
  /// перерисовывает панель. `setState` страхует перерисовку, если родитель
  /// почему-то не отреагирует на `onChanged`.
  void _selectLevelEdge(LevelEdge edge) {
    final next = _params.copyWith(levelEdge: edge);
    setState(() {});
    _updateWindow(next);
  }

  /// Блок «Подворот, мм»: четыре строки — низ, право, верх, лево.
  ///
  /// У каждой стороны свои пресеты 40/50/60/80/100/120 и числовое поле
  /// (10…200 мм);
  /// панель узкая (420 px), поэтому строка собрана из подписи, компактных
  /// чипов и поля. Внизу — итог: какой получится заготовка и как она
  /// посчитана: половина подворота каждой стороны, к высоте +20 мм.
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
          'Габарит заготовки будет '
          '${formatMm(spec.filmCutWidthWithAllowance)} × '
          '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()}: полотно идёт '
          'шире и выше готового размера на ПОЛОВИНУ подворота каждой стороны, '
          'к высоте добавляется ${formatMm(screenHemAxisExtraMm)} ${unitSuffix()} '
          'на шов и запас. Шов сварки ${formatMm(screenSeamMm)} ${unitSuffix()}.'
          // У трапеции и окна с разными высотами наклон сторон добавляет к
          // габариту ещё немного — это видно отдельным слагаемым в формулах.
          '${spec.widthSlopeExtraMm.abs() >= 0.5 || spec.heightSlopeExtraMm.abs() >= 0.5 ? ' Наклон сторон добавляет к габариту: по ширине '
                    '${formatSignedMm(spec.widthSlopeExtraMm)} ${unitSuffix()}, по высоте '
                    '${formatSignedMm(spec.heightSlopeExtraMm)} ${unitSuffix()}.' : ''}'
          // Полоса молнии сужает именно заготовку, а не подворот: подвороты
          // остаются своими, но итоговая ширина кроя меньше на полосу.
          '${spec.zipperBandTotalMm > 0 ? ' Ширина кроя уменьшена на полосу '
                    'молнии ${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()}: '
                    '${formatMm(spec.filmCutWidthBeforeZipper)}'
                    ' → ${formatMm(spec.filmCutWidth)} ${unitSuffix()} до припуска — полоса '
                    'кроится из того же полотна.' : ''}',
          key: const Key('hem-blank-label'),
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
        const SizedBox(height: 4),
        Text(
          spec.screenBlankHeightFormulaLabel,
          key: const Key('hem-height-formula'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B62C4),
          ),
        ),
        Text(
          spec.screenBlankWidthFormulaLabel,
          key: const Key('hem-width-formula'),
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Color(0xFF0B62C4),
          ),
        ),
      ],
    );
  }

  /// Одна строка подворота: сторона, пресеты 40/50/60/80/100/120 и своё число.
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
                  key: Key('hem-preset-${field.name}-${preset.round()}'),
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
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
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
                '${params.allowanceHeightLabel} ${unitSuffix()}',
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
          if (!params.isScreen) ...[
            const SizedBox(height: 4),
            SwitchListTile(
              key: const Key('pvc-height-allowance-toggle'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: const Text(
                '+10 мм к высоте по умолчанию (ПВХ)',
                style: TextStyle(fontSize: 13),
              ),
              subtitle: const Text(
                'применяется только к окнам из ПВХ; для скрина не действует',
                style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              value: params.pvcHeightAllowanceEnabled,
              onChanged: _setPvcHeightAllowance,
            ),
          ],
          const SizedBox(height: 6),
          Text(
            params.heightAllowanceBreakdownLabel,
            key: const Key('height-allowance-total'),
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF0B62C4),
            ),
          ),
          const SizedBox(height: 10),
          _panelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Плёнка в раскрое с припуском: ${formatMm(width)} × '
                  '${formatMm(height)} ${unitSuffix()}',
                  key: const Key('allowance-cut-size'),
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Изделие остаётся ${formatMm(params.bottomWidth)} × '
                  '${formatMm(params.leftHeight)} ${unitSuffix()}; площадь изделия и расход '
                  'окантовки не меняются, припуск виден в раскрое плёнки и '
                  'в расходе материала.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF66748A),
                  ),
                ),
                if (params.hasManualAllowance) ...[
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

  /// Верхний список заказов: «Заказ 1, Заказ 2…», переключение, переименование
  /// и удаление. Кнопка «Создать заказ» открывает диалог имени в main.
  Widget _ordersTopSection(OrderProject project) {
    final orders = widget.orderOverviews.isEmpty
        ? [OrderOverview(name: 'Заказ 1', windowCount: project.windowCount)]
        : widget.orderOverviews;
    final selected = widget.selectedOrderIndex.clamp(0, orders.length - 1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('Заказы', '${orders.length} шт · сверху — активный'),
        const SizedBox(height: 8),
        for (var index = 0; index < orders.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              key: Key('order-row-$index'),
              decoration: BoxDecoration(
                color: index == selected
                    ? const Color(0xFFE8F0FE)
                    : Colors.white,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: index == selected
                      ? const Color(0xFF0B62C4)
                      : const Color(0xFFD9E0EA),
                ),
              ),
              child: Material(
                color: Colors.transparent,
                child: ListTile(
                  selected: index == selected,
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  contentPadding: const EdgeInsets.only(left: 10, right: 2),
                  leading: Icon(
                    index == selected
                        ? Icons.check_circle
                        : Icons.folder_outlined,
                    size: 18,
                    color: index == selected
                        ? const Color(0xFF0B62C4)
                        : const Color(0xFF8A93A0),
                  ),
                  title: Text(
                    orders[index].name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: index == selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                  subtitle: Text(
                    'окон: ${orders[index].windowCount}',
                    style: const TextStyle(fontSize: 10.5),
                  ),
                  onTap: widget.onSelectOrder == null
                      ? null
                      : () => widget.onSelectOrder!(index),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.onRenameOrder != null)
                        IconButton(
                          key: Key('rename-order-$index'),
                          tooltip: 'Переименовать заказ',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => widget.onRenameOrder!(index),
                          icon: const Icon(Icons.edit_outlined, size: 17),
                        ),
                      if (widget.onDeleteOrder != null)
                        IconButton(
                          key: Key('delete-order-$index'),
                          tooltip: 'Удалить заказ',
                          visualDensity: VisualDensity.compact,
                          onPressed: orders.length > 1
                              ? () => widget.onDeleteOrder!(index)
                              : null,
                          icon: const Icon(Icons.delete_outline, size: 17),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 6),
        FilledButton.icon(
          key: const Key('create-order'),
          onPressed: widget.onCreateOrder,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Создать заказ'),
        ),
      ],
    );
  }

  /// Блок со всеми крепежами и ценами из прайса.
  Widget _fastenerSection(WindowSpec spec, PriceList prices) {
    final params = spec.params;
    final fastening = params.fastenerType;
    final roundEyelet =
        fastening == FastenerType.eyeletsOnly &&
        params.eyeletType == EyeletType.round10;
    return _expansion(
      title: 'Крепёж',
      subtitle:
          '${_fastenerChoiceLabel(params)} · отступ '
          '${formatMm(params.eyeletCornerOffset)} ${unitSuffix()} · интервал '
          '${formatMm(params.eyeletStep)} ${unitSuffix()}',
      children: [
        // Сначала — что за крепление, потом его параметры. Так блок читается
        // сверху вниз: выбрал крепление → отступ → стороны → интервал.
        const Text(
          'Крепления',
          style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final (key, label, price, selected, onTap) in [
              (
                'fastener-round-eyelet',
                'Круглый люверс',
                '${formatRubles(prices.eyeletPerEach(EyeletType.round10))}/шт',
                roundEyelet,
                () => _updateWindow(
                  params.copyWith(
                    fastenerType: FastenerType.eyeletsOnly,
                    eyeletType: EyeletType.round10,
                  ),
                ),
              ),
              (
                'fastener-french-lock',
                'Французский замок',
                '${formatRubles(prices.fastenerPerEach(FastenerType.frenchLocks))}/шт',
                fastening == FastenerType.frenchLocks,
                () => _updateWindow(
                  params.copyWith(fastenerType: FastenerType.frenchLocks),
                ),
              ),
              (
                'fastener-turn-buckle',
                'Поворотная скоба',
                '${formatRubles(prices.fastenerPerEach(FastenerType.turnBuckles))}/шт',
                fastening == FastenerType.turnBuckles,
                () => _updateWindow(
                  params.copyWith(fastenerType: FastenerType.turnBuckles),
                ),
              ),
              (
                'fastener-straps',
                'Подвязочный ремень',
                '${formatRubles(prices.fastenerPerEach(FastenerType.straps))}/шт',
                fastening == FastenerType.straps,
                () => _updateWindow(
                  params.copyWith(fastenerType: FastenerType.straps),
                ),
              ),
            ])
              ChoiceChip(
                key: Key(key),
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: const TextStyle(fontSize: 11.5)),
                    Text(
                      price,
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF66748A),
                      ),
                    ),
                  ],
                ),
                selected: selected,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => onTap(),
              ),
          ],
        ),
        const SizedBox(height: 10),
        _numberField(ParamField.eyeletCornerOffset),
        const SizedBox(height: 10),
        _noEyeletsSection(params),
        const SizedBox(height: 12),
        _eyeletStepField(spec),
        const SizedBox(height: 10),
        Text(
          params.isScreen
              ? 'Люверсы ставятся по линии подворота; по ней же ложится '
                    'и выбранный крепёж скрина.'
              : 'Отступ считается от угла: при 0 мм первый люверс стоит в углу.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
        if (params.eyeletPositions.isNotEmpty) ...[
          const SizedBox(height: 10),
          _panelCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Расставлено вручную',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Тяните люверс мышкой вдоль линии окантовки. После '
                  'перетаскивания рядом появляется меню: удалить, поставить '
                  'круглый люверс, французский замок или поворотную скобу.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                ),
                const SizedBox(height: 6),
                OutlinedButton.icon(
                  key: const Key('reset-eyelet-positions'),
                  onPressed: () =>
                      _updateWindow(params.clearEyeletPositions()),
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: const Text('Вернуть автоматическую расстановку'),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Тип люверса',
          style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final type in EyeletType.values)
              ChoiceChip(
                label: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(type.label, style: const TextStyle(fontSize: 11.5)),
                    Text(
                      '${formatRubles(prices.eyeletPerEach(type))}/шт',
                      style: const TextStyle(
                        fontSize: 9.5,
                        color: Color(0xFF66748A),
                      ),
                    ),
                  ],
                ),
                selected: params.eyeletType == type,
                visualDensity: VisualDensity.compact,
                onSelected: (_) =>
                    _updateWindow(params.copyWith(eyeletType: type)),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Тип люверса доступен на любом окне, включая глухое. '
          '${params.roundEyeletsEnabled ? 'В углах круглый Ø10 мм: угол тянет по диагонали, '
                    'а овальный люверс развёрнут вдоль одной стороны.' : 'Круглые люверсы в углах отключены: угловых точек нет.'}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
        const SizedBox(height: 10),
        _roundEyeletsSection(spec),
      ],
    );
  }

  String _fastenerChoiceLabel(WindowParams params) {
    if (params.fastenerType == FastenerType.eyeletsOnly) {
      return params.eyeletType == EyeletType.round10
          ? 'круглый люверс'
          : 'люверс ${params.eyeletType.label.toLowerCase()}';
    }
    return params.fastenerType.itemTitle.toLowerCase();
  }

  /// «Окна в заказе»: компактный список окон выбранного заказа.
  Widget _windowSection(OrderProject project) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(
          'Окна в заказе',
          '${project.windowCount} шт · нумерация на листе',
        ),
        const SizedBox(height: 8),
        _windowList(project),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('add-window'),
              onPressed: () => _updateProject(project.addWindow()),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Создать окно'),
            ),
            OutlinedButton.icon(
              key: const Key('duplicate-window'),
              onPressed: () => _updateProject(project.duplicateSelected()),
              icon: const Icon(Icons.copy_all_outlined, size: 18),
              label: const Text('Дублировать'),
            ),
            TextButton.icon(
              key: const Key('delete-window'),
              onPressed: project.windowCount > 1
                  ? () => _updateProject(project.removeSelected())
                  : null,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Удалить'),
            ),
          ],
        ),
      ],
    );
  }

  /// «Материал окна»: ПВХ или Скрин. У ПВХ — три вида, у скрина подвыбора нет.
  Widget _materialSection(WindowParams params) {
    final isPvc = params.isPvcFilm;
    return _expansion(
      title: 'Материал окна',
      subtitle: params.material.label,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            ChoiceChip(
              key: const Key('material-pvc'),
              label: const Text('ПВХ'),
              selected: isPvc,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                if (!isPvc) {
                  _updateWindow(params.copyWith(material: _lastPvcMaterial));
                }
              },
            ),
            ChoiceChip(
              key: const Key('material-screen'),
              label: const Text('Скрин'),
              selected: params.isScreen,
              visualDensity: VisualDensity.compact,
              onSelected: (_) {
                if (!params.isScreen) {
                  _updateWindow(params.copyWith(material: FilmMaterial.screen));
                }
              },
            ),
          ],
        ),
        if (isPvc) ...[
          const SizedBox(height: 12),
          const Text(
            'Вид ПВХ',
            style: TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final (material, label, key) in const [
                (FilmMaterial.clearPvc, 'Прозрачное', 'material-clear'),
                (FilmMaterial.tintedPvc, 'Тонированное', 'material-tinted'),
                (FilmMaterial.mosquitoNet, 'Москитная сетка', 'material-mesh'),
              ])
                ChoiceChip(
                  key: Key(key),
                  label: Text(label),
                  selected: params.material == material,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) {
                    _lastPvcMaterial = material;
                    _updateWindow(params.copyWith(material: material));
                  },
                ),
            ],
          ),
        ] else ...[
          const SizedBox(height: 10),
          TextFormField(
            key: const Key('screen-color'),
            initialValue: params.screenColor,
            decoration: const InputDecoration(
              labelText: 'Цвет скрина',
              hintText: 'например, серый',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            textInputAction: TextInputAction.done,
            onChanged: (value) =>
                _updateWindow(params.copyWith(screenColor: value)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Скрин — сетчатая ткань для проветривания. Подвороты, шов 3 мм '
            'и крепёж по подвороту задаются ниже.',
            style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
        ],
        const SizedBox(height: 8),
        Text(
          '${params.material.thickness}; доступные рулоны: '
          '${params.material.rollWidthsLabel} ${unitSuffix()}',
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
      ],
    );
  }

  /// «Тип окна»: глухое / подъёмное / Т-образное.
  Widget _typeSection(WindowParams params) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Тип окна'),
        const SizedBox(height: 8),
        _chips<WindowType>(
          values: WindowType.values,
          selected: params.windowType,
          labelOf: (value) => value.label,
          onSelected: (value) => _updateWindow(
            params.copyWith(
              windowType: value,
              // Составное окно — всегда ПВХ-полотно: если выбран скрин,
              // переводим основной материал на обычный ПВХ.
              material: value == WindowType.composite && params.isScreen
                  ? FilmMaterial.clearPvc
                  : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          params.windowType.hint,
          style: const TextStyle(fontSize: 11.5, color: Color(0xFF5B6B80)),
        ),
        const SizedBox(height: 10),
        _tShapeSection(params),
        if (params.windowType == WindowType.composite) ...[
          const SizedBox(height: 10),
          _compositeSection(params),
        ] else ...[
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              key: const Key('make-composite'),
              onPressed: () => _updateWindow(
                params.copyWith(
                  windowType: WindowType.composite,
                  material: params.isScreen
                      ? FilmMaterial.clearPvc
                      : params.material,
                ),
              ),
              icon: const Icon(Icons.dashboard_customize_outlined, size: 18),
              label: const Text('Сделать составным'),
            ),
          ),
        ],
      ],
    );
  }

  /// Раздел «Составное окно»: второй материал с любой стороны, прямой или
  /// диагональный шов. Основное полотно — всегда ПВХ.
  Widget _compositeSection(WindowParams params) {
    final composite = params.composite;
    final spec = WindowSpec.of(params);
    final layout = spec.compositeLayout;
    WindowParams withComposite(CompositeSpec value) =>
        params.copyWith(composite: value);

    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Составное окно',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                key: const Key('make-plain-composite'),
                onPressed: () => _updateWindow(
                  params.copyWith(windowType: WindowType.fixed),
                ),
                child: const Text('Вернуть обычное'),
              ),
            ],
          ),
          const Text(
            'Основное полотно — ПВХ. Второй материал (скрин или ПВХ) '
            'пристраивается с любой стороны и спаивается по общему шву; '
            'окантовка идёт только по свободным кромкам.',
            style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          const SizedBox(height: 8),
          const Text(
            'Сторона второго материала',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _chips<EdgeSide>(
            values: EdgeSide.values,
            selected: composite.side,
            labelOf: (side) => side.label,
            keyOf: (side) => 'composite-side-${side.name}',
            onSelected: (side) => _updateWindow(
              withComposite(composite.copyWith(side: side)),
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Материал второго сегмента',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _chips<FilmMaterial>(
            values: const [
              FilmMaterial.screen,
              FilmMaterial.clearPvc,
              FilmMaterial.tintedPvc,
              FilmMaterial.mosquitoNet,
            ],
            selected: composite.material,
            labelOf: (material) => material.label,
            keyOf: (material) => 'composite-material-${material.name}',
            onSelected: (material) => _updateWindow(
              withComposite(composite.copyWith(material: material)),
            ),
          ),
          const SizedBox(height: 8),
          // Ширина второго сегмента — вся выбранная сторона: размер окна
          // остаётся ровно тем, что ввели. Меняется только вынос шва внутрь.
          SizedBox(
            width: 200,
            child: _numberField(ParamField.compositeDepth),
          ),
          const SizedBox(height: 4),
          const Text(
            'Второй сегмент режется ВНУТРИ введённых габаритов: ширина — вся '
            'сторона, вынос — глубина второго материала. Общий размер окна '
            'не меняется.',
            style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          if (composite.isDiagonal) ...[
            const SizedBox(height: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Смещение шва, доля стороны',
                  style: TextStyle(fontSize: 10.5, color: Color(0xFF66748A)),
                ),
                Slider(
                  key: const Key('composite-seam-offset'),
                  value: composite.seamOffset.clamp(0.05, 0.95),
                  min: 0.05,
                  max: 0.95,
                  onChanged: (value) => _updateWindow(
                    withComposite(composite.copyWith(seamOffset: value)),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 4),
          const Text(
            'Шов',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          _chips<CompositeSeam>(
            values: CompositeSeam.values,
            selected: composite.seam,
            labelOf: (seam) => seam.label,
            keyOf: (seam) => 'composite-seam-${seam.name}',
            onSelected: (seam) => _updateWindow(
              withComposite(composite.copyWith(seam: seam)),
            ),
          ),
          if (composite.isDiagonal) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: 180,
              child: _numberField(ParamField.compositeAngle),
            ),
            const SizedBox(height: 4),
            const Text(
              'Диагональный шов режет угол основного полотна: второй сегмент '
              'встаёт к наклонной кромке встык.',
              style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            layout == null
                ? 'Второй сегмент не построен'
                : '${composite.material.label} · '
                      'шов ${formatMm(layout.seamLength)} ${unitSuffix()} · '
                      'вынос ${formatMm(layout.depth)} ${unitSuffix()} · '
                      'ПВХ ${formatMeters(layout.mainAreaMm2 / 1000000)} м² + '
                      'второй ${formatMeters(layout.secondAreaMm2 / 1000000)} м² '
                      '= ${formatMeters(spec.productAreaM2)} м²',
            key: const Key('composite-summary'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF41506A)),
          ),
          if (layout != null && layout.clamped) ...[
            const SizedBox(height: 6),
            const Text(
              'Второй сегмент не помещается на стороне: размеры подрезаны.',
              style: TextStyle(fontSize: 11, color: Color(0xFF8A5200)),
            ),
          ],
        ],
      ),
    );
  }

  /// «Размеры»: ширина/высота и поля разных сторон в компактной сетке.
  Widget _sizesSection(WindowSpec spec) {
    final params = spec.params;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle('Размеры, ${unitSuffix()}'),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _numberField(ParamField.bottomWidth)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(ParamField.topWidth)),
          ],
        ),
        Row(
          children: [
            Expanded(child: _numberField(ParamField.leftHeight)),
            const SizedBox(width: 12),
            Expanded(child: _numberField(ParamField.rightHeight)),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Для разных сторон заполните ширину низа/верха и высоты '
          'слева/справа.',
          style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
        const SizedBox(height: 10),
        _levelEdgeSelector(params),
        const SizedBox(height: 12),
        _allowanceSection(spec),
      ],
    );
  }

  /// «Окантовка / подвороты»: у ПВХ — окантовка по сторонам, у скрина —
  /// подвороты по сторонам.
  Widget _edgeOrHemSection(WindowSpec spec) {
    final params = spec.params;
    if (params.isScreen) {
      return _expansion(
        title: 'Подвороты',
        subtitle: params.hemBySideShortLabel,
        children: [
          _hemSection(spec),
          const SizedBox(height: 8),
          const Text(
            'У скрина нет окантовки: материал подворачивается сам, шов 3 мм. '
            'К высоте заготовки добавляется 20 мм на шов и запас.',
            style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
        ],
      );
    }
    return _expansion(
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
          '${formatMm(params.weldOverlapMm)} ${unitSuffix()} может не хватить ленты.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
        const SizedBox(height: 12),
        _weldOverlapField(params),
      ],
    );
  }

  /// «Ширина рулона» — в нижней части панели.
  Widget _rollWidthSection(OrderProject project, WindowParams params) {
    return _expansion(
      title: 'Ширина рулона',
      subtitle:
          '${params.material.label} · '
          '${formatMm(project.rollWidthFor(params.material))} ${unitSuffix()}',
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final width in params.availableRollWidths)
              ChoiceChip(
                label: Text(
                  '${formatMm(width)} ${unitSuffix()}',
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
        const SizedBox(height: 6),
        Text(
          'Доступные рулоны: ${params.material.rollWidthsLabel} '
          '${unitSuffix()}. Раскладка — на отдельном листе.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
      ],
    );
  }

  /// Дополнительные позиции заказа: количество вводится здесь, цена — в
  /// прайсе. В смету попадают только при количестве больше нуля.
  Widget _extraItemsSection(OrderProject project) {
    final total = PriceList.extraItemKeys.fold<double>(
      0,
      (sum, key) => sum + (project.extraQuantities[key] ?? 0),
    );
    return _expansion(
      title: 'Дополнительно',
      subtitle: total > 0 ? 'позиции в смете: ${total.toStringAsFixed(0)}' : 'доставка, парус, брус, zip…',
      children: [
        for (final key in PriceList.extraItemKeys)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: TextFormField(
              key: Key('extra-$key'),
              initialValue: _textFor(project.extraQuantities[key] ?? 0),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText:
                    '${PriceList.extraItemLabel(key)}, '
                    '${PriceList.extraItemUnit(key)}',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (raw) {
                final parsed = double.tryParse(raw.replaceAll(',', '.'));
                if (parsed == null || parsed < 0) return;
                widget.onChanged(
                  project.copyWith(
                    extraQuantities: {
                      ...project.extraQuantities,
                      key: parsed,
                    },
                  ),
                );
              },
            ),
          ),
      ],
    );
  }

  /// «Цвета» — в самом низу панели.
  Widget _colorsSection(WindowParams params) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Цвета'),
        const SizedBox(height: 8),
        _colorChips(params),
        const SizedBox(height: 6),
        const Text(
          'Цвет окантовки, подворота и крепежа на чертеже.',
          style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final project = widget.project;
    final params = project.selected;
    final spec = WindowSpec.of(params);
    final prices = widget.prices ?? const PriceList.defaults();
    final warnings = widget.issues
        .where((issue) => !issue.isError)
        .toList(growable: false);

    return Material(
      color: const Color(0xFFF7F9FC),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // 1. Заказы — в самом верху: переключение, имя, удаление.
          _ordersTopSection(project),
          const SizedBox(height: 12),
          // 2. Окна внутри выбранного заказа.
          _windowSection(project),
          const SizedBox(height: 18),
          // 3. Материал окна: ПВХ (с видом) или скрин.
          _materialSection(params),
          const SizedBox(height: 12),
          // 4. Тип окна.
          _typeSection(params),
          const SizedBox(height: 18),
          // 5. Размеры, «Ровно» и припуски на раскрой.
          _sizesSection(spec),
          const SizedBox(height: 18),
          // 6. Все крепежи с ценами.
          _fastenerSection(spec, prices),
          const SizedBox(height: 12),
          // 7. Окантовка ПВХ или подвороты скрина.
          _edgeOrHemSection(spec),
          const SizedBox(height: 12),
          if (params.isLifting && !params.isScreen) ...[
            const SizedBox(height: 12),
            _liftStrapsSection(params, spec),
          ],
          _expansion(
            title: 'Молния и фартук',
            subtitle: _specElementsSummary(params),
            children: [
              if (params.zippers.isEmpty)
                OutlinedButton.icon(
                  onPressed: () => _updateWindow(params.addZipper()),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Добавить молнию'),
                )
              else ...[
                for (var index = 0; index < params.zippers.length; index++)
                  _zipperCard(params, spec, index),
                if (params.zippers.length < maxZippers)
                  OutlinedButton.icon(
                    key: const Key('add-zipper'),
                    onPressed: () => _updateWindow(params.addZipper()),
                    icon: const Icon(Icons.add, size: 18),
                    label: Text(
                      'Добавить молнию (${params.zippers.length}/$maxZippers)',
                    ),
                  ),
                const SizedBox(height: 6),
                Text(
                  params.isScreen
                      ? 'Полоса под молнию у скрина — подвёрнутая ткань (или '
                            'накладная полоса из скрина): на чертеже полоса серая, '
                            'как подворот, со швом '
                            '${formatMm(screenSeamMm)} ${unitSuffix()} по краям. Молния не '
                            'должна подходить к кромке подворота ближе '
                            '${formatMm(minScreenZipperHemMm)} ${unitSuffix()}. Всего до '
                            '$maxZippers молний.'
                      : 'Молния впаивается в полосу тента: на чертеже показаны '
                            'полоса спайки и расстояния до кромок плёнки. Всего '
                            'до $maxZippers молний.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF66748A),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              // Две явные кнопки-переключателя: выбранная подсвечена, повторный
              // тап выключает флаг. В модели по-прежнему pocket / pocketTop.
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _apronToggle(
                    key: const Key('apron-bottom-toggle'),
                    label: 'Фартук снизу',
                    icon: Icons.vertical_align_bottom,
                    selected: params.pocket,
                    onPressed: () =>
                        _updateWindow(params.copyWith(pocket: !params.pocket)),
                  ),
                  _apronToggle(
                    key: const Key('apron-top-toggle'),
                    label: 'Фартук сверху',
                    icon: Icons.vertical_align_top,
                    selected: params.pocketTop,
                    onPressed: () => _updateWindow(
                      params.copyWith(pocketTop: !params.pocketTop),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                _apronStateLabel(params),
                key: const Key('apron-state'),
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF0B62C4),
                ),
              ),
              const SizedBox(height: 8),
              _apronWidthField(),
              const SizedBox(height: 6),
              const Text(
                'Фартук идёт от внутреннего края окантовки наружу и ниже кромки',
                key: Key('apron-caption'),
                style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
              ),
              if (params.pocket || params.pocketTop) ...[
                const SizedBox(height: 6),
                Text(
                  params.isScreen
                      ? 'У скрина фартук образуется подворотом материала '
                            '${formatMm(params.pocketWidth)} ${unitSuffix()}. Угловые люверсы со '
                            'стороны фартука не ставятся, крайние боковые смещаются '
                            'на ${formatMm(pocketCornerOffset)} ${unitSuffix()} — чтобы в полость '
                            'фартука заводился утяжитель.'
                      : 'Фартук делается из тента 200 мм, складывается пополам — '
                            'получается ${formatMm(params.pocketWidth)} ${unitSuffix()}. Угловые '
                            'люверсы со стороны фартука не ставятся: они смещаются на '
                            '${formatMm(pocketCornerOffset)} ${unitSuffix()}, чтобы в полость '
                            'фартука заводился утяжитель.',
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
                '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()}',
            children: [
              if (params.isScreen) ...[
                Text(
                  'У скрина усадки нет: заготовка равна готовому размеру плюс '
                  'половина подворота каждой стороны, к высоте добавляется '
                  '${formatMm(screenHemAxisExtraMm)} ${unitSuffix()} на шов и запас. '
                  'Нужен запас — добавьте припуск на раскрой.',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF66748A),
                  ),
                ),
                const SizedBox(height: 12),
              ] else ...[
                SwitchListTile(
                  key: const Key('shrinkage-toggle'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Учитывать усадку ПВХ',
                    style: TextStyle(fontSize: 13),
                  ),
                  subtitle: const Text(
                    'включите, если партия плёнки даёт усадку',
                    style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
                  ),
                  value: params.shrinkageEnabled,
                  onChanged: _setShrinkageEnabled,
                ),
                if (params.shrinkageEnabled) ...[
                  Text(
                    'Типовая усадка 1–2 %; поле принимает 0…'
                    '${formatDecimal(maxShrinkageFieldPercent)} %.',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF66748A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  _numberField(ParamField.shrinkagePercent),
                ],
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
                '«Ширина рулона». Раскладка строится на вкладке '
                '«Раскладка на рулоне».',
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
          const SizedBox(height: 12),
          _companySection(),
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
                label: const Text('Добавить фартук'),
              ),
              TextButton.icon(
                onPressed: widget.onReset,
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Сбросить'),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _rollWidthSection(project, params),
          const SizedBox(height: 12),
          _extraItemsSection(project),
          const SizedBox(height: 12),
          _colorsSection(params),
          if (widget.ordersSection != null) ...[
            const SizedBox(height: 16),
            widget.ordersSection!,
          ],
          if (widget.techSection != null) ...[
            const SizedBox(height: 12),
            widget.techSection!,
          ],
          if (widget.pricesSection != null) ...[
            const SizedBox(height: 12),
            widget.pricesSection!,
          ],
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// Кнопка-переключатель фартука: выбранное состояние подсвечено заливкой.
  ///
  /// Это не тумблер-переключатель, а явная кнопка: подпись называет сторону,
  /// состояние видно по заливке и галочке, а повторный тап выключает флаг.
  Widget _apronToggle({
    required Key key,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onPressed,
  }) {
    const accent = Color(0xFF0B62C4);
    return OutlinedButton.icon(
      key: key,
      onPressed: onPressed,
      icon: Icon(selected ? Icons.check_circle : icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? Colors.white : accent,
        backgroundColor: selected ? accent : Colors.white,
        side: BorderSide(color: selected ? accent : const Color(0xFFB9C6D8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  /// Подпись состояния кнопок «Фартук снизу/сверху» — чтобы состояние было
  /// видно и текстом, а не только подсветкой кнопки.
  String _apronStateLabel(WindowParams params) {
    if (params.pocket && params.pocketTop) {
      return 'Сейчас: фартук снизу и сверху';
    }
    if (params.pocket) return 'Сейчас: фартук снизу';
    if (params.pocketTop) return 'Сейчас: фартук сверху';
    return 'Фартук не включён';
  }

  /// Поле «Ширина фартука, мм» — общее для нижнего и верхнего фартука.
  Widget _apronWidthField() {
    return TextField(
      key: const Key('apron-width-field'),
      controller: _controllers[ParamField.pocketWidth],
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: 'Ширина фартука, мм',
        helperText:
            'общая для нижнего и верхнего фартука; обычно '
            '${formatMm(pocketFinishedWidth)} ${unitSuffix()}',
        helperMaxLines: 2,
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _errorFor(ParamField.pocketWidth),
        errorMaxLines: 2,
      ),
      onChanged: (raw) => _onNumberChanged(ParamField.pocketWidth, raw),
    );
  }

  String _specElementsSummary(WindowParams params) {
    final zipperPart = switch (params.zippers.length) {
      0 => null,
      1 => 'молния '
          '${formatMm(WindowSpec.of(params).layers.zipperWidthFor(params.zippers.first))} '
          '${unitSuffix()}',
      _ => 'молний ${params.zippers.length}',
    };
    final parts = <String>[
      ?zipperPart,
      if (params.cutouts.isNotEmpty) 'вырезов ${params.cutouts.length}',
      if (params.pocket)
        'фартук снизу ${formatMm(params.pocketWidth)} ${unitSuffix()}',
      if (params.pocketTop)
        'фартук сверху ${formatMm(params.pocketWidth)} ${unitSuffix()}',
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
    return '${params.cutouts.length} шт · контур ${formatMm(perimeter)} ${unitSuffix()}';
  }

  /// Раздел «Т-образное окно»: перевод в Т-форму и две пристройки.
  ///
  /// Каждая пристройка — свой блок «Пристройка 1» / «Пристройка 2»: сторона,
  /// ширина, высота, смещение, спайка и включение. Две пристройки позволяют
  /// сделать угловую форму (например, справа и снизу). Пристройки на одной
  /// стороне запрещены — панель показывает предупреждение, а расчёт оставляет
  /// только первую и не ломается.
  Widget _tShapeSection(WindowParams params) {
    if (!params.isTShape) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          OutlinedButton.icon(
            key: const Key('make-t-shape'),
            onPressed: () => _updateWindow(
              params.copyWith(
                windowType: WindowType.tShape,
                topWidth: params.bottomWidth,
                rightHeight: params.leftHeight,
              ),
            ),
            icon: const Icon(Icons.join_inner, size: 18),
            label: const Text('Сделать Т-образным'),
          ),
          const SizedBox(height: 4),
          const Text(
            'Основное полотно плюс до двух пристроек, сваренных по общим '
            'сторонам. Окантовка пойдёт только по внешнему периметру.',
            style: TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
        ],
      );
    }

    final spec = WindowSpec.of(params);
    final conflict = spec.tAnnexConflict;
    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Т-образное окно',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              TextButton(
                key: const Key('make-plain-window'),
                onPressed: () => _updateWindow(
                  params.copyWith(windowType: WindowType.fixed),
                ),
                child: const Text('Вернуть обычное'),
              ),
            ],
          ),
          Text(
            spec.tShapeSummary,
            key: const Key('t-shape-summary'),
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          if (conflict != null) ...[
            const SizedBox(height: 8),
            Container(
              key: const Key('t-annex-conflict'),
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF4E0),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0B466)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    size: 16,
                    color: Color(0xFF8A5200),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      conflict,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF8A5200),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          _annexBlock(params, 1),
          const SizedBox(height: 8),
          _annexBlock(params, 2),
          const SizedBox(height: 4),
          Text(
            'Смещение — вдоль общей стороны: от низа для пристройки справа '
            'или слева, от левого края для верхней или нижней. Две пристройки '
            'на одной стороне запрещены: выберите разные стороны.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
        ],
      ),
    );
  }

  /// Блок одной пристройки: включение, сторона, размеры, смещение и спайка.
  Widget _annexBlock(WindowParams params, int number) {
    final first = number == 1;
    final enabled = first ? params.tEnabled : params.t2Enabled;
    final side = first ? params.tSide : params.t2Side;
    final welded = first ? params.tWelded : params.t2Welded;
    final widthField = first ? ParamField.tWidth : ParamField.t2Width;
    final heightField = first ? ParamField.tHeight : ParamField.t2Height;
    final offsetField = first ? ParamField.tOffset : ParamField.t2Offset;
    final prefix = 't$number';
    WindowParams withEnabled(bool value) => first
        ? params.copyWith(tEnabled: value)
        : params.copyWith(t2Enabled: value);
    WindowParams withSide(TShapeSide value) =>
        first ? params.copyWith(tSide: value) : params.copyWith(t2Side: value);
    WindowParams withWelded(bool value) => first
        ? params.copyWith(tWelded: value)
        : params.copyWith(t2Welded: value);

    return Material(
      key: Key('t-annex-$number'),
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: enabled ? const Color(0xFFC3CCDA) : const Color(0xFFE4E8EF),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SwitchListTile(
              key: Key('$prefix-enabled'),
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: enabled,
              title: Text(
                'Пристройка $number',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              subtitle: Text(
                first
                    ? 'Основная пристройка Т-окна. Выключите, если нужна только '
                          'вторая (или ни одной).'
                    : 'Вторая пристройка — угловая форма: например, справа и '
                          'снизу.',
                style: const TextStyle(fontSize: 11),
              ),
              onChanged: (value) => _updateWindow(withEnabled(value)),
            ),
            if (enabled) ...[
              Text(
                'Сторона пристройки $number',
                style: const TextStyle(fontSize: 12, color: Color(0xFF5B6B80)),
              ),
              const SizedBox(height: 4),
              _chips<TShapeSide>(
                values: TShapeSide.values,
                selected: side,
                labelOf: (value) => value.label,
                keyOf: (value) => '$prefix-side-${value.name}',
                onSelected: (value) => _updateWindow(withSide(value)),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(child: _numberField(widthField)),
                  const SizedBox(width: 10),
                  Expanded(child: _numberField(heightField)),
                ],
              ),
              const SizedBox(height: 8),
              _numberField(offsetField),
              SwitchListTile(
                key: Key(first ? 't-welded' : 't2-welded'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: welded,
                title: const Text(
                  'Спайка по общей стороне',
                  style: TextStyle(fontSize: 12),
                ),
                subtitle: Text(
                  welded
                      ? 'Два полотна свариваются в одно окно, окантовка — только '
                            'по внешнему периметру.'
                      : 'Без спайки: отдельное окно, окантовка по всему '
                            'периметру части.',
                  style: const TextStyle(fontSize: 11),
                ),
                onChanged: (value) => _updateWindow(withWelded(value)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Карточка внутри раздела: подложка с рамкой. Прозрачный Material нужен,
  /// чтобы переключатели рисовали чернильные волны поверх заливки.
  /// «Компания на листах»: тумблер показа и настройка реквизитов с логотипом.
  Widget _companySection() {
    return ValueListenableBuilder<CompanyBrandingState>(
      valueListenable: CompanyBranding.current,
      builder: (context, branding, _) {
        final name = branding.details.name.trim();
        return _panelCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Компания на листах',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    branding.showOnSheets
                        ? (name.isEmpty ? 'включено' : name)
                        : 'выключено',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF66748A),
                    ),
                  ),
                ],
              ),
              SwitchListTile(
                key: const Key('company-on-sheets-toggle'),
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: branding.showOnSheets,
                title: const Text(
                  'Показывать данные компании и логотип',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                subtitle: const Text(
                  'Смета — логотип и строка реквизитов в синей шапке; чертёж — '
                  'логотип с названием в штампе. Выключено — листы как сейчас.',
                  style: TextStyle(fontSize: 11),
                ),
                onChanged: (value) => CompanyBranding.setShowOnSheets(value),
              ),
              OutlinedButton.icon(
                key: const Key('company-settings'),
                onPressed: () => showCompanyDialog(context),
                icon: const Icon(Icons.business_outlined, size: 18),
                label: const Text('Настроить компанию и логотип'),
              ),
              if (branding.showOnSheets && !branding.hasDetails) ...[
                const SizedBox(height: 6),
                const Text(
                  'Заполните хотя бы название — иначе блок на листах не покажется.',
                  style: TextStyle(fontSize: 11, color: Color(0xFF8A5200)),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

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

  /// Переключатель «Круглые люверсы в углах».
  ///
  /// Включён по умолчанию: в углу ставится круглый Ø10 мм, потому что угол
  /// тянет по диагонали и овальный люверс там не держит. Выключение убирает
  /// угловую точку целиком — с чертежа, из расхода и из сметы: например, когда
  /// всё крепление — французские замки, скобы или ремни и круглых люверсов
  /// не нужно ни одного.
  Widget _roundEyeletsSection(WindowSpec spec) {
    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            key: const Key('round-eyelets-corners'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: spec.params.roundEyeletsEnabled,
            title: const Text(
              'Круглые люверсы в углах',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            ),
            subtitle: const Text(
              'Угол тянет по диагонали, поэтому в нём ставится круглый '
              'люверс Ø10 мм. Выключите, если круглых люверсов не нужно '
              'ни одного: угловая точка уйдёт с чертежа, из расхода и сметы.',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) =>
                _updateWindow(spec.params.copyWith(roundEyeletsEnabled: value)),
          ),
          Text(
            spec.params.roundEyeletsEnabled
                ? 'Круглых люверсов в углах: '
                      '${spec.layers.cornerEyelets.length} шт'
                : 'Круглых люверсов нет: углы остаются без крепёжных точек.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
        ],
      ),
    );
  }

  /// Переключатели «не ставить люверсы сверху/снизу».
  ///
  /// Сторона остаётся без крепежа: там предполагается спайка с соседним окном
  /// или крепление полотна к стене/раме другим способом. Углы выключенной
  /// стороны тоже не ставятся — угол принадлежит стороне, которая идёт первой
  /// в обходе (см. WindowLayers.eyelets).
  Widget _noEyeletsSection(WindowParams params) {
    return _panelCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Стороны без люверсов',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
          SwitchListTile(
            key: const Key('no-eyelets-top'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: params.noEyeletsTop,
            title: const Text(
              'Не ставить люверсы сверху',
              style: TextStyle(fontSize: 12),
            ),
            subtitle: const Text(
              'Верх останется без крепежа: например, там будет спайка с '
              'соседним окном или крепление к стене.',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) =>
                _updateWindow(params.copyWith(noEyeletsTop: value)),
          ),
          SwitchListTile(
            key: const Key('no-eyelets-bottom'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: params.noEyeletsBottom,
            title: const Text(
              'Не ставить люверсы снизу',
              style: TextStyle(fontSize: 12),
            ),
            subtitle: const Text(
              'Низ останется без крепежа: например, там будет спайка с '
              'соседним окном или крепление к стене.',
              style: TextStyle(fontSize: 11),
            ),
            onChanged: (value) =>
                _updateWindow(params.copyWith(noEyeletsBottom: value)),
          ),
          Text(
            'По чертежу: люверсов '
            '${WindowSpec.of(params).layers.standaloneEyelets.length} шт'
            '${WindowSpec.of(params).layers.fastenerPointsCount > 0 ? ', крепежа ${WindowSpec.of(params).layers.fastenerPointsCount} шт' : ''}'
            '${params.hasEyeletlessSides ? ' (без сторон: '
                      '${WindowSpec.of(params).layers.eyeletlessSidesLabel})' : ''}.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
        ],
      ),
    );
  }

  /// Карточка одной молнии: центр или сдвиг, ширина спайки, удаление.
  /// «Подъёмные ремни»: ручное добавление и привязка к линии тента.
  ///
  /// Пустой список — прежняя автоматическая расстановка (2 шт до 2 м, далее
  /// +1 на метр). Добавили вручную — ровно эти ремни, каждый начинается на
  /// линии тента; на косом окне линия наклонена, и ремень идёт от неё.
  Widget _liftStrapsSection(WindowParams params, WindowSpec spec) {
    final offsets = params.liftStrapOffsets;
    final width = spec.filmVisibleWidth;
    final maxOffset = width.isFinite && width > 0 ? width : 1.0;
    double nextOffset() {
      if (offsets.isEmpty) return maxOffset / 2;
      final step = maxOffset / (offsets.length + 2);
      return (offsets.last + step).clamp(0.0, maxOffset);
    }

    return _expansion(
      title: 'Подъёмные ремни',
      subtitle: offsets.isEmpty
          ? 'авто: ${params.liftStrapCount} шт'
          : 'вручную: ${offsets.length} шт',
      children: [
        Text(
          offsets.isEmpty
              ? 'Ремни расставлены автоматически (2 шт до 2 м, далее +1 на '
                    'метр). Нажмите «+ ремешок», чтобы поставить их вручную — '
                    'каждый привяжется к линии тента, в том числе на косой '
                    'кромке.'
              : 'Ремни стоят вручную и начинаются на линии тента: на косом '
                    'окне кромка наклонена, ремень идёт от неё, а не висит за '
                    'окантовкой.',
          style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
        ),
        const SizedBox(height: 6),
        for (var index = 0; index < offsets.length; index++)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: Key('lift-strap-$index'),
                    controller: _strapControllers.putIfAbsent(
                      index,
                      () => TextEditingController(text: _textFor(offsets[index])),
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Ремень ${index + 1}: центр от левого края',
                      suffixText: 'мм',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (raw) {
                      final parsed = parseMm(raw);
                      if (parsed == null || !parsed.isFinite) return;
                      _updateWindow(
                        params.updateLiftStrap(
                          index,
                          parsed.clamp(0.0, maxOffset),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Удалить ремень',
                  icon: const Icon(Icons.delete_outline, size: 18),
                  onPressed: () =>
                      _updateWindow(params.removeLiftStrap(index)),
                ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              key: const Key('add-lift-strap'),
              onPressed: () =>
                  _updateWindow(params.addLiftStrap(nextOffset())),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('+ ремешок'),
            ),
            if (offsets.isNotEmpty)
              TextButton(
                key: const Key('reset-lift-straps'),
                onPressed: () =>
                    _updateWindow(params.copyWith(liftStrapOffsets: const [])),
                child: const Text('Сбросить к авто'),
              ),
          ],
        ),
      ],
    );
  }

  /// Пояснение к молнии в режиме сегментов: делит или впритык к канту.
  String _zipperSegmentNote(WindowSpec spec, int index) {
    final layout = spec.layers.zipperSegmentLayout;
    if (index >= layout.length) return '';
    final line = layout[index];
    if (line.edge) {
      return 'Молния впритык к канту: сегменты не делятся, ширина '
          '${formatMm(line.bandWidth)} ${unitSuffix()} вычитается из заготовки '
          'как полоса молнии.';
    }
    return 'Молния между сегментами: зазор '
        '${formatMm(line.gapEnd - line.gapStart)} ${unitSuffix()} '
        '(полоса молнии), полотно режется на отдельные сегменты.';
  }

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
          if (!zipper.centered && !zipper.atEdge) ...[
            const SizedBox(height: 4),
            Text(
              'Положение от левого края плёнки: ${formatMm(offset)} ${unitSuffix()}',
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
          SwitchListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            title: const Text('Вплотную к окантовке'),
            subtitle: const Text(
              'Молния у самого края: в полосу входит готовая окантовка.',
              style: TextStyle(fontSize: 11),
            ),
            value: zipper.atEdge,
            onChanged: (value) => _updateWindow(
              params.updateZipper(
                index,
                zipper.copyWith(
                  atEdge: value,
                  centered: value ? false : zipper.centered,
                ),
              ),
            ),
          ),
          if (zipper.atEdge) ...[
            const SizedBox(height: 4),
            Row(
              children: [
                ChoiceChip(
                  key: Key('zipper-edge-left-$index'),
                  label: const Text('Слева'),
                  selected: !zipper.edgeRight,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _updateWindow(
                    params.updateZipper(
                      index,
                      zipper.copyWith(
                        centered: false,
                        edgeRight: false,
                        offsetMm: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                ChoiceChip(
                  key: Key('zipper-edge-right-$index'),
                  label: const Text('Справа'),
                  selected: zipper.edgeRight,
                  visualDensity: VisualDensity.compact,
                  onSelected: (_) => _updateWindow(
                    params.updateZipper(
                      index,
                      zipper.copyWith(
                        centered: false,
                        edgeRight: true,
                        offsetMm: maxOffset,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _zipperSizeField(
                  index: index,
                  label: 'Ширина молнии',
                  helper: 'например 15',
                  value: zipper.zipWidthMm,
                  min: 1,
                  max: 100,
                  controllers: _zipperZipControllers,
                  errors: _zipperZipErrors,
                  apply: (zipper, value) =>
                      zipper.copyWith(zipWidthMm: value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _zipperSizeField(
                  index: index,
                  label: 'Ширина тента',
                  helper: 'с одной стороны',
                  value: zipper.tentWidthMm,
                  min: 5,
                  max: 300,
                  controllers: _zipperTentControllers,
                  errors: _zipperTentErrors,
                  apply: (zipper, value) =>
                      zipper.copyWith(tentWidthMm: value),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _zipperSizeField(
                  index: index,
                  label: 'Напайка',
                  helper: 'на полотно',
                  value: zipper.weldMm,
                  min: 0,
                  max: 100,
                  controllers: _zipperWeldControllers,
                  errors: _zipperWeldErrors,
                  apply: (zipper, value) => zipper.copyWith(weldMm: value),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            zipper.atEdge
                ? 'Полоса ${formatMm(spec.layers.zipperWidthFor(zipper))} ${unitSuffix()}: '
                      'окантовка ${formatMm(zipper.edgeRight ? spec.layers.finishedWidths[1] : spec.layers.finishedWidths[3])} + '
                      'молния ${formatMm(zipper.zipWidthMm)} + тент '
                      '${formatMm(zipper.tentWidthMm)} − напайка '
                      '${formatMm(zipper.weldMm)}.'
                : 'Полоса ${formatMm(spec.layers.zipperWidthFor(zipper))} ${unitSuffix()}: '
                      'молния ${formatMm(zipper.zipWidthMm)} + 2 × тент '
                      '${formatMm(zipper.tentWidthMm)} − 2 × напайка '
                      '${formatMm(zipper.weldMm)}.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          const SizedBox(height: 4),
          Text(
            'Ширина заготовки уменьшается на полосу так же, как у скрина: '
            '${formatMm(spec.filmCutWidthBeforeZipper)}'
            ' → ${formatMm(spec.filmCutWidth)} ${unitSuffix()} до припуска.',
            style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
          ),
          const SizedBox(height: 4),
          Text(
            _zipperSegmentNote(spec, index),
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
        helperText: '0–${formatMm(maxOffset)} ${unitSuffix()}, шаг 10',
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: _zipperOffsetErrors[index],
        errorMaxLines: 2,
      ),
      onChanged: (raw) => _onZipperOffsetChanged(index, raw, maxOffset),
    );
  }

  Widget _zipperSizeField({
    required int index,
    required String label,
    required String helper,
    required double value,
    required double min,
    required double max,
    required Map<int, TextEditingController> controllers,
    required Map<int, String?> errors,
    required ZipperSpec Function(ZipperSpec, double) apply,
  }) {
    return TextField(
      controller: controllers.putIfAbsent(
        index,
        () => TextEditingController(text: _textFor(value)),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: 'мм',
        helperText: helper,
        border: const OutlineInputBorder(),
        isDense: true,
        errorText: errors[index],
        errorMaxLines: 2,
      ),
      onChanged: (raw) {
        final parsed = parseMm(raw);
        if (parsed == null) {
          setState(() => errors[index] = 'Введите число, например 50');
          return;
        }
        if (parsed < min || parsed > max) {
          setState(
            () => errors[index] =
                '$label: от ${formatMm(min)} до ${formatMm(max)} мм',
          );
          return;
        }
        setState(() => errors[index] = null);
        final zipper = _params.zippers[index];
        _updateWindow(_params.updateZipper(index, apply(zipper, parsed)));
      },
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
            'Положение от 0 до ${formatMm(maxOffset)} ${unitSuffix()}',
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

  /// Карточка одного выреза: форма, размеры, положение центра, удаление.
  Widget _cutoutCard(WindowParams params, int index) {
    final cutout = params.cutouts[index];
    final isCircle = cutout.shape == CutoutShape.circle;
    // Границы хода выреза — видимая плёнка изделия (внутренняя граница
    // окантовки/подворота). Берём готовые геттеры спецификации, чтобы не
    // пересчитывать окантовку руками.
    final spec = WindowSpec.of(params);
    final maxX = spec.filmVisibleWidth;
    final maxY = spec.filmVisibleHeight;
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
                'контур ${formatMm(cutout.perimeterMm)} ${unitSuffix()}',
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
          // Ползунки двигают центр выреза мышью по видимой плёнке. Числовые
          // поля выше остаются: мелкое значение удобнее ввести руками,
          // а положение — подобрать ползунком.
          const SizedBox(height: 6),
          _cutoutSlider(
            index: index,
            field: _CutoutField.centerX,
            value: cutout.centerXMm,
            maxMm: maxX,
          ),
          const SizedBox(height: 4),
          _cutoutSlider(
            index: index,
            field: _CutoutField.centerY,
            value: cutout.centerYMm,
            maxMm: maxY,
          ),
          const SizedBox(height: 2),
          Text(
            'По видимой плёнке: 0…${formatMm(maxX)} ${unitSuffix()} по горизонтали, '
            '0…${formatMm(maxY)} ${unitSuffix()} по вертикали, шаг '
            '${formatMm(_cutoutSliderStepMm)} ${unitSuffix()}.',
            style: const TextStyle(fontSize: 10.5, color: Color(0xFF66748A)),
          ),
        ],
      ),
    );
  }

  /// Ползунок положения выреза по одной оси.
  ///
  /// Диапазон — видимая плёнка изделия, шаг [_cutoutSliderStepMm]. Значение
  /// всегда берётся из модели, поэтому ползунок и числовое поле показывают
  /// одно и то же: тянем ползунок — число переписывается через
  /// [_syncController], вводим число — ползунок встаёт на место.
  Widget _cutoutSlider({
    required int index,
    required _CutoutField field,
    required double value,
    required double maxMm,
  }) {
    final isX = field == _CutoutField.centerX;
    final axis = _cutoutAxisName(field);
    // Меньше шага двигать нечего: ползунок показываем, но выключаем.
    final limit = maxMm.isFinite && maxMm > 0 ? maxMm : 0.0;
    final enabled = limit >= _cutoutSliderStepMm;
    // Число из поля может выйти за видимую плёнку (ввели руками) — ползунок
    // показываем в пределах диапазона, иначе Slider упадёт на проверке.
    final clamped = value.clamp(0.0, limit).toDouble();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                isX ? 'Положение по горизонтали' : 'Положение по вертикали',
                style: const TextStyle(
                  fontSize: 11.5,
                  color: Color(0xFF5B6B80),
                ),
              ),
            ),
            Text(
              '${isX ? 'по горизонтали' : 'по вертикали'}: '
              '${formatMm(value)} ${unitSuffix()}',
              key: Key('cutout-$index-$axis-value'),
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: Color(0xFF0B62C4),
              ),
            ),
          ],
        ),
        SizedBox(
          // Стандартные 48 px раздувают карточку, а панель узкая (420 px).
          height: 34,
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
              // Подпись значения стоит над ползунком — пузырёк не нужен.
              showValueIndicator: ShowValueIndicator.never,
            ),
            child: Slider(
              key: Key('cutout-$index-$axis-slider'),
              min: 0,
              max: enabled ? limit : _cutoutSliderStepMm,
              divisions: enabled ? (limit / _cutoutSliderStepMm).round() : null,
              value: enabled ? clamped : 0,
              onChanged: enabled
                  ? (raw) => _onCutoutSliderChanged(index, field, raw)
                  : null,
            ),
          ),
        ),
      ],
    );
  }

  /// Движение ползунка выреза: значение округляется до шага 10 мм.
  ///
  /// Ошибку числового поля снимаем — ползунок всегда даёт корректное число.
  void _onCutoutSliderChanged(int index, _CutoutField field, double raw) {
    final cutouts = _params.cutouts;
    if (index < 0 || index >= cutouts.length) return;
    if (field != _CutoutField.centerX && field != _CutoutField.centerY) {
      return;
    }
    final snapped = (raw / _cutoutSliderStepMm).round() * _cutoutSliderStepMm;
    final cutout = cutouts[index];
    setState(() => _cutoutErrors[(index, field)] = null);
    final updated = field == _CutoutField.centerX
        ? cutout.copyWith(centerXMm: snapped)
        : cutout.copyWith(centerYMm: snapped);
    _updateWindow(_params.updateCutout(index, updated));
  }

  Widget _cutoutField({
    required int index,
    required _CutoutField field,
    required double value,
    required String label,
  }) {
    return TextField(
      key: Key('cutout-$index-${_cutoutAxisName(field)}-field'),
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
        '${material.label.toLowerCase()}: ${formatMm(project.rollWidthFor(material))} ${unitSuffix()}',
    ];
    return '${parts.join(' · ')} · зазор ${formatMm(project.rollGap)} ${unitSuffix()}';
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
                'готовая полоса ${formatMm(finished)} ${unitSuffix()} '
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
    bool initiallyExpanded = true,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD9E0EA)),
      ),
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
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
    String Function(T)? keyOf,
  }) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final value in values)
          ChoiceChip(
            key: keyOf == null ? null : Key(keyOf(value)),
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
            helperText:
                '${formatMm(minEyeletStepMm)}…'
                '${formatMm(maxEyeletStepMm)} ${unitSuffix()}; рекомендовано '
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
          'Задан ${formatMm(value)} ${unitSuffix()} → фактически '
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
      key: Key('${field.name}-field'),
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
        '${formatMm(spec.filmVisibleWidth)} × ${formatMm(spec.filmVisibleHeight)} ${unitSuffix()}',
      ),
      (
        params.isScreen
            ? 'Заготовка: готовый размер + половины подворотов, к высоте +20 мм '
                  '${params.hemBySideShortLabel}'
                  '${params.hasAllowance ? ' и припуск' : ''}'
            : 'Заготовка с запайкой ${formatMm(params.weldOverlapMm)} ${unitSuffix()}'
                  '${params.hasManualAllowance ? ' и припуском' : ''}'
                  '${params.hasAutoHeightAllowance ? ' и авто +'
                            '${formatMm(params.autoHeightAllowanceMm)} ${unitSuffix()} к высоте' : ''}',
        '${formatMm(spec.filmCutWidthWithAllowance)} × '
            '${formatMm(spec.filmCutHeightWithAllowance)} ${unitSuffix()}',
      ),
      // Молния сужает ширину заготовки у всех материалов. Строка стоит
      // отдельно, чтобы человек видел, почему ширина не равна «готовый
      // размер + 2 × подворот» (или «видимый размер + 2 × запайка»).
      if (spec.zipperBandTotalMm > 0)
        (
          'Минус полоса молнии на ширину кроя '
              '(${spec.params.zippers.length} шт)',
          '−${formatMm(spec.zipperBandTotalMm)} ${unitSuffix()}: '
              '${formatMm(spec.filmCutWidthBeforeZipper)}'
              ' → ${formatMm(spec.filmCutWidth)} ${unitSuffix()} до припуска',
        ),
      if (!params.isScreen)
        params.hasShrinkage
            ? (
                'С усадкой ${formatPercent(params.effectiveShrinkagePercent)}',
                '${formatMm(spec.filmCutWidthWithShrinkage)} × '
                    '${formatMm(spec.filmCutHeightWithShrinkage)} ${unitSuffix()}',
              )
            : ('Усадка', 'не учитывается')
      else
        ('Усадка', 'нет'),
      // Габарит заготовки и площадь полотна — разные числа: у трапеции
      // заготовка кроится прямоугольником и больше полотна.
      (
        'Площадь заготовки по контуру без усадки',
        '${formatMeters(spec.filmCutAreaM2)} м²',
      ),
      (
        'Площадь заготовки по контуру с усадкой',
        '${formatMeters(spec.filmCutAreaWithShrinkageM2)} м²',
      ),
      (
        'Площадь полотна изделия (без припуска)',
        '${formatMeters(spec.filmAreaM2)} м²',
      ),
      if (params.isScreen)
        (
          'Подворот и шов ${formatMm(screenSeamMm)} ${unitSuffix()} по сторонам '
              '(низ/право/верх/лево)',
          params.hemBySideShortLabel,
        ),
      for (final label in spec.edgeConsumptionLabels)
        ('Окантовка ${label.split(' — ').first}', label.split(' — ').last),
      ('Люверсов', '${spec.eyeletCount} шт, ${spec.eyeletStepLabel}'),
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
                  Flexible(
                    child: Text(
                      row.$2,
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF16324F),
                      ),
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
