import 'package:sqflite_common/sqlite_api.dart';

import 'db_factory.dart';

/// Локальная база приложения: склад, заказы, движения, резервы.
///
/// Одна база на установку. Все операции, меняющие остатки, проходят через
/// транзакции SQLite; остаток никогда не хранится в карточке товара — он
/// считается по журналу движений.
class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  static const int schemaVersion = 2;

  Database? _database;
  Future<Database>? _opening;
  DatabaseFactory? _factoryOverride;
  String? _pathOverride;

  /// Фабрика и путь для тестов. После вызова база откроется по этим значениям.
  void configureForTesting(DatabaseFactory factory, String path) {
    _factoryOverride = factory;
    _pathOverride = path;
    _database = null;
    _opening = null;
  }

  bool get isOpen => _database != null;

  Future<Database> get database async {
    final open = _database;
    if (open != null) return open;
    return _opening ??= _open();
  }

  Future<Database> open() => database;

  Future<Database> _open() async {
    final factory = _factoryOverride ?? await platformDatabaseFactory();
    final path = _pathOverride ?? await platformDatabasePath();
    final database = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          await db.execute('PRAGMA foreign_keys = ON');
        },
        onCreate: (db, version) async {
          await _createSchema(db);
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          await _migrate(db, oldVersion, newVersion);
        },
      ),
    );
    _database = database;
    return database;
  }

  Future<void> close() async {
    final db = _database;
    _database = null;
    _opening = null;
    await db?.close();
  }

  /// Удаляет базу (только для тестов и «сбросить всё»).
  Future<void> deleteDatabase() async {
    await close();
    final factory = _factoryOverride ?? await platformDatabaseFactory();
    final path = _pathOverride ?? await platformDatabasePath();
    await factory.deleteDatabase(path);
  }

  Future<T> transaction<T>(
    Future<T> Function(Transaction txn) action,
  ) async {
    final db = await database;
    return db.transaction<T>(action);
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();
    for (final statement in _schemaStatements) {
      batch.execute(statement);
    }
    await batch.commit(noResult: true);
  }

  /// Миграции. Версия 1 — первая схема; дальнейшие шаги добавляются сюда.
  static Future<void> _migrate(
    Database db,
    int oldVersion,
    int newVersion,
  ) async {
    if (oldVersion < 1) {
      await _createSchema(db);
      return;
    }
    if (oldVersion < 2) {
      await db.execute(
        "ALTER TABLE warehouse_products ADD COLUMN "
        "price_key TEXT NOT NULL DEFAULT ''",
      );
      await db.execute(
        'CREATE UNIQUE INDEX IF NOT EXISTS idx_products_price_key '
        "ON warehouse_products(price_key) WHERE price_key <> ''",
      );
    }
  }

  /// SQL схемы. Порядок важен: сначала справочники, затем журналы.
  static const List<String> _schemaStatements = [
    '''
    CREATE TABLE app_meta (
      key TEXT PRIMARY KEY,
      value TEXT NOT NULL
    )
    ''',
    '''
    CREATE TABLE warehouse_products (
      id TEXT PRIMARY KEY,
      name TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT '',
      material TEXT NOT NULL DEFAULT '',
      color TEXT NOT NULL DEFAULT '',
      thickness_mm REAL NOT NULL DEFAULT 0,
      unit TEXT NOT NULL DEFAULT 'piece',
      width_mm REAL NOT NULL DEFAULT 0,
      length_mm REAL NOT NULL DEFAULT 0,
      weight_kg REAL NOT NULL DEFAULT 0,
      min_quantity REAL NOT NULL DEFAULT 0,
      purchase_price REAL NOT NULL DEFAULT 0,
      sale_price REAL NOT NULL DEFAULT 0,
      supplier TEXT NOT NULL DEFAULT '',
      location TEXT NOT NULL DEFAULT '',
      barcode TEXT NOT NULL DEFAULT '',
      price_key TEXT NOT NULL DEFAULT '',
      archived INTEGER NOT NULL DEFAULT 0,
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''',
    '''
    CREATE UNIQUE INDEX idx_products_barcode
      ON warehouse_products(barcode)
      WHERE barcode <> ''
    ''',
    '''
    CREATE UNIQUE INDEX idx_products_price_key
      ON warehouse_products(price_key)
      WHERE price_key <> ''
    ''',
    '''
    CREATE INDEX idx_products_archived
      ON warehouse_products(archived, name)
    ''',
    '''
    CREATE TABLE stock_batches (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      received_at TEXT NOT NULL,
      unit_cost REAL NOT NULL DEFAULT 0,
      quantity REAL NOT NULL DEFAULT 0,
      remaining REAL NOT NULL DEFAULT 0,
      supplier TEXT NOT NULL DEFAULT '',
      order_id TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      FOREIGN KEY(product_id) REFERENCES warehouse_products(id)
        ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE INDEX idx_batches_product
      ON stock_batches(product_id, received_at, id)
    ''',
    '''
    CREATE TABLE stock_moves (
      id TEXT PRIMARY KEY,
      product_id TEXT NOT NULL,
      type TEXT NOT NULL,
      quantity REAL NOT NULL,
      direction INTEGER NOT NULL,
      unit_cost REAL NOT NULL DEFAULT 0,
      unit_price REAL NOT NULL DEFAULT 0,
      at TEXT NOT NULL,
      order_id TEXT NOT NULL DEFAULT '',
      batch_id TEXT NOT NULL DEFAULT '',
      location_from TEXT NOT NULL DEFAULT '',
      location_to TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      FOREIGN KEY(product_id) REFERENCES warehouse_products(id)
        ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE INDEX idx_moves_product_at
      ON stock_moves(product_id, at DESC)
    ''',
    '''
    CREATE INDEX idx_moves_order
      ON stock_moves(order_id, at DESC)
    ''',
    '''
    CREATE TABLE stock_move_allocations (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      move_id TEXT NOT NULL,
      batch_id TEXT NOT NULL,
      quantity REAL NOT NULL,
      unit_cost REAL NOT NULL DEFAULT 0,
      FOREIGN KEY(move_id) REFERENCES stock_moves(id) ON DELETE CASCADE,
      FOREIGN KEY(batch_id) REFERENCES stock_batches(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_allocations_move
      ON stock_move_allocations(move_id)
    ''',
    '''
    CREATE TABLE price_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      product_id TEXT NOT NULL,
      kind TEXT NOT NULL,
      price REAL NOT NULL,
      at TEXT NOT NULL,
      source TEXT NOT NULL DEFAULT '',
      FOREIGN KEY(product_id) REFERENCES warehouse_products(id)
        ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_price_history_product
      ON price_history(product_id, at DESC)
    ''',
    '''
    CREATE TABLE orders (
      id TEXT PRIMARY KEY,
      number TEXT NOT NULL DEFAULT '',
      title TEXT NOT NULL DEFAULT '',
      customer TEXT NOT NULL DEFAULT '',
      phone TEXT NOT NULL DEFAULT '',
      address TEXT NOT NULL DEFAULT '',
      status TEXT NOT NULL DEFAULT 'newOrder',
      priority TEXT NOT NULL DEFAULT 'normal',
      assignee TEXT NOT NULL DEFAULT '',
      labels TEXT NOT NULL DEFAULT '[]',
      deadline TEXT,
      archived INTEGER NOT NULL DEFAULT 0,
      amount REAL NOT NULL DEFAULT 0,
      comment TEXT NOT NULL DEFAULT '',
      project_json TEXT NOT NULL DEFAULT '{}',
      legacy_ref TEXT NOT NULL DEFAULT '',
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      status_changed_at TEXT
    )
    ''',
    '''
    CREATE UNIQUE INDEX idx_orders_number ON orders(number)
      WHERE number <> ''
    ''',
    '''
    CREATE INDEX idx_orders_status ON orders(archived, status, priority)
    ''',
    '''
    CREATE INDEX idx_orders_deadline ON orders(deadline)
    ''',
    '''
    CREATE TABLE order_events (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      text TEXT NOT NULL,
      field TEXT NOT NULL DEFAULT '',
      before_value TEXT NOT NULL DEFAULT '',
      after_value TEXT NOT NULL DEFAULT '',
      author TEXT NOT NULL DEFAULT '',
      at TEXT NOT NULL,
      FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_order_events_order
      ON order_events(order_id, at DESC)
    ''',
    '''
    CREATE TABLE order_comments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      text TEXT NOT NULL,
      author TEXT NOT NULL DEFAULT '',
      at TEXT NOT NULL,
      FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_order_comments_order
      ON order_comments(order_id, at DESC)
    ''',
    '''
    CREATE TABLE order_checklist (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      text TEXT NOT NULL,
      done INTEGER NOT NULL DEFAULT 0,
      sort INTEGER NOT NULL DEFAULT 0,
      FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_order_checklist_order
      ON order_checklist(order_id, sort)
    ''',
    '''
    CREATE TABLE order_attachments (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      name TEXT NOT NULL,
      path TEXT NOT NULL DEFAULT '',
      url TEXT NOT NULL DEFAULT '',
      mime TEXT NOT NULL DEFAULT '',
      data BLOB,
      added_at TEXT NOT NULL,
      FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
    )
    ''',
    '''
    CREATE INDEX idx_order_attachments_order
      ON order_attachments(order_id, added_at DESC)
    ''',
    '''
    CREATE TABLE order_materials (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      order_id TEXT NOT NULL,
      product_id TEXT NOT NULL,
      name TEXT NOT NULL DEFAULT '',
      unit TEXT NOT NULL DEFAULT 'piece',
      required_qty REAL NOT NULL DEFAULT 0,
      reserved_qty REAL NOT NULL DEFAULT 0,
      issued_qty REAL NOT NULL DEFAULT 0,
      state TEXT NOT NULL DEFAULT 'required',
      source TEXT NOT NULL DEFAULT '',
      note TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL,
      FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE,
      FOREIGN KEY(product_id) REFERENCES warehouse_products(id)
        ON DELETE RESTRICT
    )
    ''',
    '''
    CREATE UNIQUE INDEX idx_order_materials_unique
      ON order_materials(order_id, product_id)
    ''',
  ];
}
