import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/order_repository.dart';
import 'package:soft_window_drawer/data/warehouse_repository.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/services/bulk_materials.dart';
import 'package:soft_window_drawer/services/catalog_index.dart';
import 'package:soft_window_drawer/services/estimate.dart';
import 'package:soft_window_drawer/services/order_materials.dart';
import 'package:soft_window_drawer/services/price_warehouse_sync.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppDatabase database;
  late WarehouseRepository warehouse;
  late OrderRepository orders;

  setUp(() async {
    sqfliteFfiInit();
    database = AppDatabase.instance;
    database.configureForTesting(databaseFactoryFfi, inMemoryDatabasePath);
    await database.open();
    warehouse = WarehouseRepository(database: database);
    orders = OrderRepository(database: database);
    await PriceWarehouseSync(
      database: database,
      warehouse: warehouse,
    ).sync(const PriceList.defaults());
  });

  tearDown(() async {
    await database.close();
  });

  test('суммирует материалы по заказам разных клиентов и дат', () async {
    final first = await orders.create(
      title: 'Беседка',
      customer: 'Иванов',
      project: const OrderProject(),
    );
    final second = await orders.create(
      title: 'Терраса',
      customer: 'Петров',
      project: const OrderProject(
        windows: [
          WindowParams(material: FilmMaterial.screen),
          WindowParams(
            bottomWidth: 2000,
            topWidth: 2000,
            leftHeight: 1800,
            rightHeight: 1800,
          ),
        ],
      ),
    );
    final calc = BulkMaterialsCalculator(orders: orders, warehouse: warehouse);
    final result = await calc.calculate([first, second]);
    expect(result.orderCount, 2);
    expect(result.windowCount, 3);
    expect(result.amount, greaterThan(0));
    expect(result.lines, isNotEmpty);
    expect(result.unmatched, isEmpty);
    expect(
      result.lines.any((line) => line.name.contains('Плёнка ПВХ')),
      isTrue,
    );
    expect(result.lines.any((line) => line.name.contains('Скрин')), isTrue);
    expect(result.lines.any((line) => line.name.contains('Люверс')), isTrue);
    expect(result.shortageCount, result.lines.length);

    // Сумма по двум заказам не меньше, чем по каждому отдельно.
    final one = await calc.calculate([first]);
    final two = await calc.calculate([second]);
    final line = result.lines.firstWhere(
      (line) => line.name.contains('Люверс'),
    );
    final oneQty = one.lines
        .where((item) => item.productId == line.productId)
        .fold<double>(0, (sum, item) => sum + item.quantity);
    final twoQty = two.lines
        .where((item) => item.productId == line.productId)
        .fold<double>(0, (sum, item) => sum + item.quantity);
    expect(line.quantity, closeTo(oneQty + twoQty, 0.001));
    expect(line.orders, 2);
  });

  test('работы и раскрой не прибавляются к материалам', () async {
    final order = await orders.create(title: 'Только материал');
    final project = orders.projectOf(order);
    final estimate = Estimate.of(project, const PriceList.defaults());
    final filmLine = estimate.lines.firstWhere(
      (line) =>
          line.group == EstimateGroup.materials &&
          line.title.toLowerCase().contains('полотно'),
    );
    final plan = await OrderMaterialsService(
      warehouse: warehouse,
    ).plan(project);
    final film = plan.needs.firstWhere(
      (need) => need.productId == 'price-filmClear',
    );
    expect(film.quantity, closeTo(filmLine.quantity, 0.001));
    expect(
      plan.needs.any(
        (need) =>
            need.source.contains('Сварка') ||
            need.source.contains('Раскрой') ||
            need.source.contains('Спайка'),
      ),
      isFalse,
    );
  });

  test('остаток и дефицит считаются по складу', () async {
    final eyelet = (await warehouse.products()).firstWhere(
      (product) =>
          catalogBasePriceKey(product.priceKey) == PriceItemKeys.eyeletRound &&
          product.color == 'Коричневый',
    );
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: eyelet.id,
        quantity: 10,
        unitCost: 5,
      ),
    );
    final order = await orders.create(title: 'Один');
    final result = await BulkMaterialsCalculator(
      orders: orders,
      warehouse: warehouse,
    ).calculate([order]);
    final eyelets = result.lines.firstWhere(
      (line) => line.name.contains('Люверс'),
    );
    expect(eyelets.available, 10);
    expect(eyelets.shortage, greaterThan(0));
    expect(eyelets.quantity, eyelets.available + eyelets.shortage);
  });

  test('резерв по заказу не завышает дефицит', () async {
    await warehouse.perform(
      const StockOperation(
        type: StockMoveType.receipt,
        productId: 'price-filmClear',
        quantity: 100,
        unitCost: 500,
      ),
    );
    final order = await orders.create(title: 'С резервом');
    final plan = await OrderMaterialsService(
      warehouse: warehouse,
    ).plan(orders.projectOf(order));
    final filmNeed = plan.needs.firstWhere(
      (need) => need.productId == 'price-filmClear',
    );
    final reserved = await warehouse.reserveOrder(order.id, [filmNeed]);
    expect(reserved.ok, isTrue, reason: reserved.message);
    final result = await BulkMaterialsCalculator(
      orders: orders,
      warehouse: warehouse,
    ).calculate([order]);
    final film = result.lines.firstWhere(
      (line) => line.productId == 'price-filmClear',
    );
    expect(film.allocated, greaterThan(0));
    expect(film.shortage, 0);
    expect(film.available, greaterThan(0));
  });

  test('пустая выборка даёт пустой результат', () async {
    final result = await BulkMaterialsCalculator(
      orders: orders,
      warehouse: warehouse,
    ).calculate(const []);
    expect(result.lines, isEmpty);
    expect(result.windowCount, 0);
    expect(result.amount, 0);
  });

  test('индивидуальные планы совпадают с суммарным', () async {
    final order = await orders.create(title: 'Один');
    final plan = await OrderMaterialsService(
      warehouse: warehouse,
    ).plan(orders.projectOf(order));
    final bulk = await BulkMaterialsCalculator(
      orders: orders,
      warehouse: warehouse,
    ).calculate([order]);
    for (final line in bulk.lines) {
      final need = plan.needs
          .where((item) => item.productId == line.productId)
          .fold<double>(0, (sum, item) => sum + item.quantity);
      expect(line.quantity, closeTo(need, 0.001));
    }
  });
}
