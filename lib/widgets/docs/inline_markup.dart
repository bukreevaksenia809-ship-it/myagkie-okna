// Inline-разметка документов: **жирный**, *курсив*, __подчёркивание__.
//
// Редактор хранит текст с маркерами (это простой и надёжный формат для JSON),
// а предпросмотр и A4-страница показывают уже оформленные фрагменты. Для
// TextField есть вариант [editingSpans]: маркеры остаются в строке, чтобы
// курсор и выделение не «съезжали», но подсвечиваются серым.
import 'package:flutter/material.dart';

/// Разбирает разметку и возвращает оформленные фрагменты без маркеров.
List<TextSpan> inlineSpans(String text, {TextStyle? base}) {
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  var bold = false;
  var italic = false;
  var underline = false;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: base?.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
          fontStyle: italic ? FontStyle.italic : null,
          decoration: underline ? TextDecoration.underline : null,
        ),
      ),
    );
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    if (text.startsWith('**', i)) {
      flush();
      bold = !bold;
      i += 2;
      continue;
    }
    if (text.startsWith('__', i)) {
      flush();
      underline = !underline;
      i += 2;
      continue;
    }
    if (text[i] == '*') {
      flush();
      italic = !italic;
      i += 1;
      continue;
    }
    buffer.write(text[i]);
    i += 1;
  }
  flush();
  return spans;
}

/// Фрагменты для редактируемого поля: маркеры остаются, но приглушены.
List<TextSpan> editingSpans(String text, {TextStyle? base}) {
  final markerStyle = (base ?? const TextStyle()).copyWith(
    color: const Color(0x55000000),
  );
  final spans = <TextSpan>[];
  final buffer = StringBuffer();
  var bold = false;
  var italic = false;
  var underline = false;

  void flush() {
    if (buffer.isEmpty) return;
    spans.add(
      TextSpan(
        text: buffer.toString(),
        style: base?.copyWith(
          fontWeight: bold ? FontWeight.w700 : null,
          fontStyle: italic ? FontStyle.italic : null,
          decoration: underline ? TextDecoration.underline : null,
        ),
      ),
    );
    buffer.clear();
  }

  var i = 0;
  while (i < text.length) {
    if (text.startsWith('**', i)) {
      flush();
      spans.add(TextSpan(text: '**', style: markerStyle));
      bold = !bold;
      i += 2;
      continue;
    }
    if (text.startsWith('__', i)) {
      flush();
      spans.add(TextSpan(text: '__', style: markerStyle));
      underline = !underline;
      i += 2;
      continue;
    }
    if (text[i] == '*') {
      flush();
      spans.add(TextSpan(text: '*', style: markerStyle));
      italic = !italic;
      i += 1;
      continue;
    }
    buffer.write(text[i]);
    i += 1;
  }
  flush();
  return spans;
}

/// Убирает маркеры — для копирования текста и подписей.
String stripInlineMarkup(String text) =>
    text.replaceAll('**', '').replaceAll('__', '').replaceAll('*', '');

/// Оборачивает выделение маркером и возвращает новое значение поля.
///
/// Если выделения нет, вставляется пара маркеров, а курсор встаёт между ними.
TextEditingValue wrapSelection(
  TextEditingValue value,
  String marker,
) {
  final text = value.text;
  var selection = value.selection;
  if (!selection.isValid) {
    selection = TextSelection.collapsed(offset: text.length);
  }
  final start = selection.start.clamp(0, text.length);
  final end = selection.end.clamp(start, text.length);
  final selected = text.substring(start, end);
  if (selected.isEmpty) {
    final next = text.replaceRange(start, end, '$marker$marker');
    return TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + marker.length),
    );
  }
  final replacement = '$marker$selected$marker';
  return TextEditingValue(
    text: text.replaceRange(start, end, replacement),
    selection: TextSelection.collapsed(offset: start + replacement.length),
  );
}

/// Контроллер поля с оформлением inline-разметки.
class MarkupEditingController extends TextEditingController {
  MarkupEditingController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (withComposing && value.isComposingRangeValid) {
      return super.buildTextSpan(
        context: context,
        style: style,
        withComposing: withComposing,
      );
    }
    return TextSpan(
      style: style,
      children: editingSpans(text, base: style),
    );
  }
}
