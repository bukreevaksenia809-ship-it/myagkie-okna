import 'package:flutter_test/flutter_test.dart';
import 'package:soft_window_drawer/data/app_database.dart';
import 'package:soft_window_drawer/data/order_repository.dart';
import 'package:soft_window_drawer/data/warehouse_repository.dart';
import 'package:soft_window_drawer/models/order_project.dart';
import 'package:soft_window_drawer/models/window_params.dart';
import 'package:soft_window_drawer/models/warehouse.dart';
import 'package:soft_window_drawer/services/order_materials.dart';
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
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'потребность заказа сопоставляется со складом, резервируется и списывается',
    () async {
      final product = const WarehouseProduct(
        id: 'film',
        name: 'Плёнка ПВХ прозрачная',
        category: 'Полотно',
        material: 'ПВХ',
        unit: StockUnit.squareMeter,
        purchasePrice: 500,
        salePrice: 900,
        minQuantity: 10,
      );
      expect((await warehouse.saveProduct(product)).ok, isTrue);
      expect(
        (await warehouse.perform(
          StockOperation(
            type: StockMoveType.receipt,
            productId: 'film',
            quantity: 100,
            unitCost: 500,
          ),
        )).ok,
        isTrue,
      );

      final order = await orders.create(title: 'Заказ на плёнку');
      final project = orders.projectOf(order);
      final plan = await OrderMaterialsService().plan(project);
      expect(plan.needs, isNotEmpty);
      final filmNeed = plan.needs.firstWhere(
        (need) => need.productId == 'film',
      );
      expect(filmNeed.quantity, greaterThan(0));
      expect(filmNeed.available, 100);

      final reserved = await warehouse.reserveOrder(order.id, plan.needs);
      expect(reserved.ok, isTrue, reason: reserved.message);
      final stock = await warehouse.stockFor('film');
      expect(stock!.reserved, closeTo(filmNeed.quantity, 0.001));

      final issued = await warehouse.issueOrder(order.id);
      expect(issued.ok, isTrue, reason: issued.message);
      final after = await warehouse.stockFor('film');
      expect(after!.balance, closeTo(100 - filmNeed.quantity, 0.001));
      expect(after.reserved, 0);
    },
  );

  test('скрин не сопоставляется с товаром ПВХ', () async {
    await warehouse.saveProduct(
      const WarehouseProduct(
        id: 'pvc',
        name: 'Плёнка ПВХ прозрачная',
        category: 'Полотно',
        material: 'ПВХ',
        unit: StockUnit.squareMeter,
        purchasePrice: 500,
        salePrice: 900,
      ),
    );
    await warehouse.saveProduct(
      const WarehouseProduct(
        id: 'screen',
        name: 'Скрин серый',
        category: 'Полотно',
        material: 'Скрин',
        unit: StockUnit.squareMeter,
        purchasePrice: 600,
        salePrice: 1000,
      ),
    );
    final project = const OrderProject(
      windows: [WindowParams(material: FilmMaterial.screen)],
    );
    final plan = await OrderMaterialsService().plan(project);
    final film = plan.needs.where(
      (need) =>
          need.source.toLowerCase().contains('полотно') ||
          need.source.toLowerCase().contains('скрин'),
    );
    expect(film.map((need) => need.productId), contains('screen'));
    expect(film.map((need) => need.productId), isNot(contains('pvc')));
  });

  test('заказ не резервирует материалы сверх остатка', () async {
    final product = const WarehouseProduct(
      id: 'film',
      name: 'Плёнка ПВХ прозрачная',
      category: 'Полотно',
      material: 'ПВХ',
      unit: StockUnit.squareMeter,
      purchasePrice: 500,
      salePrice: 900,
    );
    await warehouse.saveProduct(product);
    await warehouse.perform(
      StockOperation(
        type: StockMoveType.receipt,
        productId: 'film',
        quantity: 0.1,
        unitCost: 500,
      ),
    );
    final order = await orders.create(title: 'Заказ');
    final plan = await OrderMaterialsService().plan(orders.projectOf(order));
    final result = await warehouse.reserveOrder(order.id, plan.needs);
    expect(result.ok, isFalse);
    expect(result.shortages, isNotEmpty);
  });
  test(
    'окантовка сопоставляется по ширине рулона, а не по первой позиции',
    () async {
      for (final width in [80.0, 100.0, 120.0]) {
        await warehouse.saveProduct(
          WarehouseProduct(
            id: 'edge-${width.toInt()}',
            name: 'Окантовка тент ${width.toInt()} мм',
            category: 'Окантовка',
            material: 'Тент',
            unit: StockUnit.meter,
            widthMm: width,
            purchasePrice: 50,
            salePrice: 100,
          ),
        );
      }
      const project = OrderProject(
        windows: [
          WindowParams(
            bottomWidth: 2000,
            topWidth: 2000,
            leftHeight: 2000,
            rightHeight: 2000,
            rollBottom: 120,
            rollTop: 100,
            rollLeft: 80,
            rollRight: 120,
            pvcHeightAllowanceEnabled: false,
          ),
        ],
      );
      final plan = await OrderMaterialsService(
        warehouse: warehouse,
      ).plan(project);
      for (final width in [80, 100, 120]) {
        final need = plan.needs.where(
          (item) => item.productId == 'edge-$width',
        );
        expect(need, isNotEmpty, reason: 'нет потребности для $width мм');
        expect(need.first.quantity, greaterThan(0));
      }
      expect(
        plan.unmatched.where((line) => line.contains('окантов')).toList(),
        isEmpty,
      );
    },
  );

  test('несовместимые единицы не превращаются молча в количество', () async {
    await warehouse.saveProduct(
      const WarehouseProduct(
        id: 'film-meter',
        name: 'Плёнка ПВХ прозрачная',
        category: 'Полотно',
        material: 'ПВХ',
        unit: StockUnit.meter,
        purchasePrice: 500,
        salePrice: 900,
      ),
    );
    final plan = await OrderMaterialsService(
      warehouse: warehouse,
    ).plan(const OrderProject());
    expect(plan.needs.any((need) => need.productId == 'film-meter'), isFalse);
    expect(
      plan.unmatched.any((line) => line.contains('единицы не совпадают')),
      isTrue,
    );
  });
}
