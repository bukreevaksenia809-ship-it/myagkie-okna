// Настройка размеров подписей на листах.
//
// Заказчик: «нужно добавить настройку регулирования размеров всех подписей
// (для каждой отдельно)». Восемь типов подписей задаются в пунктах (pt) и
// хранятся в shared_preferences. Значение по умолчанию — то, что было на
// листах до этой настройки, поэтому старые заказы выглядят как раньше.
//
// ВАЖНО: модель, геометрия и расчёты от кегля не зависят. Настройка меняет
// только отрисовку подписей — пейнтеры берут готовый размер из [LabelSettings]
// и перерисовываются, когда он меняется.
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Тип подписи, размер которого настраивается отдельно.
enum LabelKind {
  /// Размерные цепочки чертежа: «Ширина низ 2 000», «Высота лево 2 520».
  dimensionChain('Размерные цепочки чертежа', 8.25),

  /// Подписи сторон окна: «низ», «верх», «лево», «право», кромка.
  sideLabel('Подписи сторон (низ/верх/лево/право)', 8.25),

  /// Накопительная цепочка расстояний между креплениями.
  fastenerChain('Расстояния между креплениями', 7.5),

  /// Подписи окантовки, подворота и запайки.
  edgeLabel('Подписи окантовки и подворота', 8.25),

  /// Легенда (условные обозначения) на боковой панели листа.
  legend('Легенда', 8.6),

  /// Примечания под чертежом и на боковой панели.
  notes('Примечания', 7.9),

  /// Штамп листа.
  stamp('Штамп', 9.4),

  /// Подписи на листе «Раскрой».
  cutSheet('Подписи на листе «Раскрой»', 7.9);

  const LabelKind(this.label, this.defaultPt);

  /// Подпись для диалога настроек.
  final String label;

  /// Размер по умолчанию, pt: ровно прежние кегли листов.
  final double defaultPt;

  /// Ключ shared_preferences для этого типа подписи.
  String get storageKey => 'label_size_$name';
}

/// Размеры подписей всех восьми типов.
@immutable
class LabelSettings {
  const LabelSettings(this._sizes);

  /// Значения по умолчанию — прежние кегли листов.
  factory LabelSettings.defaults() => LabelSettings({
    for (final kind in LabelKind.values) kind: kind.defaultPt,
  });

  /// Минимальный размер в диалоге, pt.
  static const double minPt = 5;

  /// Максимальный размер в диалоге, pt.
  static const double maxPt = 24;

  final Map<LabelKind, double> _sizes;

  /// Размер подписи в пунктах.
  double ptFor(LabelKind kind) => _sizes[kind] ?? kind.defaultPt;

  /// Размер подписи в точках листа 96 dpi (1 pt = 4/3 px).
  double pxFor(LabelKind kind) => ptFor(kind) / 0.75;

  /// Новые размеры с изменённым значением одного типа.
  LabelSettings withSize(LabelKind kind, double pt) {
    final clamped = pt.isFinite
        ? pt.clamp(minPt, maxPt).toDouble()
        : kind.defaultPt;
    return LabelSettings({..._sizes, kind: clamped});
  }

  /// Все значения — стандартные?
  bool get isDefault => LabelKind.values.every(
    (kind) => (ptFor(kind) - kind.defaultPt).abs() < 0.001,
  );

  /// Текущая настройка. Слушатели перерисовывают листы при изменении.
  static final ValueNotifier<LabelSettings> current =
      ValueNotifier<LabelSettings>(LabelSettings.defaults());

  /// Текущая настройка для удобства чтения.
  static LabelSettings get value => current.value;

  /// Читает сохранённые размеры при запуске.
  ///
  /// Ошибка хранилища не мешает приложению: остаются значения по умолчанию.
  static Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sizes = <LabelKind, double>{};
      for (final kind in LabelKind.values) {
        final saved = prefs.getDouble(kind.storageKey);
        sizes[kind] = (saved != null && saved.isFinite)
            ? saved.clamp(minPt, maxPt).toDouble()
            : kind.defaultPt;
      }
      current.value = LabelSettings(sizes);
    } catch (_) {
      current.value = LabelSettings.defaults();
    }
  }

  /// Меняет размер одной подписи и сохраняет его.
  static Future<void> setSize(LabelKind kind, double pt) async {
    final next = current.value.withSize(kind, pt);
    current.value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(kind.storageKey, next.ptFor(kind));
    } catch (_) {
      // Без хранилища настройка всё равно работает до перезапуска.
    }
  }

  /// Возвращает все размеры к стандартным и сохраняет их.
  static Future<void> resetToDefaults() async {
    current.value = LabelSettings.defaults();
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final kind in LabelKind.values) {
        await prefs.remove(kind.storageKey);
      }
    } catch (_) {
      // Без хранилища сброс всё равно работает до перезапуска.
    }
  }

  /// Сбрасывает настройку в памяти (для тестов).
  @visibleForTesting
  static void resetForTest() {
    current.value = LabelSettings.defaults();
  }

  @override
  bool operator ==(Object other) =>
      other is LabelSettings &&
      LabelKind.values.every(
        (kind) => (ptFor(kind) - other.ptFor(kind)).abs() < 0.0001,
      );

  @override
  int get hashCode => Object.hashAll([
    for (final kind in LabelKind.values) ptFor(kind).toStringAsFixed(3),
  ]);

  @override
  String toString() =>
      'LabelSettings(${LabelKind.values.map((kind) => '${kind.name}: '
          '${ptFor(kind)}').join(', ')})';
}
