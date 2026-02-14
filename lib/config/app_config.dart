import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AppConfig {
  static late AppConfig _instance;
  static AppConfig get instance => _instance;

  static const String _aiApiKeyEnv = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  static const String _stabilityApiKeyEnv =
      String.fromEnvironment('STABILITY_API_KEY', defaultValue: '');

  late Map<String, dynamic> _config;

  static Future<void> load() async {
    _instance = AppConfig();
    final data = await rootBundle.loadString('assets/app_config.json');
    _instance._config = json.decode(data);
  }

  double get splitRatio => (_config['split_ratio'] ?? 0.5).toDouble();
  int get maxPhotos => _config['max_photos'] ?? 50;
  bool get autoSave => _config['auto_save'] ?? false;
  bool get galleryPageIndicator => _config['gallery_page_indicator'] ?? true;
  bool get hapticFeedback => _config['haptic_feedback'] ?? true;
  double get previewAspectRatioMultiplier => (_config['preview_aspect_ratio_multiplier'] ?? 1.0).toDouble();
  String get defaultPrimaryLabel => _config['default_primary_label'] ?? '식재료';
  bool get aiEnabled => _config['ai_enabled'] ?? false;
  String get aiEndpoint => _config['ai_endpoint'] ?? '';
  String get aiApiKey => _aiApiKeyEnv.isNotEmpty ? _aiApiKeyEnv : (_config['ai_api_key'] ?? '');
  int get aiTimeoutMs => _config['ai_timeout_ms'] ?? 4000;
  String get stabilityApiKey => _stabilityApiKeyEnv.isNotEmpty
      ? _stabilityApiKeyEnv
      : (_config['stability_api_key'] ?? '');

  void debugPrintKeys() {
    debugPrint('🍳 GEMINI_API_KEY present: ${_aiApiKeyEnv.isNotEmpty}');
    debugPrint('🍳 STABILITY_API_KEY present: ${_stabilityApiKeyEnv.isNotEmpty}');
  }
  Map<String, String> get primaryLabelCategoryMap {
    final raw = _config['primary_label_category_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, value.toString()));
    }
    return {};
  }

  Map<String, String> get categoryDisplayMap {
    final raw = _config['category_display_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, value.toString()));
    }
    return {};
  }

  Map<String, String> get freshnessDisplayMap {
    final raw = _config['freshness_display_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, value.toString()));
    }
    return {};
  }

  Map<String, int> get shelfLifeDaysMap {
    final raw = _config['shelf_life_days_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, (value as num).toInt()));
    }
    return {};
  }

  Map<String, int> get shelfLifeDaysFrozenMap {
    final raw = _config['shelf_life_days_frozen_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, (value as num).toInt()));
    }
    return {};
  }

  Map<String, Map<String, String>> get freshnessStyleMap {
    final raw = _config['freshness_style_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) {
        if (value is Map<String, dynamic>) {
          return MapEntry(
            key,
            value.map((k, v) => MapEntry(k, v.toString())),
          );
        }
        return MapEntry(key, <String, String>{});
      });
    }
    return {};
  }

  Map<String, String> get amountDisplayMap {
    final raw = _config['amount_display_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, value.toString()));
    }
    return {};
  }

  Map<String, String> get usageRoleDisplayMap {
    final raw = _config['usage_role_display_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, value.toString()));
    }
    return {};
  }

  Map<String, String> get stateTagDisplayMap {
    final raw = _config['state_tag_display_map'];
    if (raw is Map<String, dynamic>) {
      return raw.map((key, value) => MapEntry(key, value.toString()));
    }
    return {};
  }

  Map<String, dynamic> get categoryHierarchy {
    final raw = _config['category_hierarchy'];
    if (raw is Map<String, dynamic>) {
      return raw;
    }
    return {};
  }

  List<String> get ocrScripts {
    final raw = _config['ocr_scripts'];
    if (raw is List) {
      return raw.map((e) => e.toString()).toList();
    }
    return const ['latin'];
  }

  List<Map<String, dynamic>> get materialIndex {
    final raw = _config['material_index'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  List<Map<String, String>> get recipeCategories {
    final raw = _config['recipe_categories'];
    if (raw is List) {
      return raw
          .whereType<Map<String, dynamic>>()
          .map((item) => {
                'id': item['id']?.toString() ?? '',
                'label': item['label']?.toString() ?? '',
                'icon': item['icon']?.toString() ?? '',
              })
          .where((item) => (item['id'] ?? '').isNotEmpty && (item['label'] ?? '').isNotEmpty)
          .toList();
    }
    return const [];
  }

  ResolutionPreset get cameraResolution {
    final resolution = _config['camera_resolution'] ?? 'high';
    switch (resolution) {
      case 'low':
        return ResolutionPreset.low;
      case 'medium':
        return ResolutionPreset.medium;
      case 'high':
        return ResolutionPreset.high;
      case 'veryHigh':
        return ResolutionPreset.veryHigh;
      case 'ultraHigh':
        return ResolutionPreset.ultraHigh;
      default:
        return ResolutionPreset.high;
    }
  }
}
