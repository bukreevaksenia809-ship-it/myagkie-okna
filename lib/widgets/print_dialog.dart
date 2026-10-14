import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../main.dart';

/// С какого числа листов предупреждаем, что в браузере это долго.
const int kWebManySheetsThreshold = 3;

/// Подсказка для браузера: много листов за раз собираются заметно медленнее.
const String kWebManySheetsHint =
    'В браузере лучше печатать не больше 3 листов за раз: '
    'остальные добавятся медленнее';

/// Нужно ли предупреждать, что листов слишком много для браузера.
///
/// [isWeb] можно задать явно (например, в тестах); по умолчанию платформа
/// определяется через [kIsWeb].
bool shouldWarnManySheets(int selectedCount, {bool? isWeb}) =>
    (isWeb ?? kIsWeb) && selectedCount > kWebManySheetsThreshold;

/// Название листа — как на вкладке.
String sheetTabTitle(SheetTab tab) => switch (tab) {
      SheetTab.drawing => 'Чертёж',
      SheetTab.cut => 'Раскрой',
      SheetTab.roll => 'Раскладка на рулоне',
      SheetTab.costs => 'Расходы',
      SheetTab.estimate => 'Смета',
      SheetTab.techCard => 'Техкарта',
    };

/// Окно «Что печатать»: галочки по листам заказа.
///
/// По умолчанию отмечен текущий лист, поэтому привычная печать одного листа
/// остаётся в один клик. Возвращает выбранные листы в порядке вкладок либо
/// null, если пользователь закрыл окно или нажал «Отмена».
///
/// [warnManySheets] — показывать ли подсказку про браузер при выборе больше
/// [kWebManySheetsThreshold] листов. По умолчанию это так в вебе; в тестах
/// и на десктопе подсказки нет. Печать при этом не запрещается.
Future<List<SheetTab>?> showPrintSheetDialog(
  BuildContext context, {
  required SheetTab current,
  required bool isMultiWindow,
  bool? warnManySheets,
}) {
  return showDialog<List<SheetTab>>(
    context: context,
    builder: (context) => _PrintSheetDialog(
      current: current,
      isMultiWindow: isMultiWindow,
      warnManySheets: warnManySheets ?? kIsWeb,
    ),
  );
}

/// Короткая подсказка: что именно попадёт на печать.
String _tabHint(SheetTab tab, bool isMultiWindow) => switch (tab) {
      SheetTab.drawing => isMultiWindow
          ? 'Чертежи всех окон заказа'
          : 'Чертёж окна (окон)',
      SheetTab.cut => 'Заготовки плёнки',
      SheetTab.roll => 'Как лягут полотна на рулоне',
      SheetTab.costs => 'Ведомость расхода',
      SheetTab.estimate => 'Стоимость по позициям заказа',
      SheetTab.techCard => 'Технологическая карта',
    };

class _PrintSheetDialog extends StatefulWidget {
  const _PrintSheetDialog({
    required this.current,
    required this.isMultiWindow,
    required this.warnManySheets,
  });

  final SheetTab current;
  final bool isMultiWindow;
  final bool warnManySheets;

  @override
  State<_PrintSheetDialog> createState() => _PrintSheetDialogState();
}

class _PrintSheetDialogState extends State<_PrintSheetDialog> {
  final Set<SheetTab> _selected = <SheetTab>{};

  @override
  void initState() {
    super.initState();
    // Текущий лист отмечен по умолчанию.
    _selected.add(widget.current);
  }

  /// Выбранные листы в порядке вкладок, а не в порядке нажатий.
  List<SheetTab> get _orderedSelection => [
        for (final tab in SheetTab.values)
          if (_selected.contains(tab)) tab,
      ];

  void _toggle(SheetTab tab, bool? checked) {
    setState(() {
      if (checked ?? false) {
        _selected.add(tab);
      } else {
        _selected.remove(tab);
      }
    });
  }

  void _toggleAll(bool? checked) {
    setState(() {
      _selected.clear();
      if (checked ?? false) _selected.addAll(SheetTab.values);
    });
  }

  @override
  Widget build(BuildContext context) {
    // 380 — желаемая ширина; на узком экране окно сжимается, чтобы
    // список не переполнялся по горизонтали.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final width = math.min(380.0, math.max(200.0, screenWidth - 96));
    final allSelected = _selected.length == SheetTab.values.length;
    final showWarning = shouldWarnManySheets(
      _selected.length,
      isWeb: widget.warnManySheets,
    );

    return AlertDialog(
      title: const Text('Что печатать', style: TextStyle(fontSize: 17)),
      titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
      contentPadding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      content: SizedBox(
        width: width,
        // На низком экране список можно прокрутить — ничего не обрезается.
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final tab in SheetTab.values) _tabTile(tab),
              const Divider(height: 1),
              CheckboxListTile(
                dense: true,
                visualDensity: VisualDensity.compact,
                controlAffinity: ListTileControlAffinity.leading,
                value: allSelected,
                onChanged: _toggleAll,
                title: const Text(
                  'Отметить все',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              if (showWarning)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 2, 16, 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.hourglass_bottom_outlined,
                        size: 15,
                        color: Color(0xFFB07A1E),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          kWebManySheetsHint,
                          style: TextStyle(
                            fontSize: 11,
                            height: 1.3,
                            color: Color(0xFF8A6A1E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Отмена'),
        ),
        FilledButton(
          // Печатать нечего — кнопка неактивна.
          onPressed: _selected.isEmpty
              ? null
              : () => Navigator.of(context).pop(_orderedSelection),
          child: const Text('Печать'),
        ),
      ],
    );
  }

  Widget _tabTile(SheetTab tab) {
    return CheckboxListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      controlAffinity: ListTileControlAffinity.leading,
      value: _selected.contains(tab),
      onChanged: (checked) => _toggle(tab, checked),
      title: Text(sheetTabTitle(tab), style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        _tabHint(tab, widget.isMultiWindow),
        style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
      ),
    );
  }
}

/// Прогресс подготовки листов к печати.
class PrintProgress {
  const PrintProgress({
    required this.current,
    required this.total,
    required this.title,
    this.pagesReady = 0,
    this.assembling = false,
  });

  /// Номер листа (с 1), который готовится сейчас.
  final int current;

  /// Сколько всего листов в задании.
  final int total;

  /// Название листа, который готовится сейчас.
  final String title;

  /// Сколько страниц PDF уже готово.
  final int pagesReady;

  /// Листы сняты, идёт сборка PDF.
  final bool assembling;

  /// Текст для окна прогресса.
  String get message => assembling
      ? 'Собираем PDF — готово страниц: $pagesReady'
      : 'Готовим лист $current из $total: $title';

  /// Доля готовых листов: текущий лист ещё в работе.
  double get fraction => total <= 0 ? 0 : ((current - 1) / total).clamp(0.0, 1.0);
}

/// Ключ завесы прогресса: по нему видно, что окно само не закрывается.
const Key printProgressBarrierKey = Key('print-progress-barrier');

/// Модальная завеса с прогрессом подготовки печати.
///
/// Показывается поверх экрана, пока снимаются листы. В браузере это занимает
/// секунды, и без видимого прогресса вкладка выглядит зависшей. Нажатия
/// завеса не пропускает и сама не закрывается — убрать её может только код,
/// который её показал.
class PrintProgressOverlay extends StatelessWidget {
  const PrintProgressOverlay({super.key, required this.progress});

  final PrintProgress progress;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const ModalBarrier(
          key: printProgressBarrierKey,
          dismissible: false,
          color: Color(0x8A000000),
        ),
        Center(
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'Подготовка печати',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: 300,
                    child: Text(
                      progress.message,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: 300,
                    child: LinearProgressIndicator(value: progress.fraction),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Страниц PDF готово: ${progress.pagesReady}',
                    style: const TextStyle(fontSize: 11.5, color: Color(0xFF66748A)),
                  ),
                  const SizedBox(height: 4),
                  const SizedBox(
                    width: 300,
                    child: Text(
                      'Не закрывайте вкладку: в браузере сборка идёт медленнее, '
                      'чем на компьютере',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.3,
                        color: Color(0xFF66748A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
