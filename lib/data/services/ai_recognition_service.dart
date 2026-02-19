import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../config/app_config.dart';
import '../dao/capture_dao.dart';
import '../../models/ai_result.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;

class AiRecognitionService {
  AiRecognitionService._();

  static final AiRecognitionService instance = AiRecognitionService._();

  final CaptureDao _dao = CaptureDao();
  final ValueNotifier<int> revision = ValueNotifier(0);
  final List<_RecognitionTask> _queue = [];
  bool _running = false;
  final Map<TextRecognitionScript, TextRecognizer> _recognizers = {};
  static const List<String> _allowedCategories = [
    'MEAT',
    'SEAFOOD',
    'VEG',
    'FRUIT',
    'DAIRY_EGG',
    'GRAIN_NOODLE',
    'SAUCE',
    'DRINK',
    'PROCESSED',
    'ETC',
  ];

  void enqueueRecognition({
    required String captureId,
    required String filePath,
  }) {
    enqueueRecognitionAndWait(captureId: captureId, filePath: filePath);
  }

  Future<bool> enqueueRecognitionAndWait({
    required String captureId,
    required String filePath,
  }) async {
    final shouldEnqueue = await _shouldEnqueue(captureId);
    if (!shouldEnqueue) {
      debugPrint('🧠 AI 큐 스킵(이미 실패/완료): $captureId');
      return false;
    }

    debugPrint('🧠 AI 큐 추가: $captureId');
    final completer = Completer<bool>();
    _queue.add(
      _RecognitionTask(
        captureId: captureId,
        filePath: filePath,
        completer: completer,
      ),
    );
    _runNext();
    return completer.future;
  }

  void _runNext() {
    if (_running || _queue.isEmpty) {
      return;
    }
    _running = true;
    final task = _queue.removeAt(0);
    _process(task).then((success) {
      if (task.completer != null && !task.completer!.isCompleted) {
        task.completer!.complete(success);
      }
    }).catchError((_) {
      if (task.completer != null && !task.completer!.isCompleted) {
        task.completer!.complete(false);
      }
    }).whenComplete(() {
      _running = false;
      _runNext();
    });
  }

  Future<bool> _shouldEnqueue(String captureId) async {
    try {
      final record = await _dao.getCapture(captureId);
      if (record.modelVersion == 'ai-error') {
        return false;
      }
      if (record.modelVersion?.isNotEmpty ?? false) {
        return false;
      }
      return true;
    } catch (_) {
      return true;
    }
  }

  Future<bool> _process(_RecognitionTask task) async {
    await _dao.insertAiRequestedEvent(task.captureId);
    try {
      debugPrint('🧠 AI 처리 시작: ${task.captureId}');
      final result = await _recognize(task);
      final normalized = _applyFallback(result);
      if (_isNonIngredient(normalized)) {
        debugPrint('🧠 AI 결과 비식재료(실패 처리): ${task.captureId}');
        await _dao.updateFromAiResult(normalized);
        revision.value++;
        return true;
      }
      await _dao.updateFromAiResult(normalized);
      revision.value++;
      debugPrint('🧠 AI 처리 완료: ${task.captureId}');
      return true;
    } catch (e) {
      debugPrint('🧠 AI 처리 실패: ${task.captureId} / $e');
      await _dao.markAiFailed(task.captureId, e.toString());
      revision.value++;
      return false;
    }
  }

  Future<AiResult> _recognize(_RecognitionTask task) async {
    final signal = await _readOcrSignal(task.filePath);
    final apiKey = AppConfig.instance.aiApiKey;
    if (!AppConfig.instance.aiEnabled || apiKey.isEmpty) {
      debugPrint('🧠 AI 비활생성 또는 키 없음: enabled=${AppConfig.instance.aiEnabled}, key=${apiKey.isNotEmpty}');
      return _buildOcrResult(task, signal);
    }

    final endpoint = AppConfig.instance.aiEndpoint.trim();
    final uri = endpoint.isEmpty
        ? Uri.parse(
            'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$apiKey',
          )
        : Uri.parse(endpoint);

    final imageBytes = await File(task.filePath).readAsBytes();
    final base64Image = base64Encode(imageBytes);
    final ocrHint = _buildOcrHint(signal);

    final requestBody = jsonEncode({
      'contents': [
        {
          'parts': [
            {
              'text': _buildPrompt(ocrHint: ocrHint),
            },
            {
              'inline_data': {
                'mime_type': 'image/jpeg',
                'data': base64Image,
              }
            }
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.4,
        'maxOutputTokens': 1024,
      }
    });

    final timeout = Duration(milliseconds: AppConfig.instance.aiTimeoutMs);
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    ).timeout(timeout);

    debugPrint('🧠 AI 응답 코드: ${response.statusCode}');

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Gemini API failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseGeminiResponse(task.captureId, decoded);
  }

  Future<List<Map<String, dynamic>>> suggestMaterialCandidates({
    required String query,
    required List<Map<String, dynamic>> topHits,
  }) async {
    final apiKey = AppConfig.instance.aiApiKey;
    if (!AppConfig.instance.aiEnabled || apiKey.isEmpty) {
      debugPrint('🧠 AI 비활생성 또는 키 없음: enabled=${AppConfig.instance.aiEnabled}, key=${apiKey.isNotEmpty}');
      return const [];
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
              'text': _buildMaterialIndexPrompt(query: query, topHits: topHits),
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.3,
        'maxOutputTokens': 512,
      }
    });

    final timeout = Duration(milliseconds: AppConfig.instance.aiTimeoutMs);
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: requestBody,
    ).timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException('Gemini API failed: ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body) as Map<String, dynamic>;
    return _parseMaterialCandidates(decoded);
  }

  String _buildMaterialIndexPrompt({
    required String query,
    required List<Map<String, dynamic>> topHits,
  }) {
    final hitsJson = jsonEncode(topHits.take(10).toList());
    return '''
당신은 한국 가정용 식재료와 식품 분류 전문가입니다.

요청:
- 사용자가 입력한 검색어 Q를 기준으로 material_index에 추가될 후보를 제안합니다.
- category_hierarchy는 절대 수정하지 않습니다.
- 최대 2~6개 후보만 제시하세요.
- 후보는 서로 다른 실제 품목이어야 합니다.

Q: $query

현재 로컬 검색 힌트(중복 방지용):
$hitsJson

출력은 JSON 배열만 허용됩니다. 추가 문장, 마크다운, 주석 금지.
각 후보 형식:
{
  "keyword": string,
  "category": "MEAT|SEAFOOD|VEG|FRUIT|DAIRY_EGG|GRAIN_NOODLE|SAUCE|DRINK|PROCESSED|ETC",
  "primaryLabel": string,
  "secondaryLabel": string,
  "stateTags": string[],
  "aliases": string[],
  "source": string
}
''';
  }

  List<Map<String, dynamic>> _parseMaterialCandidates(Map<String, dynamic> response) {
    try {
      final candidates = response['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        return const [];
      }

      final content = candidates[0]['content'] as Map<String, dynamic>;
      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        return const [];
      }

      final text = parts[0]['text'] as String?;
      if (text == null) {
        return const [];
      }

      final jsonMatch = RegExp(r'\[[\s\S]*\]').firstMatch(text);
      if (jsonMatch == null) {
        return const [];
      }

      final parsed = jsonDecode(jsonMatch.group(0)!) as List<dynamic>;
      final result = <Map<String, dynamic>>[];
      for (final item in parsed) {
        if (item is! Map<String, dynamic>) {
          continue;
        }
        final keyword = item['keyword']?.toString() ?? '';
        final category = item['category']?.toString() ?? 'ETC';
        if (keyword.trim().isEmpty || !_allowedCategories.contains(category)) {
          continue;
        }
        result.add({
          'keyword': keyword,
          'category': category,
          'primaryLabel': item['primaryLabel']?.toString() ??
              AppConfig.instance.defaultPrimaryLabel,
          'secondaryLabel': item['secondaryLabel']?.toString() ?? '',
          'stateTags': (item['stateTags'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          'aliases': (item['aliases'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              const [],
          'source': item['source']?.toString() ?? 'ai_suggested',
        });
      }
      return result;
    } catch (e) {
      debugPrint('🧠 material_index 파싱 실패: $e');
      return const [];
    }
  }

  String _buildPrompt({String? ocrHint}) {
    return '''
당신은 아주 훌륭한 셰프이며, 냉장고 속 식재료와 포장 제품을 선별하고
신선도와 사용 가능성을 판단하는 데 탁월한 전문가입니다.
사진 속에 보이는 대상이 실제 요리에 사용 가능한 식재료인지,
또는 가공·포장된 식품(완제품, 반조리, 소스, 음료 등)인지 구분하여 판단하고,
전문가의 시선으로 가장 적절한 분류와 상태를 결정하세요.

${ocrHint == null || ocrHint.isEmpty ? '' : 'OCR_HINT:\n$ocrHint\n'}

아래 JSON 형식으로만 응답하세요. 설명이나 추가 문장은 절대 포함하지 마세요.

{
  "category": "MEAT|SEAFOOD|VEG|FRUIT|DAIRY_EGG|GRAIN_NOODLE|SAUCE|DRINK|PROCESSED|ETC",
  "primaryLabel": "고기",
  "secondaryLabel": "닭가슴살",
  "description": "짧은 요약 문장",
  "secondaryLabelGuess": true,
  "stateTags": ["raw", "packaged"],
  "freshnessHint": "OK|USE_SOON|URGENT",
  "shelfLifeDays": 7,
  "amountLabel": "LOW|MEDIUM|HIGH",
  "usageRole": "MAIN_INGREDIENT|SIDE|SEASONING",
  "confidence": 0.85
}

판단 규칙:
- category는 반드시 지정된 enum 중 하나만 사용
- primaryLabel은 category_hierarchy의 1단계 그룹(예: "돼지고기", "잎채소", "냉동", "장류")으로 선택
- secondaryLabel은 primaryLabel 하위 아이템(예: "삼겹살", "상추", "만두", "간장")만 사용
- category_hierarchy는 절대 수정하지 않는다. 변경 제안이 필요하면 material_index 안의 새 항목만 제안
- material_index에 새 항목을 제안/생생성할 경우 반드시 source 필드를 포함
- 식재료가 아니라고 판단되면:
  - category = ETC
  - primaryLabel = "비식재료"
  - confidence = 0.0
- OCR_HINT에 텍스트가 있고 포장/제품 키워드가 보이면 포장/가공식품(또는 음료/소스) 우선 고려
- 식재료이지만 종류가 불확실하면:
  - secondaryLabel = null
  - secondaryLabelGuess = true
- 보관 위치는 stateTags로 반드시 포함: chilled|frozen|room 중 하나
- 주류로 판단되면 stateTags에 alcohol 포함
- 매우 불확실한 경우 category = ETC
- freshnessHint는 포장 상태, 색상, 윤기 등 **시각 정보만**으로 판단
- shelfLifeDays는 식재료별 일반적인 냉장 보관 기준 일수(정수)로 추정
- 단, stateTags에 frozen이 포함된 경우에만 냉동 보관 기준 일수로 추정
- 기준 예시: 냉장 오이 7일, 냉동 오이 21일
- 양을 판단하기 어렵다면 amountLabel = null
- JSON 객체만 출력하고, 설명·마크다운·주석은 절대 금지
''';
  }

  AiResult _parseGeminiResponse(String captureId, Map<String, dynamic> response) {
    try {
      final candidates = response['candidates'] as List<dynamic>?;
      if (candidates == null || candidates.isEmpty) {
        throw FormatException('No candidates in response');
      }

      final content = candidates[0]['content'] as Map<String, dynamic>;
      final parts = content['parts'] as List<dynamic>?;
      if (parts == null || parts.isEmpty) {
        throw FormatException('No parts in content');
      }

      final text = parts[0]['text'] as String?;
      if (text == null) {
        throw FormatException('No text in parts');
      }

      final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(text);
      if (jsonMatch == null) {
        throw FormatException('No JSON found in response');
      }

      final aiData = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
      debugPrint('🧠 AI 응답 텍스트: $text');
      debugPrint('🧠 AI 파싱 JSON: ${jsonEncode(aiData)}');

      final normalizedCategory = _normalizeCategory(
        aiData['category'] as String?,
        aiData['primaryLabel'] as String?,
      );

      final rawTags = (aiData['stateTags'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const [];
      final normalizedTags = _normalizeStateTags(rawTags);

      return AiResult(
        captureId: captureId,
        category: normalizedCategory,
        primaryLabel: (aiData['primaryLabel'] as String?) ??
            AppConfig.instance.defaultPrimaryLabel,
        secondaryLabel: aiData['secondaryLabel'] as String?,
        secondaryLabelGuess: (aiData['secondaryLabelGuess'] as bool?) ?? true,
        stateTags: normalizedTags,
        freshnessHint: aiData['freshnessHint'] as String?,
        shelfLifeDays: _resolveShelfLifeDays(
          aiData['shelfLifeDays'],
          aiData['secondaryLabel'] as String?,
          aiData['primaryLabel'] as String?,
          normalizedTags,
        ),
        amountLabel: aiData['amountLabel'] as String?,
        usageRole: aiData['usageRole'] as String?,
        confidence: (aiData['confidence'] as num?)?.toDouble() ?? 0.0,
        modelVersion: 'gemini-2.0-flash-exp',
        rawJson: {
          'parsed': aiData,
          'response': response,
        },
        createdAt: DateTime.now(),
      );
    } catch (e) {
      return AiResult(
        captureId: captureId,
        category: 'ETC',
        primaryLabel: AppConfig.instance.defaultPrimaryLabel,
        secondaryLabel: null,
        secondaryLabelGuess: false,
        stateTags: const [],
        freshnessHint: null,
        shelfLifeDays: null,
        amountLabel: null,
        usageRole: null,
        confidence: 0.0,
        modelVersion: 'gemini-2.0-flash-exp-error',
        rawJson: {'error': e.toString(), 'rawResponse': response},
        createdAt: DateTime.now(),
      );
    }
  }

  String _normalizeCategory(String? category, String? primaryLabel) {
    const allowed = {
      'MEAT',
      'SEAFOOD',
      'VEG',
      'FRUIT',
      'DAIRY_EGG',
      'GRAIN_NOODLE',
      'SAUCE',
      'DRINK',
      'PROCESSED',
      'ETC',
    };

    final rawCategory = (category ?? '').trim();
    if (rawCategory.isNotEmpty && allowed.contains(rawCategory)) {
      return rawCategory;
    }

    final label = (primaryLabel ?? '').trim();
    if (label.isNotEmpty) {
      final mapped = AppConfig.instance.primaryLabelCategoryMap[label];
      if (mapped != null && allowed.contains(mapped)) {
        return mapped;
      }
    }

    return 'ETC';
  }


  AiResult _applyFallback(AiResult result) {
    final normalizedTags = _normalizeStateTags(result.stateTags);
    final base = _withStateTags(result, normalizedTags);
    if (base.primaryLabel.trim() == '비식재료') {
      return base;
    }
    if ((base.confidence ?? 0.0) < 0.3) {
      return AiResult(
        captureId: base.captureId,
        category: 'ETC',
        primaryLabel: AppConfig.instance.defaultPrimaryLabel,
        secondaryLabel: null,
        secondaryLabelGuess: false,
        stateTags: base.stateTags,
        freshnessHint: base.freshnessHint,
        shelfLifeDays: base.shelfLifeDays,
        amountLabel: base.amountLabel,
        usageRole: base.usageRole,
        confidence: base.confidence,
        modelVersion: base.modelVersion,
        rawJson: base.rawJson,
        createdAt: base.createdAt,
      );
    }

    if ((base.confidence ?? 0.0) < 0.55) {
      return AiResult(
        captureId: base.captureId,
        category: base.category,
        primaryLabel: base.primaryLabel,
        secondaryLabel: null,
        secondaryLabelGuess: false,
        stateTags: base.stateTags,
        freshnessHint: base.freshnessHint,
        shelfLifeDays: base.shelfLifeDays,
        amountLabel: base.amountLabel,
        usageRole: base.usageRole,
        confidence: base.confidence,
        modelVersion: base.modelVersion,
        rawJson: base.rawJson,
        createdAt: base.createdAt,
      );
    }

    return base;
  }

  AiResult _withStateTags(AiResult result, List<String> stateTags) {
    if (stateTags == result.stateTags) {
      return result;
    }
    return AiResult(
      captureId: result.captureId,
      category: result.category,
      primaryLabel: result.primaryLabel,
      secondaryLabel: result.secondaryLabel,
      secondaryLabelGuess: result.secondaryLabelGuess,
      stateTags: stateTags,
      freshnessHint: result.freshnessHint,
      shelfLifeDays: result.shelfLifeDays,
      amountLabel: result.amountLabel,
      usageRole: result.usageRole,
      confidence: result.confidence,
      modelVersion: result.modelVersion,
      rawJson: result.rawJson,
      createdAt: result.createdAt,
    );
  }

  List<String> _normalizeStateTags(List<String> tags) {
    if (tags.isEmpty) {
      return tags;
    }
    final cleaned = tags.map((t) => t.trim()).where((t) => t.isNotEmpty).toList();
    final set = <String>{...cleaned};

    const exclusive = ['frozen', 'chilled', 'cooked', 'raw'];
    String? chosen;
    for (final tag in exclusive) {
      if (set.contains(tag)) {
        chosen = tag;
        break;
      }
    }
    if (chosen != null) {
      for (final tag in exclusive) {
        if (tag != chosen) {
          set.remove(tag);
        }
      }
    }
    return set.toList();
  }

  bool _isNonIngredient(AiResult result) {
    final label = result.primaryLabel.trim();
    if (label == '비식재료') {
      return true;
    }
    return result.category == 'ETC' && (result.confidence ?? 0.0) <= 0.0;
  }

  Future<_OcrSignal> _readOcrSignal(String filePath) async {
    try {
      final inputImage = InputImage.fromFilePath(filePath);
      final scripts = _resolveOcrScripts(AppConfig.instance.ocrScripts);
      final parts = <String>[];
      for (final script in scripts) {
        try {
          final recognizer = _getRecognizer(script);
          final recognizedText = await recognizer.processImage(inputImage);
          final text = recognizedText.text.trim();
          if (text.isNotEmpty) {
            parts.add(text);
          }
        } catch (e) {
          debugPrint('🧠 OCR 스크립트 실패($script): $e');
        }
      }
      final mergedText = parts.join('\n').trim();
      if (mergedText.isEmpty) {
        return _OcrSignal(text: '', flags: const {});
      }
      final flags = _extractOcrFlags(mergedText);
      debugPrint(
        '🧠 OCR 텍스트: ${mergedText.length > 400 ? mergedText.substring(0, 400) : mergedText}',
      );
      debugPrint('🧠 OCR 플래그: ${flags.join(", ")}');
      return _OcrSignal(text: mergedText, flags: flags);
    } catch (e) {
      debugPrint('🧠 OCR 실패: $e');
      return _OcrSignal(text: '', flags: const {});
    }
  }

  TextRecognizer _getRecognizer(TextRecognitionScript script) {
    return _recognizers.putIfAbsent(
      script,
      () => TextRecognizer(script: script),
    );
  }

  List<TextRecognitionScript> _resolveOcrScripts(List<String> scripts) {
    final map = <String, TextRecognitionScript>{
      'latin': TextRecognitionScript.latin,
      'korean': TextRecognitionScript.korean,
      'japanese': TextRecognitionScript.japanese,
      'chinese': TextRecognitionScript.chinese,
      
    };
    final resolved = <TextRecognitionScript>[];
    for (final script in scripts) {
      final key = script.toLowerCase().trim();
      final found = map[key];
      if (found != null && !resolved.contains(found)) {
        resolved.add(found);
      }
    }
    if (resolved.isEmpty) {
      resolved.add(TextRecognitionScript.latin);
    }
    return resolved;
  }

  String _buildOcrHint(_OcrSignal signal) {
    if (signal.text.isEmpty) {
      return '';
    }
    final preview = signal.text.length > 200 ? signal.text.substring(0, 200) : signal.text;
    final summary = signal.flags.isEmpty ? 'OCR 텍스트 존재' : signal.flags.join(', ');
    return 'SUMMARY: $summary\nTEXT: $preview';
  }



  Set<String> _extractOcrFlags(String text) {
    final lower = text.toLowerCase();
    final flags = <String>{};

    if (RegExp(r'(ml|l|g|kg)\b').hasMatch(lower)) {
      flags.add('용량 표기 가능');
    }
    if (lower.contains('유통기한') || lower.contains('소비기한') || lower.contains('best before')) {
      flags.add('유통기한 문구');
    }
    if (lower.contains('제품') || lower.contains('원재료') || lower.contains('생성분') || lower.contains('영양')) {
      flags.add('포장/제품 라벨 문구');
    }
    if (lower.contains('냉동') || lower.contains('frozen')) {
      flags.add('냉동 표기');
    }
    if (lower.contains('냉장') || lower.contains('chilled')) {
      flags.add('냉장 표기');
    }
    if (lower.contains('개봉') || lower.contains('opened')) {
      flags.add('개봉 표기');
    }
    if (lower.contains('소스') || lower.contains('간장') || lower.contains('된장') || lower.contains('고추장')) {
      flags.add('소스/양념 키워드');
    }
    if (lower.contains('주스') || lower.contains('음료') || lower.contains('커피') || lower.contains('차') || lower.contains('탄산')) {
      flags.add('음료 키워드');
    }
    return flags;
  }

  AiResult _buildOcrResult(_RecognitionTask task, _OcrSignal signal) {
    if (signal.text.isEmpty) {
      return AiResult(
        captureId: task.captureId,
        category: 'ETC',
        primaryLabel: AppConfig.instance.defaultPrimaryLabel,
        secondaryLabel: null,
        secondaryLabelGuess: false,
        stateTags: const [],
        freshnessHint: null,
        shelfLifeDays: null,
        amountLabel: null,
        usageRole: null,
        confidence: 0.1,
        modelVersion: 'ocr-0.1',
        rawJson: {'ocr': 'empty'},
        createdAt: DateTime.now(),
      );
    }

    final lower = signal.text.toLowerCase();
    String category = 'PROCESSED';
    String primary = '가공식품';
    String secondary = '기타';

    if (lower.contains('소스') || lower.contains('간장') || lower.contains('된장') || lower.contains('고추장')) {
      category = 'SAUCE';
      primary = '양념';
      secondary = '소스류';
    } else if (lower.contains('주스') || lower.contains('음료') || lower.contains('커피') || lower.contains('차') || lower.contains('탄산')) {
      category = 'DRINK';
      primary = '음료';
      secondary = '음료류';
    } else if (lower.contains('냉동')) {
      category = 'PROCESSED';
      primary = '가공식품';
      secondary = '냉동식품';
    }

    return AiResult(
      captureId: task.captureId,
      category: category,
      primaryLabel: primary,
      secondaryLabel: secondary,
      secondaryLabelGuess: true,
      stateTags: const ['packaged'],
      freshnessHint: null,
      shelfLifeDays: _resolveShelfLifeDays(null, secondary, primary, const ['packaged']),
      amountLabel: null,
      usageRole: null,
      confidence: 0.45,
      modelVersion: 'ocr-0.1',
      rawJson: {
        'ocr': signal.text,
        'flags': signal.flags.toList(),
      },
      createdAt: DateTime.now(),
    );
  }

  int? _resolveShelfLifeDays(
    Object? aiValue,
    String? secondaryLabel,
    String? primaryLabel,
    List<String> stateTags,
  ) {
    final numValue = aiValue is num ? aiValue.toInt() : null;
    final isFrozen = stateTags.map((tag) => tag.toLowerCase()).contains('frozen');
    final map = isFrozen
        ? AppConfig.instance.shelfLifeDaysFrozenMap
        : AppConfig.instance.shelfLifeDaysMap;

    if (secondaryLabel != null && map.containsKey(secondaryLabel)) {
      return map[secondaryLabel];
    }
    if (primaryLabel != null && map.containsKey(primaryLabel)) {
      return map[primaryLabel];
    }

    if (!isFrozen && numValue != null && numValue > 0) {
      return numValue;
    }
    return null;
  }
}

class _OcrSignal {
  final String text;
  final Set<String> flags;

  const _OcrSignal({
    required this.text,
    required this.flags,
  });
}

class _RecognitionTask {
  final String captureId;
  final String filePath;
  final Completer<bool>? completer;

  _RecognitionTask({
    required this.captureId,
    required this.filePath,
    this.completer,
  });
}
