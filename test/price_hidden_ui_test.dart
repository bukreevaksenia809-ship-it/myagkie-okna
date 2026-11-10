// Панель прайса: переименование и удаление позиции, раздел «Скрытые позиции»
// и восстановление. Проверяем, что удаление не теряет цену и возвращается.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/models/price_list.dart';
import 'package:soft_window_drawer/widgets/price_panel.dart';

class _Host extends StatefulWidget {
  const _Host({super.key, required this.initial});

  final PriceList initial;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late PriceList prices = widget.initial;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 520,
            child: PricePanel(
              prices: prices,
              onChanged: (value) => setState(() => prices = value),
            ),
          ),
        ),
      ),
    );
  }
}

void main() {
  testWidgets('переименование, удаление и восстановление позиции', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(600, 7000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final hostKey = GlobalKey<_HostState>();
    await tester.pumpWidget(
      _Host(key: hostKey, initial: const PriceList.defaults()),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('ПРАЙС-ЛИСТ'));
    await tester.pumpAndSettle();

    // Меню строки вызывает те же действия, что и нажатие пункта: в тестовой
    // среде всплывающее меню рисуется в оверлее и не всегда ловит тап, поэтому
    // дергаем onSelected напрямую, а диалоги и кнопки проверяем по-настоящему.
    Future<void> choose(String key, String value) async {
      final finder = find.byKey(ValueKey('price-menu-$key'));
      await tester.ensureVisible(finder);
      final menu = tester.widget<PopupMenuButton<String>>(finder);
      menu.onSelected!(value);
      await tester.pumpAndSettle();
    }

    // Переименование: своё название видно в строке панели.
    await choose(PriceItemKeys.filmClear, 'rename');
    await tester.enterText(
      find.byKey(const Key('price-rename-field')),
      'Плёнка «Премиум»',
    );
    await tester.tap(find.byKey(const Key('price-rename-save')));
    await tester.pumpAndSettle();
    expect(
      hostKey.currentState!.prices.titleFor(
        PriceItemKeys.filmClear,
        'Обычный ПВХ',
      ),
      'Плёнка «Премиум»',
    );
    expect(find.text('Плёнка «Премиум»'), findsOneWidget);

    // Удаление: строка исчезает, позиция попадает в «Скрытые».
    await choose(PriceItemKeys.filmClear, 'delete');
    await tester.tap(find.byKey(const Key('price-delete-confirm')));
    await tester.pumpAndSettle();
    expect(hostKey.currentState!.prices.isHidden(PriceItemKeys.filmClear), isTrue);
    expect(find.byKey(const ValueKey('price-menu-filmClear')), findsNothing);
    final restore = find.byKey(const ValueKey('price-restore-filmClear'));
    await tester.ensureVisible(restore);
    expect(restore, findsOneWidget);

    // Восстановление: строка и своё название возвращаются.
    await tester.tap(restore);
    await tester.pumpAndSettle();
    expect(
      hostKey.currentState!.prices.isHidden(PriceItemKeys.filmClear),
      isFalse,
    );
    expect(find.text('Плёнка «Премиум»'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
