import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../../config/app_config.dart';
import '../dao/recipe_cache_dao.dart';
import '../dao/suggested_substitute_dao.dart';
import '../../models/recipe_recommendation.dart';

class RecipeRecommendationService {
  RecipeRecommendationService._();

  static final RecipeRecommendationService instance =
      RecipeRecommendationService._();

  final RecipeCacheDao _cacheDao = RecipeCacheDao();
  final SuggestedSubstituteDao _substituteDao = SuggestedSubstituteDao();

  Future<List<RecipeCard>> recommendDefault({
    required List<String> ingredients,
  }) async {
    return _requestRecipeCards(
      ingredients: ingredients,
      categoryId: null,
      categoryLabel: null,
    );
  }

  Future<List<RecipeCard>> recommendByCategory({
    required List<String> ingredients,
    required String categoryId,
    required String categoryLabel,
  }) async {
    return _requestRecipeCards(
      ingredients: ingredients,
      categoryId: categoryId,
      categoryLabel: categoryLabel,
    );
  }

  Future<bool> hasCachedCards({
    required List<String> ingredients,
    String? categoryId,
  }) async {
    final cacheKey = _buildCacheKey(
      kind: 'cards',
      ingredients: ingredients,
      categoryId: categoryId ?? '',
      recipeId: null,
    );
    final cached = await _cacheDao.getCache(cacheKey);
    return cached != null;
  }

  Future<List<String>> suggestIngredientSubstitutes({
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
    required String summary,
    required List<String> steps,
    required String missingIngredient,
  }) async {
    final normalizedMissing = _normalizeMissingIngredient(missingIngredient);
    final stored = await _substituteDao.getSubstitutes(
      recipeId: recipeId,
      missingIngredient: normalizedMissing,
    );
    if (stored.isNotEmpty) {
      return stored;
    }

    final cacheKey = _buildCacheKey(
      kind: 'subs',
      ingredients: ingredients,
      categoryId: null,
      recipeId: recipeId,
      recipeTitle: '$recipeTitle::$normalizedMissing',
    );

    final cached = await _cacheDao.getCache(cacheKey);
    if (cached != null) {
      final responseJson = jsonDecode(cached['response_json'] as String)
          as Map<String, dynamic>;
      final parsed = _parseSubstituteList(responseJson);
      if (parsed.isNotEmpty) {
        await _substituteDao.upsertSubstitutes(
          recipeId: recipeId,
          missingIngredient: normalizedMissing,
          substitutes: parsed,
        );
      }
      return parsed;
    }

    final response = await _postPrompt(
      _buildSubstitutePrompt(
        recipeTitle: recipeTitle,
        ingredients: ingredients,
        summary: summary,
        steps: steps,
        missingIngredient: missingIngredient,
      ),
    );

    await _cacheDao.upsertCache(
      cacheKey: cacheKey,
      kind: 'subs',
      recipeId: recipeId,
      requestPayload: {
        'recipeTitle': recipeTitle,
        'ingredients': ingredients,
        'summary': summary,
        'steps': steps,
        'missingIngredient': missingIngredient,
      },
      responseJson: response,
    );

    final parsed = _parseSubstituteList(response);
    if (parsed.isNotEmpty) {
      await _substituteDao.upsertSubstitutes(
        recipeId: recipeId,
        missingIngredient: normalizedMissing,
        substitutes: parsed,
      );
    }
    return parsed;
  }

  Future<bool> hasCachedSubstitutes({
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
    required String missingIngredient,
  }) async {
    final normalizedMissing = _normalizeMissingIngredient(missingIngredient);
    final stored = await _substituteDao.getSubstitutes(
      recipeId: recipeId,
      missingIngredient: normalizedMissing,
    );
    if (stored.isNotEmpty) {
      return true;
    }

    final cacheKey = _buildCacheKey(
      kind: 'subs',
      ingredients: ingredients,
      categoryId: null,
      recipeId: recipeId,
      recipeTitle: '$recipeTitle::$normalizedMissing',
    );

    final cached = await _cacheDao.getCache(cacheKey);
    return cached != null;
  }

  Future<RecipeDetail> fetchRecipeDetail({
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
    bool forceRefresh = false,
    String? categoryLabel,
  }) async {
    final requestPayload = {
      'recipeId': recipeId,
      'recipeTitle': recipeTitle,
      'categoryLabel': categoryLabel,
      'ingredients': _normalizeIngredients(ingredients),
    };
    final cacheKey = _buildCacheKey(
      kind: 'detail',
      ingredients: ingredients,
      categoryId: null,
      recipeId: recipeId,
      recipeTitle: recipeTitle,
    );

    if (!forceRefresh) {
      final cached = await _cacheDao.getCache(cacheKey);
      if (cached != null) {
        final responseJson = jsonDecode(cached['response_json'] as String)
            as Map<String, dynamic>;
        return _parseRecipeDetail(responseJson);
      }
    }

    final response = await _postPrompt(
      _buildDetailPrompt(
        recipeId: recipeId,
        recipeTitle: recipeTitle,
        ingredients: ingredients,
        categoryLabel: categoryLabel,
      ),
    );

    await _cacheDao.upsertCache(
      cacheKey: cacheKey,
      kind: 'detail',
      recipeId: recipeId,
      requestPayload: requestPayload,
      responseJson: response,
    );

    return _parseRecipeDetail(response);
  }

  Future<bool> hasCachedDetail({
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
  }) async {
    final cacheKey = _buildCacheKey(
      kind: 'detail',
      ingredients: ingredients,
      categoryId: null,
      recipeId: recipeId,
      recipeTitle: recipeTitle,
    );
    final cached = await _cacheDao.getCache(cacheKey);
    return cached != null;
  }

  Future<List<RecipeCard>> _requestRecipeCards({
    required List<String> ingredients,
    String? categoryId,
    String? categoryLabel,
  }) async {
    final normalizedIngredients = _normalizeIngredients(ingredients);
    final requestPayload = {
      'categoryId': categoryId ?? '',
      'categoryLabel': categoryLabel ?? '',
      'ingredients': normalizedIngredients,
    };
    final cacheKey = _buildCacheKey(
      kind: 'cards',
      ingredients: normalizedIngredients,
      categoryId: categoryId,
      recipeId: null,
    );

    final cached = await _cacheDao.getCache(cacheKey);
    if (cached != null) {
      final responseJson = jsonDecode(cached['response_json'] as String)
          as Map<String, dynamic>;
      return _parseRecipeCards(responseJson, categoryId ?? '');
    }

    final response = await _postPrompt(
      _buildCardsPrompt(
        ingredients: ingredients,
        categoryId: categoryId ?? '',
        categoryLabel: categoryLabel ?? '',
      ),
    );

    await _cacheDao.upsertCache(
      cacheKey: cacheKey,
      kind: 'cards',
      categoryId: categoryId ?? '',
      requestPayload: requestPayload,
      responseJson: response,
    );

    return _parseRecipeCards(response, categoryId ?? '');
  }

  String _buildCacheKey({
    required String kind,
    required List<String> ingredients,
    String? categoryId,
    String? recipeId,
    String? recipeTitle,
  }) {
    final payload = {
      'kind': kind,
      'categoryId': categoryId ?? '',
      'recipeId': recipeId ?? '',
      'recipeTitle': recipeTitle ?? '',
      'ingredients': _normalizeIngredients(ingredients),
    };
    return jsonEncode(payload);
  }

  List<String> _normalizeIngredients(List<String> ingredients) {
    final normalized = ingredients
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    normalized.sort();
    return normalized;
  }

  Future<Map<String, dynamic>> _postPrompt(String prompt) async {
    final apiKey = AppConfig.instance.aiApiKey;
    if (!AppConfig.instance.aiEnabled || apiKey.isEmpty) {
      debugPrint('🍳 레시피 AI 비활생성 또는 키 없음');
      throw StateError('AI disabled');
    }

    final endpoint = AppConfig.instance.aiEndpoint.trim();
    final uri = endpoint.isEmpty
        ? Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
          )
        : Uri.parse(endpoint);

    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text': prompt,
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.5,
        'maxOutputTokens': 1024,
      }
    });

    final timeout = Duration(milliseconds: AppConfig.instance.aiTimeoutMs);
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: requestBody,
        )
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Gemini API failed: ${response.statusCode}');
    }

    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  String _buildCardsPrompt({
    required List<String> ingredients,
    required String categoryId,
    required String categoryLabel,
  }) {
    final ingredientList = ingredients.isEmpty
        ? '없음'
        : ingredients.map((e) => '- $e').join('\n');

    final categoryLine = categoryId.isEmpty
      ? '카테고리 필터 없음'
      : '카테고리: $categoryLabel ($categoryId)';

    return '''
당신은 한국 가정식 레시피 추천 전문가입니다.
아래 재료 목록을 기반으로 가능한 요리를 추천하세요.

재료 목록:
$ingredientList

$categoryLine

요청:
- 가능한 요리 3가지를 추천합니다.
- 각 추천은 요리명, 요약, 핵심 재료 3~6개, 예상 소요시간(분)을 포함합니다.
- 재료 목록에 괄호로 표기된 양 정보를 고려해 추천하고, 양이 적은 재료를 우선 소진하도록 구생성하세요.
- 재료 항목에 `freshness: URGENT/USE_SOON/OK` 태그가 있으면 URGENT > USE_SOON > OK 순으로 우선 사용하세요.
- 없는 재료는 무리하게 추가하지 말고, 대체 재료는 요약에 간단히 언급하세요.
- 출력은 JSON 배열만 허용합니다. 추가 문장, 마크다운, 주석 금지.

출력 형식:
[
  {
    "id": "string",
    "title": "string",
    "summary": "string",
    "mainIngredients": ["string"],
    "timeMinutes": 20
  }
]
''';
  }

  String _buildDetailPrompt({
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
    String? categoryLabel,
  }) {
    final ingredientList = ingredients.isEmpty
      ? '없음'
      : ingredients.map((e) => '- $e').join('\n');

    final categoryLine =
      categoryLabel == null ? '' : '카테고리: $categoryLabel\n';

    return '''
당신은 한국 가정식 레시피를 자세히 안내하는 요리 전문가입니다.
아래 재료와 요리명을 기반으로 레시피 상세를 작생성하세요.

요리명: $recipeTitle
$categoryLine재료 목록:
$ingredientList

요청:
- 재료 목록, 조리 순서(5~10단계), 간단 요약, 팁(선택), 예상 소요시간(분), 분량을 포함합니다.
- 대표 이미지 URL(imageUrl)은 가능한 경우 https URL을 제공하고, 없으면 빈 문자열로 둡니다.
- 재료 목록에 괄호로 표기된 양 정보를 고려해 가능한 범위에서 분량과 사용량을 제시하세요.
- 재료 항목에 `freshness: URGENT/USE_SOON/OK` 태그가 있으면 URGENT > USE_SOON > OK 순으로 우선 사용하도록 구생성하세요.
- 모든 텍스트는 한국어로만 작생성합니다. 영어/로마자/외국어 사용 금지.
- 출력은 JSON 객체만 허용합니다. 추가 문장, 마크다운, 주석 금지.

출력 형식:
{
  "id": "$recipeId",
  "title": "string",
  "summary": "string",
  "imageUrl": "https://...",
  "ingredients": ["string"],
  "steps": ["string"],
  "tips": "string",
  "timeMinutes": 20,
  "servings": "2인분"
}
''';
  }

  String _buildSubstitutePrompt({
    required String recipeTitle,
    required List<String> ingredients,
    required String summary,
    required List<String> steps,
    required String missingIngredient,
  }) {
    final ingredientList = ingredients.isEmpty
        ? '없음'
        : ingredients.map((e) => '- $e').join('\n');
    final stepHint = steps.isEmpty ? '' : steps.first;

    return '''
당신은 한국 가정식 레시피 대체재 추천 전문가입니다.
레시피 맥락과 조리법에 맞는 대체 재료를 추천하세요.

요리명: $recipeTitle
빠진 재료: $missingIngredient
재료 목록:
$ingredientList
요약:
$summary
조리 힌트:
$stepHint

요청:
- 대체 재료 3~5개를 추천합니다.
- 대체재는 조리법과 맛/식감에 어울리는 것으로만 고릅니다.
- 없는 재료를 무리하게 복잡한 재료로 대체하지 않습니다.
- 출력은 JSON 배열만 허용합니다. 추가 문장, 마크다운, 주석 금지.

출력 형식:
[
  "string",
  "string"
]
''';
  }

  List<RecipeCard> _parseRecipeCards(
    Map<String, dynamic> response,
    String categoryId,
  ) {
    final text = _extractText(response);
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (jsonMatch == null) {
      throw const FormatException('No JSON array found');
    }

    final parsed = jsonDecode(jsonMatch.group(0)!) as List<dynamic>;
    return parsed
        .whereType<Map<String, dynamic>>()
        .map((item) {
          final card = RecipeCard.fromJson(item);
          final resolvedId = card.id.isNotEmpty
              ? card.id
              : _fallbackRecipeId(card.title, categoryId);
          return RecipeCard(
            id: resolvedId,
            title: card.title,
            summary: card.summary,
            mainIngredients: card.mainIngredients,
            timeMinutes: card.timeMinutes,
            categoryId: categoryId,
          );
        })
        .toList();
  }

  String _fallbackRecipeId(String title, String? categoryId) {
    final base = '${categoryId ?? ''}::$title'.trim();
    return base64UrlEncode(utf8.encode(base));
  }

  RecipeDetail _parseRecipeDetail(Map<String, dynamic> response) {
    final text = _extractText(response);
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch == null) {
      throw const FormatException('No JSON object found');
    }

    final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
    return RecipeDetail.fromJson(parsed);
  }

  List<String> _parseSubstituteList(Map<String, dynamic> response) {
    final text = _extractText(response);
    final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(text);
    if (jsonMatch == null) {
      return const [];
    }
    final parsed = jsonDecode(jsonMatch.group(0)!) as List<dynamic>;
    return parsed.map((item) => item.toString()).toList();
  }

  String _normalizeMissingIngredient(String value) {
    final head = value.split('(').first;
    final cleaned = head.replaceAll(RegExp(r'[^\w\s가-힣]'), ' ');
    return cleaned.replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase();
  }


  Future<String?> getGeneratedRecipeImagePath({
    required String recipeId,
    required String recipeTitle,
  }) async {
    final file = await _getGeneratedImageFile(
      recipeId: recipeId,
      recipeTitle: recipeTitle,
    );
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  Future<String?> generateRecipeImage({
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
    required String summary,
    required List<String> steps,
    bool force = false,
    String? categoryLabel,
  }) async {
    final file = await _getGeneratedImageFile(
      recipeId: recipeId,
      recipeTitle: recipeTitle,
    );
    if (await file.exists()) {
      if (!force) {
        return file.path;
      }
      try {
        await file.delete();
      } catch (_) {}
    }

    final apiKey = AppConfig.instance.stabilityApiKey.trim();
    debugPrint('🍳 stability api key present: ${apiKey.isNotEmpty}');
    if (apiKey.isEmpty) {
      return null;
    }

    final promptData = await _getEnglishImagePromptData(
      recipeId: recipeId,
      recipeTitle: recipeTitle,
      ingredients: ingredients,
      summary: summary,
      steps: steps,
      categoryLabel: categoryLabel,
    );

    final prompt = _buildRecipeImagePrompt(
      title: promptData.title,
      ingredients: promptData.ingredients,
      summary: promptData.summary,
      stepHint: promptData.stepHint,
      categoryLabel: promptData.categoryLabel,
    );

    final response = await http.post(
      Uri.parse(
        'https://api.stability.ai/v1/generation/stable-diffusion-xl-1024-v1-0/text-to-image',
      ),
      headers: {
        'Authorization': 'Bearer $apiKey',
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
      body: jsonEncode({
        'text_prompts': [
          {'text': prompt, 'weight': 1},
          {
            'text': 'blurry, low quality, text, watermark, logo, people',
            'weight': -1,
          },
        ],
        'cfg_scale': 6,
        'height': 1024,
        'width': 1024,
        'samples': 1,
        'steps': 15,
      }),
    );

    debugPrint('🍳 stability status: ${response.statusCode}');
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('🍳 stability error body: ${response.body}');
      return null;
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    final artifacts = decoded['artifacts'] as List<dynamic>?;
    if (artifacts == null || artifacts.isEmpty) {
      return null;
    }

    final first = artifacts.first as Map<String, dynamic>;
    final base64Data = first['base64'] as String?;
    if (base64Data == null || base64Data.isEmpty) {
      return null;
    }

    final bytes = base64Decode(base64Data);
    await file.writeAsBytes(bytes);
    return file.path;
  }

  Future<File> _getGeneratedImageFile({
    required String recipeId,
    required String recipeTitle,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final imagesDir = Directory('${dir.path}/recipe_images_generated');
    if (!await imagesDir.exists()) {
      await imagesDir.create(recursive: true);
    }

    final fileKey = _hashImageKey('gen::$recipeId::$recipeTitle');
    return File('${imagesDir.path}/$fileKey.png');
  }

  String _buildRecipeImagePrompt({
    required String title,
    required List<String> ingredients,
    required String summary,
    required String stepHint,
    required String categoryLabel,
  }) {
    final mainIngredients = ingredients
        .map((item) => item.split('(').first.trim())
        .where((item) => item.isNotEmpty)
        .take(6)
        .map(_toEnglishPromptToken)
        .where((item) => item.isNotEmpty)
        .toList()
        .join(', ');
    final labelPart = _toEnglishPromptToken(categoryLabel.trim());
    final trimmedSummary = _toEnglishPromptToken(summary.trim());
    final safeStepHint = _toEnglishPromptToken(stepHint.trim());
    final safeTitle = _toEnglishPromptToken(title.trim());
    final titleLabel =
      safeTitle.isNotEmpty ? safeTitle : 'Korean home-cooked dish';

    final parts = <String>[
      'Korean home-cooked dish photo of $titleLabel',
      if (labelPart.isNotEmpty) labelPart,
      if (mainIngredients.isNotEmpty) 'ingredients: $mainIngredients',
      if (trimmedSummary.isNotEmpty) 'description: $trimmedSummary',
      if (safeStepHint.isNotEmpty) 'prep hint: $safeStepHint',
      'portion size strictly follows the quantities; do not overfill the plate',
      'small amounts must look small; do not upscale ingredients',
      'natural lighting, plated, appetizing, high detail, no text, no watermark',
    ];

    return parts.join(', ');
  }

  Future<_EnglishImagePromptData> _getEnglishImagePromptData({
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
    required String summary,
    required List<String> steps,
    String? categoryLabel,
  }) async {
    final cacheKey = _buildCacheKey(
      kind: 'image_prompt_en',
      ingredients: ingredients,
      categoryId: categoryLabel,
      recipeId: recipeId,
      recipeTitle: recipeTitle,
    );

    final cached = await _cacheDao.getCache(cacheKey);
    if (cached != null) {
      final responseJson = jsonDecode(cached['response_json'] as String)
          as Map<String, dynamic>;
      return _parseEnglishImagePrompt(
        responseJson,
        fallbackTitle: recipeTitle,
        fallbackIngredients: ingredients,
      );
    }

    final requestPayload = {
      'recipeId': recipeId,
      'recipeTitle': recipeTitle,
      'categoryLabel': categoryLabel,
      'ingredients': ingredients,
      'summary': summary,
      'steps': steps,
    };

    try {
      final response = await _postPrompt(
        _buildEnglishImagePrompt(
          recipeTitle: recipeTitle,
          ingredients: ingredients,
          summary: summary,
          steps: steps,
          categoryLabel: categoryLabel ?? '',
        ),
      );

      await _cacheDao.upsertCache(
        cacheKey: cacheKey,
        kind: 'image_prompt_en',
        recipeId: recipeId,
        requestPayload: requestPayload,
        responseJson: response,
      );

      return _parseEnglishImagePrompt(
        response,
        fallbackTitle: recipeTitle,
        fallbackIngredients: ingredients,
      );
    } catch (e) {
      debugPrint('🍳 english prompt generation failed: $e');
      return _EnglishImagePromptData.fromFallback(
        title: recipeTitle,
        ingredients: ingredients,
        summary: summary,
        stepHint: steps.isEmpty ? '' : steps.first,
        categoryLabel: categoryLabel ?? '',
      );
    }
  }

  String _buildEnglishImagePrompt({
    required String recipeTitle,
    required List<String> ingredients,
    required String summary,
    required List<String> steps,
    required String categoryLabel,
  }) {
    final ingredientList = ingredients.isEmpty
        ? 'none'
        : ingredients.map((e) => '- $e').join('\n');
    final stepHint = steps.isEmpty ? '' : steps.first;
    final categoryLine = categoryLabel.trim().isEmpty
        ? 'category: none'
        : 'category: $categoryLabel';

    return '''
You are a translator and food editor.
Translate the recipe data into English only (ASCII characters). Do not use any Korean.
Preserve ingredient quantities/amounts and portion sizes accurately.
The image should reflect the quantities (small amounts look small, large amounts look plentiful).
If a quantity is small, explicitly describe it as a small amount (e.g., "1 shrimp", "a few slices").
Never upscale amounts or add extra ingredients.
Output a JSON object only. No extra text.

Recipe title: $recipeTitle
$categoryLine
Ingredients:
$ingredientList
Summary:
$summary
Step hint:
$stepHint

Output format:
{
  "title_en": "string",
  "summary_en": "string",
  "ingredients_en": ["string"],
  "step_hint_en": "string",
  "category_en": "string"
}
''';
  }

  _EnglishImagePromptData _parseEnglishImagePrompt(
    Map<String, dynamic> response, {
    required String fallbackTitle,
    required List<String> fallbackIngredients,
  }) {
    final text = _extractText(response);
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (jsonMatch == null) {
      return _EnglishImagePromptData.fromFallback(
        title: fallbackTitle,
        ingredients: fallbackIngredients,
        summary: '',
        stepHint: '',
        categoryLabel: '',
      );
    }

    final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
    return _EnglishImagePromptData(
      title: parsed['title_en']?.toString() ?? fallbackTitle,
      summary: parsed['summary_en']?.toString() ?? '',
      ingredients: (parsed['ingredients_en'] as List<dynamic>? ?? [])
          .map((e) => e.toString())
          .toList(),
      stepHint: parsed['step_hint_en']?.toString() ?? '',
      categoryLabel: parsed['category_en']?.toString() ?? '',
    );
  }

  String _toEnglishPromptToken(String value) {
    final asciiOnly = value.replaceAll(RegExp(r'[^\x20-\x7E]'), ' ');
    return asciiOnly.replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _hashImageKey(String value) {
    const int fnvPrime = 1099511628211;
    const int fnvOffset = 1469598103934665603;
    var hash = fnvOffset;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * fnvPrime) & 0xFFFFFFFFFFFFFFFF;
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  String _extractText(Map<String, dynamic> response) {
    final candidates = response['candidates'] as List<dynamic>?;
    if (candidates == null || candidates.isEmpty) {
      throw const FormatException('No candidates in response');
    }

    final content = candidates[0]['content'] as Map<String, dynamic>;
    final parts = content['parts'] as List<dynamic>?;
    if (parts == null || parts.isEmpty) {
      throw const FormatException('No parts in content');
    }

    final text = parts[0]['text'] as String?;
    if (text == null) {
      throw const FormatException('No text in parts');
    }

    return text;
  }
}

class _EnglishImagePromptData {
  final String title;
  final String summary;
  final List<String> ingredients;
  final String stepHint;
  final String categoryLabel;

  const _EnglishImagePromptData({
    required this.title,
    required this.summary,
    required this.ingredients,
    required this.stepHint,
    required this.categoryLabel,
  });

  factory _EnglishImagePromptData.fromFallback({
    required String title,
    required List<String> ingredients,
    required String summary,
    required String stepHint,
    required String categoryLabel,
  }) {
    return _EnglishImagePromptData(
      title: title,
      summary: summary,
      ingredients: ingredients,
      stepHint: stepHint,
      categoryLabel: categoryLabel,
    );
  }
}
