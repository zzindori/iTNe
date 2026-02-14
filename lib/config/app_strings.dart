import 'dart:convert';
import 'package:flutter/services.dart';

class AppStrings {
  static late AppStrings _instance;
  static AppStrings get instance => _instance;

  late Map<String, dynamic> _strings;

  static Future<void> load() async {
    _instance = AppStrings();
    final data = await rootBundle.loadString('assets/app_strings.json');
    _instance._strings = json.decode(data);
  }

  String get(String key, {Map<String, String>? params}) {
    String value = _strings[key] ?? key;
    
    if (params != null) {
      params.forEach((key, val) {
        value = value.replaceAll('{$key}', val);
      });
    }
    
    return value;
  }

  String get appTitle => get('app_title');
  String get emptyGalleryMessage => get('empty_gallery_message');
  String get captureButtonTooltip => get('capture_button_tooltip');
  String get saveButton => get('save_button');
  String get deleteButton => get('delete_button');
  String get markIncorrect => get('mark_incorrect');
  String get cameraInitializing => get('camera_initializing');
  String get cameraError => get('camera_error');
  String get saveSuccess => get('save_success');
  String get deleteConfirm => get('delete_confirm');
  String get cancelButton => get('cancel_button');
  String get historyTitle => get('history_title');
  String get historyAppBarTitle => get('history_appbar_title');
  String get historySearchTitle => get('history_search_title');
  String get historySearchHint => get('history_search_hint');
  String get historySearchClear => get('history_search_clear');
  String get historySearchEmpty => get('history_search_empty');
  String get historyTabEmpty => get('history_tab_empty');
  String get historyEmpty => get('history_empty');
  String get historyDetailTitle => get('history_detail_title');
  String get historyDeleteSuccess => get('history_delete_success');
  String get historyReanalyze => get('history_reanalyze');
  String get historyReanalyzeStarted => get('history_reanalyze_started');
  String get recipeTitle => get('recipe_title');
  String get recipeDefaultSection => get('recipe_default_section');
  String get recipeCategorySection => get('recipe_category_section');
  String get recipeSelectCategory => get('recipe_select_category');
  String get recipeLoading => get('recipe_loading');
  String get recipeError => get('recipe_error');
  String get recipeEmpty => get('recipe_empty');
  String get recipeRetry => get('recipe_retry');
  String get recipeDetailTitle => get('recipe_detail_title');
  String get recipeDetailIngredients => get('recipe_detail_ingredients');
  String get recipeDetailSteps => get('recipe_detail_steps');
  String get recipeDetailTips => get('recipe_detail_tips');
  String get recipeDetailTime => get('recipe_detail_time');
  String get recipeDetailServings => get('recipe_detail_servings');
    String get recipeDetailImageTapGenerate =>
      get('recipe_detail_image_tap_generate');
    String get recipeDetailImageGenerating =>
      get('recipe_detail_image_generating');
    String get recipeDetailImageGenerateFailed =>
      get('recipe_detail_image_generate_failed');
  String get recipeButtonTooltip => get('recipe_button_tooltip');
  String get recipeNavHome => get('recipe_nav_home');
  String get recipeNavGallery => get('recipe_nav_gallery');
  String get freshnessUrgentIcon => get('freshness_urgent_icon');
  String get freshnessUseSoonIcon => get('freshness_use_soon_icon');
  String get freshnessOkIcon => get('freshness_ok_icon');
  String get freshnessUrgentDesc => get('freshness_urgent_desc');
  String get freshnessUseSoonDesc => get('freshness_use_soon_desc');
  String get freshnessOkDesc => get('freshness_ok_desc');
  String get freshnessHelpOk => get('freshness_help_ok');
  String get historyAll => get('history_all');
  String get historyFilterLevel2 => get('history_filter_level2');
  String get historyFilterLevel3 => get('history_filter_level3');
  String get editTitle => get('edit_title');
  String get editLevel1 => get('edit_level1');
  String get editLevel2 => get('edit_level2');
  String get editLevel3 => get('edit_level3');
  String get editApply => get('edit_apply');
  String get editUpdated => get('edit_updated');

  String maxPhotosWarning(int count) => get('max_photos_warning', params: {'count': count.toString()});
  String get timeJustNow => get('time_just_now');
  String timeMinutesAgo(int count) => get('time_minutes_ago', params: {'count': count.toString()});
  String timeHoursAgo(int count) => get('time_hours_ago', params: {'count': count.toString()});
  String timeDaysAgo(int count) => get('time_days_ago', params: {'count': count.toString()});
  
  String photoCount(int count) => get('photo_count', params: {'count': count.toString()});
  
  // Debug messages
  String get debugInitStart => get('debug_init_start');
  String get debugCameraPermissionRequesting => get('debug_camera_permission_requesting');
  String get debugCameraPermissionDenied => get('debug_camera_permission_denied');
  String get debugCameraPermissionGranted => get('debug_camera_permission_granted');
  String get debugCameraPermissionPermanentlyDenied => get('debug_camera_permission_permanently_denied');
  String get debugCameraChecking => get('debug_camera_checking');
  String debugCameraCount(int count) => get('debug_camera_count', params: {'count': count.toString()});
  String get debugCreditInitializing => get('debug_credit_initializing');
}
