// Водяной знак на PDF-документах приложения.
//
// Глобальный рубильник и текст хранятся в shared_preferences. Сам знак
// рисуется поверх готовой страницы PDF: диагональная серая надпись с
// прозрачностью, по одной на каждой странице. Настройка не влияет ни на
// модель заказа, ни на вёрстку листов — только на экспорт и печать PDF.
//
// ВАЖНО: знак накладывается при сборке PDF, а не при снимке листа. Поэтому
// он попадает и на листы-картинки (чертёж, таблицы, документы заказа), и на
// векторные страницы отчёта клиенту, но не портит предпросмотр на экране.
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:shared_preferences/shared_preferences.dart';

/// Глобальные настройки водяного знака.
///
/// Два [ValueNotifier] вместо одного объекта: интерфейсу достаточно слушать
/// только тот переключатель, который он показывает, а генераторы PDF читают
/// готовые [enabled] и [text] без подписки.
class WatermarkSettings {
  WatermarkSettings._();

  /// Ключ shared_preferences: включён ли водяной знак.
  static const String enabledKey = 'watermark_enabled';

  /// Ключ shared_preferences: текст водяного знака.
  static const String textKey = 'watermark_text';

  /// По умолчанию знак выключен: прежние PDF выглядят как раньше.
  static const bool defaultEnabled = false;

  /// Текст по умолчанию.
  static const String defaultText = 'Мягкие окна Excl';

  /// Включён ли водяной знак. Слушатель перерисовывает настройки.
  static final ValueNotifier<bool> enabled = ValueNotifier<bool>(
    defaultEnabled,
  );

  /// Текст водяного знака. Слушатель перерисовывает настройки.
  static final ValueNotifier<String> text = ValueNotifier<String>(defaultText);

  /// Нужно ли рисовать знак: включён и текст не пустой.
  static bool get isEnabled => enabled.value && text.value.trim().isNotEmpty;

  /// Читает сохранённые настройки при запуске.
  ///
  /// Ошибка хранилища не мешает приложению: остаются значения по умолчанию.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      enabled.value = prefs.getBool(enabledKey) ?? defaultEnabled;
      final saved = prefs.getString(textKey);
      text.value = (saved == null || saved.trim().isEmpty)
          ? defaultText
          : saved.trim();
    } catch (_) {
      enabled.value = defaultEnabled;
      text.value = defaultText;
    }
  }

  /// Сохраняет настройки. Переданные значения сначала применяются в памяти,
  /// затем пишутся в shared_preferences.
  ///
  /// Без аргументов сохраняет текущие значения — так удобно вызывать после
  /// прямого изменения [enabled] или [text] в интерфейсе.
  static Future<void> save({bool? enabled, String? text}) async {
    if (enabled != null) WatermarkSettings.enabled.value = enabled;
    if (text != null) {
      final trimmed = text.trim();
      WatermarkSettings.text.value = trimmed.isEmpty ? defaultText : trimmed;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, WatermarkSettings.enabled.value);
      await prefs.setString(textKey, WatermarkSettings.text.value);
    } catch (_) {
      // Без хранилища настройка всё равно работает до перезапуска.
    }
  }

  /// Включает/выключает знак и сохраняет настройку.
  static Future<void> setEnabled(bool value) => save(enabled: value);

  /// Меняет текст знака и сохраняет настройку. Пустой текст заменяется
  /// значением по умолчанию: включённый знак не должен быть невидимым.
  static Future<void> setText(String value) => save(text: value);

  /// Сбрасывает настройки в памяти (для тестов).
  @visibleForTesting
  static void resetForTest() {
    enabled.value = defaultEnabled;
    text.value = defaultText;
  }
}

/// Наложение водяного знака на страницы PDF.
///
/// Знак — отдельный слой [pw.Stack] поверх содержимого страницы, поэтому
/// существующая вёрстка не пересчитывается: обёртка получает те же
/// ограничения, что и исходный `build` страницы.
class PdfWatermark {
  PdfWatermark._();

  /// Шрифт с кириллицей. PT Sans уже лежит в assets для листов и отчёта,
  /// поэтому новых зависимостей и файлов не нужно.
  static const String fontAsset = 'assets/fonts/PTSans-Regular.ttf';

  /// Байты шрифта кэшируются: [pw.Font] привязывается к документу PDF, а
  /// держать его между сборками нельзя — иначе последний документ (с
  /// картинками страниц) останется в памяти до следующего экспорта.
  static ByteData? _fontData;
  static bool _fontLoadAttempted = false;

  /// Цвет знака: серый, прозрачность задаёт [pw.Opacity].
  static const PdfColor color = PdfColorGrey(0.25);

  /// Прозрачность знака: заметно на бумаге, но не мешает читать содержимое.
  static const double opacity = 0.16;

  /// Загружает шрифт для знака и отдаёт новый [pw.Font] для одной сборки PDF.
  ///
  /// Возвращает null, если ассет недоступен: тогда PDF соберётся без знака,
  /// а не упадёт. Вызывать до `document.save()`, потому что `build` страниц
  /// выполняется синхронно внутри сохранения.
  static Future<pw.Font?> loadFont() async {
    final data = await _loadFontData();
    return data == null ? null : pw.Font.ttf(data);
  }

  static Future<ByteData?> _loadFontData() async {
    if (_fontData != null) return _fontData;
    if (_fontLoadAttempted) return null;
    _fontLoadAttempted = true;
    try {
      _fontData = await rootBundle.load(fontAsset);
    } catch (_) {
      _fontData = null;
    }
    return _fontData;
  }

  /// Оборачивает содержимое страницы PDF слоем водяного знака.
  ///
  /// [font] нужен для кириллицы: встроенный Helvetica её не содержит.
  /// Без шрифта возвращается исходное содержимое — генерация PDF не ломается.
  /// true, если последний [apply] реально наложил знак (для тестов).
  static bool lastApplied = false;

  static pw.Widget apply(
    pw.Context context,
    pw.Widget content, {
    pw.Font? font,
  }) {
    lastApplied = false;
    if (!WatermarkSettings.isEnabled) return content;
    final resolvedFont = font ?? _themeFont(context);
    if (resolvedFont == null) return content;
    lastApplied = true;
    return pw.Stack(
      // Знак может чуть выходить за поля страницы — это нормально, а вот
      // обрезать его по границе содержимого не нужно.
      overflow: pw.Overflow.visible,
      children: [
        content,
        pw.Positioned.fill(
          child: _WatermarkLayer(
            text: WatermarkSettings.text.value.trim(),
            font: resolvedFont,
          ),
        ),
      ],
    );
  }

  /// Шрифт документа по умолчанию — запасной вариант для векторных страниц,
  /// где генератор уже передал свой шрифт в тему.
  static pw.Font? _themeFont(pw.Context context) {
    try {
      return pw.Theme.of(context).defaultTextStyle.font;
    } catch (_) {
      return null;
    }
  }

  /// Сбрасывает кэш шрифта (для тестов).
  @visibleForTesting
  static void resetForTest() {
    _fontData = null;
    _fontLoadAttempted = false;
    lastApplied = false;
  }
}

/// Слой с одной диагональной надписью по центру страницы.
class _WatermarkLayer extends pw.StatelessWidget {
  _WatermarkLayer({required this.text, required this.font});

  final String text;
  final pw.Font font;

  @override
  pw.Widget build(pw.Context context) {
    // Размеры страницы знает только layout, поэтому кегль подбираем здесь:
    // короткая надпись занимает ~12 % короткой стороны, длинная ужимается,
    // чтобы не вылезти за диагональ.
    return pw.LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints?.maxWidth;
        final maxHeight = constraints?.maxHeight;
        final width = maxWidth != null && maxWidth.isFinite ? maxWidth : 595.0;
        final height = maxHeight != null && maxHeight.isFinite
            ? maxHeight
            : 842.0;
        final diagonal = math.sqrt(width * width + height * height);
        final base = math.min(width, height) * 0.12;
        final fit = diagonal * 0.72 / (math.max(text.length, 1) * 0.55);
        final fontSize = math.min(base, fit).clamp(10.0, 96.0).toDouble();

        return pw.Center(
          child: pw.Transform.rotate(
            // +45°: надпись идёт снизу слева вверх направо.
            angle: math.pi / 4,
            child: pw.Opacity(
              opacity: PdfWatermark.opacity,
              child: pw.Text(
                text,
                maxLines: 1,
                style: pw.TextStyle(
                  font: font,
                  fontSize: fontSize,
                  color: PdfWatermark.color,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
