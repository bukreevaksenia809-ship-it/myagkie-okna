import '../models/order_project.dart';
import '../models/warehouse.dart';
import '../services/estimate.dart';
import 'warehouse_store.dart';

/// Списывает материалы по смете заказа со склада.
///
/// Сопоставление намеренно прозрачное: строка сметы ищет товар по названию
/// (плёнка/окантовка/люверс/скоба/ремень). Если товара нет или остатка меньше
/// нужного, операция всё равно фиксируется на доступное количество, а в
/// примечании остаётся «не хватило …» — так склад не уходит в минус.
Future<String> consumeOrderMaterials(
  OrderProject project, {
  required String orderTitle,
}) async {
  final data = await WarehouseStore.load();
  if (data.products.isEmpty) return 'Склад пуст — сначала добавьте товары.';
  final estimate = Estimate.of(project, PriceList.defaults());
  final products = [...data.products];
  final moves = <StockMove>[];
  final shortages = <String>[];

  WarehouseProduct? find(String needle) {
    final lower = needle.toLowerCase();
    for (final product in products) {
      final name = product.name.toLowerCase();
      if (name.contains(lower) || lower.contains(name)) return product;
    }
    return null;
  }

  for (final line in estimate.lines) {
    final title = line.title.toLowerCase();
    String? needle;
    if (title.contains('полотно') || title.contains('плёнка')) {
      if (title.contains('скрин')) {
        needle = 'скрин';
      } else if (title.contains('тонир')) {
        needle = 'тонир';
      } else {
        needle = 'плён';
      }
    } else if (title.contains('окантовка')) {
      needle = 'окантов';
    } else if (title.contains('люверс')) {
      needle = 'люверс';
    } else if (title.contains('скоба') || title.contains('замок')) {
      needle = 'скоб';
    } else if (title.contains('ремень')) {
      needle = 'ремень';
    }
    if (needle == null) continue;
    final product = find(needle);
    if (product == null) {
      shortages.add('${line.title}: нет товара на складе');
      continue;
    }
    final balance = data.balanceOf(product.id) +
        moves
            .where((move) => move.productId == product.id)
            .fold(0.0, (sum, move) => sum + move.signedQuantity);
    final wanted = line.quantity;
    final quantity = wanted <= balance ? wanted : balance;
    if (quantity <= 0) {
      shortages.add('${product.name}: нет остатка');
      continue;
    }
    if (quantity < wanted) {
      shortages.add(
        '${product.name}: нужно ${wanted.toStringAsFixed(2)}, '
        'есть ${quantity.toStringAsFixed(2)}',
      );
    }
    moves.add(
      StockMove(
        id: '${DateTime.now().microsecondsSinceEpoch}-${moves.length}',
        productId: product.id,
        type: StockMoveType.issue,
        quantity: quantity,
        price: product.purchasePrice,
        at: DateTime.now(),
        orderId: orderTitle,
        note: 'Списание по смете',
      ),
    );
  }

  if (moves.isEmpty) {
    return shortages.isEmpty
        ? 'В смете нет материалов, которые есть на складе.'
        : shortages.join('\n');
  }
  var updated = data;
  for (final move in moves) {
    updated = WarehouseData(
      products: updated.products,
      moves: [...updated.moves, move],
    );
  }
  await WarehouseStore.save(updated);
  return [
    'Списано позиций: ${moves.length}.',
    if (shortages.isNotEmpty) 'Не хватило:\n${shortages.join('\n')}',
  ].join('\n');
}
