class AiResult {
  final String captureId;
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
  final String modelVersion;
  final Map<String, dynamic> rawJson;
  final DateTime createdAt;

  AiResult({
    required this.captureId,
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
    required this.rawJson,
    required this.createdAt,
  });

  factory AiResult.fromJson(Map<String, dynamic> json) {
    return AiResult(
      captureId: json['captureId'] as String,
      category: json['category'] as String,
      primaryLabel: json['primaryLabel'] as String,
      secondaryLabel: json['secondaryLabel'] as String?,
      secondaryLabelGuess: (json['secondaryLabelGuess'] as bool?) ?? true,
      stateTags: (json['stateTags'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      freshnessHint: json['freshnessHint'] as String?,
      shelfLifeDays: json['shelfLifeDays'] as int?,
      amountLabel: json['amountLabel'] as String?,
      usageRole: json['usageRole'] as String?,
      confidence: (json['confidence'] as num?)?.toDouble(),
      modelVersion: json['modelVersion'] as String,
      rawJson: json['rawJson'] as Map<String, dynamic>,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}
