import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';

/// Окно «Что печатать»: галочки по листам заказа.
///
/// По умолчанию отмечен текущий лист, поэтому привычная печать одного листа
/// остаётся в один клик. Возвращает выбранные листы в порядке вкладок либо
/// null, если пользователь закрыл окно или нажал «Отмена».
Future<List<SheetTab>?> showPrintSheetDialog(
  BuildContext context, {
  required SheetTab current,
  required bool isMultiWindow,
}) {
  return showDialog<List<SheetTab>>(
    context: context,
    builder: (context) => _PrintSheetDialog(
      current: current,
      isMultiWindow: isMultiWindow,
    ),
  );
}

/// Название листа — как на вкладке.
String _tabTitle(SheetTab tab) => switch (tab) {
      SheetTab.drawing => 'Чертёж',
      SheetTab.cut => 'Раскрой',
      SheetTab.roll => 'Раскладка на рулоне',
      SheetTab.costs => 'Расходы',
      SheetTab.estimate => 'Смета',
      SheetTab.techCard => 'Техкарта',
    };

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
  const _PrintSheetDialog({required this.current, required this.isMultiWindow});

  final SheetTab current;
  final bool isMultiWindow;

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
      title: Text(_tabTitle(tab), style: const TextStyle(fontSize: 13.5)),
      subtitle: Text(
        _tabHint(tab, widget.isMultiWindow),
        style: const TextStyle(fontSize: 11, color: Color(0xFF66748A)),
      ),
    );
  }
}
