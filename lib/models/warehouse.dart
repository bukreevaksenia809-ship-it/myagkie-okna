import 'dart:convert';

/// Единица складского учёта.
enum StockUnit {
  piece('шт'),
  squareMeter('м²'),
  meter('м'),
  roll('рулон');

  const StockUnit(this.label);
  final String label;
}

/// Тип движения по складу.
enum StockMoveType {
  receipt('Приход'),
  sale('Продажа'),
  issue('Списание в заказ'),
  writeOff('Списание'),
  returnIn('Возврат'),
  inventory('Инвентаризация');

  const StockMoveType(this.label);
  final String label;

  /// Приходные операции увеличивают остаток.
  bool get increases =>
      this == StockMoveType.receipt ||
      this == StockMoveType.returnIn ||
      this == StockMoveType.inventory;
}

/// Карточка товара склада.
class WarehouseProduct {
  const WarehouseProduct({
    required this.id,
    required this.name,
    required this.unit,
    required this.purchasePrice,
    required this.salePrice,
    this.material = '',
    this.widthMm = 0,
    this.lengthMm = 0,
    this.minQuantity = 0,
    this.supplier = '',
    this.location = '',
    this.note = '',
  });

  final String id;
  final String name;
  final StockUnit unit;
  final double purchasePrice;
  final double salePrice;
  final String material;
  final double widthMm;
  final double lengthMm;
  final double minQuantity;
  final String supplier;
  final String location;
  final String note;

  /// Площадь одной единицы, м² (для рулона/листа).
  double get unitAreaM2 =>
      widthMm > 0 && lengthMm > 0 ? widthMm * lengthMm / 1000000 : 0;

  WarehouseProduct copyWith({
    String? name,
    StockUnit? unit,
    double? purchasePrice,
    double? salePrice,
    String? material,
    double? widthMm,
    double? lengthMm,
    double? minQuantity,
    String? supplier,
    String? location,
    String? note,
  }) => WarehouseProduct(
    id: id,
    name: name ?? this.name,
    unit: unit ?? this.unit,
    purchasePrice: purchasePrice ?? this.purchasePrice,
    salePrice: salePrice ?? this.salePrice,
    material: material ?? this.material,
    widthMm: widthMm ?? this.widthMm,
    lengthMm: lengthMm ?? this.lengthMm,
    minQuantity: minQuantity ?? this.minQuantity,
    supplier: supplier ?? this.supplier,
    location: location ?? this.location,
    note: note ?? this.note,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'unit': unit.name,
    'purchasePrice': purchasePrice,
    'salePrice': salePrice,
    'material': material,
    'widthMm': widthMm,
    'lengthMm': lengthMm,
    'minQuantity': minQuantity,
    'supplier': supplier,
    'location': location,
    'note': note,
  };

  factory WarehouseProduct.fromJson(Map<String, dynamic> json) =>
      WarehouseProduct(
        id: '${json['id'] ?? ''}',
        name: '${json['name'] ?? ''}',
        unit: StockUnit.values.firstWhere(
          (value) => value.name == json['unit'],
          orElse: () => StockUnit.piece,
        ),
        purchasePrice: (json['purchasePrice'] as num?)?.toDouble() ?? 0,
        salePrice: (json['salePrice'] as num?)?.toDouble() ?? 0,
        material: '${json['material'] ?? ''}',
        widthMm: (json['widthMm'] as num?)?.toDouble() ?? 0,
        lengthMm: (json['lengthMm'] as num?)?.toDouble() ?? 0,
        minQuantity: (json['minQuantity'] as num?)?.toDouble() ?? 0,
        supplier: '${json['supplier'] ?? ''}',
        location: '${json['location'] ?? ''}',
        note: '${json['note'] ?? ''}',
      );
}

/// Движение по складу. Остаток НЕ хранится в товаре — он считается по
/// журналу, поэтому историю нельзя «потерять» редактированием карточки.
class StockMove {
  const StockMove({
    required this.id,
    required this.productId,
    required this.type,
    required this.quantity,
    required this.price,
    required this.at,
    this.orderId = '',
    this.note = '',
  });

  final String id;
  final String productId;
  final StockMoveType type;
  final double quantity;
  final double price;
  final DateTime at;
  final String orderId;
  final String note;

  double get signedQuantity => type.increases ? quantity : -quantity;

  Map<String, dynamic> toJson() => {
    'id': id,
    'productId': productId,
    'type': type.name,
    'quantity': quantity,
    'price': price,
    'at': at.toIso8601String(),
    'orderId': orderId,
    'note': note,
  };

  factory StockMove.fromJson(Map<String, dynamic> json) => StockMove(
    id: '${json['id'] ?? ''}',
    productId: '${json['productId'] ?? ''}',
    type: StockMoveType.values.firstWhere(
      (value) => value.name == json['type'],
      orElse: () => StockMoveType.receipt,
    ),
    quantity: (json['quantity'] as num?)?.toDouble() ?? 0,
    price: (json['price'] as num?)?.toDouble() ?? 0,
    at: DateTime.tryParse('${json['at']}') ?? DateTime.now(),
    orderId: '${json['orderId'] ?? ''}',
    note: '${json['note'] ?? ''}',
  );
}

/// Хранилище склада в JSON (shared_preferences).
class WarehouseData {
  WarehouseData({List<WarehouseProduct>? products, List<StockMove>? moves})
    : products = products ?? const [],
      moves = moves ?? const [];

  final List<WarehouseProduct> products;
  final List<StockMove> moves;

  double balanceOf(String productId) => moves
      .where((move) => move.productId == productId)
      .fold(0.0, (sum, move) => sum + move.signedQuantity);

  double get stockValue => products.fold(
    0,
    (sum, product) => sum + balanceOf(product.id) * product.purchasePrice,
  );

  List<WarehouseProduct> get lowStock => [
    for (final product in products)
      if (balanceOf(product.id) <= product.minQuantity) product,
  ];

  String toJson() => jsonEncode({
    'products': [for (final product in products) product.toJson()],
    'moves': [for (final move in moves) move.toJson()],
  });

  factory WarehouseData.fromJsonString(String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return WarehouseData();
      return WarehouseData(
        products: [
          for (final item in (decoded['products'] as List? ?? const []))
            if (item is Map)
              WarehouseProduct.fromJson(item.cast<String, dynamic>()),
        ],
        moves: [
          for (final item in (decoded['moves'] as List? ?? const []))
            if (item is Map) StockMove.fromJson(item.cast<String, dynamic>()),
        ],
      );
    } catch (_) {
      return WarehouseData();
    }
  }
}
