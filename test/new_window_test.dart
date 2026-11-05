import 'package:flutter_test/flutter_test.dart';

import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';

void main() {
  test('Создать окно добавляет стандарт 1500 × 2500', () {
    const project = OrderProject(
      windows: [
        WindowParams(
          bottomWidth: 900,
          topWidth: 900,
          leftHeight: 1800,
          rightHeight: 1800,
        ),
      ],
    );
    final next = project.addWindow();
    expect(next.windowCount, 2);
    expect(next.selected.bottomWidth, 1500);
    expect(next.selected.topWidth, 1500);
    expect(next.selected.leftHeight, 2500);
    expect(next.selected.rightHeight, 2500);
  });

  test('Дублировать копирует предыдущее выбранное окно', () {
    const project = OrderProject(
      windows: [
        WindowParams(
          bottomWidth: 900,
          topWidth: 900,
          leftHeight: 1800,
          rightHeight: 1800,
        ),
        WindowParams(
          bottomWidth: 1200,
          topWidth: 1200,
          leftHeight: 2200,
          rightHeight: 2200,
        ),
      ],
      selectedIndex: 1,
    );
    final next = project.duplicateSelected();
    expect(next.windowCount, 3);
    expect(next.selected.bottomWidth, 1200);
    expect(next.selectedIndex, 2);
  });
}
