import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/main.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/widgets/params_panel.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets('экран конструктора: панель, лист и переключение вкладок', (
    WidgetTester tester,
  ) async {
    // Высокое окно, чтобы вся панель параметров была построена без прокрутки.
    // Панель выросла (тумблеры усадки и авто-припуска +10 мм), поэтому
    // берём запас по высоте.
    tester.view.physicalSize = const Size(1700, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('four-sizes-toggle')));
    await tester.pumpAndSettle();

    // Панель параметров и список окон заказа.
    expect(
      find.text('Мягкие окна — чертежи, раскрой, раскладка'),
      findsOneWidget,
    );
    expect(find.text('Ширина низ'), findsOneWidget);
    expect(find.text('Ширина верх'), findsOneWidget);
    expect(find.text('Создать окно'), findsOneWidget);
    expect(find.text('Глухое'), findsWidgets);
    expect(find.text('Подъёмное'), findsWidgets);

    // Комбинированного типа больше нет: молния и фартук — отдельные кнопки.
    expect(find.text('Комбинированное'), findsNothing);

    // Молния и фартук — отдельные кнопки-пресеты.
    expect(find.text('Добавить молнию'), findsOneWidget);
    // Фартук убран в «Дополнительно».
    expect(find.text('Добавить фартук'), findsNothing);

    // Раздел «Материал окна»: ПВХ с видами и скрин.
    expect(find.text('ПВХ'), findsWidgets);
    expect(find.text('Скрин'), findsWidgets);
    expect(find.text('Прозрачное'), findsWidgets);
    expect(find.text('Тонированное'), findsWidgets);
    expect(find.text('Москитная сетка'), findsWidgets);

    // Режимы листа.
    expect(find.text('Одно окно'), findsOneWidget);
    expect(find.text('Все окна'), findsOneWidget);

    // Номер окна подписан на листе.
    expect(find.textContaining('Окно №1'), findsWidgets);

    // Раздел сохранённых заказов — внизу панели: прокручиваем к нему.
    await tester.scrollUntilVisible(
      find.text('СОХРАНЁННЫЕ ЗАКАЗЫ (ФАЙЛЫ)'),
      800,
      scrollable: find
          .descendant(
            of: find.byType(ParamsPanel),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(find.text('СОХРАНЁННЫЕ ЗАКАЗЫ (ФАЙЛЫ)'), findsOneWidget);
    expect(find.text('Сохранить заказ'), findsOneWidget);

    // Вкладка расходов.
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ведомость расхода материалов'), findsOneWidget);
    expect(find.text('ИТОГИ ПО ЗАКАЗУ'), findsOneWidget);

    // Вкладка раскладки на рулоне (вкладка уехала в конец панели).
    final rollTab = find.byIcon(Icons.view_week_outlined);
    await tester.ensureVisible(rollTab);
    await tester.tap(rollTab);
    await tester.pumpAndSettle();
    expect(find.text('РАСКЛАДКА НА РУЛОНЕ'), findsOneWidget);

    // Возврат к чертежу.
    await tester.tap(find.byIcon(Icons.architecture));
    await tester.pumpAndSettle();
    expect(find.textContaining('Окно №1'), findsWidgets);
  });

  testWidgets('панель 420: своя ширина окантовки вводится руками', (
    WidgetTester tester,
  ) async {
    // Узкая панель (420) и высокое окно: весь раздел «Окантовка» построен,
    // по ширине ничего не переполняется.
    tester.view.physicalSize = const Size(420, 9000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    var project = const OrderProject();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => ParamsPanel(
              project: project,
              issues: const [],
              onChanged: (value) => setState(() => project = value),
              onReset: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // По полю на каждую сторону и по пять ГОТОВЫХ пресетов в каждой:
    // 40/50/60/100/120 мм (рулоны 80/100/120/200/240).
    expect(find.text('Готовая ширина, мм'), findsNWidgets(4));
    for (final finished in [40, 50, 60, 100, 120]) {
      expect(find.text('$finished мм'), findsAtLeastNWidgets(4));
    }

    // Первое поле — низ: готовая 75 мм = рулон 150 мм уходит в модель.
    final bottomField = find
        .ancestor(
          of: find.text('Готовая ширина, мм').first,
          matching: find.byType(TextField),
        )
        .first;
    await tester.enterText(bottomField, '75');
    await tester.pumpAndSettle();

    expect(project.selected.rollBottom, 150);
    expect(tester.takeException(), isNull);
  });
}
