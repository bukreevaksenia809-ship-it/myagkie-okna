import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/main.dart';
import 'package:soft_window_drawer/services/pdf_export.dart';
import 'package:soft_window_drawer/widgets/print_dialog.dart';

/// Подписи листов в окне «Что печатать» — в порядке вкладок.
const _titles = <String>[
  'Чертёж',
  'Раскрой',
  'Раскладка на рулоне',
  'Расходы',
  'Смета',
  'Техкарта',
];

/// Место, куда хост-кнопка складывает ответ диалога.
class _DialogHost {
  List<SheetTab>? result;
}

void main() {
  /// Открывает окно «Что печатать» поверх простого экрана с кнопкой.
  Future<_DialogHost> openDialog(
    WidgetTester tester, {
    required SheetTab current,
    bool isMultiWindow = false,
    Size size = const Size(700, 1000),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final host = _DialogHost();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () async {
                  host.result = await showPrintSheetDialog(
                    context,
                    current: current,
                    isMultiWindow: isMultiWindow,
                  );
                },
                child: const Text('Открыть окно'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Открыть окно'));
    await tester.pumpAndSettle();
    return host;
  }

  /// Отмечен ли пункт с такой подписью.
  bool checked(WidgetTester tester, String title) {
    final tile = tester.widget<CheckboxListTile>(
      find.ancestor(
        of: find.text(title),
        matching: find.byType(CheckboxListTile),
      ),
    );
    return tile.value ?? false;
  }

  testWidgets('окно показывает все листы и отмечает текущий', (tester) async {
    await openDialog(tester, current: SheetTab.costs);

    expect(find.text('Что печатать'), findsOneWidget);
    for (final title in _titles) {
      expect(find.text(title), findsOneWidget, reason: 'нет пункта «$title»');
    }
    // Короткие подсказки: что именно попадёт на печать.
    expect(find.text('Ведомость расхода'), findsOneWidget);
    expect(find.text('Заготовки плёнки'), findsOneWidget);

    expect(checked(tester, 'Расходы'), isTrue);
    for (final title in _titles.where((title) => title != 'Расходы')) {
      expect(checked(tester, title), isFalse, reason: '«$title» не отмечен');
    }
    expect(checked(tester, 'Отметить все'), isFalse);

    expect(tester.takeException(), isNull);
  });

  testWidgets('подсказка чертежа зависит от числа окон в заказе', (tester) async {
    await openDialog(tester, current: SheetTab.drawing);
    expect(find.text('Чертёж окна (окон)'), findsOneWidget);
    expect(find.text('Чертежи всех окон заказа'), findsNothing);
  });

  testWidgets('выбор двух листов возвращает их в порядке вкладок',
      (tester) async {
    final host = await openDialog(tester, current: SheetTab.cut);
    await tester.tap(find.text('Смета'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Печать'));
    await tester.pumpAndSettle();

    expect(host.result, [SheetTab.cut, SheetTab.estimate]);
    expect(find.text('Что печатать'), findsNothing);
  });

  testWidgets('порядок листов — как на вкладках, а не как нажимали',
      (tester) async {
    final host = await openDialog(tester, current: SheetTab.techCard);
    // «Чертёж» нажат после техкарты, но на печать уходит первым.
    await tester.tap(find.text('Чертёж'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Печать'));
    await tester.pumpAndSettle();

    expect(host.result, [SheetTab.drawing, SheetTab.techCard]);
  });

  testWidgets('«Отмена» возвращает null', (tester) async {
    final host = await openDialog(tester, current: SheetTab.drawing);
    await tester.tap(find.text('Отмена'));
    await tester.pumpAndSettle();

    expect(host.result, isNull);
    expect(find.text('Что печатать'), findsNothing);
  });

  testWidgets('без галочек кнопка «Печать» неактивна', (tester) async {
    await openDialog(tester, current: SheetTab.techCard);
    // Снимаем единственную галочку — текущий лист.
    await tester.tap(find.text('Техкарта'));
    await tester.pumpAndSettle();

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Печать'),
    );
    expect(button.onPressed, isNull);

    // Нажатие по неактивной кнопке окно не закрывает.
    await tester.tap(find.text('Печать'));
    await tester.pumpAndSettle();
    expect(find.text('Что печатать'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('«Отметить все» отмечает все шесть листов', (tester) async {
    final host = await openDialog(tester, current: SheetTab.drawing);
    await tester.tap(find.text('Отметить все'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Печать'));
    await tester.pumpAndSettle();

    expect(host.result, SheetTab.values);
  });

  testWidgets('на узком экране окно не переполняется', (tester) async {
    await openDialog(
      tester,
      current: SheetTab.techCard,
      isMultiWindow: true,
      size: const Size(320, 480),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('Что печатать'), findsOneWidget);
    for (final title in _titles) {
      expect(find.text(title), findsOneWidget);
    }
    expect(find.widgetWithText(FilledButton, 'Печать'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Отмена'), findsOneWidget);

    // Окно целиком укладывается в экран: ни по ширине, ни по высоте.
    final dialog = tester.getRect(find.byType(AlertDialog));
    expect(dialog.width, lessThanOrEqualTo(320));
    expect(dialog.height, lessThanOrEqualTo(480));
    expect(tester.takeException(), isNull);
  });

  testWidgets('страницы-картинки нескольких листов собираются в один PDF',
      (tester) async {
    // Два простых PNG — как будто сняли два листа.
    final pages = await tester.runAsync(() async {
      final result = <Uint8List>[];
      for (final color in const [Color(0xFFFF0000), Color(0xFF0000FF)]) {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        canvas.drawRect(
          const Rect.fromLTWH(0, 0, 200, 100),
          Paint()..color = color,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(200, 100);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        picture.dispose();
        image.dispose();
        result.add(data!.buffer.asUint8List());
      }
      return result;
    });

    final bytes = await tester.runAsync(() => buildMultiSheetPdf(pages!));
    expect(String.fromCharCodes(bytes!.take(5)), '%PDF-');
    final text = String.fromCharCodes(bytes);
    expect(RegExp(r'/Type\s*/Page[^s]').allMatches(text).length, 2);
  });
}
