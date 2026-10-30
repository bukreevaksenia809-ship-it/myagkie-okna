import 'package:sqflite_common/sqlite_api.dart';

import '../data/app_database.dart';
import '../data/warehouse_repository.dart';
import '../models/price_list.dart';
import '../models/warehouse.dart';

/// Синхронизация номенклатуры склада с прайс-листом.
///
/// В прайсе перечислены только ходовые материалы; работы и проценты в склад
/// не попадают. Каждая позиция получает стабильный [WarehouseProduct.priceKey],
/// поэтому повторная синхронизация не создаёт дублей и может обновить цену
/// продажи, если её поправили в прайсе.
class PriceWarehouseSync {
  PriceWarehouseSync({AppDatabase? database, WarehouseRepository? warehouse})
    : _database = database ?? AppDatabase.instance,
      _warehouse = warehouse ?? WarehouseRepository.instance;

  final AppDatabase _database;
  final WarehouseRepository _warehouse;

  static const String _seedKey = 'price_warehouse_seed_v2';

  /// Один раз при первом запуске 2.1: добавляет материалы прайса в пустой
  /// или старый склад. Повторно не навязывает позиции.
  Future<int> seedOnce({PriceList prices = const PriceList.defaults()}) async {
    final db = await _database.database;
    final rows = await db.query(
      'app_meta',
      where: 'key = ?',
      whereArgs: [_seedKey],
      limit: 1,
    );
    if (rows.isNotEmpty) return 0;
    final created = await sync(prices, updatePrices: true);
    await db.insert('app_meta', {
      'key': _seedKey,
      'value': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
    return created;
  }

  /// Добавляет недостающие позиции прайса. Возвращает число созданных.
  Future<int> sync(PriceList prices, {bool updatePrices = false}) async {
    final existing = await _warehouse.products(includeArchived: true);
    final byKey = {
      for (final product in existing)
        if (product.priceKey.isNotEmpty) product.priceKey: product,
    };
    var created = 0;
    for (final definition in _definitions(prices)) {
      final product =
          byKey[definition.key] ?? _matchByName(existing, definition);
      if (product == null) {
        final result = await _warehouse.saveProduct(definition.toProduct());
        if (result.ok) created++;
      } else if (product.priceKey.isEmpty) {
        // Старый товар с тем же названием: не плодим дубль, а привязываем
        // его к позиции прайса. Остатки и закупочная цена сохраняются.
        await _warehouse.saveProduct(
          product.copyWith(
            priceKey: definition.key,
            category: definition.category,
            material: definition.material,
            color: definition.color,
            unit: definition.unit,
            widthMm: definition.widthMm,
            salePrice: definition.salePrice,
          ),
        );
      } else if (updatePrices) {
        await _warehouse.saveProduct(
          product.copyWith(
            name: definition.name,
            category: definition.category,
            material: definition.material,
            color: definition.color,
            unit: definition.unit,
            widthMm: definition.widthMm,
            salePrice: definition.salePrice,
          ),
        );
      }
    }
    return created;
  }

  static List<_PriceProduct> _definitions(PriceList p) {
    final result = <_PriceProduct>[
      _PriceProduct(
        key: PriceItemKeys.filmClear,
        name: 'Плёнка ПВХ прозрачная',
        category: 'Полотно',
        material: 'ПВХ',
        color: 'Прозрачный',
        unit: StockUnit.squareMeter,
        salePrice: p.filmClearPerM2,
      ),
      _PriceProduct(
        key: PriceItemKeys.filmTinted,
        name: 'Плёнка ПВХ тонированная',
        category: 'Полотно',
        material: 'ПВХ',
        color: 'Тонированный',
        unit: StockUnit.squareMeter,
        salePrice: p.filmTintedPerM2,
      ),
      _PriceProduct(
        key: PriceItemKeys.filmMesh,
        name: 'Москитная сетка',
        category: 'Полотно',
        material: 'Сетка',
        color: 'Серый',
        unit: StockUnit.squareMeter,
        salePrice: p.filmMeshPerM2,
      ),
      _PriceProduct(
        key: PriceItemKeys.filmScreen,
        name: 'Скрин',
        category: 'Полотно',
        material: 'Скрин',
        color: 'Серый',
        unit: StockUnit.squareMeter,
        salePrice: p.filmScreenPerM2,
      ),
      for (final (key, width, price) in [
        (PriceItemKeys.edge80, 80.0, p.edge80PerM),
        (PriceItemKeys.edge100, 100.0, p.edge100PerM),
        (PriceItemKeys.edge120, 120.0, p.edge120PerM),
        (PriceItemKeys.edge200, 200.0, p.edge200PerM),
        (PriceItemKeys.edge240, 240.0, p.edge240PerM),
      ])
        _PriceProduct(
          key: key,
          name: 'Окантовка тент ${width.toStringAsFixed(0)} мм',
          category: 'Окантовка',
          material: 'Тент',
          color: 'Коричневый',
          unit: StockUnit.meter,
          widthMm: width,
          salePrice: price,
        ),
      _PriceProduct(
        key: PriceItemKeys.eyeletRound,
        name: 'Люверс круглый Ø10',
        category: 'Люверсы',
        material: 'Металл',
        color: 'Латунь',
        unit: StockUnit.piece,
        salePrice: p.eyeletPrice + p.eyeletInstall,
      ),
      _PriceProduct(
        key: PriceItemKeys.eyeletOval,
        name: 'Люверс овальный 42×22',
        category: 'Люверсы',
        material: 'Металл',
        color: 'Латунь',
        unit: StockUnit.piece,
        salePrice: p.eyeletOvalPrice + p.eyeletInstall,
      ),
      _PriceProduct(
        key: PriceItemKeys.zipper,
        name: 'Молния тракторная',
        category: 'Фурнитура',
        material: 'Молния',
        color: 'Коричневый',
        unit: StockUnit.meter,
        salePrice: p.zipperPerM,
      ),
      _PriceProduct(
        key: PriceItemKeys.strap,
        name: 'Ремень подъёмный / силиконовый',
        category: 'Фурнитура',
        material: 'Лента',
        color: 'Коричневый',
        unit: StockUnit.piece,
        salePrice: p.strapPrice,
      ),
      _PriceProduct(
        key: PriceItemKeys.aluminumBox,
        name: 'Алюминиевый бокс',
        category: 'Комплектующие',
        material: 'Алюминий',
        color: 'Серебристый',
        unit: StockUnit.meter,
        salePrice: p.aluminumBoxPerM,
      ),
      _PriceProduct(
        key: PriceItemKeys.turnBuckle,
        name: 'Скоба поворотная',
        category: 'Фурнитура',
        material: 'Металл',
        color: 'Чёрный',
        unit: StockUnit.piece,
        salePrice: p.turnBucklePrice,
      ),
      _PriceProduct(
        key: PriceItemKeys.frenchLock,
        name: 'Французский замок / пластиковая скоба',
        category: 'Фурнитура',
        material: 'Металл',
        color: 'Коричневый',
        unit: StockUnit.piece,
        salePrice: p.frenchLockPrice,
      ),
      _PriceProduct(
        key: PriceItemKeys.screw,
        name: 'Саморез верхнего ряда',
        category: 'Крепёж',
        material: 'Металл',
        color: 'Серебристый',
        unit: StockUnit.piece,
        salePrice: p.screwPrice,
      ),
      _PriceProduct(
        key: PriceItemKeys.drain,
        name: 'Дренажное отверстие',
        category: 'Фурнитура',
        material: 'Металл',
        color: 'Серебристый',
        unit: StockUnit.piece,
        salePrice: p.drainPrice,
      ),
      _PriceProduct(
        key: 'crossbar',
        name: 'Перемычка (полоса тента)',
        category: 'Комплектующие',
        material: 'Тент',
        color: 'Коричневый',
        unit: StockUnit.meter,
        salePrice: p.crossbarPerM,
      ),
      _PriceProduct(
        key: PriceList.extraBeam,
        name: 'Брус',
        category: 'Пиломатериалы',
        material: 'Дерево',
        color: 'Натуральный',
        unit: StockUnit.meter,
        salePrice: p.beamPerM,
      ),
      _PriceProduct(
        key: PriceList.extraDecorBeam,
        name: 'Декоративный брус',
        category: 'Пиломатериалы',
        material: 'Дерево',
        color: 'Коричневый',
        unit: StockUnit.meter,
        salePrice: p.decorBeamPerM,
      ),
      _PriceProduct(
        key: PriceList.extraZip,
        name: 'Zip-система',
        category: 'Комплектующие',
        material: 'Zip',
        color: 'Коричневый',
        unit: StockUnit.squareMeter,
        salePrice: p.zipPerM2,
      ),
      _PriceProduct(
        key: PriceList.extraShadowSail,
        name: 'Теневой парус',
        category: 'Полотно',
        material: 'Тент',
        color: 'Бежевый',
        unit: StockUnit.squareMeter,
        salePrice: p.shadowSailPerM2,
      ),
      _PriceProduct(
        key: PriceList.extraRomanAwning,
        name: 'Римский навес',
        category: 'Полотно',
        material: 'Тент',
        color: 'Бежевый',
        unit: StockUnit.squareMeter,
        salePrice: p.romanAwningPerM2,
      ),
    ];
    // Свободные позиции прайса — тоже материалы, если заполнены.
    for (var i = 0; i < p.customItems.length; i++) {
      final item = p.customItems[i];
      if (!item.isFilled || item.unitPrice <= 0) continue;
      final key = 'custom:${item.name.trim().toLowerCase()}';
      result.add(
        _PriceProduct(
          key: key,
          name: item.name.trim(),
          category: 'Прочее',
          material: '',
          color: '',
          unit: _unitFor(item.unit),
          salePrice: item.unitPrice,
        ),
      );
    }
    return result;
  }

  static WarehouseProduct? _matchByName(
    List<WarehouseProduct> products,
    _PriceProduct definition,
  ) {
    final needle = definition.name.trim().toLowerCase();
    for (final product in products) {
      if (product.priceKey.isNotEmpty) continue;
      if (product.name.trim().toLowerCase() == needle) return product;
    }
    return null;
  }

  static StockUnit _unitFor(String raw) {
    final value = raw.toLowerCase();
    if (value.contains('м²') || value.contains('м2') || value.contains('кв')) {
      return StockUnit.squareMeter;
    }
    if (value.contains('рул')) return StockUnit.roll;
    if (value.contains('м')) return StockUnit.meter;
    return StockUnit.piece;
  }
}

class _PriceProduct {
  _PriceProduct({
    required this.key,
    required this.name,
    required this.category,
    required this.material,
    required this.color,
    required this.unit,
    required this.salePrice,
    this.widthMm = 0,
  });

  final String key;
  final String name;
  final String category;
  final String material;
  final String color;
  final StockUnit unit;
  final double salePrice;
  final double widthMm;

  WarehouseProduct toProduct() => WarehouseProduct(
    id: 'price-$key',
    name: name,
    category: category,
    material: material,
    color: color,
    unit: unit,
    widthMm: widthMm,
    purchasePrice: 0,
    salePrice: salePrice,
    priceKey: key,
    note: 'Позиция прайса. Закупочную цену заполните при первом приходе.',
  );
}
