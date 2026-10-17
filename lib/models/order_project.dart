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
class OrderProject {
  const OrderProject({
    this.windows = const [WindowParams()],
    this.selectedIndex = 0,
    this.rollWidths = const {},
    this.rollGap = 20,
    this.options = const DrawingOptions(),
    this.sheetMode = SheetMode.single,
    this.gridColumns = 2,
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

  OrderProject addWindow() => copyWith(
        windows: [...windows, selected.copyWith(drawingNumber: '')],
        selectedIndex: windows.length,
      );

  /// Добавить окно к спайке: копия выбранного окна встаёт рядом (после него)
  /// и сваривается с ним по указанной стороне.
  ///
  /// Копия повторяет шаблон целиком — размеры, материал, окантовку, молнии,
  /// вырезы, фартук; отличается только маркировка ([WindowParams.drawingNumber]
  /// очищается) и сторона спайки: у копии это [EdgeSide.opposite]. Работает
  /// для всех четырёх сторон: справа/слева и сверху/снизу. Повторный вызов с
  /// той же стороной не дублирует её в [WindowParams.weldedSides].
  OrderProject addWeldedWindow(EdgeSide side) {
    final index = selectedIndex.clamp(0, windows.length - 1);
    final source = windows[index];

    final current = source.isWelded(side)
        ? source
        : source.copyWith(weldedSides: [...source.weldedSides, side]);

    final opposite = side.opposite;
    final copyBase = source.copyWith(drawingNumber: '');
    final copy = copyBase.isWelded(opposite)
        ? copyBase
        : copyBase.copyWith(weldedSides: [...copyBase.weldedSides, opposite]);

    final next = [...windows];
    next[index] = current;
    next.insert(index + 1, copy);
    return copyWith(windows: next, selectedIndex: index + 1);
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
