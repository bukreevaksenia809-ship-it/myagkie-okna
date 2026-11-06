import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/price_list.dart';
import '../services/estimate.dart';

/// Позиция производственной себестоимости. Это те же статьи, что и в смете,
/// но с закупочной ценой за единицу (м², м или шт.).
class CostPosition {
  const CostPosition(this.key, this.label, this.unit);

  final String key;
  final String label;
  final String unit;
}

const List<CostPosition> costPositions = [
  CostPosition(PriceItemKeys.filmClear, 'Полотно прозрачное', 'м²'),
  CostPosition(PriceItemKeys.filmTinted, 'Полотно тонированное', 'м²'),
  CostPosition(PriceItemKeys.filmMesh, 'Полотно сетка', 'м²'),
  CostPosition(PriceItemKeys.filmScreen, 'Скрин', 'м²'),
  CostPosition(PriceItemKeys.edge80, 'Окантовка 80 мм', 'м'),
  CostPosition(PriceItemKeys.edge100, 'Окантовка 100 мм', 'м'),
  CostPosition(PriceItemKeys.edge120, 'Окантовка 120 мм', 'м'),
  CostPosition(PriceItemKeys.edge200, 'Окантовка 200 мм', 'м'),
  CostPosition(PriceItemKeys.edge240, 'Окантовка 240 мм', 'м'),
  CostPosition(PriceItemKeys.eyeletRound, 'Люверс круглый', 'шт'),
  CostPosition(PriceItemKeys.eyeletOval, 'Люверс овальный', 'шт'),
  CostPosition(PriceItemKeys.eyeletInstall, 'Установка люверса', 'шт'),
  CostPosition(PriceItemKeys.zipper, 'Молния', 'м'),
  CostPosition(PriceItemKeys.weld, 'Спайка', 'м'),
  CostPosition(PriceItemKeys.pocket, 'Фартук', 'м'),
  CostPosition(PriceItemKeys.strap, 'Ремень', 'шт'),
  CostPosition(PriceItemKeys.aluminumBox, 'Алюминиевый бокс', 'м'),
  CostPosition(PriceItemKeys.drain, 'Дренаж', 'шт'),
  CostPosition(PriceItemKeys.cutout, 'Вырез', 'шт'),
  CostPosition(PriceItemKeys.turnBuckle, 'Поворотная скоба', 'шт'),
  CostPosition(PriceItemKeys.frenchLock, 'Пластиковая скоба', 'шт'),
  CostPosition(PriceItemKeys.screw, 'Саморез', 'шт'),
  CostPosition(PriceItemKeys.labor, 'Работа', 'м²'),
  CostPosition(PriceItemKeys.cutting, 'Раскрой', 'м²'),
  CostPosition(PriceItemKeys.screenHem, 'Подворот скрина', 'м'),
];

/// Себестоимость позиций, заполняемая один раз при первом открытии склада.
/// Позиция может быть отключена — тогда она не участвует в расчёте.
class CostCatalog {
  CostCatalog({
    Map<String, double>? costs,
    Set<String>? disabled,
    this.configured = false,
  }) : costs = Map.unmodifiable(costs ?? const {}),
       disabled = Set.unmodifiable(disabled ?? const {});

  static final CostCatalog instance = CostCatalog();

  static const String _key = 'production_cost_catalog_v1';
  final Map<String, double> costs;
  final Set<String> disabled;
  final bool configured;

  double? costFor(String? key) {
    if (key == null || disabled.contains(key)) return null;
    final value = costs[key];
    return value != null && value > 0 ? value : null;
  }

  CostCatalog copyWith({
    Map<String, double>? costs,
    Set<String>? disabled,
    bool? configured,
  }) => CostCatalog(
    costs: costs ?? this.costs,
    disabled: disabled ?? this.disabled,
    configured: configured ?? this.configured,
  );

  Future<CostCatalog> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return this;
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return this;
      final costs = <String, double>{};
      final rawCosts = json['costs'];
      if (rawCosts is Map) {
        for (final entry in rawCosts.entries) {
          final value = entry.value;
          if (value is num && value.isFinite && value >= 0) {
            costs[entry.key.toString()] = value.toDouble();
          }
        }
      }
      final disabled = <String>{};
      final rawDisabled = json['disabled'];
      if (rawDisabled is List) {
        for (final item in rawDisabled) {
          disabled.add(item.toString());
        }
      }
      return CostCatalog(
        costs: costs,
        disabled: disabled,
        configured: json['configured'] == true,
      );
    } catch (_) {
      return this;
    }
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'costs': costs,
        'disabled': disabled.toList(),
        'configured': configured,
      }),
    );
  }

  double orderCost(Estimate estimate) {
    var total = 0.0;
    for (final line in estimate.lines) {
      final cost = costFor(line.itemKey);
      if (cost != null) total += line.quantity * cost;
    }
    return total;
  }
}
