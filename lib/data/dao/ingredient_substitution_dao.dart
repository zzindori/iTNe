import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';

class IngredientSubstitutionDao {
  Future<List<IngredientSubstitutionEntry>> getSubstitutions({
    required String recipeId,
  }) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'ingredient_substitutions',
      where: 'recipe_id = ',
      whereArgs: [recipeId],
      orderBy: 'updated_at DESC',
    );
    if (rows.isEmpty) {
      return const [];
    }
    return rows
        .map((row) => IngredientSubstitutionEntry(
              recipeId: row['recipe_id'] as String,
              missingIngredient: row['missing_ingredient'] as String,
              missingOriginal: row['missing_original'] as String,
              substitute: row['substitute'] as String,
            ))
        .toList();
  }

  Future<void> upsertSubstitution({
    required String recipeId,
    required String missingIngredient,
    required String missingOriginal,
    required String substitute,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'ingredient_substitutions',
      {
        'recipe_id': recipeId,
        'missing_ingredient': missingIngredient,
        'missing_original': missingOriginal,
        'substitute': substitute,
        'updated_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
}

class IngredientSubstitutionEntry {
  final String recipeId;
  final String missingIngredient;
  final String missingOriginal;
  final String substitute;

  const IngredientSubstitutionEntry({
    required this.recipeId,
    required this.missingIngredient,
    required this.missingOriginal,
    required this.substitute,
  });
}
