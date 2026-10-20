// Кнопка «Настройки подписей» внизу экрана рядом с единицами мм/см.
//
// Проверяем, что диалог открывается, показывает все восемь типов подписей и
// кнопка сброса возвращает стандартные размеры.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:soft_window_drawer/main.dart';
import 'package:soft_window_drawer/services/label_settings.dart';

void main() {
  testWidgets('диалог настроек подписей: восемь типов и сброс', (tester) async {
    SharedPreferences.setMockInitialValues({});
    LabelSettings.resetForTest();
    addTearDown(LabelSettings.resetForTest);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const SoftWindowApp());
    await tester.pumpAndSettle();

    final button = find.byKey(const Key('label-settings-button'));
    expect(button, findsOneWidget, reason: 'кнопка рядом с единицами мм/см');
    await tester.tap(button);
    await tester.pumpAndSettle();

    expect(find.text('Настройки подписей'), findsWidgets);
    for (final kind in LabelKind.values) {
      expect(
        find.text(kind.label),
        findsOneWidget,
        reason: 'в диалоге есть тип «${kind.label}»',
      );
    }
    expect(find.byKey(const Key('label-size-dimensionChain')), findsOneWidget);

    // Меняем один размер и убеждаемся, что он применился в памяти.
    await LabelSettings.setSize(LabelKind.notes, 20);
    await tester.pumpAndSettle();
    expect(LabelSettings.value.ptFor(LabelKind.notes), 20);
    await tester.tap(find.byKey(const Key('label-settings-reset')));
    await tester.pumpAndSettle();
    expect(LabelSettings.value.isDefault, isTrue);
    expect(
      LabelSettings.value.ptFor(LabelKind.notes),
      LabelKind.notes.defaultPt,
    );

    await tester.tap(find.text('Готово'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
