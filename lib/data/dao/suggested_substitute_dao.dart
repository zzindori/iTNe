import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

class SuggestedSubstituteDao {
  Future<List<String>> getSubstitutes({
    required String recipeId,
    required String missingIngredient,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'suggested_substitutes',
      where: 'recipe_id = ? AND missing_ingredient = ?',
      whereArgs: [recipeId, missingIngredient],
      limit: 1,
    );
    if (rows.isEmpty) {
      return const [];
    }
    final raw = rows.first['substitutes_json'] as String;
    if (raw.isEmpty) {
      return const [];
    }
    final decoded = jsonDecode(raw) as List<dynamic>;
    return decoded.map((item) => item.toString()).toList();
  }

  Future<void> upsertSubstitutes({
    required String recipeId,
    required String missingIngredient,
    required List<String> substitutes,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'suggested_substitutes',
      {
        'recipe_id': recipeId,
        'missing_ingredient': missingIngredient,
        'substitutes_json': jsonEncode(substitutes),
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}
