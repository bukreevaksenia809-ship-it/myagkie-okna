
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/main.dart';

void main() {
  testWidgets('экран конструктора: панель, лист и переключение вкладок',
      (WidgetTester tester) async {
    // Высокое окно, чтобы вся панель параметров была построена без прокрутки.
    tester.view.physicalSize = const Size(1700, 6000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();

    // Панель параметров и список окон заказа.
    expect(find.text('Мягкие окна — чертежи, раскрой, раскладка'), findsOneWidget);
    expect(find.text('Ширина низ'), findsOneWidget);
    expect(find.text('Ширина верх'), findsOneWidget);
    expect(find.text('Добавить окно'), findsOneWidget);
    expect(find.text('Глухое'), findsWidgets);
    expect(find.text('Подъёмное'), findsWidgets);

    // Комбинированного типа больше нет: молния и карман — отдельные кнопки.
    expect(find.text('Комбинированное'), findsNothing);

    // Молния и карман — отдельные кнопки-пресеты.
    expect(find.text('Добавить молнию'), findsOneWidget);
    expect(find.text('Добавить карман'), findsOneWidget);

    // Раздел «Полотно»: материалы и доступные ширины рулонов.
    expect(find.text('Обычный ПВХ'), findsWidgets);
    expect(find.text('Тонированный ПВХ'), findsWidgets);
    expect(find.text('Москитная сетка'), findsWidgets);

    // Режимы листа.
    expect(find.text('Одно окно'), findsOneWidget);
    expect(find.text('Все окна'), findsOneWidget);

    // Номер окна подписан на листе.
    expect(find.textContaining('Окно №1'), findsWidgets);

    // Раздел заказов в панели: сохранение и отчётность.
    expect(find.text('ЗАКАЗЫ (ОТЧЁТНОСТЬ)'), findsOneWidget);
    expect(find.text('Сохранить заказ'), findsOneWidget);

    // Вкладка расходов.
    await tester.tap(find.byIcon(Icons.receipt_long_outlined));
    await tester.pumpAndSettle();
    expect(find.text('Ведомость расхода материалов'), findsOneWidget);
    expect(find.text('ИТОГИ ПО ЗАКАЗУ'), findsOneWidget);

    // Вкладка раскладки на рулоне (тапаем по иконке — текст есть и в панели).
    await tester.tap(find.byIcon(Icons.view_week_outlined));
    await tester.pumpAndSettle();
    expect(find.text('РАСКЛАДКА НА РУЛОНЕ'), findsOneWidget);

    // Возврат к чертежу.
    await tester.tap(find.byIcon(Icons.architecture));
    await tester.pumpAndSettle();
    expect(find.textContaining('Окно №1'), findsWidgets);
  });
}
