import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../data/dao/capture_dao.dart';
import '../data/services/recipe_recommendation_service.dart';
import '../data/services/credit_service.dart';
import '../models/capture_record.dart';
import '../models/recipe_recommendation.dart';
import '../models/credit_provider.dart';
import '../widgets/credit_confirm_dialog.dart';
import '../widgets/credit_balance_widget.dart';
import 'capture_history_screen.dart';
import 'recipe_detail_screen.dart';

class RecipeRecommendationScreen extends StatefulWidget {
  final List<CaptureRecord>? initialRecords;

  const RecipeRecommendationScreen({
    super.key,
    this.initialRecords,
  });

  @override
  State<RecipeRecommendationScreen> createState() =>
      _RecipeRecommendationScreenState();
}

class _RecipeRecommendationScreenState
  extends State<RecipeRecommendationScreen>
  with SingleTickerProviderStateMixin {
  final CaptureDao _dao = CaptureDao();
  final RecipeRecommendationService _service =
      RecipeRecommendationService.instance;

  bool _loading = true;
  bool _loadingCategory = false;
  String? _error;
  String? _categoryError;
  List<String> _ingredients = [];
  List<RecipeCard> _defaultCards = [];
  Map<String, List<RecipeCard>> _categoryCards = {};
  String? _selectedCategoryId;
  final Map<String, String> _freshnessByName = {};
  late final AnimationController _skeletonController;
  late final Animation<double> _skeletonShift;

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
    _loadDefaults();
  }

  @override
  void dispose() {
    _skeletonController.dispose();
    super.dispose();
  }

  Future<void> _loadDefaults() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final records = widget.initialRecords ?? await _dao.getAllCaptures();
      _ingredients = _extractIngredients(records);
      if (_ingredients.isEmpty) {
        setState(() {
          _defaultCards = [];
          _loading = false;
        });
        return;
      }
      final hasCache = await _service.hasCachedCards(
        ingredients: _ingredients,
        categoryId: null,
      );
      if (!hasCache) {
        final canProceed = await _confirmAndDeductRecipeGenerate();
        if (!canProceed) {
          setState(() {
            _loading = false;
          });
          return;
        }
      }
      _defaultCards = await _service.recommendDefault(
        ingredients: _ingredients,
      );
      setState(() {
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadCategory(String categoryId, String categoryLabel) async {
    setState(() {
      _selectedCategoryId = categoryId;
      _loadingCategory = true;
      _categoryError = null;
    });

    try {
      final hasCache = await _service.hasCachedCards(
        ingredients: _ingredients,
        categoryId: categoryId,
      );
      if (!hasCache) {
        final canProceed = await _confirmAndDeductRecipeGenerate();
        if (!canProceed) {
          setState(() {
            _loadingCategory = false;
          });
          return;
        }
      }
      final cards = await _service.recommendByCategory(
        ingredients: _ingredients,
        categoryId: categoryId,
        categoryLabel: categoryLabel,
      );
      setState(() {
        _categoryCards[categoryId] = cards;
        _loadingCategory = false;
      });
    } catch (e) {
      setState(() {
        _categoryError = e.toString();
        _loadingCategory = false;
      });
    }
  }

  List<String> _extractIngredients(List<CaptureRecord> records) {
    final cfg = AppConfig.instance;
    final items = <String>{};
    _freshnessByName.clear();
    for (final record in records) {
      final value = (record.secondaryLabel ?? record.primaryLabel).trim();
      if (value.isNotEmpty) {
        final freshnessTag = record.effectiveFreshnessHint();
        final normalizedName = _normalizeIngredientName(value);
        final existing = _freshnessByName[normalizedName];
        if (existing == null || _freshnessRank(freshnessTag) < _freshnessRank(existing)) {
          _freshnessByName[normalizedName] = freshnessTag;
        }
        final amountLabel = record.amountLabel;
        if (amountLabel != null && amountLabel.trim().isNotEmpty) {
          final display = cfg.amountDisplayMap[amountLabel] ?? amountLabel;
          items.add('$value ($display) | freshness: $freshnessTag');
        } else {
          items.add('$value | freshness: $freshnessTag');
        }
      }
    }
    return items.toList();
  }

  String _normalizeIngredientName(String value) {
    return value.split('(').first.trim().toLowerCase();
  }

  String _stripIngredientDecorations(String value) {
    final withoutFreshness = value.split('|').first.trim();
    return withoutFreshness.split('(').first.trim();
  }

  int _freshnessRank(String tag) {
    switch (tag) {
      case 'URGENT':
        return 0;
      case 'USE_SOON':
        return 1;
      default:
        return 2;
    }
  }

  Future<bool> _confirmAndDeductRecipeGenerate() async {
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
      onCharge: () {
        Navigator.pop(context, false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider.getUIString('snackbar_ad_coming_soon'))),
        );
      },
    );

    if (confirmed != true) {
      return false;
    }

    final authToken = await creditProvider.deductCredits(CreditPackage.recipeGenerate);
    if (authToken == null || authToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(creditProvider.getUIString('snackbar_deduct_failed'))),
      );
      return false;
    }

    return true;
  }

  MapEntry<String, String>? _suggestedHighlight() {
    if (_ingredients.isEmpty || _freshnessByName.isEmpty) {
      return null;
    }

    String? bestKey;
    String? bestTag;
    int bestRank = 999;
    _freshnessByName.forEach((key, tag) {
      final rank = _freshnessRank(tag);
      if (rank < bestRank) {
        bestRank = rank;
        bestKey = key;
        bestTag = tag;
      }
    });

    if (bestKey == null || bestTag == null) {
      return null;
    }

    String displayName = bestKey!;
    for (final item in _ingredients) {
      final name = _stripIngredientDecorations(item);
      if (_normalizeIngredientName(name) == bestKey) {
        displayName = name;
        break;
      }
    }

    return MapEntry(displayName, bestTag!);
  }

  String? _findFreshnessTag(String ingredient) {
    final key = _normalizeIngredientName(ingredient);
    return _freshnessByName[key];
  }

  String _freshnessBadgeLabel(String tag) {
    final strings = AppStrings.instance;
    switch (tag) {
      case 'URGENT':
        return strings.freshnessUrgentIcon;
      case 'USE_SOON':
        return strings.freshnessUseSoonIcon;
      default:
        return strings.freshnessOkIcon;
    }
  }

  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.instance;
    final categories = AppConfig.instance.recipeCategories;
    final headerText = _currentHeaderText(strings, categories);

    return Scaffold(
      appBar: _buildAppBar(strings, headerText),
      body: _loading
          ? _buildLoadingBody()
          : _error != null
              ? _buildErrorState(strings)
              : _buildContent(strings, categories),
    );
  }

  String _currentHeaderText(
    AppStrings strings,
    List<Map<String, String>> categories,
  ) {
    if (_loading) {
      return strings.recipeDefaultSection;
    }
    if (_selectedCategoryId == null) {
      return strings.recipeDefaultSection;
    }
    return _categoryLabel(_selectedCategoryId, categories) ??
      strings.recipeCategorySection;
  }

  PreferredSizeWidget _buildAppBar(AppStrings strings, String headerText) {
    return AppBar(
      title: Text(
        strings.recipeTitle,
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
        tooltip: strings.recipeNavHome,
        onPressed: () {
          Navigator.of(context).popUntil((route) => route.isFirst);
        },
        icon: const Icon(Icons.home),
      ),
      actions: [
        IconButton(
          tooltip: strings.recipeNavGallery,
          onPressed: () {
            final highlight = _suggestedHighlight();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CaptureHistoryScreen(
                  initialHighlightName: highlight?.key,
                  initialHighlightFreshness: highlight?.value,
                ),
              ),
            );
          },
          icon: const Icon(Icons.photo_library),
        ),
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
                          onWatchAd: () {
                            Navigator.pop(sheetContext);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(creditService.getUIString('snackbar_ad_coming_soon')),
                                duration: const Duration(seconds: 2),
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
                  if (creditProvider.balance != null)
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
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(36),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _buildHeaderPill(headerText),
        ),
      ),
    );
  }

  Widget _buildLoadingBody() {
    return Column(
      children: [
        Expanded(
          child: _buildSkeletonList(),
        ),
        _buildBottomCategoryBar(AppConfig.instance.recipeCategories),
      ],
    );
  }

  Widget _buildErrorState(AppStrings strings) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(strings.recipeError),
          const SizedBox(height: 8),
          TextButton(
            onPressed: _loadDefaults,
            child: Text(strings.recipeRetry),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(
    AppStrings strings,
    List<Map<String, String>> categories,
  ) {
    if (_ingredients.isEmpty) {
      return Center(child: Text(strings.recipeEmpty));
    }

    return Column(
      children: [
        Expanded(
          child: _buildActiveList(strings, categories),
        ),
        _buildBottomCategoryBar(categories),
      ],
    );
  }

  Widget _buildHeaderPill(String sectionText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFE9F1E4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFF2E5E3F), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      child: Text(
        sectionText,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF2E5E3F),
        ),
      ),
    );
  }

  Widget _buildActiveList(
    AppStrings strings,
    List<Map<String, String>> categories,
  ) {
    if (_selectedCategoryId == null) {
      return _buildRecipeList(_defaultCards, strings);
    }

    if (_loadingCategory) {
      return _buildSkeletonList();
    }

    if (_categoryError != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(strings.recipeError),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                final selected = categories.firstWhere(
                  (item) => item['id'] == _selectedCategoryId,
                  orElse: () => {},
                );
                final id = selected['id'];
                final label = selected['label'];
                if (id != null && label != null) {
                  _loadCategory(id, label);
                }
              },
              child: Text(strings.recipeRetry),
            ),
          ],
        ),
      );
    }

    final cards = _categoryCards[_selectedCategoryId] ?? [];
    return _buildRecipeList(cards, strings);
  }

  Widget _buildRecipeList(List<RecipeCard> cards, AppStrings strings) {
    if (cards.isEmpty) {
      return Center(child: Text(strings.recipeEmpty));
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: cards
          .map((card) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildRecipeCard(card),
              ))
          .toList(),
    );
  }

  Widget _buildSkeletonList() {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      itemCount: 4,
      itemBuilder: (context, index) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSkeletonBar(width: 140, height: 16),
                const SizedBox(height: 8),
                _buildSkeletonBar(width: double.infinity, height: 12),
                const SizedBox(height: 6),
                _buildSkeletonBar(width: 220, height: 12),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _buildSkeletonChip(width: 56),
                    _buildSkeletonChip(width: 68),
                    _buildSkeletonChip(width: 50),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSkeletonBar({required double width, required double height}) {
    return _buildShimmer(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: width,
        height: height,
        color: Colors.black.withValues(alpha: 0.08),
      ),
    );
  }

  Widget _buildSkeletonChip({required double width}) {
    return _buildShimmer(
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: width,
        height: 20,
        color: Colors.black.withValues(alpha: 0.08),
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

  Widget _buildBottomCategoryBar(List<Map<String, String>> categories) {
    if (categories.isEmpty) {
      return const SizedBox.shrink();
    }

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
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
          children: categories.map((category) {
            final id = category['id'] ?? '';
            final label = category['label'] ?? '';
            final icon = category['icon'] ?? '';
            final selected = _selectedCategoryId == id;
            return Expanded(
              child: InkWell(
                onTap: () {
                  if (selected) {
                    setState(() {
                      _selectedCategoryId = null;
                    });
                    return;
                  }
                  _loadCategory(id, label);
                },
                borderRadius: BorderRadius.circular(999),
                child: Center(
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: selected
                          ? Colors.black.withValues(alpha: 0.1)
                          : Colors.black.withValues(alpha: 0.02),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF2E5E3F)
                            : const Color(0xFFC5D6BD),
                      ),
                      boxShadow: selected
                          ? [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.08),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Opacity(
                      opacity: selected ? 1.0 : 0.75,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedScale(
                            duration: const Duration(milliseconds: 140),
                            scale: selected ? 1.12 : 1.0,
                            child: Text(
                              icon.isEmpty ? label : icon,
                              style: const TextStyle(fontSize: 22),
                            ),
                          ),
                          const SizedBox(height: 4),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              label,
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }


  String? _categoryLabel(
    String? categoryId,
    List<Map<String, String>> categories,
  ) {
    if (categoryId == null) {
      return null;
    }
    final match = categories.firstWhere(
      (item) => item['id'] == categoryId,
      orElse: () => {},
    );
    return match['label'];
  }

  Widget _buildRecipeCard(RecipeCard card) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () {
        final categoryLabel = _selectedCategoryId == null
            ? null
            : AppConfig.instance.recipeCategories
                .firstWhere(
                  (item) => item['id'] == _selectedCategoryId,
                  orElse: () => {},
                )['label'];
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => RecipeDetailScreen(
              card: card,
              ingredients: _ingredients,
              categoryLabel: categoryLabel ?? '',
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              card.title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            if (card.summary.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(card.summary),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: card.mainIngredients
                  .map((item) => _buildIngredientChip(item))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIngredientChip(String item) {
    final tag = _findFreshnessTag(item);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            item,
            style: const TextStyle(fontSize: 12),
          ),
          if (tag != null) ...[
            const SizedBox(width: 6),
            Text(
              _freshnessBadgeLabel(tag),
              style: const TextStyle(
                fontSize: 14,
                height: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
