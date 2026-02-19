import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/dao/capture_dao.dart';
import '../data/services/credit_service.dart';
import '../data/services/ad_service.dart';
import '../models/capture_record.dart';
import '../models/credit_provider.dart';
import '../config/app_strings.dart';
import '../config/app_config.dart';
import '../main.dart';
import '../widgets/credit_balance_widget.dart';
import 'capture_detail_screen.dart';
import 'recipe_recommendation_screen.dart';
import 'reward_claim_screen.dart';

class CaptureHistoryScreen extends StatefulWidget {
  final String? initialQuery;
  final String? initialHighlightName;
  final String? initialHighlightFreshness;

  const CaptureHistoryScreen({
    super.key,
    this.initialQuery,
    this.initialHighlightName,
    this.initialHighlightFreshness,
  });

  @override
  State<CaptureHistoryScreen> createState() => _CaptureHistoryScreenState();
}

class _CaptureHistoryScreenState extends State<CaptureHistoryScreen> {
  late Future<List<CaptureRecord>> _future;
  final CaptureDao _dao = CaptureDao();
  String _searchQuery = '';
  late final TextEditingController _searchController;
  String? _highlightId;
  String? _highlightFreshness;
  bool _didAutoScroll = false;
  bool _didTabJump = false;
  final Map<String, GlobalKey> _itemKeys = {};

  @override
  void initState() {
    super.initState();
    _future = _dao.getAllCaptures();
    _searchController = TextEditingController();
    final query = (widget.initialQuery ?? '').trim();
    if (query.isNotEmpty) {
      _searchQuery = query;
      _searchController.text = query;
    }
    _highlightId = null;
    _highlightFreshness = widget.initialHighlightFreshness;
    _didAutoScroll = false;
    _didTabJump = false;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _future = _dao.getAllCaptures();
    });
  }

  String _formatDateTime(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    final h = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $h:$mm';
  }

  Future<void> _deleteCapture(BuildContext context, CaptureRecord item) async {
    final strings = AppStrings.instance;
    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return Material(
          type: MaterialType.transparency,
          child: Center(
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 24),
              decoration: BoxDecoration(
                color: const Color(0xFFF7F1E4),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFF2A4DB3), width: 2),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.2),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    decoration: const BoxDecoration(
                      color: Color(0xFF2A4DB3),
                      borderRadius: BorderRadius.vertical(top: Radius.circular(4)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            strings.deleteButton,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          width: 18,
                          height: 18,
                          decoration: BoxDecoration(
                            color: Colors.red.shade700,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: IconButton(
                            onPressed: () => Navigator.pop(context, false),
                            icon: const Icon(Icons.close, size: 12, color: Colors.white),
                            padding: EdgeInsets.zero,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 38,
                          height: 38,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53935),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.close, color: Colors.white, size: 22),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              strings.deleteConfirm,
                              style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: Colors.black87) ??
                                  const TextStyle(color: Colors.black87),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    child: Row(
                      children: [
                        const Spacer(),
                        SizedBox(
                          height: 34,
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context, false),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.black87,
                              side: const BorderSide(color: Colors.black26),
                              backgroundColor: const Color(0xFFEDEDED),
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            child: Text(strings.cancelButton),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          height: 34,
                          child: ElevatedButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF2A4DB3),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            child: Text(strings.deleteButton),
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

    if (confirm != true) {
      return;
    }

    try {
      if (item.thumbnailPath != null) {
        try {
          await File(item.thumbnailPath!).delete();
        } catch (_) {}
      }
      try {
        await File(item.filePath).delete();
      } catch (_) {}
      final deleted = await _dao.deleteCapture(item.id);
      if (!deleted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('삭제에 실패했습니다. 다시 시도해 주세요.')),
          );
        }
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.historyDeleteSuccess)),
        );
      }
      _refresh();
    } catch (e) {
      debugPrint('❌ [History] delete failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제에 실패했습니다. 다시 시도해 주세요.')),
        );
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    final strings = AppStrings.instance;
    return Scaffold(
      backgroundColor: const Color(0xFFF5F8F3),
      appBar: AppBar(
        title: Text(
          strings.historyAppBarTitle,
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
          if (_searchQuery.trim().isNotEmpty)
            IconButton(
              tooltip: strings.historySearchClear,
              onPressed: () {
                _searchController.clear();
                setState(() {
                  _searchQuery = '';
                });
              },
              icon: const Icon(Icons.clear),
            ),
          IconButton(
            onPressed: () => _openSearchSheet(context),
            icon: const Icon(Icons.search),
          ),
          IconButton(
            tooltip: strings.recipeButtonTooltip,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const RecipeRecommendationScreen(),
                ),
              );
            },
            icon: const Icon(Icons.restaurant_menu),
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
                            onWatchAd: () async {
                              final adService = AdService();
                              
                              Navigator.pop(sheetContext);
                              
                              // Wait for bottom sheet context to dispose before using outer context
                              await Future.delayed(const Duration(milliseconds: 100));
                              
                              if (!mounted) return;
                              
                              // Check if ad is ready
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
                              
                              // Show the ad
                              print('📱 [Screen] Showing rewarded ad...');
                              bool rewardCallbackFired = false;
                              final rewardAmount = 0.5;
                              final rewardEarned = await adService.showRewardedAd(
                                onReward: (amount) {
                                  rewardCallbackFired = true;
                                  print('🎁 [Screen] Reward callback called: $amount');
                                },
                                onAdDismissed: () {
                                  if (!rewardCallbackFired) {
                                    return;
                                  }
                                  navigatorKey.currentState?.push(
                                    PageRouteBuilder(
                                      pageBuilder: (_, __, ___) => RewardClaimScreen(
                                        rewardAmount: rewardAmount,
                                        symbol: creditService.getUIString('symbol'),
                                      ),
                                      transitionDuration: Duration.zero,
                                      reverseTransitionDuration: Duration.zero,
                                    ),
                                  );
                                },
                              );
                              
                              print('📱 [Screen] Ad finished. Reward earned: $rewardEarned');
                              
                              // Check if context is still valid (user didn't navigate away)
                              if (!mounted) {
                                print('⚠️ [Screen] Context deactivated, skipping notification');
                                return;
                              }
                              
                              if (!rewardEarned) {
                                print('❌ [Screen] No reward earned, user closed ad early');
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(creditService.getUIString('snackbar_ad_failed')),
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              
                              print('✅ [Screen] User earned reward, reward screen shown on ad dismiss');
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
      body: FutureBuilder<List<CaptureRecord>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final data = snapshot.data;
          if (data == null || data.isEmpty) {
            return Center(child: Text(strings.historyEmpty));
          }

          final items = _filterByQuery(data);
          if (items.isEmpty) {
            return Center(child: Text(strings.historySearchEmpty));
          }

          final grouped = _groupByFreshness(items);
          final isSearching = _searchQuery.trim().isNotEmpty;

          return DefaultTabController(
            initialIndex: _initialTabIndex(),
            length: _freshnessKeys.length,
            child: Builder(
              builder: (context) {
                if (!isSearching) {
                  _scheduleTabJump(DefaultTabController.of(context));
                }
                return Column(
                  children: [
                    if (!isSearching)
                      TabBar(
                        labelColor: const Color(0xFF2E5E3F),
                        unselectedLabelColor: const Color(0xFF4C6D57),
                        indicatorColor: const Color(0xFF2E5E3F),
                        tabs: _freshnessKeys
                            .map(
                              (key) => _buildFreshnessTab(
                                key,
                                (grouped[key] ?? []).length,
                              ),
                            )
                            .toList(),
                      ),
                    Expanded(
                      child: isSearching
                          ? _buildSearchList(items)
                          : TabBarView(
                              children: _freshnessKeys
                                  .map((key) => _buildTabList(key, grouped[key] ?? []))
                                  .toList(),
                            ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  static const List<String> _freshnessKeys = ['URGENT', 'USE_SOON', 'OK'];

  int _initialTabIndex() {
    final target = (widget.initialHighlightFreshness ?? '').trim();
    if (target.isEmpty) {
      return 0;
    }
    final normalized = _normalizeFreshness(target);
    final index = _freshnessKeys.indexOf(normalized);
    return index == -1 ? 0 : index;
  }

  String _normalizeHighlightName(String value) {
    return value.trim().toLowerCase();
  }

  bool _isHighlighted(CaptureRecord item) {
    if (_highlightId != null && _highlightId == item.id) {
      return true;
    }
    final targetName = (widget.initialHighlightName ?? '').trim();
    if (targetName.isEmpty) {
      return false;
    }

    final targetFreshness = (widget.initialHighlightFreshness ?? '').trim();
    if (targetFreshness.isNotEmpty) {
      final itemKey = _normalizeFreshness(item.effectiveFreshnessHint());
      if (itemKey != _normalizeFreshness(targetFreshness)) {
        return false;
      }
    }

    final needle = _normalizeHighlightName(targetName);
    final primary = _normalizeHighlightName(item.primaryLabel);
    final secondary = _normalizeHighlightName(item.secondaryLabel ?? '');
    return primary.contains(needle) || secondary.contains(needle);
  }

  Future<void> _openSearchSheet(BuildContext context) async {
    final strings = AppStrings.instance;
    _searchController.text = _searchQuery;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: _searchController.text.length),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              16 + MediaQuery.viewInsetsOf(context).bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      strings.historySearchTitle,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      child: Text(strings.historySearchClear),
                    ),
                  ],
                ),
                TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.trim();
                    });
                  },
                  onSubmitted: (_) => Navigator.pop(context),
                  decoration: InputDecoration(
                    hintText: strings.historySearchHint,
                    prefixIcon: const Icon(Icons.search),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<CaptureRecord> _filterByQuery(List<CaptureRecord> items) {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) {
      return items;
    }

    final cfg = AppConfig.instance;
    return items.where((item) {
      final displayCategory =
          cfg.categoryDisplayMap[item.category] ?? item.category;
      final haystack = [
        item.primaryLabel,
        item.secondaryLabel ?? '',
        displayCategory,
        _formatDateTime(item.createdAt),
      ].join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  Map<String, List<CaptureRecord>> _groupByFreshness(
      List<CaptureRecord> items) {
    final grouped = <String, List<CaptureRecord>>{
      for (final key in _freshnessKeys) key: <CaptureRecord>[],
    };

    for (final item in items) {
      final key = _normalizeFreshness(item.effectiveFreshnessHint());
      (grouped[key] ??= []).add(item);
    }

    return grouped;
  }

  String _normalizeFreshness(String hint) {
    if (hint == 'URGENT' || hint == 'USE_SOON' || hint == 'OK') {
      return hint;
    }
    return 'OK';
  }

  String _freshnessLabel(String key) {
    final strings = AppStrings.instance;
    switch (key) {
      case 'URGENT':
        return strings.freshnessUrgentIcon;
      case 'USE_SOON':
        return strings.freshnessUseSoonIcon;
      default:
        return strings.freshnessOkIcon;
    }
  }

  String _freshnessDescription(String key) {
    final strings = AppStrings.instance;
    switch (key) {
      case 'URGENT':
        return strings.freshnessUrgentDesc;
      case 'USE_SOON':
        return strings.freshnessUseSoonDesc;
      default:
        return strings.freshnessOkDesc;
    }
  }

  Future<void> _showFreshnessHelp(BuildContext context, String key) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(_freshnessLabel(key)),
        content: Text(_freshnessDescription(key)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppStrings.instance.freshnessHelpOk),
          ),
        ],
      ),
    );
  }

  Widget _buildFreshnessTab(String key, int count) {
    return Tab(
      child: Tooltip(
        message: _freshnessDescription(key),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: Text(
                  _freshnessLabel(key),
                  style: const TextStyle(fontSize: 26),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                color: const Color(0xFF4C6D57),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabList(String key, List<CaptureRecord> items) {
    if (items.isEmpty) {
      return Center(child: Text(_freshnessDescription(key)));
    }

    _scheduleScrollToHighlight(items);

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.only(bottom: 12 + bottomInset),
      children: items
          .map((item) => _buildCaptureCard(item, highlight: _isHighlighted(item)))
          .toList(),
    );
  }

  Widget _buildSearchList(List<CaptureRecord> items) {
    _scheduleScrollToHighlight(items);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.only(bottom: 12 + bottomInset),
      children: items
          .map((item) => _buildCaptureCard(item, highlight: _isHighlighted(item)))
          .toList(),
    );
  }

  void _scheduleScrollToHighlight(List<CaptureRecord> items) {
    if (_didAutoScroll) {
      return;
    }

    final highlightId = _resolveHighlightId(items);
    if (highlightId == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _itemKeys[highlightId];
      final context = key?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          alignment: 0.1,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
        _didAutoScroll = true;
      }
    });
  }

  void _scheduleTabJump(TabController controller) {
    if (_didTabJump) {
      return;
    }

    final target = (_highlightFreshness ?? '').trim();
    if (target.isEmpty) {
      return;
    }

    final normalized = _normalizeFreshness(target);
    final index = _freshnessKeys.indexOf(normalized);
    if (index == -1 || controller.index == index) {
      _didTabJump = true;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      controller.animateTo(index);
      _didTabJump = true;
      _didAutoScroll = false;
    });
  }

  String? _resolveHighlightId(List<CaptureRecord> items) {
    if (_highlightId != null) {
      return _highlightId;
    }

    final targetName = (widget.initialHighlightName ?? '').trim();
    if (targetName.isEmpty) {
      return null;
    }

    for (final item in items) {
      if (_isHighlighted(item)) {
        return item.id;
      }
    }
    return null;
  }

  Widget _buildCaptureCard(CaptureRecord item, {bool highlight = false}) {
    final cfg = AppConfig.instance;
    final displayCategory =
        cfg.categoryDisplayMap[item.category] ?? item.category;
    final secondary = (item.secondaryLabel ?? '').trim();
    final secondaryLabel = secondary.isEmpty ? null : secondary;
    final titleLabel = secondaryLabel ?? item.primaryLabel;
    final primaryLabel = item.primaryLabel.trim();
    final roleLabel = item.usageRole == null
        ? null
        : (cfg.usageRoleDisplayMap[item.usageRole] ?? item.usageRole);
    final countdown = item.shelfLifeCountdownLabel();
    final tagLabels = item.stateTags
        .map((tag) => cfg.stateTagDisplayMap[tag] ?? tag)
        .where((tag) => tag.trim().isNotEmpty)
        .toList();
    final freshnessKey = _normalizeFreshness(item.effectiveFreshnessHint());
    final metaChipWidgets = <Widget>[];
    if (secondaryLabel == null && primaryLabel.isNotEmpty) {
      metaChipWidgets.add(_buildMetaChip(primaryLabel, isTag: false));
    } else if (secondaryLabel != null && primaryLabel.isNotEmpty) {
      metaChipWidgets.add(_buildMetaChip(primaryLabel, isTag: false));
    }
    if (roleLabel != null && roleLabel.trim().isNotEmpty) {
      metaChipWidgets.add(_buildMetaChip(roleLabel, isTag: false));
    }
    if (countdown != null) {
      metaChipWidgets.add(
        _buildMetaChip(countdown, isTag: false),
      );
    }
    if (tagLabels.isNotEmpty) {
      final visibleTags = tagLabels.take(2).toList();
      metaChipWidgets.addAll(
        visibleTags.map((label) => _buildMetaChip(label, isTag: true)),
      );
      final remaining = tagLabels.length - visibleTags.length;
      if (remaining > 0) {
        metaChipWidgets.add(_buildMetaChip('+$remaining', isTag: true));
      }
    }
    final itemKey = _itemKeys.putIfAbsent(item.id, () => GlobalKey());
    return KeyedSubtree(
      key: itemKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            final result = await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => CaptureDetailScreen(
                  record: item,
                  returnHighlightOnCancel: true,
                ),
              ),
            );
            if (result is Map) {
              final deletedId = result['deletedId'] as String?;
              if (deletedId != null && deletedId.isNotEmpty) {
                setState(() {
                  if (_highlightId == deletedId) {
                    _highlightId = null;
                    _highlightFreshness = null;
                  }
                });
              }
              final highlightId = result['highlightId'] as String?;
              final highlightFreshness = result['highlightFreshness'] as String?;
              if ((highlightId != null && highlightId.isNotEmpty) ||
                  (highlightFreshness != null && highlightFreshness.isNotEmpty)) {
                setState(() {
                  _highlightId = highlightId;
                  _highlightFreshness = highlightFreshness;
                  _didAutoScroll = false;
                  _didTabJump = false;
                });
              }
            }
            _refresh();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: highlight
                  ? const Color(0xFFDDE8D6)
                  : const Color(0xFFE9F1E4),
              border: Border.all(
                color: highlight
                    ? const Color(0xFF2E5E3F)
                    : const Color(0xFFC5D6BD),
                width: highlight ? 1.6 : 1.0,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: highlight
                  ? [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(
                  File(item.filePath),
                  width: 56,
                  height: 56,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 56,
                      height: 56,
                      color: Colors.black12,
                      child:
                          const Icon(Icons.broken_image, color: Colors.black45),
                    );
                  },
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            titleLabel,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF2E5E3F),
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: BorderRadius.circular(999),
                          onTap: () =>
                              _showFreshnessHelp(context, freshnessKey),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 2),
                            child: Text(
                              _freshnessLabel(freshnessKey),
                              style: const TextStyle(fontSize: 18),
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete, color: Colors.red),
                          onPressed: () => _deleteCapture(context, item),
                          constraints: const BoxConstraints(
                            minWidth: 32,
                            minHeight: 32,
                          ),
                          padding: const EdgeInsets.all(4),
                          splashRadius: 18,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '$displayCategory · ${_formatDateTime(item.createdAt)}',
                      style: const TextStyle(color: Color(0xFF4C6D57)),
                    ),
                    if (metaChipWidgets.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      SizedBox(
                        height: 24,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: metaChipWidgets
                                .map(
                                  (chip) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: chip,
                                  ),
                                )
                                .toList(),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMetaChip(String label, {required bool isTag}) {
    final Color chipColor = isTag
      ? const Color(0xFFE3EFE9)
      : Colors.black.withValues(alpha: 0.04);
    final Color borderColor = isTag
      ? const Color(0xFF6C8F7B)
      : const Color(0xFFC5D6BD);
    final Color textColor = isTag
      ? const Color(0xFF2E5E3F)
      : const Color(0xFF4C6D57);

    return Container(
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: chipColor,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: borderColor),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 11,
          height: 1.0,
          color: textColor,
          fontWeight: isTag ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
    );
  }
}
