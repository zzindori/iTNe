import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../data/dao/capture_dao.dart';
import '../data/dao/ingredient_substitution_dao.dart';
import '../data/services/recipe_recommendation_service.dart';
import '../data/services/credit_service.dart';
import '../data/services/ad_service.dart';
import '../models/recipe_recommendation.dart';
import '../models/capture_record.dart';
import '../models/credit_provider.dart';
import '../main.dart';
import '../widgets/credit_confirm_dialog.dart';
import '../widgets/credit_balance_widget.dart';
import 'capture_detail_screen.dart';
import 'reward_claim_screen.dart';

class RecipeDetailScreen extends StatefulWidget {
  final RecipeCard card;
  final List<String> ingredients;
  final String categoryLabel;

  const RecipeDetailScreen({
    super.key,
    required this.card,
    required this.ingredients,
    required this.categoryLabel,
  });

  @override
  State<RecipeDetailScreen> createState() => _RecipeDetailScreenState();
}

class _RecipeDetailScreenState extends State<RecipeDetailScreen>
    with SingleTickerProviderStateMixin {
  Future<RecipeDetail>? _detailFuture;
  final ScrollController _scrollController = ScrollController();
  late final AnimationController _skeletonController;
  late final Animation<double> _skeletonShift;
  final CaptureDao _captureDao = CaptureDao();
  final IngredientSubstitutionDao _substitutionDao =
      IngredientSubstitutionDao();
  late Future<List<CaptureRecord>> _capturesFuture;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  CaptureRecord? _drawerRecord;
  String? _linkedIngredientKey;
  // ignore: unused_field
  String? _linkedIngredientLabel;
  final Set<String> _unlinkedIngredients = {};
  String? _missingIngredient;
  List<CaptureRecord> _missingSimilar = const [];
  Future<List<String>>? _missingAiFuture;
  bool _missingAiHasCache = false;
  RecipeDetail? _currentDetail;
  Map<String, String> _ingredientSubstitutions = {};
  Map<String, String> _ingredientOriginals = {};
  bool _checkedSubstitutions = false;
  String _activeSection = 'summary';
  String? _generatedImagePath;
  bool _isGeneratingImage = false;
  bool _checkedGeneratedImage = false;
  String? _generateErrorMessage;

  @override
  void initState() {
    super.initState();
    _skeletonController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _skeletonShift = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _skeletonController, curve: Curves.easeInOut),
    );
    AppConfig.instance.debugPrintKeys();
    _capturesFuture = _captureDao.getAllCaptures();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reloadDetail(allowPopOnCancel: true);
    });
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.instance;
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: Text(
          strings.recipeDetailTitle,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFFAABEA5),
        foregroundColor: const Color(0xFF2E5E3F),
        surfaceTintColor: const Color(0xFFAABEA5),
        leading: IconButton(
          tooltip: MaterialLocalizations.of(context).backButtonTooltip,
          onPressed: () {
            Navigator.of(context).maybePop();
          },
          icon: const Icon(Icons.chevron_left),
        ),
        actions: [
          Consumer<CreditProvider>(
            builder: (context, creditProvider, _) {
              final creditService = CreditService();
              return IconButton(
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (sheetContext) {
                      final height = MediaQuery.of(sheetContext).size.height * 0.6;
                      return SizedBox(
                        height: height,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                          decoration: const BoxDecoration(
                            color: Color(0xFF1F1F1F),
                            borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                          ),
                          child: CreditBalancePanel(
                            creditProvider: sheetContext.read<CreditProvider>(),
                            onWatchAd: () async {
                              final adService = AdService();
                              Navigator.pop(sheetContext);
                              await Future.delayed(const Duration(milliseconds: 100));
                              if (!mounted) return;
                              
                              if (!adService.isAdReady) {
                                print('⏳ [Screen] Ad not ready, loading...');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(creditService.getUIString('snackbar_ad_loading')),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                adService.loadRewardedAd();
                                
                                // Wait for ad to be ready (poll every 500ms, max 30 seconds)
                                int attempts = 0;
                                while (!adService.isAdReady && attempts < 60) {
                                  await Future.delayed(const Duration(milliseconds: 500));
                                  attempts++;
                                  print('⏳ [Screen] Waiting for ad... attempts: $attempts');
                                }
                                
                                if (!adService.isAdReady) {
                                  print('❌ [Screen] Ad failed to load after 30 seconds');
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(creditService.getUIString('snackbar_ad_failed')),
                                        duration: const Duration(seconds: 2),
                                      ),
                                    );
                                  }
                                  return;
                                }
                                print('✅ [Screen] Ad ready after loading');
                              }
                              
                              final rewardEarned = await adService.showRewardedAd(
                                onReward: (amount) {},
                              );
                              
                              if (!rewardEarned) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(creditService.getUIString('snackbar_ad_failed')),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              
                              final rewardAmount = 0.5;
                              navigatorKey.currentState?.push(
                                MaterialPageRoute(
                                  builder: (_) => RewardClaimScreen(
                                    rewardAmount: rewardAmount,
                                    symbol: creditService.getUIString('symbol'),
                                  ),
                                  fullscreenDialog: true,
                                ),
                              );
                            },
                            onPurchase: () {
                              Navigator.pop(sheetContext);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(creditService.getUIString('snackbar_purchase_coming_soon')),
                                  duration: const Duration(seconds: 2),
                                ),
                              );
                            },
                          ),
                        ),
                      );
                    },
                  );
                },
                icon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.credit_card,
                      size: 16,
                      color: Color(0xFF2E5E3F),
                    ),
                    if (creditProvider.hasActiveSubscription)
                      const Padding(
                        padding: EdgeInsets.only(left: 2),
                        child: Row(
                          children: [
                            Icon(
                              Icons.lock,
                              size: 12,
                              color: Color(0xFF2E5E3F),
                            ),
                            SizedBox(width: 2),
                            Text(
                              'LOCK',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF2E5E3F),
                              ),
                            ),
                          ],
                        ),
                      )
                    else if (creditProvider.balance != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 2),
                        child: Text(
                          creditProvider.balance!.credits.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF2E5E3F),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      drawer: _buildMissingIngredientDrawer(),
      endDrawer: _buildIngredientDrawer(),
      body: _detailFuture == null
          ? Column(
              children: [
                Expanded(
                  child: _buildLoadingBody(),
                ),
                _buildBottomSectionBarLoading(strings),
              ],
            )
          : FutureBuilder<RecipeDetail>(
              future: _detailFuture,
              builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Column(
              children: [
                Expanded(
                  child: _buildLoadingBody(),
                ),
                _buildBottomSectionBarLoading(strings),
              ],
            );
          }

          if (snapshot.hasError || !snapshot.hasData) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(strings.recipeError),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () {
                      _reloadDetail(forceRefresh: true);
                    },
                    child: Text(strings.recipeRetry),
                  ),
                ],
              ),
            );
          }

          final detail = snapshot.data!;
          _currentDetail = detail;
          _maybeLoadGeneratedImage(detail);
          _maybeLoadSubstitutions(detail);
          final effectiveDetail = _applySubstitutions(detail);

          return Column(
            children: [
              Expanded(
                child: SingleChildScrollView(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  child: _buildSectionContent(strings, effectiveDetail),
                ),
              ),
              _buildBottomSectionBar(strings, effectiveDetail),
            ],
          );
        },
      ),
    );
  }

  Future<void> _reloadDetail({
    bool forceRefresh = false,
    bool allowPopOnCancel = false,
  }) async {
    _generatedImagePath = null;
    _generateErrorMessage = null;
    _checkedGeneratedImage = false;
    _isGeneratingImage = false;
    _checkedSubstitutions = false;
    _ingredientSubstitutions = {};
    _ingredientOriginals = {};

    final hasCache = !forceRefresh &&
        await RecipeRecommendationService.instance.hasCachedDetail(
          recipeId: widget.card.id,
          recipeTitle: widget.card.title,
          ingredients: widget.ingredients,
        );
    if (!hasCache) {
      final canProceed = await _confirmAndDeductRecipeGenerate(
        allowPopOnCancel: allowPopOnCancel,
      );
      if (!canProceed) {
        return;
      }
    }

    final future = _fetchRecipeDetailWithCharge(
      shouldDeduct: !hasCache,
      forceRefresh: forceRefresh,
    );
    if (!mounted) {
      _detailFuture = future;
      return;
    }
    setState(() {
      _detailFuture = future;
    });
  }

  Future<void> _openIngredientDrawerForItem(
    String ingredient,
    CaptureRecord record,
  ) async {
    if (_isExpiredForDiscardWarning(record)) {
      final shouldDelete = await _showIngredientExpiredWarningDialog(record);
      if (shouldDelete == true) {
        await _deleteCaptureFromRecipeDetail(record);
      }
      return;
    }

    final key = _normalizeIngredientName(ingredient);
    if (!mounted) {
      return;
    }
    setState(() {
      _drawerRecord = record;
      _linkedIngredientKey = key.isEmpty? null : key;
      _linkedIngredientLabel = ingredient;
    });
    _scaffoldKey.currentState?.openEndDrawer();
  }

  void _unlinkIngredient() {
    final key = _linkedIngredientKey;
    if (key == null || key.isEmpty) {
      return;
    }
    setState(() {
      _unlinkedIngredients.add(key);
      _drawerRecord = null;
      _linkedIngredientKey = null;
      _linkedIngredientLabel = null;
    });
    Navigator.of(context).maybePop();
  }

  bool _isExpiredForDiscardWarning(CaptureRecord record) {
    final shelfLifeDays = record.shelfLifeDays;
    if (shelfLifeDays == null || shelfLifeDays <= 0) {
      return false;
    }
    final ageDays = DateTime.now().difference(record.createdAt).inDays;
    return ageDays > shelfLifeDays;
  }

  Future<bool?> _showIngredientExpiredWarningDialog(CaptureRecord record) async {
    final countdown = record.shelfLifeCountdownLabel() ?? 'D+1';

    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              width: 390,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xFFC0C0C0),
                border: Border.all(color: Colors.black, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 10,
                    offset: const Offset(3, 3),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF0A3AA2), Color(0xFF4E79D8)],
                      ),
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Windows',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Container(
                          width: 16,
                          height: 16,
                          decoration: BoxDecoration(
                            color: const Color(0xFFC0C0C0),
                            border: Border.all(color: Colors.black, width: 1),
                          ),
                          child: const Icon(Icons.close, size: 11, color: Colors.black),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                    padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC0C0C0),
                      border: Border.all(color: const Color(0xFF7A7A7A), width: 1),
                    ),
                    child: Column(
                      children: [
                        const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFCC9A00),
                              size: 34,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '유통기한이 지난 식재료입니다.\n삭제(폐기)를 권장합니다.',
                                style: TextStyle(
                                  color: Colors.black,
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            '현재 상태: $countdown',
                            style: const TextStyle(
                              color: Colors.black87,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 90,
                          height: 30,
                          child: OutlinedButton(
                            onPressed: () {
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(false);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                              backgroundColor: const Color(0xFFD9D9D9),
                              side: const BorderSide(color: Colors.black, width: 1),
                              shape: const RoundedRectangleBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text('유지'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 90,
                          height: 30,
                          child: OutlinedButton(
                            onPressed: () {
                              if (dialogContext.mounted) {
                                Navigator.of(dialogContext).pop(true);
                              }
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black,
                              backgroundColor: const Color(0xFFD9D9D9),
                              side: const BorderSide(color: Colors.black, width: 1),
                              shape: const RoundedRectangleBorder(),
                              padding: EdgeInsets.zero,
                            ),
                            child: const Text('삭제'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteCaptureFromRecipeDetail(CaptureRecord record) async {
    bool deleted = false;

    try {
      final file = File(record.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}

    try {
      deleted = await _captureDao.deleteCapture(record.id);
    } catch (_) {
      deleted = false;
    }

    if (!mounted) {
      return;
    }

    if (!deleted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제에 실패했습니다. 다시 시도해 주세요.')),
      );
      return;
    }

    setState(() {
      if (_drawerRecord?.id == record.id) {
        _drawerRecord = null;
        _linkedIngredientKey = null;
        _linkedIngredientLabel = null;
      }
      _capturesFuture = _captureDao.getAllCaptures();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('만료 식재료를 삭제했습니다.')),
    );
  }

  Future<void> _openMissingIngredientDrawer(
    String ingredient,
    RecipeDetail detail,
    List<CaptureRecord> captures,
  ) async {
    final recipeId = detail.id.isNotEmpty? detail.id : widget.card.id;
    final hasCache = await RecipeRecommendationService.instance
        .hasCachedSubstitutes(
      recipeId: recipeId,
      recipeTitle: detail.title,
      ingredients: detail.ingredients,
      missingIngredient: ingredient,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _missingIngredient = ingredient;
      _missingSimilar = _findSimilarCaptures(ingredient, captures);
      _missingAiHasCache = hasCache;
      _missingAiFuture = hasCache
          ? _suggestSubstitutesWithCharge(
              shouldDeduct: false,
              recipeId: recipeId,
              recipeTitle: detail.title,
              ingredients: detail.ingredients,
              summary: detail.summary,
              steps: detail.steps,
              missingIngredient: ingredient,
            )
          : null;
    });
    _scaffoldKey.currentState?.openDrawer();
  }

  Future<void> _requestMissingIngredientSuggestions(RecipeDetail detail) async {
    final ingredient = _missingIngredient;
    if (ingredient == null || ingredient.isEmpty) {
      return;
    }

    final shouldDeduct = !_missingAiHasCache;
    if (shouldDeduct) {
      if (!mounted) {
        return;
      }
      final creditProvider = context.read<CreditProvider>();
      final balance = creditProvider.balance;
      if (balance == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider.getUIString('snackbar_loading_credit'))),
        );
        return;
      }
      if (!creditProvider.hasEnough(CreditPackage.recipeGenerate)) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider.getUIString('snackbar_deduct_failed'))),
        );
        return;
      }
    }

    final recipeId = detail.id.isNotEmpty ? detail.id : widget.card.id;
    setState(() {
      _missingAiFuture = _suggestSubstitutesWithCharge(
        shouldDeduct: shouldDeduct,
        recipeId: recipeId,
        recipeTitle: detail.title,
        ingredients: detail.ingredients,
        summary: detail.summary,
        steps: detail.steps,
        missingIngredient: ingredient,
      );
      _missingAiHasCache = true;
    });
  }

  Future<RecipeDetail> _fetchRecipeDetailWithCharge({
    required bool shouldDeduct,
    required bool forceRefresh,
  }) async {
    final detail = await RecipeRecommendationService.instance.fetchRecipeDetail(
      recipeId: widget.card.id,
      recipeTitle: widget.card.title,
      ingredients: widget.ingredients,
      forceRefresh: forceRefresh,
      categoryLabel: widget.categoryLabel,
    );

    if (shouldDeduct) {
      final deducted = await _deductRecipeGenerateCredits();
      if (!deducted) {
        throw StateError('credit_deduct_failed');
      }
    }

    return detail;
  }

  Future<List<String>> _suggestSubstitutesWithCharge({
    required bool shouldDeduct,
    required String recipeId,
    required String recipeTitle,
    required List<String> ingredients,
    required String summary,
    required List<String> steps,
    required String missingIngredient,
  }) async {
    final substitutes = await RecipeRecommendationService.instance
        .suggestIngredientSubstitutes(
      recipeId: recipeId,
      recipeTitle: recipeTitle,
      ingredients: ingredients,
      summary: summary,
      steps: steps,
      missingIngredient: missingIngredient,
    );

    if (shouldDeduct) {
      final deducted = await _deductRecipeGenerateCredits();
      if (!deducted) {
        throw StateError('credit_deduct_failed');
      }
    }

    return substitutes;
  }

  Future<bool> _confirmAndDeductRecipeGenerate({
    bool allowPopOnCancel = false,
  }) async {
    if (!mounted) {
      return false;
    }
    final cfg = AppConfig.instance;
    if (!cfg.aiEnabled || cfg.aiApiKey.isEmpty) {
      return true;
    }
    final creditProvider = context.read<CreditProvider>();
    final costInfo = creditProvider.getCostInfo(CreditPackage.recipeGenerate);
    final currentBalance = creditProvider.balance;

    if (currentBalance == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(creditProvider.getUIString('snackbar_loading_credit'))),
      );
      return false;
    }

    final confirmed = await CreditConfirmDialog.show(
      context,
      costInfo: costInfo,
      currentCredits: currentBalance.credits,
      onConfirm: () {},
      onCharge: () async {
        Navigator.pop(context, false);
        
        final adService = AdService();
        
        // Check if ad is ready
        if (!adService.isAdReady) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(creditProvider.getUIString('snackbar_ad_loading')),
              duration: const Duration(seconds: 2),
            ),
          );
          adService.loadRewardedAd();
          return;
        }
        
        // Show the ad
        print('📱 [RecipeDetail] Showing rewarded ad...');
        bool rewardCallbackFired = false;
        final rewardAmount = 0.5;
        final rewardEarned = await adService.showRewardedAd(
          onReward: (amount) {
            rewardCallbackFired = true;
            print('🎁 [RecipeDetail] Reward callback called: $amount');
          },
          onAdDismissed: () {
            if (!rewardCallbackFired) {
              return;
            }
            navigatorKey.currentState?.push(
              PageRouteBuilder(
                pageBuilder: (_, __, ___) => RewardClaimScreen(
                  rewardAmount: rewardAmount,
                  symbol: creditProvider.getUIString('symbol'),
                ),
                transitionDuration: Duration.zero,
                reverseTransitionDuration: Duration.zero,
              ),
            );
          },
        );
        
        print('📱 [RecipeDetail] Ad finished. Reward earned: $rewardEarned');
        
        // Check if context is still valid (user didn't navigate away)
        if (!mounted) {
          print('⚠️ [RecipeDetail] Context deactivated, skipping notification');
          return;
        }
        
        if (!rewardEarned) {
          print('❌ [RecipeDetail] No reward earned, user closed ad early');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(creditProvider.getUIString('snackbar_ad_failed')),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        
        print('✅ [RecipeDetail] User earned reward, reward screen shown on ad dismiss');
      },
    );

    if (confirmed != true) {
      if (allowPopOnCancel && mounted) {
        Navigator.of(context).maybePop();
      }
      return false;
    }

    return true;
  }

  Future<bool> _deductRecipeGenerateCredits() async {
    if (!mounted) {
      return false;
    }
    final creditProvider = context.read<CreditProvider>();
    final authToken = await creditProvider.deductCredits(CreditPackage.recipeGenerate);
    if (authToken == null || authToken.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider.getUIString('snackbar_deduct_failed'))),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _applyIngredientSubstitution(
    String missing,
    String substitute,
  ) async {
    final detail = _currentDetail;
    if (detail == null) {
      return;
    }
    final recipeId = detail.id.isNotEmpty? detail.id : widget.card.id;
    final normalized = _normalizeIngredientName(missing);
    if (normalized.isEmpty) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('재료 바꾸기'),
          content: Text('"$missing"을 "$substitute"로 바꿔볼까요'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('바꾸기'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    await _substitutionDao.upsertSubstitution(
      recipeId: recipeId,
      missingIngredient: normalized,
      missingOriginal: missing,
      substitute: substitute,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _ingredientSubstitutions[normalized] = substitute;
      _ingredientOriginals[normalized] = missing;
    });

    Navigator.of(context).maybePop();
  }

  Future<void> _loadGeneratedImage(RecipeDetail detail) async {
    final path = await RecipeRecommendationService.instance
        .getGeneratedRecipeImagePath(
      recipeId: detail.id.isNotEmpty? detail.id : widget.card.id,
      recipeTitle: detail.title,
    );
    if (!mounted) {
      return;
    }
    if (detail.imagePath.isNotEmpty) {
      setState(() {
        _generatedImagePath = path;
      });
    }
  }

  void _maybeLoadGeneratedImage(RecipeDetail detail) {
    if (_checkedGeneratedImage) {
      return;
    }
    _checkedGeneratedImage = true;
    _loadGeneratedImage(detail);
  }

  void _maybeLoadSubstitutions(RecipeDetail detail) {
    if (_checkedSubstitutions) {
      return;
    }
    _checkedSubstitutions = true;
    _loadSubstitutions(detail);
  }

  Future<void> _loadSubstitutions(RecipeDetail detail) async {
    final recipeId = detail.id.isNotEmpty? detail.id : widget.card.id;
    final entries =
        await _substitutionDao.getSubstitutions(recipeId: recipeId);
    if (!mounted) {
      return;
    }
    setState(() {
      _ingredientSubstitutions = {
        for (final entry in entries) entry.missingIngredient: entry.substitute,
      };
      _ingredientOriginals = {
        for (final entry in entries) entry.missingIngredient: entry.missingOriginal,
      };
    });
  }

  Future<void> _handleGenerateTap(
    AppStrings strings,
    RecipeDetail detail, {
    bool force = false,
  }) async {
    if (_isGeneratingImage) {
      return;
    }

    if (!force) {
      final existingPath = await RecipeRecommendationService.instance
          .getGeneratedRecipeImagePath(
        recipeId: detail.id.isNotEmpty? detail.id : widget.card.id,
        recipeTitle: detail.title,
      );
      if (existingPath != null && existingPath.isNotEmpty) {
        if (mounted) {
          setState(() {
            _generatedImagePath = existingPath;
            _generateErrorMessage = null;
            _isGeneratingImage = false;
          });
        }
        return;
      }
    }

    if (AppConfig.instance.stabilityApiKey.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('이미지 생성 API 키가 설정되지 않았습니다')),
        );
      }
      return;
    }

    bool shouldDeductImage = false;

    // 크레딧 비용 확인
    if (mounted && context.mounted) {
      final creditProvider = context.read<CreditProvider>();
      final costInfo = creditProvider.getCostInfo(CreditPackage.imageGenerate);
      final currentBalance = creditProvider.balance;

      if (currentBalance == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider.getUIString('snackbar_loading_credit'))),
        );
        return;
      }

      // Confirm 대화상자 표시
      final confirmed = await CreditConfirmDialog.show(
        context,
        costInfo: costInfo,
        currentCredits: currentBalance.credits,
        onConfirm: () {},
        onCharge: () async {
          Navigator.pop(context, false);
          
          final adService = AdService();
          
          // Check if ad is ready
          if (!adService.isAdReady) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(creditProvider.getUIString('snackbar_ad_loading')),
                duration: const Duration(seconds: 2),
              ),
            );
            adService.loadRewardedAd();
            return;
          }
          
          // Show the ad
          print('📱 [RecipeImage] Showing rewarded ad...');
          bool rewardCallbackFired = false;
          final rewardAmount = 0.5;
          final rewardEarned = await adService.showRewardedAd(
            onReward: (amount) {
              rewardCallbackFired = true;
              print('🎁 [RecipeImage] Reward callback called: $amount');
            },
            onAdDismissed: () {
              if (!rewardCallbackFired) {
                return;
              }
              navigatorKey.currentState?.push(
                PageRouteBuilder(
                  pageBuilder: (_, __, ___) => RewardClaimScreen(
                    rewardAmount: rewardAmount,
                    symbol: creditProvider.getUIString('symbol'),
                  ),
                  transitionDuration: Duration.zero,
                  reverseTransitionDuration: Duration.zero,
                ),
              );
            },
          );
          
          print('📱 [RecipeImage] Ad finished. Reward earned: $rewardEarned');
          
          // Check if context is still valid (user didn't navigate away)
          if (!mounted) {
            print('⚠️ [RecipeImage] Context deactivated, skipping notification');
            return;
          }
          
          if (!rewardEarned) {
            print('❌ [RecipeImage] No reward earned, user closed ad early');
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(creditProvider.getUIString('snackbar_ad_failed')),
                duration: const Duration(seconds: 2),
              ),
            );
            return;
          }
          
          print('✅ [RecipeImage] User earned reward, reward screen shown on ad dismiss');
        },
      );

      if (confirmed != true) {
        return;
      }
      shouldDeductImage = true;
    }

    setState(() {
      _isGeneratingImage = true;
      _generateErrorMessage = null;
    });

    final path = await RecipeRecommendationService.instance.generateRecipeImage(
      recipeId: detail.id.isNotEmpty? detail.id : widget.card.id,
      recipeTitle: detail.title,
      ingredients: detail.ingredients,
      summary: detail.summary,
      steps: detail.steps,
      force: force,
      categoryLabel: widget.categoryLabel,
    );

    if (!mounted) {
      return;
    }

    if (path == null || path.isEmpty) {
      setState(() {
        _isGeneratingImage = false;
        _generateErrorMessage = strings.recipeDetailImageGenerateFailed;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.recipeDetailImageGenerateFailed)),
      );
      return;
    }

    if (shouldDeductImage) {
      final creditProvider = context.read<CreditProvider>();
      final authToken = await creditProvider.deductCredits(CreditPackage.imageGenerate);
      if (authToken == null || authToken.isEmpty) {
        setState(() {
          _isGeneratingImage = false;
          _generateErrorMessage = creditProvider.getUIString('snackbar_deduct_failed');
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider.getUIString('snackbar_deduct_failed'))),
        );
        return;
      }
    }

    final imageProvider = FileImage(File(path));
    await imageProvider.evict();

    setState(() {
      _isGeneratingImage = false;
      _generatedImagePath = path;
    });
  }

  Widget _buildBottomSectionBarLoading(AppStrings strings) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F1E4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildSectionButton(
                label: strings.recipeDetailIngredients,
                icon: Icons.kitchen,
                selected: false,
                enabled: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSectionButton(
                label: strings.recipeDetailSteps,
                icon: Icons.format_list_numbered,
                selected: false,
                enabled: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSectionButton(
                label: strings.recipeDetailTips,
                icon: Icons.lightbulb_outline,
                selected: false,
                enabled: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingBody() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLoadingImage(),
          const SizedBox(height: 12),
          _buildLoadingBar(width: 160, height: 16),
          const SizedBox(height: 8),
          _buildLoadingBar(width: double.infinity, height: 12),
          const SizedBox(height: 6),
          _buildLoadingBar(width: 220, height: 12),
          const SizedBox(height: 12),
          _buildLoadingBar(width: 140, height: 12),
        ],
      ),
    );
  }

  Widget _buildLoadingImage() {
    return _buildShimmer(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 180,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
    );
  }

  Widget _buildLoadingBar({required double width, required double height}) {
    return _buildShimmer(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
      ),
    );
  }

  Widget _buildShimmer({
    required Widget child,
    required BorderRadius borderRadius,
  }) {
    return AnimatedBuilder(
      animation: _skeletonShift,
      builder: (context, _) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + _skeletonShift.value, 0),
              end: Alignment(1.0 + _skeletonShift.value, 0),
              colors: [
                Colors.white.withValues(alpha: 0.0),
                Colors.white.withValues(alpha: 0.35),
                Colors.white.withValues(alpha: 0.0),
              ],
              stops: const [0.2, 0.5, 0.8],
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: ClipRRect(
            borderRadius: borderRadius,
            child: child,
          ),
        );
      },
    );
  }

  Widget _buildBottomSectionBar(AppStrings strings, RecipeDetail detail) {
    final hasTips = detail.tips.isNotEmpty;
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F1E4),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.08),
              blurRadius: 8,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildSectionButton(
                label: strings.recipeDetailIngredients,
                icon: Icons.kitchen,
                selected: _activeSection == 'ingredients',
                onTap: () => _setSection('ingredients'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSectionButton(
                label: strings.recipeDetailSteps,
                icon: Icons.format_list_numbered,
                selected: _activeSection == 'steps',
                onTap: () => _setSection('steps'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _buildSectionButton(
                label: strings.recipeDetailTips,
                icon: Icons.lightbulb_outline,
                selected: _activeSection == 'tips',
                enabled: hasTips,
                onTap: hasTips
                    ? () => _setSection('tips')
                    : null,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionButton({
    required String label,
    required IconData icon,
    required bool selected,
    VoidCallback ? onTap,
    bool enabled = true,
  }) {
    const accent = Color(0xFF2E5E3F);
    const panelBorder = Color(0xFFC5D6BD);
    const selectedBg = Color(0xFFE0E9DA);
    return InkWell(
      onTap: enabled? onTap : null,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          color: selected? selectedBg : Colors.white.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected? accent : panelBorder,
            width: selected? 1.4 : 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  ),
                ],
        ),
        child: Opacity(
          opacity: enabled? 1.0 : 0.4,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: selected? accent : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: selected? accent : panelBorder,
                    width: 1.0,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 18,
                  color: selected? Colors.white : accent,
                ),
              ),
              const SizedBox(height: 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: selected? accent : const Color(0xFF4C6D57),
                    letterSpacing: -0.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _setSection(String sectionId) {
    setState(() {
      _activeSection = _activeSection == sectionId? 'summary' : sectionId;
    });
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Widget _buildSectionContent(AppStrings strings, RecipeDetail detail) {
    switch (_activeSection) {
      case 'ingredients':
        return _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(strings.recipeDetailIngredients),
              const SizedBox(height: 8),
              FutureBuilder<List<CaptureRecord>>(
                future: _capturesFuture,
                builder: (context, snapshot) {
                  final captures = snapshot.data ?? const <CaptureRecord>[];
                  return Column(
                    children: detail.ingredients
                        .map((item) {
                          final isUnlinked =
                              _unlinkedIngredients.contains(_normalizeIngredientName(item));
                          final match =
                              isUnlinked? null : _findCaptureForIngredient(item, captures);
                          return _buildIngredientRow(
                            item,
                            match,
                            detail,
                            captures,
                          );
                        })
                        .toList(),
                  );
                },
              ),
            ],
          ),
        );
      case 'steps':
        return _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(strings.recipeDetailSteps),
              const SizedBox(height: 8),
              ...detail.steps.asMap().entries.map(
                    (entry) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '${entry.key + 1}. ${_stripStepNumber(entry.value)}',
                      ),
                    ),
                  ),
            ],
          ),
        );
      case 'tips':
        if (detail.tips.isEmpty) {
          return const SizedBox.shrink();
        }
        return _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle(strings.recipeDetailTips),
              const SizedBox(height: 8),
              Text(detail.tips),
            ],
          ),
        );
      case 'summary':
      default:
        return _buildPanel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildRecipeImage(strings, detail),
              if (_generateErrorMessage != null) ...[
                const SizedBox(height: 6),
                Text(
                  _generateErrorMessage!,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8A2D2D),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                detail.title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (detail.summary.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(detail.summary),
              ],
              const SizedBox(height: 12),
              _buildMetaRow(strings, detail),
            ],
          ),
        );
    }
  }

  Widget _buildRecipeImage(AppStrings strings, RecipeDetail detail) {
    const height = 180.0;
    final path = _generatedImagePath;

    Widget image;
    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      image = Image.file(
        File(path),
        fit: BoxFit.cover,
        width: double.infinity,
        height: height,
      );
    } else {
      image = _buildImagePlaceholder(
        height,
        strings.recipeDetailImageTapGenerate,
      );
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: _isGeneratingImage
             ? null
            : () => _handleGenerateTap(strings, detail),
        borderRadius: BorderRadius.circular(12),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            alignment: Alignment.center,
            children: [
              image,
              // if (_generatedImagePath != null)
              //   Positioned(
              //     top: 10,
              //     left: 10,
              //     child: AbsorbPointer(
              //       absorbing: _isGeneratingImage,
              //       child: Material(
              //         color: Colors.black.withValues(alpha: 0.55),
              //         borderRadius: BorderRadius.circular(14),
              //         child: InkWell(
              //           onTap: () => _handleGenerateTap(
              //             strings,
              //             detail,
              //             force: true,
              //           ),
              //           borderRadius: BorderRadius.circular(14),
              //           child: Padding(
              //             padding: const EdgeInsets.symmetric(
              //               horizontal: 10,
              //               vertical: 6,
              //             ),
              //             child: Row(
              //               mainAxisSize: MainAxisSize.min,
              //               children: [
              //                 if (_isGeneratingImage)
              //                   const SizedBox(
              //                     width: 12,
              //                     height: 12,
              //                     child: CircularProgressIndicator(
              //                       strokeWidth: 2,
              //                       valueColor:
              //                           AlwaysStoppedAnimation<Color>(
              //                         ? Colors.white,
              //                       ),
              //                     ),
              //                   )
              //                 else
              //                   const Icon(
              //                     Icons.refresh,
              //                     size: 14,
              //                     color: Colors.white,
              //                   ),
              //                 const SizedBox(width: 6),
              //                 Text(
              //                   '이미지 생성',
              //                   style: TextStyle(
              //                     color: _isGeneratingImage
              //                          ? Colors.white70
              //                         : Colors.white,
              //                     fontSize: 11,
              //                     fontWeight: FontWeight.w700,
              //                   ),
              //                 ),
              //               ],
              //             ),
              //           ),
              //         ),
              //       ),
              //     ),
              //   ),
              if (_isGeneratingImage)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.45),
                    child: Center(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                valueColor:
                                    AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  strings.recipeDetailImageGenerating,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                const Text(
                                  '10~20초 정도 소요돼요',
                                  style: TextStyle(
                                    color: Colors.white70,
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(double height, String label) {
    return Consumer<CreditProvider>(
      builder: (context, CreditProvider, _) {
        return Container(
          height: height,
          color: Colors.black.withValues(alpha: 0.06),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.restaurant_menu, color: Color(0xFF7A8F82)),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFF7A8F82),
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPanel({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
      ),
      child: child,
    );
  }

  Widget _buildIngredientRow(
    String item,
    CaptureRecord? match,
    RecipeDetail detail,
    List<CaptureRecord> captures,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: InkWell(
          onTap: () async {
            if (match != null) {
              await _openIngredientDrawerForItem(item, match);
              return;
            }
            await _openMissingIngredientDrawer(item, detail, captures);
          },
          borderRadius: BorderRadius.circular(10),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  '$item',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2B22),
                  ),
                ),
              ),
              if (match != null) ...[
                const SizedBox(width: 8),
                _buildIngredientThumbnail(match),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIngredientDrawer() {
    final record = _drawerRecord;
    final width = (MediaQuery.of(context).size.width * 0.85).clamp(260, 380);
    return Drawer(
      child: SafeArea(
        child: SizedBox(
          width: width.toDouble(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '재료 정보',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2B22),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, size: 20),
                      color: const Color(0xFF4C6D57),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (record == null)
                  const Text(
                    '선택하세요',
                    style: TextStyle(color: Color(0xFF7A8F82), fontSize: 12),
                  )
                else ...[
                  _buildDrawerImage(record),
                  const SizedBox(height: 12),
                  _buildDrawerStatusPanel(record),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _unlinkIngredient,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF2E5E3F),
                            side: const BorderSide(
                              color: Color(0xFF2E5E3F),
                              width: 1.1,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '연결 끊기',
                            style:
                                TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () async {
                            Navigator.of(context).maybePop();
                            final result = await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => CaptureDetailScreen(record: record),
                              ),
                            );
                            if (!mounted) {
                              return;
                            }
                            if (result is Map && result['deletedId'] != null) {
                              setState(() {
                                _capturesFuture = _captureDao.getAllCaptures();
                                if (_drawerRecord?.id == result['deletedId']) {
                                  _drawerRecord = null;
                                  _linkedIngredientKey = null;
                                  _linkedIngredientLabel = null;
                                }
                              });
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF2E5E3F),
                            foregroundColor: const Color(0xFFE9F1E4),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          child: const Text(
                            '자세히',
                            style:
                                TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMissingIngredientDrawer() {
    final detail = _currentDetail;
    final creditProvider = context.read<CreditProvider>();
    final creditService = CreditService();
    final recipeCost = creditProvider.getCostInfo(CreditPackage.recipeGenerate).costCredits;
    final width = (MediaQuery.of(context).size.width * 0.85).clamp(260, 380);
    return Drawer(
      child: SafeArea(
        child: SizedBox(
          width: width.toDouble(),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      '부족 재료 안내',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2B22),
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.of(context).maybePop(),
                      icon: const Icon(Icons.close, size: 20),
                      color: const Color(0xFF4C6D57),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: _missingIngredient == null || detail == null
                        ? const Text(
                            '선택하세요',
                            style:
                                TextStyle(color: Color(0xFF7A8F82), fontSize: 12),
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '필요 재료: $_missingIngredient',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF2E5E3F),
                                ),
                              ),
                              const SizedBox(height: 12),
                              const Text(
                                '정보 내 유사 재료',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2B22),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (_missingSimilar.isEmpty)
                                const Text(
                                  '유사 정보가 없습니다.',
                                  style:
                                      TextStyle(color: Color(0xFF7A8F82), fontSize: 12),
                                )
                              else
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _missingSimilar
                                      .map((record) => _buildSimilarChip(record))
                                      .toList(),
                                ),
                              const SizedBox(height: 16),
                              const Text(
                                'AI 추천 재료',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF1F2B22),
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (!_missingAiHasCache) ...[
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: () => _requestMissingIngredientSuggestions(detail),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: const Color(0xFF2E5E3F),
                                      side: const BorderSide(color: Color(0xFF2E5E3F), width: 1),
                                      padding: const EdgeInsets.symmetric(vertical: 10),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    child: Text(
                                      'AI 추천 받기 (${creditService.getUIString('symbol')} ${recipeCost.toStringAsFixed(1)} 차감)',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                              ],
                              if (_missingAiFuture == null)
                                Text(
                                  _missingAiHasCache
                                      ? '저장된 추천을 자동으로 불러오는 중입니다.'
                                      : 'AI 호출 시 크레딧이 차감됩니다.',
                                  style: const TextStyle(
                                      color: Color(0xFF7A8F82), fontSize: 12),
                                )
                              else
                                FutureBuilder<List<String>>(
                                  future: _missingAiFuture,
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState ==
                                        ConnectionState.waiting) {
                                      return const Row(
                                        children: [
                                          SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                                strokeWidth: 2),
                                          ),
                                          SizedBox(width: 8),
                                          Text(
                                            '추천 생성 중..',
                                            style: TextStyle(
                                              color: Color(0xFF7A8F82),
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      );
                                    }
                                    final items = snapshot.data??const <String>[];
                                    if (items.isEmpty) {
                                      return const Text(
                                        '추천 재료가 없습니다.',
                                        style: TextStyle(
                                            color: Color(0xFF7A8F82), fontSize: 12),
                                      );
                                    }
                                    return Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: items
                                          .map((item) => _buildSubstituteChip(item))
                                          .toList(),
                                    );
                                  },
                                ),
                            ],
                          ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _missingIngredient == null
                         ? null
                        : () {
                            Navigator.of(context)
                                .popUntil((route) => route.isFirst);
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E5E3F),
                      foregroundColor: const Color(0xFFE9F1E4),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(
                      _missingIngredient == null
                          ? '재료 기록'
                          : '${_cleanIngredientLabel(_missingIngredient!)} 기록',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSimilarChip(CaptureRecord record) {
    final secondary = record.secondaryLabel ?? '';
    final label = secondary.isNotEmpty ? secondary : record.primaryLabel;
    return InkWell(
      onTap: () {
        final missing = _missingIngredient;
        if (missing != null) {
          _applyIngredientSubstitution(missing, label);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.black.withValues(alpha: 0.1)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildIngredientThumbnail(record),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF1F2B22),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSubstituteChip(String item) {
    return InkWell(
      onTap: () {
        final missing = _missingIngredient;
        if (missing != null) {
          _applyIngredientSubstitution(missing, item);
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFE9F1E4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFC5D6BD)),
        ),
        child: Text(
          item,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2E5E3F),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerImage(CaptureRecord record) {
    final thumbPath = record.thumbnailPath;
    final thumbFile =
        (thumbPath != null && File(thumbPath).existsSync()) ? File(thumbPath) : null;
    final imageFile = thumbFile ?? File(record.filePath);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 180,
        width: double.infinity,
        color: Colors.black.withValues(alpha: 0.06),
        child: Image.file(
          imageFile,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.image_not_supported,
              size: 24,
              color: Color(0xFF7A8F82),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDrawerStatusPanel(CaptureRecord record) {
    final strings = AppStrings.instance;
    final cfg = AppConfig.instance;
    final none = strings.get('status_value_none');
    const panelBg = Color(0xFF000000);
    const panelBorder = Color(0xFF00FF66);
    const panelText = Color(0xFF7CFF9A);

    final category = cfg.categoryDisplayMap[record.category] ?? record.category;
    final effectiveFreshness = record.effectiveFreshnessHint();
    final freshness =
        cfg.freshnessDisplayMap[effectiveFreshness] ?? effectiveFreshness;
    final amount = record.amountLabel == null
      ? none
      : (cfg.amountDisplayMap[record.amountLabel!] ?? record.amountLabel!);
    final role = record.usageRole == null
      ? none
      : (cfg.usageRoleDisplayMap[record.usageRole!] ?? record.usageRole!);
    final countdown = record.shelfLifeCountdownLabel();
    final secondary = record.secondaryLabel;
    final tagLabels = record.stateTags
        .map((tag) => cfg.stateTagDisplayMap[tag] ?? tag)
        .toList();
    final tags = tagLabels.isEmpty ? none : tagLabels.join(', ');
    final confidence = record.confidence?.toStringAsFixed(2) ?? none;
    final description = _extractDrawerDescription(record.aiRawJson) ?? none;
    final time = _formatDrawerDateTime(record.createdAt);

    final textLines = <String>[];
    final primaryLine =
        '${strings.get('status_label_primary')}: ${record.primaryLabel}';
    final categoryLine = '${strings.get('status_label_category')}: $category';
    final secondaryLine = '${strings.get('status_label_secondary')}: $secondary';
    final tagsLine = '${strings.get('status_label_tags')}: $tags';
    final roleLine = '${strings.get('status_label_role')}: $role';
    final descriptionLine =
        '${strings.get('status_label_description')}: $description';

    if (!_shouldHideDrawerValue(record.primaryLabel, none)) {
      textLines.add(primaryLine);
    }
    if (!_shouldHideDrawerValue(category, none)) {
      textLines.add(categoryLine);
    }
    if (!_shouldHideDrawerValue(secondary, none)) {
      textLines.add(secondaryLine);
    }
    if (!_shouldHideDrawerValue(tags, none)) {
      textLines.add(tagsLine);
    }
    if (!_shouldHideDrawerValue(role, none)) {
      textLines.add(roleLine);
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: panelBg.withValues(alpha: 0.6),
        border: Border.all(color: panelBorder, width: 1.4),
        borderRadius: BorderRadius.circular(6),
        boxShadow: [
          BoxShadow(
            color: panelBorder.withValues(alpha: 0.35),
            blurRadius: 10,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Stack(
        children: [
          DefaultTextStyle(
            style: const TextStyle(
              color: panelText,
              fontSize: 14,
              height: 1.3,
              fontFamily: 'monospace',
              shadows: [
                Shadow(color: panelBorder, blurRadius: 6),
              ],
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ...textLines.map(Text.new),
                    if (!_shouldHideDrawerValue(freshness, none))
                      _buildDrawerMetricBar(
                        strings.get('status_label_freshness'),
                        _drawerMetricLabel(freshness, none),
                        _drawerFreshnessLevel(effectiveFreshness),
                        3,
                      ),
                    if (!_shouldHideDrawerValue(amount, none))
                      _buildDrawerMetricBar(
                        strings.get('status_label_amount'),
                        _drawerMetricLabel(amount, none),
                        _drawerAmountLevel(record.amountLabel),
                        3,
                      ),
                    if (!_shouldHideDrawerValue(confidence, none))
                      _buildDrawerMetricBar(
                        strings.get('status_label_confidence'),
                        _drawerMetricLabel(confidence, none),
                        _drawerConfidenceLevel(record.confidence),
                        10,
                      ),
                    if (!_shouldHideDrawerValue(description, none))
                      Text(descriptionLine),
                  ],
                ),
              ),
            ),
          ),
          if (time.isNotEmpty)
            Positioned(
              top: 2,
              left: 100,
              right: 0,
              child: Align(
                alignment: Alignment.topRight,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: panelText,
                        fontSize: 13,
                        fontFamily: 'monospace',
                        shadows: [
                          Shadow(color: panelBorder, blurRadius: 6),
                        ],
                      ),
                    ),
                    if (countdown != null && countdown.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.fromLTRB(5, 2, 5, 1),
                        decoration: BoxDecoration(
                          color: panelBg.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: panelBorder, width: 0.8),
                        ),
                        child: Text(
                          countdown,
                          style: const TextStyle(
                            color: panelText,
                            fontSize: 10,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            shadows: [
                              Shadow(color: panelBorder, blurRadius: 4),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _shouldHideDrawerValue(String? value, String noneLabel) {
    if (value == null) {
      return true;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    return trimmed == noneLabel;
  }

  String _drawerMetricLabel(String? value, String noneLabel) {
    return _shouldHideDrawerValue(value, noneLabel) ? '' : value!;
  }

  int _drawerFreshnessLevel(String value) {
    switch (value) {
      case 'OK':
        return 3;
      case 'USE_SOON':
        return 2;
      case 'URGENT':
        return 1;
      default:
        return 0;
    }
  }

  int _drawerAmountLevel(String? value) {
    if (value == null) {
      return 0;
    }
    switch (value) {
      case 'HIGH':
        return 3;
      case 'MEDIUM':
        return 2;
      case 'LOW':
        return 1;
      default:
        return 0;
    }
  }

  int _drawerConfidenceLevel(double? value) {
    if (value == null) {
      return 0;
    }
    return (value.clamp(0.0, 1.0) * 10).round();
  }

  Widget _buildDrawerMetricBar(
    String label,
    String valueLabel,
    int level,
    int max,
  ) {
    if (level <= 0) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: 56,
            child: Text('$label:'),
          ),
          Expanded(
            child: Row(
              children: List.generate(max, (index) {
                final active = index < level;
                return Expanded(
                  child: Container(
                    height: 6,
                    margin: EdgeInsets.only(right: index == max - 1 ? 0 : 2),
                    decoration: BoxDecoration(
                      color:
                          active ? const Color(0xFF7CFF9A) : const Color(0xFF0B1A0E),
                      border: Border.all(
                        color: const Color(0xFF00FF66),
                        width: 0.6,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          if (valueLabel.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(valueLabel),
          ],
        ],
      ),
    );
  }

  String? _extractDrawerDescription(Map<String, dynamic>? raw) {
    if (raw == null) {
      return null;
    }
    final parsed = raw['parsed'];
    if (parsed is Map<String, dynamic>) {
      final desc = parsed['description'];
      if (desc is String && desc.trim().isNotEmpty) {
        return desc.trim();
      }
    }
    final direct = raw['description'];
    if (direct is String && direct.trim().isNotEmpty) {
      return direct.trim();
    }
    return null;
  }

  String _formatDrawerDateTime(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Widget _buildIngredientThumbnail(CaptureRecord record) {
    final thumbPath = record.thumbnailPath;
    final filePath = record.filePath;
    final thumbFile =
        (thumbPath != null && File(thumbPath).existsSync()) ? File(thumbPath) : null;
    final imageFile = thumbFile??File(filePath);

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 36,
        height: 36,
        color: Colors.black.withValues(alpha: 0.08),
        child: Image.file(
          imageFile,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => const Center(
            child: Icon(
              Icons.image_not_supported,
              size: 16,
              color: Color(0xFF7A8F82),
            ),
          ),
        ),
      ),
    );
  }

  CaptureRecord? _findCaptureForIngredient(
    String ingredient,
    List<CaptureRecord> captures,
  ) {
    if (captures.isEmpty) {
      return null;
    }
    final needle = _normalizeIngredientName(ingredient);
    if (needle.isEmpty) {
      return null;
    }

    for (final record in captures) {
      final secondary = _normalizeIngredientName(record.secondaryLabel ?? '');
      if (secondary.isNotEmpty && needle.contains(secondary)) {
        return record;
      }
    }

    for (final record in captures) {
      final primary = _normalizeIngredientName(record.primaryLabel);
      if (primary.isNotEmpty && needle.contains(primary)) {
        return record;
      }
    }

    return null;
  }

  List<CaptureRecord> _findSimilarCaptures(
    String ingredient,
    List<CaptureRecord> captures,
  ) {
    final needle = _normalizeIngredientName(ingredient);
    if (needle.isEmpty) {
      return const [];
    }
    final tokens = needle.split(' ').where((t) => t.isNotEmpty).toList();
    final results = <CaptureRecord>[];

    for (final record in captures) {
      final secondary = _normalizeIngredientName(record.secondaryLabel ?? '');
      final primary = _normalizeIngredientName(record.primaryLabel);
      if (secondary.isNotEmpty && needle.contains(secondary)) {
        results.add(record);
        continue;
      }
      if (primary.isNotEmpty && needle.contains(primary)) {
        results.add(record);
        continue;
      }
      final recordTokens = <String>{
        ...secondary.split(' ').where((t) => t.isNotEmpty),
        ...primary.split(' ').where((t) => t.isNotEmpty),
      };
      if (tokens.any(recordTokens.contains)) {
        results.add(record);
      }
    }

    return results.take(5).toList();
  }

  RecipeDetail _applySubstitutions(RecipeDetail detail) {
    if (_ingredientSubstitutions.isEmpty) {
      return detail;
    }

    String replaceText(String text) {
      var result = text;
      _ingredientSubstitutions.forEach((key, substitute) {
        final original = _ingredientOriginals[key];
        if (original != null && original.isNotEmpty) {
          result = result.replaceAll(original, substitute);
        }
        if (key.isNotEmpty) {
          result = result.replaceAll(
            RegExp(RegExp.escape(key), caseSensitive: false),
            substitute,
          );
        }
      });
      return result;
    }

    final newIngredients = detail.ingredients.map((item) {
      var updated = item;
      _ingredientSubstitutions.forEach((key, substitute) {
        final original = _ingredientOriginals[key];
        if (original != null && original.isNotEmpty) {
          updated = updated.replaceAll(original, substitute);
          return;
        }
        if (key.isNotEmpty) {
          updated = updated.replaceAll(
            RegExp(RegExp.escape(key), caseSensitive: false),
            substitute,
          );
        }
      });
      return updated;
    }).toList();

    final newSteps = detail.steps.map(replaceText).toList();
    final newSummary = replaceText(detail.summary);

    return RecipeDetail(
      id: detail.id,
      title: detail.title,
      summary: newSummary,
      imageUrl: detail.imageUrl,
      imagePath: detail.imagePath,
      ingredients: newIngredients,
      steps: newSteps,
      tips: detail.tips,
      timeMinutes: detail.timeMinutes,
      servings: detail.servings,
    );
  }

  String _normalizeIngredientName(String value) {
    return value.split('(').first.trim().toLowerCase();
  }

  String _stripStepNumber(String value) {
    return value.replaceFirst(RegExp(r'^\s*\d+\s*[\.)]\s*'), '').trim();
  }

  String _cleanIngredientLabel(String value) {
    var label = value.split('(').first.trim();
    label = label.replaceAll(RegExp(r'\d+[\/\d\s\.]*'), ' ');
    label = label.replaceAll(
      RegExp(
        r'(g|kg|ml|l|cc|tbsp|tsp|cup|ea|마리|큰술|작은술)',
        caseSensitive: false,
      ),
      ' ',
    );
    label = label.replaceAll(RegExp(r'\s+'), ' ').trim();
    return label.isEmpty ? value : label;
  }

  Widget _buildSectionTitle(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
    );
  }

  Widget _buildMetaRow(AppStrings strings, RecipeDetail detail) {
    final items = <Widget>[];
    items.add(Text('${strings.recipeDetailTime}: ${detail.timeMinutes}분'));
    if (detail.servings.isNotEmpty) {
      items.add(Text('${strings.recipeDetailServings}: ${detail.servings}'));
    }

    if (items.isEmpty) {
      return const SizedBox.shrink();
    }

    return Wrap(
      spacing: 12,
      runSpacing: 6,
      children: items,
    );
  }
}
