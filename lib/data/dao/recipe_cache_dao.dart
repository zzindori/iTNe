import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

class RecipeCacheDao {
  Future<Map<String, dynamic>?> getCache(String cacheKey) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'recipe_cache',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
      limit: 1,
    );
    if (rows.isEmpty) {
      return null;
    }
    return rows.first.map((key, value) => MapEntry(key, value));
  }

  Future<void> upsertCache({
    required String cacheKey,
    required String kind,
    String? categoryId,
    String? recipeId,
    required Map<String, dynamic> requestPayload,
    required Map<String, dynamic> responseJson,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'recipe_cache',
      {
        'cache_key': cacheKey,
        'kind': kind,
        'category_id': categoryId,
        'recipe_id': recipeId,
        'request_payload': jsonEncode(requestPayload),
        'response_json': jsonEncode(responseJson),
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
