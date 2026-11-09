import '../data/warehouse_repository.dart';
import '../models/order_project.dart';
import '../models/window_params.dart';
import '../models/warehouse.dart';
import '../services/estimate.dart';

/// Потребность заказа в материалах: сопоставленные строки и то, что осталось
/// без товара на складе.
class OrderNeedPlan {
  const OrderNeedPlan({
    required this.needs,
    required this.unmatched,
    required this.estimateTotal,
  });

  final List<OrderMaterialNeed> needs;
  final List<String> unmatched;
  final double estimateTotal;

  bool get hasUnmatched => unmatched.isNotEmpty;

  int get shortageCount => needs.where((need) => need.shortage > 0).length;
}

/// Связывает смету заказа с номенклатурой склада.
///
/// Сопоставление прозрачное и предсказуемое: сначала по категории и материалу
/// (полотно/окантовка/люверсы/фурнитура), затем по вхождению названия. Если
/// единицы не совпадают, количество пересчитывается через площадь/длину
/// единицы товара; если пересчёт невозможен — строка попадает в «не
/// сопоставлено», а не пропадает молча.
class OrderMaterialsService {
  OrderMaterialsService({WarehouseRepository? warehouse})
    : _warehouse = warehouse ?? WarehouseRepository.instance;

  final WarehouseRepository _warehouse;

  Future<OrderNeedPlan> plan(
    OrderProject project, {
    PriceList prices = const PriceList.defaults(),
  }) async {
    final estimate = Estimate.of(project, prices);
    final products = await _warehouse.products();
    final merged = <String, OrderMaterialNeed>{};
    final unmatched = <String>[];

    // Если в заказе один материал, смета пишет строку просто «Полотно».
    // Подсказываем сопоставлению, какой именно материал искать.
    final materialHint = project.materialsInOrder.length == 1
        ? project.materialsInOrder.first
        : null;
    // В смете есть работы (сварка, раскрой, установка). Это не материал:
    // если их не отфильтровать, площадь работ прибавляется к плёнке и
    // потребность завышается в разы.
    for (final line in estimate.lines.where(
      (line) =>
          line.group != EstimateGroup.work &&
          line.itemKey != PriceItemKeys.cutout &&
          line.quantity > 0,
    )) {
      final product = _match(
        line.title,
        line.unit,
        products,
        materialHint: materialHint,
        itemKey: line.itemKey,
        colorHint: _colorHint(project, line.itemKey),
      );
      if (product == null) {
        unmatched.add('${line.title} — ${line.quantityLabel}');
        continue;
      }
      final quantity = _convert(line.quantity, line.unit, product);
      if (quantity == null) {
        unmatched.add(
          '${line.title} — ${line.quantityLabel} (единицы не совпадают с '
          '«${product.name}», ${product.unit.label})',
        );
        continue;
      }
      final previous = merged[product.id];
      if (previous == null) {
        merged[product.id] = OrderMaterialNeed(
          productId: product.id,
          name: product.name,
          unit: product.unit,
          quantity: quantity,
          available: 0,
          reserved: 0,
          source: line.title,
          note: line.note ?? '',
        );
      } else {
        merged[product.id] = OrderMaterialNeed(
          productId: product.id,
          name: previous.name,
          unit: previous.unit,
          quantity: previous.quantity + quantity,
          available: 0,
          reserved: 0,
          source: '${previous.source}, ${line.title}',
          note: previous.note,
        );
      }
    }

    final needs = await _warehouse.checkNeeds(merged.values.toList());
    needs.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return OrderNeedPlan(
      needs: needs,
      unmatched: unmatched,
      estimateTotal: estimate.total,
    );
  }

  String? _colorHint(OrderProject project, String? itemKey) {
    if (itemKey == null) return null;
    final params = project.selected;
    if (itemKey.startsWith('edge')) return params.edgeColor.label;
    if (itemKey.startsWith('eyelet')) return params.eyeletColor.label;
    if (itemKey == PriceItemKeys.frenchLock ||
        itemKey == PriceItemKeys.turnBuckle) {
      return params.fastenerColor.label;
    }
    return null;
  }

  WarehouseProduct? _match(
    String title,
    String unit,
    List<WarehouseProduct> products, {
    FilmMaterial? materialHint,
    String? itemKey,
    String? colorHint,
  }) {
    final lower = title.toLowerCase();
    // В заказе с несколькими материалами смета подписывает полотно:
    // «Полотно: Скрин», «Полотно: Тонированный ПВХ». Подсказка нужна,
    // чтобы не выбрать первый попавшийся рулон.
    var hint = materialHint;
    if (lower.contains('скрин')) {
      hint = FilmMaterial.screen;
    } else if (lower.contains('тонир')) {
      hint = FilmMaterial.tintedPvc;
    } else if (lower.contains('сетк')) {
      hint = FilmMaterial.mosquitoNet;
    } else if (lower.contains('обычн') || lower.contains('прозрач')) {
      hint = FilmMaterial.clearPvc;
    }
    final scored = <(WarehouseProduct, int)>[];
    for (final product in products) {
      if (product.archived) continue;
      var score = 0;
      final name = product.name.toLowerCase();
      final category = product.category.toLowerCase();
      final material = product.material.toLowerCase();
      final haystack =
          '$name $category $material ${product.color.toLowerCase()}';

      // Позиция прайса — самый точный признак: плёнка, окантовка и
      // фурнитура получают ровно тот товар, который заведён из прайса.
      if (itemKey != null && itemKey.isNotEmpty) {
        final key = product.priceKey ?? '';
        if (key == itemKey) {
          score += 80;
        } else if (key.startsWith('$itemKey:')) {
          score += 75;
        }
      }
      if (colorHint != null && colorHint.isNotEmpty) {
        score += product.color.toLowerCase() == colorHint.toLowerCase()
            ? 35
            : -15;
      }

      // Материал в строке сметы должен совпасть с товаром. Иначе «скрин»
      // цепляется за ПВХ и заказ резервирует не то полотно.
      if (lower.contains('скрин') &&
          !(material.contains('скрин') || name.contains('скрин'))) {
        continue;
      }
      if (lower.contains('тонир') &&
          !(material.contains('тонир') || name.contains('тонир'))) {
        continue;
      }
      if (lower.contains('сетк') &&
          !(material.contains('сетк') || name.contains('сетк'))) {
        continue;
      }

      if (hint != null &&
          (lower.contains('полотно') || lower.contains('плёнка'))) {
        final isFilmLine =
            category.contains('полотно') ||
            material.contains('пвх') ||
            material.contains('скрин') ||
            material.contains('сетк') ||
            name.contains('плён') ||
            name.contains('скрин') ||
            name.contains('сетк');
        if (isFilmLine) {
          var matchesHint = false;
          if (materialHint == FilmMaterial.clearPvc) {
            matchesHint =
                haystack.contains('прозрач') ||
                haystack.contains('обычный пвх');
          } else if (materialHint == FilmMaterial.tintedPvc) {
            matchesHint = haystack.contains('тонир');
          } else if (materialHint == FilmMaterial.mosquitoNet) {
            matchesHint = haystack.contains('сетк');
          } else if (materialHint == FilmMaterial.screen) {
            matchesHint = haystack.contains('скрин');
          }
          score += matchesHint ? 50 : -20;
        }
      }
      if (lower.contains('люверс') && name.contains('люверс')) score += 40;
      if ((lower.contains('тент') || lower.contains('окантов')) &&
          (name.contains('тент') ||
              name.contains('окантов') ||
              category.contains('окантов'))) {
        score += 34;
      }
      if (lower.contains('перемыч') &&
          (name.contains('перемыч') ||
              category.contains('комплект') ||
              material.contains('тент'))) {
        score += 34;
      }
      if (lower.contains('бокс') && name.contains('бокс')) score += 30;
      if (lower.contains('саморез') && name.contains('саморез')) score += 30;
      if (lower.contains('дренаж') && name.contains('дренаж')) score += 30;
      if ((lower.contains('ремен') || lower.contains('ремн')) &&
          name.contains('ремен')) {
        score += 30;
      }
      if ((lower.contains('брус') || lower.contains('декор')) &&
          name.contains('брус')) {
        score += 28;
      }
      if ((lower.contains('скоба') || lower.contains('замок')) &&
          (name.contains('скоб') ||
              name.contains('замок') ||
              category.contains('фурнитур'))) {
        score += 24;
      }
      if (lower.contains('ремень') && name.contains('ремен')) score += 40;
      if (lower.contains('молния') && name.contains('молни')) score += 40;
      if (lower.contains('окантов') &&
          (name.contains('окант') ||
              name.contains('тент') ||
              category.contains('окант'))) {
        score += 36;
      }
      if ((lower.contains('полотно') || lower.contains('плёнка')) &&
          (category.contains('полотно') ||
              category.contains('плён') ||
              material.contains('пвх') ||
              material.contains('скрин') ||
              name.contains('плён') ||
              name.contains('скрин'))) {
        score += 28;
      }
      if (lower.contains('скрин') &&
          (material.contains('скрин') || name.contains('скрин'))) {
        score += 30;
      }
      if (lower.contains('тонир') &&
          (material.contains('тонир') || name.contains('тонир'))) {
        score += 26;
      }
      if (lower.contains('сетк') &&
          (material.contains('сетк') || name.contains('сетк'))) {
        score += 26;
      }
      if (lower.contains('фартук') && name.contains('фартук')) score += 24;
      if (lower.contains('ремен') && name.contains('ремен')) score += 20;
      if (lower.contains('груз') && name.contains('груз')) score += 20;

      // Ширина окантовки: «Тент 100 мм» должен попасть в товар 100 мм,
      // а не в первый попавшийся 80/120 мм. Без этого заказ резервировал
      // не тот рулон, а количество считалось по чужой ширине.
      final isEdgeProduct =
          category.contains('окант') ||
          name.contains('окант') ||
          (name.contains('тент') && product.widthMm > 0);
      if (isEdgeProduct) {
        final titleWidths = _numbers(lower);
        final productWidth = product.widthMm > 0
            ? product.widthMm
            : _firstNumber(name);
        if (productWidth != null && titleWidths.isNotEmpty) {
          final matches = titleWidths.any(
            (value) => (value - productWidth).abs() < 0.5,
          );
          score += matches ? 48 : -35;
        }
      }

      // Точное вхождение названия товара в строку сметы — сильный признак.
      if (name.length >= 4 && lower.contains(name)) score += 18;
      // Общие слова длиннее трёх букв.
      final words = lower
          .split(RegExp(r'[^a-zа-яё0-9]+'))
          .where((word) => word.length > 3)
          .toSet();
      for (final word in words) {
        if (haystack.contains(word)) score += 3;
      }

      // Единица совпадает — приоритет, но только если уже есть смысловое
      // совпадение. Иначе любой товар в метрах «цепляет» любую строку в
      // метрах (например, плёнка — окантовку).
      final hasSemanticMatch = score > 0;
      if (product.unit.label == unit) score += 8;
      if (product.unit == StockUnit.roll && unit == 'м²') score += 4;

      if (hasSemanticMatch) scored.add((product, score));
    }
    if (scored.isEmpty) return null;
    scored.sort((a, b) {
      final byScore = b.$2.compareTo(a.$2);
      if (byScore != 0) return byScore;
      return a.$1.name.length.compareTo(b.$1.name.length);
    });
    return scored.first.$1;
  }

  double? _convert(double quantity, String unit, WarehouseProduct product) {
    if (quantity <= 0) return 0;
    final lineUnit = _normalizeUnit(unit);
    final productUnit = _normalizeUnit(product.unit.label);
    if (lineUnit == productUnit) return quantity;
    if (lineUnit == 'м²') {
      if (product.unit == StockUnit.roll && product.unitAreaM2 > 0) {
        return quantity / product.unitAreaM2;
      }
      if (product.unit == StockUnit.meter && product.widthMm > 0) {
        return quantity / (product.widthMm / 1000);
      }
    }
    if (lineUnit == 'м') {
      if (product.unit == StockUnit.roll && product.lengthMm > 0) {
        return quantity / (product.lengthMm / 1000);
      }
      if (product.unit == StockUnit.squareMeter && product.widthMm > 0) {
        return quantity * (product.widthMm / 1000);
      }
    }
    if (lineUnit == 'шт' && product.unit == StockUnit.piece) return quantity;
    if (lineUnit == 'рулон' && product.unit == StockUnit.roll) return quantity;
    // Несовместимые единицы нельзя молча считать «как есть»: иначе
    // площадь превращается в метры, а потребность получается неверной.
    return null;
  }

  static String _normalizeUnit(String raw) {
    final value = raw.toLowerCase().replaceAll(' ', '').replaceAll('.', '');
    if (value.contains('м²') || value.contains('м2') || value.contains('квм')) {
      return 'м²';
    }
    if (value.contains('погм') || value == 'м' || value.contains('метр')) {
      return 'м';
    }
    if (value.contains('рул')) return 'рулон';
    if (value.contains('шт')) return 'шт';
    return value;
  }

  static List<double> _numbers(String text) => RegExp(r'\d+(?:[.,]\d+)?')
      .allMatches(text)
      .map((match) {
        return double.tryParse(match.group(0)!.replaceAll(',', '.')) ?? 0;
      })
      .where((value) => value > 0)
      .toList();

  static double? _firstNumber(String text) {
    final values = _numbers(text);
    return values.isEmpty ? null : values.first;
  }
}
