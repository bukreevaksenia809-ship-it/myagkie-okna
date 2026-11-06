// Единицы отображения линейных размеров: миллиметры или сантиметры.
//
// ВАЖНО: модель, JSON, раскладка, раскрой и все расчёты остаются в
// миллиметрах. Переключатель меняет и показ, и ввод: в сантиметрах поле
// принимает сантиметры и переводит их в миллиметры (266,6 → 2666 мм),
// поэтому точность модели остаётся миллиметровой.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Единица показа линейных размеров.
enum LengthUnit {
  mm('мм'),
  cm('см');

  const LengthUnit(this.suffix);

  /// Подпись единицы для интерфейса: «мм» или «см».
  final String suffix;

  /// Единица для человека: «миллиметры» / «сантиметры».
  String get title => this == LengthUnit.mm ? 'Миллиметры' : 'Сантиметры';
}

/// Глобальная настройка единиц и форматирование чисел.
class DisplayUnits {
  DisplayUnits._();

  /// Ключ в shared_preferences.
  static const String storageKey = 'length_unit';

  /// Текущая единица. Слушатель перерисовывает панель и листы.
  static final ValueNotifier<LengthUnit> current = ValueNotifier<LengthUnit>(
    LengthUnit.mm,
  );

  /// Текущая единица.
  static LengthUnit get unit => current.value;

  /// Подпись текущей единицы: «мм» или «см».
  static String get suffix => unit.suffix;

  /// Читает сохранённую единицу при запуске. Ошибка хранилища не мешает
  /// приложению: остаётся миллиметр по умолчанию.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      final parsed = switch (saved) {
        'cm' => LengthUnit.cm,
        'mm' => LengthUnit.mm,
        _ => LengthUnit.mm,
      };
      current.value = parsed;
    } catch (_) {
      current.value = LengthUnit.mm;
    }
  }

  /// Меняет единицу и сохраняет её. Слушатели перерисовывают интерфейс.
  static Future<void> setUnit(LengthUnit unit) async {
    if (current.value != unit) current.value = unit;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(storageKey, unit.name);
    } catch (_) {
      // Без хранилища переключатель всё равно работает до перезапуска.
    }
  }

  /// Сбрасывает единицу в мм (для тестов).
  @visibleForTesting
  static void resetForTest() {
    current.value = LengthUnit.mm;
  }

  /// Число в текущей единице без подписи.
  ///
  /// В миллиметрах по умолчанию 0 знаков после запятой (как раньше), в
  /// сантиметрах — один знак только при дробной части: 2 080 мм → «208»,
  /// 278,6 мм → «27,9».
  static String formatNumber(
    num millimeters, {
    int decimals = 0,
    LengthUnit? inUnit,
  }) {
    final value = millimeters.toDouble();
    if (!value.isFinite) return '—';
    final unit = inUnit ?? current.value;
    final digits = unit == LengthUnit.cm ? 1 : decimals;
    var text = formatDecimal(
      unit == LengthUnit.cm ? value / 10 : value,
      decimals: digits,
    );
    // 208,0 см → 208 см: целое без хвостового нуля.
    if (unit == LengthUnit.cm && text.endsWith(',0')) {
      text = text.substring(0, text.length - 2);
    }
    return text;
  }
}

/// Число с запятой и неразрывными пробелами между тысячами.
///
/// Отдельная функция нужна форматтерам, которые показывают уже готовую
/// единицу: например, площадь всегда в м² и от переключателя не зависит.
String formatDecimal(num value, {int decimals = 0}) {
  if (!value.isFinite) return '—';
  final text = value.toDouble().toStringAsFixed(decimals);
  final negative = text.startsWith('-');
  final body = negative ? text.substring(1) : text;
  final parts = body.split('.');
  final grouped = _groupThousands(parts.first);
  final fraction = parts.length > 1 ? ',${parts[1]}' : '';
  return '${negative ? '−' : ''}$grouped$fraction';
}

String _groupThousands(String digits) {
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('\u202F');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Подпись единицы: «мм» или «см». Без аргумента — текущая единица.
String unitSuffix([LengthUnit? unit]) => (unit ?? DisplayUnits.unit).suffix;

/// Длина в заданной единице с подписью: «2 080 мм» или «208,0 см».
///
/// Это основной форматтер для новых подписей. Старые подписи используют
/// [formatMm] (число в текущей единице) и [unitSuffix] рядом с ним.
String formatLength(num millimeters, LengthUnit unit) {
  final value = millimeters.toDouble();
  if (!value.isFinite) return '—';
  if (unit == LengthUnit.cm) {
    var text = formatDecimal(value / 10, decimals: 1);
    if (text.endsWith(',0')) text = text.substring(0, text.length - 2);
    return '$text ${unit.suffix}';
  }
  // В миллиметрах дробную часть показываем, только если она есть:
  // 2 080 → «2 080 мм», 278,6 → «278,6 мм».
  final rounded = value.roundToDouble();
  final digits = (value - rounded).abs() < 0.05 ? 0 : 1;
  return '${formatDecimal(value, decimals: digits)} ${unit.suffix}';
}

/// Площадь всегда в квадратных метрах: единица длины её не меняет.
String formatArea(num squareMeters) =>
    '${formatDecimal(squareMeters, decimals: 2)} м²';
