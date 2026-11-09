import 'window_params.dart';

/// Что показывать на листе чертежа.
enum SheetMode {
  /// Подробно только выбранное окно.
  single,

  /// Все окна заказа сеткой.
  grid;

  String get label => switch (this) {
    SheetMode.single => 'Одно окно',
    SheetMode.grid => 'Все окна',
  };
}

/// Заказ: одно или несколько окон, параметры раскладки на рулоне, вид листа.
/// Статус заказа в производстве.
enum OrderStatus {
  newOrder('Новый'),
  measured('Замерен'),
  production('В производстве'),
  ready('Готов'),
  installed('Смонтирован'),
  cancelled('Отменён');

  const OrderStatus(this.label);

  final String label;

  static OrderStatus fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => OrderStatus.newOrder,
  );
}

class OrderProject {
  const OrderProject({
    this.windows = const [WindowParams()],
    this.selectedIndex = 0,
    this.rollWidths = const {},
    this.rollGap = 20,
    this.options = const DrawingOptions(),
    this.sheetMode = SheetMode.single,
    // 0 — «Авто, окон в ряду»: для 2–4 окон программа сама перебирает
    // раскладки с поворотом и выбирает самую крупную.
    this.gridColumns = 0,
    this.extraQuantities = const {},
    this.status = OrderStatus.newOrder,
    this.statusChangedAt,
    this.deadline,
    this.estimateMarkupPercent,
    this.estimateDiscountPercent,
    this.estimateEdits = const {},
    this.manualEstimateLines = const [],
  });

  /// Окна заказа. Номер окна — его позиция в списке (нумерация с единицы).
  final List<WindowParams> windows;

  final int selectedIndex;

  /// Выбранная ширина рулона по каждому материалу, мм.
  /// Пустая карта — берётся ширина по умолчанию для материала.
  final Map<FilmMaterial, double> rollWidths;

  /// Зазор между заготовками при раскладке, мм.
  final double rollGap;

  final DrawingOptions options;

  /// Вид листа: одно окно подробно или все окна сеткой.
  final SheetMode sheetMode;

  /// Сколько окон в ряду на листе «все окна» (0 — подобрать автоматически).
  final int gridColumns;

  /// Количество дополнительных позиций прайса: доставка, парус, навес,
  /// брус, декоративный брус, zip. Ключи — [PriceList.extraItemKeys].
  final Map<String, double> extraQuantities;

  /// Статус заказа: от нового замера до монтажа.
  final OrderStatus status;

  /// Когда статус изменён — для напоминаний и контроля сроков.
  final DateTime? statusChangedAt;

  /// Срок сдачи заказа (для ежедневника и предупреждений).
  final DateTime? deadline;

  /// Ручная наценка/скидка только для этого заказа. null — из прайса.
  final double? estimateMarkupPercent;
  final double? estimateDiscountPercent;

  /// Правки строк автосметы по индексу.
  final Map<int, EstimateLineEdit> estimateEdits;

  /// Ручные строки, добавленные в смету.
  final List<ManualEstimateLine> manualEstimateLines;

  int get windowCount => windows.length;

  bool get isMultiWindow => windows.length > 1;

  WindowParams get selected =>
      windows[selectedIndex.clamp(0, windows.length - 1)];

  /// Материалы, которые встречаются в заказе (в порядке появления).
  List<FilmMaterial> get materialsInOrder {
    final result = <FilmMaterial>[];
    for (final window in windows) {
      if (!result.contains(window.material)) result.add(window.material);
    }
    return result;
  }

  /// Ширина рулона для материала: выбранная или по умолчанию.
  double rollWidthFor(FilmMaterial material) {
    final selectedWidth = rollWidths[material];
    if (selectedWidth != null && material.rollWidths.contains(selectedWidth)) {
      return selectedWidth;
    }
    return material.defaultRollWidth;
  }

  /// Подпись окна на чертеже: номер обязателен.
  String labelFor(int index) => 'Окно №${index + 1}';

  OrderProject copyWith({
    List<WindowParams>? windows,
    int? selectedIndex,
    Map<FilmMaterial, double>? rollWidths,
    double? rollGap,
    DrawingOptions? options,
    SheetMode? sheetMode,
    int? gridColumns,
    Map<String, double>? extraQuantities,
    OrderStatus? status,
    DateTime? statusChangedAt,
    bool clearStatusChangedAt = false,
    DateTime? deadline,
    bool clearDeadline = false,
    double? estimateMarkupPercent,
    double? estimateDiscountPercent,
    bool clearEstimateOverrides = false,
    Map<int, EstimateLineEdit>? estimateEdits,
    List<ManualEstimateLine>? manualEstimateLines,
  }) {
    final nextWindows = windows ?? this.windows;
    final index = selectedIndex ?? this.selectedIndex;
    return OrderProject(
      windows: nextWindows,
      selectedIndex: index.clamp(0, nextWindows.length - 1),
      rollWidths: rollWidths ?? this.rollWidths,
      rollGap: rollGap ?? this.rollGap,
      options: options ?? this.options,
      sheetMode: sheetMode ?? this.sheetMode,
      gridColumns: (gridColumns ?? this.gridColumns).clamp(0, 4),
      extraQuantities: extraQuantities ?? this.extraQuantities,
      status: status ?? this.status,
      statusChangedAt: clearStatusChangedAt
          ? null
          : (statusChangedAt ?? this.statusChangedAt),
      deadline: clearDeadline ? null : (deadline ?? this.deadline),
      estimateMarkupPercent: clearEstimateOverrides
          ? null
          : (estimateMarkupPercent ?? this.estimateMarkupPercent),
      estimateDiscountPercent: clearEstimateOverrides
          ? null
          : (estimateDiscountPercent ?? this.estimateDiscountPercent),
      estimateEdits: estimateEdits ?? this.estimateEdits,
      manualEstimateLines: manualEstimateLines ?? this.manualEstimateLines,
    );
  }

  /// Добавляет окно — копию текущего (обычно окна в заказе одного размера).
  /// Дублировать выбранное окно: одинаковых окон в заказе обычно много.
  OrderProject duplicateSelected() {
    final source = windows[selectedIndex];
    final copy = source.copyWith(
      drawingNumber: '',
      projectName: source.projectName,
    );
    final next = [...windows]..insert(selectedIndex + 1, copy);
    return copyWith(windows: next, selectedIndex: selectedIndex + 1);
  }

  /// Новое окно — стандарт 1500 × 2500 мм. Остальные настройки берём
  /// с текущего окна, но тип сбрасываем на обычный, чтобы Т-окно или
  /// составное не появилось неожиданно.
  OrderProject addWindow() {
    final type = switch (selected.windowType) {
      WindowType.fixed || WindowType.lifting => selected.windowType,
      _ => WindowType.fixed,
    };
    final fresh = selected.copyWith(
      windowType: type,
      bottomWidth: 1500,
      topWidth: 1500,
      leftHeight: 2500,
      rightHeight: 2500,
      drawingNumber: '',
    );
    return copyWith(
      windows: [...windows, fresh],
      selectedIndex: windows.length,
    );
  }

  OrderProject removeSelected() {
    if (windows.length <= 1) return this;
    final next = [...windows]
      ..removeAt(selectedIndex.clamp(0, windows.length - 1));
    return copyWith(
      windows: next,
      selectedIndex: (selectedIndex - 1).clamp(0, next.length - 1),
    );
  }

  OrderProject select(int index) => copyWith(selectedIndex: index);

  OrderProject updateSelected(WindowParams params) {
    final next = [...windows];
    next[selectedIndex.clamp(0, next.length - 1)] = params;
    return copyWith(windows: next);
  }

  OrderProject updateWindow(int index, WindowParams params) {
    final next = [...windows];
    if (index < 0 || index >= next.length) return this;
    next[index] = params;
    return copyWith(windows: next);
  }

  OrderProject updateOptions(DrawingOptions options) =>
      copyWith(options: options);

  OrderProject setRollWidth(FilmMaterial material, double width) =>
      copyWith(rollWidths: {...rollWidths, material: width});

  OrderProject setRollGap(double gap) => copyWith(rollGap: gap);

  OrderProject setSheetMode(SheetMode mode) => copyWith(sheetMode: mode);

  OrderProject setGridColumns(int columns) =>
      copyWith(gridColumns: columns.clamp(0, 4));
}

/// Правка одной строки сметы поверх автоматического расчёта.
class EstimateLineEdit {
  const EstimateLineEdit({
    this.title,
    this.quantity,
    this.unitPrice,
    this.hidden = false,
  });

  final String? title;
  final double? quantity;
  final double? unitPrice;
  final bool hidden;

  EstimateLineEdit copyWith({
    String? title,
    double? quantity,
    double? unitPrice,
    bool? hidden,
  }) => EstimateLineEdit(
    title: title ?? this.title,
    quantity: quantity ?? this.quantity,
    unitPrice: unitPrice ?? this.unitPrice,
    hidden: hidden ?? this.hidden,
  );

  Map<String, dynamic> toJson() => {
    if (title != null) 'title': title,
    if (quantity != null) 'quantity': quantity,
    if (unitPrice != null) 'unitPrice': unitPrice,
    if (hidden) 'hidden': true,
  };

  static EstimateLineEdit fromJson(Object? raw) {
    if (raw is! Map) return const EstimateLineEdit();
    return EstimateLineEdit(
      title: raw['title'] is String ? raw['title'] as String : null,
      quantity: raw['quantity'] is num
          ? (raw['quantity'] as num).toDouble()
          : null,
      unitPrice: raw['unitPrice'] is num
          ? (raw['unitPrice'] as num).toDouble()
          : null,
      hidden: raw['hidden'] == true,
    );
  }
}

/// Своя строка сметы, добавленная вручную.
class ManualEstimateLine {
  const ManualEstimateLine({
    this.title = 'Новая позиция',
    this.quantity = 1,
    this.unit = 'шт',
    this.unitPrice = 0,
  });

  final String title;
  final double quantity;
  final String unit;
  final double unitPrice;

  ManualEstimateLine copyWith({
    String? title,
    double? quantity,
    String? unit,
    double? unitPrice,
  }) => ManualEstimateLine(
    title: title ?? this.title,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    unitPrice: unitPrice ?? this.unitPrice,
  );

  Map<String, dynamic> toJson() => {
    'title': title,
    'quantity': quantity,
    'unit': unit,
    'unitPrice': unitPrice,
  };

  static ManualEstimateLine fromJson(Object? raw) {
    if (raw is! Map) return const ManualEstimateLine();
    return ManualEstimateLine(
      title: raw['title'] is String ? raw['title'] as String : 'Новая позиция',
      quantity: raw['quantity'] is num
          ? (raw['quantity'] as num).toDouble()
          : 1,
      unit: raw['unit'] is String ? raw['unit'] as String : 'шт',
      unitPrice: raw['unitPrice'] is num
          ? (raw['unitPrice'] as num).toDouble()
          : 0,
    );
  }
}
