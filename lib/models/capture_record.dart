import 'dart:convert';

class CaptureRecord {
  final String id;
  final String filePath;
  final String? thumbnailPath;
  final DateTime createdAt;
  final String category;
  final String primaryLabel;
  final String? secondaryLabel;
  final bool secondaryLabelGuess;
  final List<String> stateTags;
  final String? freshnessHint;
  final int? shelfLifeDays;
  final String? amountLabel;
  final String? usageRole;
  final double? confidence;
  final String? modelVersion;
  final Map<String, dynamic>? aiRawJson;

  CaptureRecord({
    required this.id,
    required this.filePath,
    required this.thumbnailPath,
    required this.createdAt,
    required this.category,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.secondaryLabelGuess,
    required this.stateTags,
    required this.freshnessHint,
    required this.shelfLifeDays,
    required this.amountLabel,
    required this.usageRole,
    required this.confidence,
    required this.modelVersion,
    required this.aiRawJson,
  });

  Map<String, Object?> toDbMap() {
    return {
      'id': id,
      'file_path': filePath,
      'thumbnail_path': thumbnailPath,
      'created_at': createdAt.toIso8601String(),
      'category': category,
      'primary_label': primaryLabel,
      'secondary_label': secondaryLabel,
      'secondary_label_guess': secondaryLabelGuess ? 1 : 0,
      'freshness_hint': freshnessHint,
      'shelf_life_days': shelfLifeDays,
      'amount_label': amountLabel,
      'usage_role': usageRole,
      'confidence': confidence,
      'model_version': modelVersion,
      'ai_raw_json': aiRawJson == null ? null : jsonEncode(aiRawJson),
    };
  }

  factory CaptureRecord.fromDbMap(Map<String, Object?> map, List<String> stateTags) {
    return CaptureRecord(
      id: map['id'] as String,
      filePath: map['file_path'] as String,
      thumbnailPath: map['thumbnail_path'] as String?,
      createdAt: DateTime.parse(map['created_at'] as String),
      category: map['category'] as String,
      primaryLabel: map['primary_label'] as String,
      secondaryLabel: map['secondary_label'] as String?,
      secondaryLabelGuess: (map['secondary_label_guess'] as int? ?? 0) == 1,
      freshnessHint: map['freshness_hint'] as String?,
      shelfLifeDays: map['shelf_life_days'] as int?,
      amountLabel: map['amount_label'] as String?,
      usageRole: map['usage_role'] as String?,
      confidence: (map['confidence'] as num?)?.toDouble(),
      modelVersion: map['model_version'] as String?,
      aiRawJson: map['ai_raw_json'] == null
          ? null
          : jsonDecode(map['ai_raw_json'] as String) as Map<String, dynamic>,
      stateTags: stateTags,
    );
  }

  String effectiveFreshnessHint() {
    final base = freshnessHint ?? 'OK';
    if (shelfLifeDays == null || shelfLifeDays! <= 0) {
      return base;
    }

    final ageDays = DateTime.now().difference(createdAt).inDays;
    final useSoonAt = (shelfLifeDays! * 0.7).ceil();
    String derived;
    if (ageDays >= shelfLifeDays!) {
      derived = 'URGENT';
    } else if (ageDays >= useSoonAt) {
      derived = 'USE_SOON';
    } else {
      derived = 'OK';
    }

    return _worseFreshness(base, derived);
  }

  String _worseFreshness(String a, String b) {
    int rank(String value) {
      switch (value) {
        case 'URGENT':
          return 2;
        case 'USE_SOON':
          return 1;
        default:
          return 0;
      }
    }

    return rank(a) >= rank(b) ? a : b;
  }

  String? shelfLifeCountdownLabel() {
    if (shelfLifeDays == null || shelfLifeDays! <= 0) {
      return null;
    }

    final ageDays = DateTime.now().difference(createdAt).inDays;
    final remainingDays = shelfLifeDays! - ageDays;
    if (remainingDays >= 0) {
      return 'D-$remainingDays';
    }
    return 'D+${remainingDays.abs()}';
  }
}
