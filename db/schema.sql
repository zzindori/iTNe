-- iTNe DB schema (SQLite)

CREATE TABLE IF NOT EXISTS captures (
  id TEXT PRIMARY KEY,
  file_path TEXT NOT NULL,
  thumbnail_path TEXT,
  created_at TEXT NOT NULL,

  category TEXT NOT NULL CHECK (category IN (
    'MEAT','SEAFOOD','VEG','FRUIT','DAIRY_EGG','GRAIN_NOODLE','SAUCE','DRINK','PROCESSED','ETC'
  )),
  primary_label TEXT NOT NULL,
  secondary_label TEXT,
  secondary_label_guess INTEGER NOT NULL DEFAULT 1,

  freshness_hint TEXT CHECK (freshness_hint IN ('OK','USE_SOON','URGENT')),
  shelf_life_days INTEGER,
  amount_label TEXT CHECK (amount_label IN ('LOW','MEDIUM','HIGH')),
  usage_role TEXT CHECK (usage_role IN ('MAIN_INGREDIENT','SIDE','SEASONING')),

  confidence REAL,
  model_version TEXT,
  ai_raw_json TEXT
);

CREATE TABLE IF NOT EXISTS capture_state_tags (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  capture_id TEXT NOT NULL,
  tag TEXT NOT NULL CHECK (tag IN (
    'raw','cooked','frozen','chilled','packaged','opened','leftover','sliced'
  )),
  FOREIGN KEY (capture_id) REFERENCES captures(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS capture_events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  capture_id TEXT NOT NULL,
  type TEXT NOT NULL CHECK (type IN ('CREATED','AI_REQUESTED','AI_COMPLETED','USER_FEEDBACK')),
  payload TEXT,
  created_at TEXT NOT NULL,
  FOREIGN KEY (capture_id) REFERENCES captures(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS recipe_cache (
  cache_key TEXT PRIMARY KEY,
  kind TEXT NOT NULL,
  category_id TEXT,
  recipe_id TEXT,
  request_payload TEXT NOT NULL,
  response_json TEXT NOT NULL,
  created_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS suggested_substitutes (
  recipe_id TEXT NOT NULL,
  missing_ingredient TEXT NOT NULL,
  substitutes_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (recipe_id, missing_ingredient)
);

CREATE TABLE IF NOT EXISTS ingredient_substitutions (
  recipe_id TEXT NOT NULL,
  missing_ingredient TEXT NOT NULL,
  missing_original TEXT NOT NULL,
  substitute TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  PRIMARY KEY (recipe_id, missing_ingredient)
);

CREATE INDEX IF NOT EXISTS idx_captures_created_at ON captures(created_at);
CREATE INDEX IF NOT EXISTS idx_captures_category ON captures(category);
CREATE INDEX IF NOT EXISTS idx_state_tags_capture_id ON capture_state_tags(capture_id);
CREATE INDEX IF NOT EXISTS idx_events_capture_id ON capture_events(capture_id);
CREATE INDEX IF NOT EXISTS idx_recipe_cache_kind ON recipe_cache(kind);
CREATE INDEX IF NOT EXISTS idx_recipe_cache_category ON recipe_cache(category_id);
CREATE INDEX IF NOT EXISTS idx_substitutes_recipe ON suggested_substitutes(recipe_id);
CREATE INDEX IF NOT EXISTS idx_ingredient_subs_recipe ON ingredient_substitutions(recipe_id);
