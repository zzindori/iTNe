import 'dart:convert';
import 'package:sqflite/sqflite.dart';

import '../db/app_database.dart';
import '../../models/ai_result.dart';
import '../../models/capture_record.dart';

class CaptureDao {
  Future<List<CaptureRecord>> getAllCaptures() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'captures',
      orderBy: 'created_at DESC',
    );
    if (rows.isEmpty) {
      return [];
    }

    final results = <CaptureRecord>[];
    for (final row in rows) {
      final id = row['id'] as String;
      final tagRows = await db.query(
        'capture_state_tags',
        columns: ['tag'],
        where: 'capture_id = ?',
        whereArgs: [id],
      );
      final tags = tagRows.map((t) => t['tag'] as String).toList();
      results.add(CaptureRecord.fromDbMap(row, tags));
    }
    return results;
  }
  Future<CaptureRecord> getCapture(String captureId) async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query(
      'captures',
      where: 'id = ?',
      whereArgs: [captureId],
      limit: 1,
    );
    if (rows.isEmpty) {
      throw Exception('Capture not found');
    }

    final tagRows = await db.query(
      'capture_state_tags',
      columns: ['tag'],
      where: 'capture_id = ?',
      whereArgs: [captureId],
    );
    final tags = tagRows.map((row) => row['tag'] as String).toList();
    return CaptureRecord.fromDbMap(rows.first, tags);
  }

  Future<void> insertCapture(CaptureRecord record) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.insert('captures', record.toDbMap());
      await _replaceStateTags(txn, record.id, record.stateTags);
      await _insertEvent(txn, record.id, 'CREATED');
    });
  }

  Future<void> updateFromAiResult(AiResult result) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'captures',
        {
          'category': result.category,
          'primary_label': result.primaryLabel,
          'secondary_label': result.secondaryLabel,
          'secondary_label_guess': result.secondaryLabelGuess ? 1 : 0,
          'freshness_hint': result.freshnessHint,
          'shelf_life_days': result.shelfLifeDays,
          'amount_label': result.amountLabel,
          'usage_role': result.usageRole,
          'confidence': result.confidence,
          'model_version': result.modelVersion,
          'ai_raw_json': jsonEncode(result.rawJson),
        },
        where: 'id = ?',
        whereArgs: [result.captureId],
      );
      await _replaceStateTags(txn, result.captureId, result.stateTags);
      await _insertEvent(txn, result.captureId, 'AI_COMPLETED');
    });
  }

  Future<void> deleteCapture(String captureId) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'capture_state_tags',
        where: 'capture_id = ?',
        whereArgs: [captureId],
      );
      await txn.delete(
        'capture_events',
        where: 'capture_id = ?',
        whereArgs: [captureId],
      );
      await txn.delete(
        'captures',
        where: 'id = ?',
        whereArgs: [captureId],
      );
    });
  }

  Future<void> resetForReanalysis(String captureId) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'captures',
      {
        'model_version': null,
        'confidence': null,
        'ai_raw_json': null,
        'freshness_hint': null,
        'shelf_life_days': null,
      },
      where: 'id = ?',
      whereArgs: [captureId],
    );
  }

  Future<List<Map<String, dynamic>>> getMaterialIndex() async {
    final db = await AppDatabase.instance.database;
    final rows = await db.query('material_index');
    return rows
        .map((row) => {
              'keyword': row['keyword'],
              'category': row['category'],
              'primaryLabel': row['primary_label'],
              'secondaryLabel': row['secondary_label'],
              'stateTags': row['state_tags'] == null
                  ? const []
                  : (jsonDecode(row['state_tags'] as String) as List<dynamic>)
                      .map((e) => e.toString())
                      .toList(),
              'aliases': row['aliases'] == null
                  ? const []
                  : (jsonDecode(row['aliases'] as String) as List<dynamic>)
                      .map((e) => e.toString())
                      .toList(),
              'source': row['source'],
            })
        .toList();
  }

  Future<void> upsertMaterialIndex({
    required String keyword,
    required String category,
    required String primaryLabel,
    required String secondaryLabel,
    required List<String> stateTags,
    required List<String> aliases,
    required String source,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.insert(
      'material_index',
      {
        'keyword': keyword,
        'category': category,
        'primary_label': primaryLabel,
        'secondary_label': secondaryLabel,
        'state_tags': jsonEncode(stateTags),
        'aliases': jsonEncode(aliases),
        'source': source,
        'created_at': DateTime.now().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateManualClassification({
    required String captureId,
    required String category,
    required String primaryLabel,
    required String secondaryLabel,
    required List<String> stateTags,
  }) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'captures',
        {
          'category': category,
          'primary_label': primaryLabel,
          'secondary_label': secondaryLabel,
          'secondary_label_guess': 0,
          'model_version': 'manual',
          'confidence': null,
          'ai_raw_json': null,
        },
        where: 'id = ?',
        whereArgs: [captureId],
      );
      await _replaceStateTags(txn, captureId, stateTags);
      await _insertEvent(txn, captureId, 'USER_FEEDBACK', payload: {
        'action': 'manual_classification',
      });
    });
  }

  Future<void> markAiFailed(String captureId, String reason) async {
    final db = await AppDatabase.instance.database;
    await db.update(
      'captures',
      {
        'model_version': 'ai-error',
        'confidence': null,
        'ai_raw_json': jsonEncode({'error': reason}),
      },
      where: 'id = ?',
      whereArgs: [captureId],
    );
  }

  Future<void> insertAiRequestedEvent(String captureId) async {
    final db = await AppDatabase.instance.database;
    await _insertEvent(db, captureId, 'AI_REQUESTED');
  }

  Future<void> fallbackToTop(String captureId, String primaryLabel) async {
    final db = await AppDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.update(
        'captures',
        {
          'category': 'ETC',
          'primary_label': primaryLabel,
          'secondary_label': null,
          'secondary_label_guess': 0,
          'freshness_hint': null,
          'amount_label': null,
          'usage_role': null,
          'confidence': null,
          'model_version': null,
          'ai_raw_json': null,
        },
        where: 'id = ?',
        whereArgs: [captureId],
      );
      await _replaceStateTags(txn, captureId, const []);
      await _insertEvent(txn, captureId, 'USER_FEEDBACK', payload: {
        'action': 'fallback_to_top',
      });
    });
  }

  Future<void> _replaceStateTags(
    dynamic txn,
    String captureId,
    List<String> stateTags,
  ) async {
    await txn.delete(
      'capture_state_tags',
      where: 'capture_id = ?',
      whereArgs: [captureId],
    );

    for (final tag in stateTags) {
      await txn.insert('capture_state_tags', {
        'capture_id': captureId,
        'tag': tag,
      });
    }
  }

  Future<void> _insertEvent(
    dynamic txn,
    String captureId,
    String type, {
    Map<String, dynamic>? payload,
  }) async {
    await txn.insert('capture_events', {
      'capture_id': captureId,
      'type': type,
      'payload': payload == null ? null : jsonEncode(payload),
      'created_at': DateTime.now().toIso8601String(),
    });
  }
}
