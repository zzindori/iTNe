import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

class AppDatabase {
  AppDatabase._();

  static final AppDatabase instance = AppDatabase._();

  Database? _db;

  Future<void> init() async {
    await database;
  }

  Future<Database> get database async {
    final db = _db;
    if (db != null) {
      return db;
    }
    final opened = await _open();
    _db = opened;
    return opened;
  }

  Future<Database> _open() async {
    final dir = await getApplicationDocumentsDirectory();
    final path = p.join(dir.path, 'itne.db');
    return openDatabase(
      path,
      version: 7,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute(
            "CREATE TABLE IF NOT EXISTS capture_state_tags_new ("
            "id INTEGER PRIMARY KEY AUTOINCREMENT,"
            "capture_id TEXT NOT NULL,"
            "tag TEXT NOT NULL CHECK (tag IN ("
            "'raw','cooked','frozen','chilled','room','packaged','opened','leftover','sliced','alcohol','ready_to_eat'"
            "))," 
            "FOREIGN KEY (capture_id) REFERENCES captures(id) ON DELETE CASCADE"
            ")",
          );
          await db.execute(
            "INSERT INTO capture_state_tags_new (id, capture_id, tag) "
            "SELECT id, capture_id, tag FROM capture_state_tags",
          );
          await db.execute("DROP TABLE capture_state_tags");
          await db.execute("ALTER TABLE capture_state_tags_new RENAME TO capture_state_tags");
          await _createMaterialIndexTable(db);
        }
        if (oldVersion < 3) {
          await db.execute(
            "ALTER TABLE material_index ADD COLUMN source TEXT",
          );
        }
        if (oldVersion < 4) {
          await _createRecipeCacheTable(db);
        }
        if (oldVersion < 5) {
          await db.execute(
            "ALTER TABLE captures ADD COLUMN shelf_life_days INTEGER",
          );
        }
        if (oldVersion < 6) {
          await _createSuggestedSubstitutesTable(db);
        }
        if (oldVersion < 7) {
          await _createIngredientSubstitutionsTable(db);
        }
      },
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS captures ("
      "id TEXT PRIMARY KEY,"
      "file_path TEXT NOT NULL,"
      "thumbnail_path TEXT,"
      "created_at TEXT NOT NULL,"
      "category TEXT NOT NULL CHECK (category IN ("
      "'MEAT','SEAFOOD','VEG','FRUIT','DAIRY_EGG','GRAIN_NOODLE','SAUCE','DRINK','PROCESSED','ETC'"
      ")),"
      "primary_label TEXT NOT NULL,"
      "secondary_label TEXT,"
      "secondary_label_guess INTEGER NOT NULL DEFAULT 1,"
      "freshness_hint TEXT CHECK (freshness_hint IN ('OK','USE_SOON','URGENT')),"
      "shelf_life_days INTEGER,"
      "amount_label TEXT CHECK (amount_label IN ('LOW','MEDIUM','HIGH')),"
      "usage_role TEXT CHECK (usage_role IN ('MAIN_INGREDIENT','SIDE','SEASONING')),"
      "confidence REAL,"
      "model_version TEXT,"
      "ai_raw_json TEXT"
      ")",
    );

    await db.execute(
      "CREATE TABLE IF NOT EXISTS capture_state_tags ("
      "id INTEGER PRIMARY KEY AUTOINCREMENT,"
      "capture_id TEXT NOT NULL,"
      "tag TEXT NOT NULL CHECK (tag IN ("
      "'raw','cooked','frozen','chilled','room','packaged','opened','leftover','sliced','alcohol','ready_to_eat'"
      ")),"
      "FOREIGN KEY (capture_id) REFERENCES captures(id) ON DELETE CASCADE"
      ")",
    );

    await _createMaterialIndexTable(db);
    await _createRecipeCacheTable(db);
    await _createSuggestedSubstitutesTable(db);
    await _createIngredientSubstitutionsTable(db);

    await db.execute(
      "CREATE TABLE IF NOT EXISTS capture_events ("
      "id INTEGER PRIMARY KEY AUTOINCREMENT,"
      "capture_id TEXT NOT NULL,"
      "type TEXT NOT NULL CHECK (type IN ('CREATED','AI_REQUESTED','AI_COMPLETED','USER_FEEDBACK')),"
      "payload TEXT,"
      "created_at TEXT NOT NULL,"
      "FOREIGN KEY (capture_id) REFERENCES captures(id) ON DELETE CASCADE"
      ")",
    );

    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_captures_created_at ON captures(created_at)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_captures_category ON captures(category)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_state_tags_capture_id ON capture_state_tags(capture_id)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_events_capture_id ON capture_events(capture_id)",
    );
  }

  Future<void> _createMaterialIndexTable(Database db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS material_index ("
      "keyword TEXT PRIMARY KEY,"
      "category TEXT NOT NULL,"
      "primary_label TEXT NOT NULL,"
      "secondary_label TEXT,"
      "state_tags TEXT,"
      "aliases TEXT,"
      "source TEXT,"
      "created_at TEXT NOT NULL"
      ")",
    );
  }

  Future<void> _createRecipeCacheTable(Database db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS recipe_cache ("
      "cache_key TEXT PRIMARY KEY,"
      "kind TEXT NOT NULL,"
      "category_id TEXT,"
      "recipe_id TEXT,"
      "request_payload TEXT NOT NULL,"
      "response_json TEXT NOT NULL,"
      "created_at TEXT NOT NULL"
      ")",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_recipe_cache_kind ON recipe_cache(kind)",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_recipe_cache_category ON recipe_cache(category_id)",
    );
  }

  Future<void> _createSuggestedSubstitutesTable(Database db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS suggested_substitutes ("
      "recipe_id TEXT NOT NULL,"
      "missing_ingredient TEXT NOT NULL,"
      "substitutes_json TEXT NOT NULL,"
      "updated_at TEXT NOT NULL,"
      "PRIMARY KEY (recipe_id, missing_ingredient)"
      ")",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_substitutes_recipe ON suggested_substitutes(recipe_id)",
    );
  }

  Future<void> _createIngredientSubstitutionsTable(Database db) async {
    await db.execute(
      "CREATE TABLE IF NOT EXISTS ingredient_substitutions ("
      "recipe_id TEXT NOT NULL,"
      "missing_ingredient TEXT NOT NULL,"
      "missing_original TEXT NOT NULL,"
      "substitute TEXT NOT NULL,"
      "updated_at TEXT NOT NULL,"
      "PRIMARY KEY (recipe_id, missing_ingredient)"
      ")",
    );
    await db.execute(
      "CREATE INDEX IF NOT EXISTS idx_ingredient_subs_recipe ON ingredient_substitutions(recipe_id)",
    );
  }
}
