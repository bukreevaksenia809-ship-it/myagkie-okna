import 'dart:math' as math;

/// Единица складского учёта.
enum StockUnit {
  piece('шт', 'шт'),
  squareMeter('м²', 'м²'),
  meter('м', 'м'),
  roll('рулон', 'рул');

  const StockUnit(this.label, this.shortLabel);

  final String label;
  final String shortLabel;

  static StockUnit fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => StockUnit.piece,
  );
}

/// Тип движения по складу.
///
/// [direction] — знак влияния на остаток. У инвентаризации знак вычисляется
/// по разнице фактического и учётного остатка, поэтому в записи он хранится
/// явно, а не выводится из типа.
enum StockMoveType {
  receipt('Приход', 1),
  purchase('Закупка', 1),
  sale('Продажа', -1),
  issue('Списание в заказ', -1),
  writeOff('Списание брака', -1),
  returnIn('Возврат', 1),
  transferOut('Перемещение · расход', -1),
  transferIn('Перемещение · приход', 1),
  inventory('Инвентаризация', 0);

  const StockMoveType(this.label, this.direction);

  final String label;

  /// Знак по умолчанию: +1 приход, −1 расход, 0 — по разнице.
  final int direction;

  bool get isIncome => direction > 0;

  bool get isExpense => direction < 0;

  bool get isTransfer =>
      this == StockMoveType.transferIn || this == StockMoveType.transferOut;

  static StockMoveType fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => StockMoveType.receipt,
  );
}

/// Карточка номенклатуры склада.
class WarehouseProduct {
  const WarehouseProduct({
    required this.id,
    required this.name,
    required this.unit,
    required this.purchasePrice,
    required this.salePrice,
    this.category = '',
    this.material = '',
    this.color = '',
    this.thicknessMm = 0,
    this.widthMm = 0,
    this.lengthMm = 0,
    this.weightKg = 0,
    this.minQuantity = 0,
    this.supplier = '',
    this.location = '',
    this.barcode = '',
    this.priceKey = '',
    this.archived = false,
    this.note = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String category;
  final String material;
  final String color;
  final double thicknessMm;
  final StockUnit unit;
  final double widthMm;
  final double lengthMm;
  final double weightKg;
  final double minQuantity;
  final double purchasePrice;
  final double salePrice;
  final String supplier;
  final String location;
  final String barcode;

  /// Ключ позиции прайса, если товар создан из прайса.
  final String priceKey;

  final bool archived;
  final String note;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  /// Площадь одной единицы, м² (для рулона/листа).
  double get unitAreaM2 =>
      widthMm > 0 && lengthMm > 0 ? widthMm * lengthMm / 1000000 : 0;

  /// Наценка к закупочной цене, %.
  double get markupPercent =>
      purchasePrice > 0 ? (salePrice - purchasePrice) / purchasePrice * 100 : 0;

  /// Маржинальность от цены продажи, %.
  double get marginPercent =>
      salePrice > 0 ? (salePrice - purchasePrice) / salePrice * 100 : 0;

  String get dimensionsLabel {
    if (widthMm <= 0 && lengthMm <= 0) return '—';
    if (lengthMm <= 0) return '${_num(widthMm)} мм';
    return '${_num(widthMm)} × ${_num(lengthMm)} мм';
  }

  String get subtitle {
    final parts = <String>[
      if (category.isNotEmpty) category,
      if (material.isNotEmpty) material,
      if (color.isNotEmpty) color,
      if (thicknessMm > 0) '${_num(thicknessMm)} мм',
    ];
    return parts.join(' · ');
  }

  WarehouseProduct copyWith({
    String? id,
    String? name,
    String? category,
    String? material,
    String? color,
    double? thicknessMm,
    StockUnit? unit,
    double? widthMm,
    double? lengthMm,
    double? weightKg,
    double? minQuantity,
    double? purchasePrice,
    double? salePrice,
    String? supplier,
    String? location,
    String? barcode,
    String? priceKey,
    bool? archived,
    String? note,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => WarehouseProduct(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    material: material ?? this.material,
    color: color ?? this.color,
    thicknessMm: thicknessMm ?? this.thicknessMm,
    unit: unit ?? this.unit,
    widthMm: widthMm ?? this.widthMm,
    lengthMm: lengthMm ?? this.lengthMm,
    weightKg: weightKg ?? this.weightKg,
    minQuantity: minQuantity ?? this.minQuantity,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    salePrice: salePrice ?? this.salePrice,
    supplier: supplier ?? this.supplier,
    location: location ?? this.location,
    barcode: barcode ?? this.barcode,
    priceKey: priceKey ?? this.priceKey,
    archived: archived ?? this.archived,
    note: note ?? this.note,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  Map<String, Object?> toDb() => {
    'id': id,
    'name': name,
    'category': category,
    'material': material,
    'color': color,
    'thickness_mm': thicknessMm,
    'unit': unit.name,
    'width_mm': widthMm,
    'length_mm': lengthMm,
    'weight_kg': weightKg,
    'min_quantity': minQuantity,
    'purchase_price': purchasePrice,
    'sale_price': salePrice,
    'supplier': supplier,
    'location': location,
    'barcode': barcode,
    'price_key': priceKey,
    'archived': archived ? 1 : 0,
    'note': note,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory WarehouseProduct.fromDb(Map<String, Object?> row) =>
      WarehouseProduct(
        id: '${row['id']}',
        name: '${row['name'] ?? ''}',
        category: '${row['category'] ?? ''}',
        material: '${row['material'] ?? ''}',
        color: '${row['color'] ?? ''}',
        thicknessMm: _double(row['thickness_mm']),
        unit: StockUnit.fromName(row['unit'] as String?),
        widthMm: _double(row['width_mm']),
        lengthMm: _double(row['length_mm']),
        weightKg: _double(row['weight_kg']),
        minQuantity: _double(row['min_quantity']),
        purchasePrice: _double(row['purchase_price']),
        salePrice: _double(row['sale_price']),
        supplier: '${row['supplier'] ?? ''}',
        location: '${row['location'] ?? ''}',
        barcode: '${row['barcode'] ?? ''}',
        priceKey: '${row['price_key'] ?? ''}',
        archived: _int(row['archived']) == 1,
        note: '${row['note'] ?? ''}',
        createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
        updatedAt: DateTime.tryParse('${row['updated_at'] ?? ''}'),
      );

  /// Чтение старого JSON склада.
  factory WarehouseProduct.fromLegacyJson(Map<String, dynamic> json) =>
      WarehouseProduct(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        unit: StockUnit.fromName(json['unit'] as String?),
        purchasePrice: _double(json['purchasePrice']),
        salePrice: _double(json['salePrice']),
        material: '${json['material'] ?? ''}',
        widthMm: _double(json['widthMm']),
        lengthMm: _double(json['lengthMm']),
        minQuantity: _double(json['minQuantity']),
        supplier: '${json['supplier'] ?? ''}',
        location: '${json['location'] ?? ''}',
        note: '${json['note'] ?? ''}',
      );

  @override
  bool operator ==(Object other) =>
      other is WarehouseProduct && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Партия товара: приход с одной ценой. Остаток партии уменьшается по FIFO.
class StockBatch {
  const StockBatch({
    required this.id,
    required this.productId,
    required this.receivedAt,
    required this.unitCost,
    required this.quantity,
    required this.remaining,
    this.supplier = '',
    this.orderId = '',
    this.note = '',
  });

  final String id;
  final String productId;
  final DateTime receivedAt;
  final double unitCost;
  final double quantity;
  final double remaining;
  final String supplier;
  final String orderId;
  final String note;

  double get consumed => math.max(0, quantity - remaining);

  double get value => remaining * unitCost;

  Map<String, Object?> toDb() => {
    'id': id,
    'product_id': productId,
    'received_at': receivedAt.toIso8601String(),
    'unit_cost': unitCost,
    'quantity': quantity,
    'remaining': remaining,
    'supplier': supplier,
    'order_id': orderId,
    'note': note,
  };

  factory StockBatch.fromDb(Map<String, Object?> row) => StockBatch(
    id: '${row['id']}',
    productId: '${row['product_id']}',
    receivedAt:
        DateTime.tryParse('${row['received_at'] ?? ''}') ?? DateTime.now(),
    unitCost: _double(row['unit_cost']),
    quantity: _double(row['quantity']),
    remaining: _double(row['remaining']),
    supplier: '${row['supplier'] ?? ''}',
    orderId: '${row['order_id'] ?? ''}',
    note: '${row['note'] ?? ''}',
  );
}

/// Запись журнала движений. Остаток всегда считается по журналу.
class StockMove {
  const StockMove({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.direction,
    required this.at,
    this.unitCost = 0,
    this.unitPrice = 0,
    this.orderId = '',
    this.batchId = '',
    this.locationFrom = '',
    this.locationTo = '',
    this.note = '',
    this.createdAt,
  });

  final String id;
  final String productId;
  final StockMoveType type;

  /// Количество по модулю.
  final double quantity;

  /// +1 приход, −1 расход.
  final int direction;

  /// Себестоимость единицы (FIFO или закупочная).
  final double unitCost;

  /// Цена продажи/закупки в документе.
  final double unitPrice;

  final DateTime at;
  final String orderId;
  final String batchId;
  final String locationFrom;
  final String locationTo;
  final String note;
  final DateTime? createdAt;

  double get signedQuantity => quantity * direction;

  double get costAmount => quantity * unitCost;

  double get priceAmount => quantity * unitPrice;

  Map<String, Object?> toDb() => {
    'id': id,
    'product_id': productId,
    'type': type.name,
    'quantity': quantity,
    'direction': direction,
    'unit_cost': unitCost,
    'unit_price': unitPrice,
    'at': at.toIso8601String(),
    'order_id': orderId,
    'batch_id': batchId,
    'location_from': locationFrom,
    'location_to': locationTo,
    'note': note,
    'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
  };

  factory StockMove.fromDb(Map<String, Object?> row) => StockMove(
    id: '${row['id']}',
    productId: '${row['product_id']}',
    type: StockMoveType.fromName(row['type'] as String?),
    quantity: _double(row['quantity']),
    direction: _int(row['direction']),
    unitCost: _double(row['unit_cost']),
    unitPrice: _double(row['unit_price']),
    at: DateTime.tryParse('${row['at'] ?? ''}') ?? DateTime.now(),
    orderId: '${row['order_id'] ?? ''}',
    batchId: '${row['batch_id'] ?? ''}',
    locationFrom: '${row['location_from'] ?? ''}',
    locationTo: '${row['location_to'] ?? ''}',
    note: '${row['note'] ?? ''}',
    createdAt: DateTime.tryParse('${row['created_at'] ?? ''}'),
  );
}

/// Товар с остатками и ценами, посчитанными по журналу и партиям.
class WarehouseStock {
  const WarehouseStock({
    required this.product,
    required this.balance,
    required this.reserved,
    required this.averageCost,
    required this.batches,
  });

  final WarehouseProduct product;
  final double balance;
  final double reserved;
  final double averageCost;
  final List<StockBatch> batches;

  double get available => math.max(0, balance - reserved);

  double get balanceValue => balance * averageCost;

  double get saleValue => balance * product.salePrice;

  bool get isLow =>
      product.minQuantity > 0 && balance <= product.minQuantity;

  bool get isOut => balance <= 0;

  double get minCoverage =>
      product.minQuantity <= 0 ? 1 : (balance / product.minQuantity).clamp(0, 1);

  /// Себестоимость по FIFO для ближайшего списания [quantity].
  double fifoCostFor(double quantity) {
    var left = quantity;
    var cost = 0.0;
    for (final batch in batches) {
      if (left <= 0) break;
      if (batch.remaining <= 0) continue;
      final take = math.min(left, batch.remaining);
      cost += take * batch.unitCost;
      left -= take;
    }
    if (left > 0) cost += left * averageCost;
    return quantity <= 0 ? 0 : cost / quantity;
  }
}

/// Сводка склада: товары, остатки, резервы и итоги.
class WarehouseSnapshot {
  const WarehouseSnapshot({
    required this.stocks,
    required this.moves,
    required this.generatedAt,
  });

  final List<WarehouseStock> stocks;
  final List<StockMove> moves;
  final DateTime generatedAt;

  double get totalValue =>
      stocks.fold(0.0, (sum, stock) => sum + stock.balanceValue);

  double get totalSaleValue =>
      stocks.fold(0.0, (sum, stock) => sum + stock.saleValue);

  int get skuCount => stocks.length;

  int get lowCount => stocks.where((stock) => stock.isLow).length;

  double get reservedValue => stocks.fold(
    0.0,
    (sum, stock) => sum + stock.reserved * stock.averageCost,
  );

  WarehouseStock? byProduct(String id) =>
      stocks.where((stock) => stock.product.id == id).firstOrNull;

  List<WarehouseStock> get lowStocks =>
      stocks.where((stock) => stock.isLow).toList();
}

/// Операция склада, которую пользователь проводит одной транзакцией.
class StockOperation {
  const StockOperation({
    required this.type,
    required this.productId,
    required this.quantity,
    this.unitPrice,
    this.unitCost,
    this.orderId = '',
    this.note = '',
    this.locationFrom = '',
    this.locationTo = '',
    this.at,
  });

  final StockMoveType type;
  final String productId;
  final double quantity;

  /// Цена документа: закупка/продажа. Для списаний — 0 (берётся FIFO).
  final double? unitPrice;

  /// Себестоимость для приходных операций. null — средняя/закупочная.
  final double? unitCost;

  final String orderId;
  final String note;
  final String locationFrom;
  final String locationTo;
  final DateTime? at;

  bool get isTransfer =>
      type == StockMoveType.transferIn || type == StockMoveType.transferOut;
}

/// Строка потребности заказа в материале склада.
class OrderMaterialNeed {
  const OrderMaterialNeed({
    required this.productId,
    required this.name,
    required this.unit,
    required this.quantity,
    required this.available,
    required this.reserved,
    this.source = '',
    this.note = '',
    this.linked = true,
  });

  final String productId;
  final String name;
  final StockUnit unit;
  final double quantity;
  final double available;
  final double reserved;
  final String source;
  final String note;
  final bool linked;

  double get shortage => math.max(0, quantity - available);

  bool get enough => linked && shortage <= 0.0001;
}

/// Состояние материала заказа.
enum OrderMaterialState {
  required('Нужно'),
  reserved('Зарезервировано'),
  issued('Списано'),
  returned('Возвращено'),
  released('Резерв снят');

  const OrderMaterialState(this.label);

  final String label;

  static OrderMaterialState fromName(String? name) => values.firstWhere(
    (value) => value.name == name,
    orElse: () => OrderMaterialState.required,
  );
}

/// Связь заказа и материала склада.
class OrderMaterial {
  const OrderMaterial({
    required this.id,
    required this.orderId,
    required this.productId,
    required this.name,
    required this.unit,
    required this.requiredQty,
    required this.reservedQty,
    required this.issuedQty,
    required this.state,
    this.source = '',
    this.note = '',
    this.updatedAt,
  });

  final int id;
  final String orderId;
  final String productId;
  final String name;
  final StockUnit unit;
  final double requiredQty;
  final double reservedQty;
  final double issuedQty;
  final OrderMaterialState state;
  final String source;
  final String note;
  final DateTime? updatedAt;

  double get shortage => math.max(0, requiredQty - reservedQty - issuedQty);

  Map<String, Object?> toDb() => {
    'id': id == 0 ? null : id,
    'order_id': orderId,
    'product_id': productId,
    'name': name,
    'unit': unit.name,
    'required_qty': requiredQty,
    'reserved_qty': reservedQty,
    'issued_qty': issuedQty,
    'state': state.name,
    'source': source,
    'note': note,
    'updated_at': (updatedAt ?? DateTime.now()).toIso8601String(),
  };

  factory OrderMaterial.fromDb(Map<String, Object?> row) => OrderMaterial(
    id: _int(row['id']),
    orderId: '${row['order_id']}',
    productId: '${row['product_id']}',
    name: '${row['name'] ?? ''}',
    unit: StockUnit.fromName(row['unit'] as String?),
    requiredQty: _double(row['required_qty']),
    reservedQty: _double(row['reserved_qty']),
    issuedQty: _double(row['issued_qty']),
    state: OrderMaterialState.fromName(row['state'] as String?),
    source: '${row['source'] ?? ''}',
    note: '${row['note'] ?? ''}',
    updatedAt: DateTime.tryParse('${row['updated_at'] ?? ''}'),
  );
}

/// Виды складских отчётов.
enum WarehouseReportKind {
  stock('Остатки'),
  movement('Движение'),
  orderConsumption('Расход по заказам'),
  purchases('Закупки'),
  sales('Продажи'),
  profit('Прибыль'),
  lowStock('Низкие остатки'),
  inventory('Инвентаризация');

  const WarehouseReportKind(this.label);

  final String label;
}

/// Табличный отчёт склада.
class WarehouseReport {
  const WarehouseReport({
    required this.kind,
    required this.title,
    required this.columns,
    required this.rows,
    required this.totals,
    this.note = '',
  });

  final WarehouseReportKind kind;
  final String title;
  final List<String> columns;
  final List<List<String>> rows;
  final Map<String, String> totals;
  final String note;
}

double _double(Object? value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;

int _int(Object? value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

String _num(double value) {
  if (!value.isFinite) return '—';
  final fixed = value.toStringAsFixed(value == value.roundToDouble() ? 0 : 2);
  return fixed.replaceAll('.', ',');
}
