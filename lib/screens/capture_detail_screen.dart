import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../data/dao/capture_dao.dart';
import '../data/services/ai_recognition_service.dart';
import '../data/services/credit_service.dart';
import '../data/services/ad_service.dart';
import '../models/capture_record.dart';
import '../models/credit_provider.dart';
import '../main.dart';
import '../widgets/credit_confirm_dialog.dart';
import 'recipe_recommendation_screen.dart';
import 'reward_claim_screen.dart';

class CaptureDetailScreen extends StatefulWidget {
  final CaptureRecord record;
  final bool returnHighlightOnCancel;

  const CaptureDetailScreen({
    super.key,
    required this.record,
    this.returnHighlightOnCancel = false,
  });

  @override
  State<CaptureDetailScreen> createState() => _CaptureDetailScreenState();
}

class _CaptureDetailScreenState extends State<CaptureDetailScreen> {
  static const String _hideExpiredWarningDateKey = 'hide_expired_warning_date';
  final CaptureDao _dao = CaptureDao();
  final AiRecognitionService _aiService = AiRecognitionService.instance;
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _statusScrollController = ScrollController();
  late CaptureRecord _record;
  late final VoidCallback _revisionListener;
  bool _isReanalyzing = false;
  bool _expiredWarningDisplayed = false;
  late _MaterialItem? _selectedMaterial;
  List<_MaterialItem> _materialIndex = [];

  @override
  void initState() {
    super.initState();
    _record = widget.record;
    _selectedMaterial = _findMaterialForRecord();
    _materialIndex = _buildSearchItems(AppConfig.instance.materialIndex);
    _loadUserMaterialIndex();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowExpiredWarningDialog();
    });
    _revisionListener = () async {
      final updated = await _dao.getCapture(_record.id);
      if (!mounted) {
        return;
      }
      setState(() {
        _record = updated;
        if (_isReanalyzing) {
          _isReanalyzing = !_isRecordAnalyzed(updated);
        }
      });
    };
    _aiService.revision.addListener(_revisionListener);
  }

  @override
  void dispose() {
    _aiService.revision.removeListener(_revisionListener);
    _searchController.dispose();
    _statusScrollController.dispose();
    super.dispose();
  }

  Future<void> _reanalyzeCurrent() async {
    final strings = AppStrings.instance;
    if (_isReanalyzing) {
      return;
    }

    CreditProvider? creditProvider;

    // �크레딧 프리뷰용 �확인
    if (mounted && context.mounted) {
      creditProvider = context.read<CreditProvider>();
      final costInfo = creditProvider.getCostInfo(CreditPackage.ingredientScan);
      final currentBalance = creditProvider.balance;

      if (currentBalance == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider.getUIString('snackbar_loading_credit'))),
        );
        return;
      }

      // Confirm ~~표표시
      final confirmed = await CreditConfirmDialog.show(
        context,
        costInfo: costInfo,
        currentCredits: currentBalance.credits,
        onConfirm: () {},
        onCharge: () {
          Navigator.pop(context, false); // 취소
          showModalBottomSheet(
            context: context,
            backgroundColor: Colors.transparent,
            builder: (context) {
              // 충전 �실패널 �표표시
              return const SizedBox(height: 1);
            },
          );
        },
      );

      if (confirmed != true) {
        return;
      }
    }

    try {
      if (mounted) {
        setState(() {
          _isReanalyzing = true;
        });
      }
      await _dao.resetForReanalysis(_record.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(strings.historyReanalyzeStarted)),
        );
      }

      final success = await _aiService.enqueueRecognitionAndWait(
        captureId: _record.id,
        filePath: _record.filePath,
      );

      if (!mounted) {
        return;
      }

      if (!success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 분석 실패로 크레딧이 차감되지 않았습니다')),
        );
        return;
      }

      final authToken = await creditProvider?.deductCredits(CreditPackage.ingredientScan);
      if (authToken == null || authToken.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(creditProvider?.getUIString('snackbar_deduct_failed') ?? '크레딧 차감 실패')),
        );
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isReanalyzing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.65,
            child: Stack(
              children: [
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.file(
                          File(_record.filePath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              color: Colors.black54,
                              child: const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Colors.white54,
                                  size: 64,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 260, 12, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final overlayHeight =
                            constraints.maxHeight.clamp(120.0, constraints.maxHeight);
                        return Align(
                          alignment: Alignment.topLeft,
                          child: _buildStatusPanel(context, overlayHeight),
                        );
                      },
                    ),
                  ),
                ),
                Positioned(
                  top: 12 + MediaQuery.paddingOf(context).top,
                  right: 12,
                  child: IconButton(
                    tooltip: AppStrings.instance.recipeButtonTooltip,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecipeRecommendationScreen(
                            initialRecords: [_record],
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.restaurant_menu),
                    color: const Color(0xFF2E5E3F),
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFFAABEA5),
                    ),
                  ),
                ),
                Positioned(
                  top: 12 + MediaQuery.paddingOf(context).top,
                  left: 12,
                  child: _buildReanalyzeControl(),
                ),
              ],
            ),
          ),
          Expanded(child: _buildEditSection(context)),
        ],
      ),
    );
  }

  bool _isRecordAnalyzed(CaptureRecord record) {
    return (record.modelVersion?.isNotEmpty ?? false) ||
        record.category != 'ETC' ||
        record.primaryLabel != AppConfig.instance.defaultPrimaryLabel;
  }

  Widget _buildReanalyzeControl() {
    const fg = Color(0xFF2E5E3F);
    const bg = Color(0xFFAABEA5);
    if (_isReanalyzing) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.0,
                  valueColor: AlwaysStoppedAnimation<Color>(fg),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                AppStrings.instance.get('status_value_analyzing'),
                style: const TextStyle(
                  color: fg,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return IconButton(
      tooltip: AppStrings.instance.historyReanalyze,
      onPressed: _reanalyzeCurrent,
      icon: const Icon(Icons.autorenew),
      color: fg,
      style: IconButton.styleFrom(
        backgroundColor: bg,
      ),
    );
  }

  Widget _buildStatusPanel(BuildContext context, double maxHeight) {
    final strings = AppStrings.instance;
    final cfg = AppConfig.instance;
    final none = strings.get('status_value_none');
    const panelBg = Color(0xFF000000);
    const panelBorder = Color(0xFF00FF66);
    const panelText = Color(0xFF7CFF9A);

    final category = cfg.categoryDisplayMap[_record.category] ?? _record.category;
    final effectiveFreshness = _record.effectiveFreshnessHint();
    final freshness = cfg.freshnessDisplayMap[effectiveFreshness] ??
      effectiveFreshness;
    final amount = _record.amountLabel == null
      ? none
      : (cfg.amountDisplayMap[_record.amountLabel!] ?? _record.amountLabel!);
    final role = _record.usageRole == null
      ? none
      : (cfg.usageRoleDisplayMap[_record.usageRole!] ?? _record.usageRole!);
    final countdown = _record.shelfLifeCountdownLabel();
    final secondary = _record.secondaryLabel;
    final tagLabels = _record.stateTags
        .map((tag) => cfg.stateTagDisplayMap[tag] ?? tag)
        .toList();
    final tags = tagLabels.isEmpty ? none : tagLabels.join(', ');
    final confidence = _record.confidence?.toStringAsFixed(2) ?? none;
    final description = _extractDescription(_record.aiRawJson) ?? none;

    final time = _formatDateTime(_record.createdAt);

    final textLines = <String>[];
    final primaryLine = '${strings.get('status_label_primary')}: ${_record.primaryLabel}';
    final categoryLine = '${strings.get('status_label_category')}: $category';
    final secondaryLine = '${strings.get('status_label_secondary')}: $secondary';
    final tagsLine = '${strings.get('status_label_tags')}: $tags';
    final roleLine = '${strings.get('status_label_role')}: $role';
    final descriptionLine = '${strings.get('status_label_description')}: $description';

    if (!_shouldHideValue(_record.primaryLabel, none)) {
      textLines.add(primaryLine);
    }
    if (!_shouldHideValue(category, none)) {
      textLines.add(categoryLine);
    }
    if (!_shouldHideValue(secondary, none)) {
      textLines.add(secondaryLine);
    }
    if (!_shouldHideValue(tags, none)) {
      textLines.add(tagsLine);
    }
    if (!_shouldHideValue(role, none)) {
      textLines.add(roleLine);
    }

    final panelHeight = maxHeight.clamp(120.0, maxHeight);

    return Container(
      width: double.infinity,
      height: panelHeight,
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
            child: ScrollbarTheme(
              data: ScrollbarThemeData(
                thumbColor: WidgetStateProperty.all(panelText.withValues(alpha: 0.7)),
                trackColor: WidgetStateProperty.all(panelBg.withValues(alpha: 0.6)),
                thickness: WidgetStateProperty.all(6),
                radius: const Radius.circular(0),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return Scrollbar(
                    thumbVisibility: true,
                    controller: _statusScrollController,
                    child: SingleChildScrollView(
                      controller: _statusScrollController,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minWidth: constraints.maxWidth),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(0, 6, 10, 6),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              ...textLines.map(Text.new),
                              if (!_shouldHideValue(freshness, none))
                                _buildMetricBar(
                                  strings.get('status_label_freshness'),
                                  _metricLabel(freshness, none),
                                  _freshnessLevel(effectiveFreshness),
                                  3,
                                ),
                              if (!_shouldHideValue(amount, none))
                                _buildMetricBar(
                                  strings.get('status_label_amount'),
                                  _metricLabel(amount, none),
                                  _amountLevel(_record.amountLabel),
                                  3,
                                ),
                              if (!_shouldHideValue(confidence, none))
                                _buildMetricBar(
                                  strings.get('status_label_confidence'),
                                  _metricLabel(confidence, none),
                                  _confidenceLevel(_record.confidence),
                                  10,
                                ),
                              if (!_shouldHideValue(description, none))
                                Text(descriptionLine),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
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
                child: Row(
                  mainAxisSize: MainAxisSize.min,
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
                    if (countdown != null && countdown.isNotEmpty) ...[
                      const SizedBox(width: 6),
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
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  bool _shouldHideValue(String? value, String noneLabel) {
    if (value == null) {
      return true;
    }
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return true;
    }
    return trimmed == noneLabel;
  }

  String _metricLabel(String? value, String noneLabel) {
    return _shouldHideValue(value, noneLabel) ? '' : value!;
  }

  int _freshnessLevel(String value) {
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

  int _amountLevel(String? value) {
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

  int _confidenceLevel(double? value) {
    if (value == null) {
      return 0;
    }
    return (value.clamp(0.0, 1.0) * 10).round();
  }

  Widget _buildMetricBar(String label, String valueLabel, int level, int max) {
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
                      color: active ? const Color(0xFF7CFF9A) : const Color(0xFF0B1A0E),
                      border: Border.all(color: const Color(0xFF00FF66), width: 0.6),
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

  String? _extractDescription(Map<String, dynamic>? raw) {
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

  String _formatDateTime(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Widget _buildEditSection(BuildContext context) {
    final strings = AppStrings.instance;
    final levelValueStyle = Theme.of(context).textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: const Color(0xFF2E5E3F),
        ) ?? const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2E5E3F));
    final levelLabelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w600,
          color: const Color(0xFF4C6D57),
        ) ?? const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF4C6D57));
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 2, 16, 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: const Border(top: BorderSide(color: Colors.black12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              icon: const Icon(Icons.search, size: 18),
              label: Text(strings.get('edit_search_label')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFAABEA5),
                foregroundColor: const Color(0xFF2E5E3F),
                elevation: 2,
                shadowColor: Colors.black.withValues(alpha: 0.15),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => _openSearchSheet(context),
            ),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFE9F1E4),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFC5D6BD)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                _buildEditLevelRow(
                  label: strings.editLevel1,
                  value: _selectedMaterial?.categoryLabel ?? '',
                  labelStyle: levelLabelStyle,
                  valueStyle: levelValueStyle,
                ),
                const SizedBox(height: 6),
                _buildEditLevelRow(
                  label: strings.editLevel2,
                  value: _selectedMaterial?.primaryLabel ?? '',
                  labelStyle: levelLabelStyle,
                  valueStyle: levelValueStyle,
                ),
                const SizedBox(height: 6),
                _buildEditLevelRow(
                  label: strings.editLevel3,
                  value: _selectedMaterial?.secondaryLabel ?? '',
                  labelStyle: levelLabelStyle,
                  valueStyle: levelValueStyle,
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _applyClassification(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2E5E3F),
                    foregroundColor: const Color(0xFFB8C9B0),
                    elevation: 2,
                    shadowColor: Colors.black.withValues(alpha: 0.12),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(strings.editApply),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _handleCancel,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF2E5E3F),
                    side: const BorderSide(color: Color(0xFF2E5E3F), width: 1.2),
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: Text(strings.get('edit_cancel')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _handleCancel() {
    if (widget.returnHighlightOnCancel) {
      Navigator.of(context).pop({
        'highlightId': _record.id,
        'highlightFreshness': _record.effectiveFreshnessHint(),
      });
      return;
    }
    Navigator.of(context).maybePop();
  }

  bool _isExpiredForDiscardWarning() {
    final shelfLifeDays = _record.shelfLifeDays;
    if (shelfLifeDays == null || shelfLifeDays <= 0) {
      return false;
    }
    final ageDays = DateTime.now().difference(_record.createdAt).inDays;
    return ageDays > shelfLifeDays;
  }

  Future<void> _maybeShowExpiredWarningDialog() async {
    if (!mounted || _expiredWarningDisplayed) {
      return;
    }
    if (!_isExpiredForDiscardWarning()) {
      return;
    }
    if (await _isExpiredWarningHiddenToday()) {
      return;
    }
    _expiredWarningDisplayed = true;
    await _showExpiredWarningDialog();
  }

  String _todayKey() {
    final now = DateTime.now();
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  Future<bool> _isExpiredWarningHiddenToday() async {
    final prefs = await SharedPreferences.getInstance();
    final hiddenDate = prefs.getString(_hideExpiredWarningDateKey);
    return hiddenDate == _todayKey();
  }

  Future<void> _hideExpiredWarningForToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hideExpiredWarningDateKey, _todayKey());
  }

  Future<void> _showExpiredWarningDialog() async {
    final countdown = _record.shelfLifeCountdownLabel() ?? 'D+1';
    bool hideTodayChecked = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
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
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFCC9A00),
                                  size: 34,
                                ),
                                const SizedBox(width: 10),
                                const Expanded(
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
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                setDialogState(() {
                                  hideTodayChecked = !hideTodayChecked;
                                });
                              },
                              child: Row(
                                children: [
                                  SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: Checkbox(
                                      value: hideTodayChecked,
                                      onChanged: (value) {
                                        setDialogState(() {
                                          hideTodayChecked = value ?? false;
                                        });
                                      },
                                      visualDensity: VisualDensity.compact,
                                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  const Expanded(
                                    child: Text(
                                      '오늘 하루 숨기기',
                                      style: TextStyle(
                                        color: Colors.black,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
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
                                onPressed: () async {
                                  if (hideTodayChecked) {
                                    await _hideExpiredWarningForToday();
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
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
                                onPressed: () async {
                                  if (hideTodayChecked) {
                                    await _hideExpiredWarningForToday();
                                  }
                                  if (dialogContext.mounted) {
                                    Navigator.of(dialogContext).pop();
                                  }
                                  await _deleteCurrentRecordAndClose();
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
      },
    );
  }

  Future<void> _deleteCurrentRecordAndClose() async {
    bool deleted = false;

    try {
      final file = File(_record.filePath);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (e) {
      debugPrint('❌ [CaptureDetail] File delete failed: $e');
    }

    try {
      deleted = await _dao.deleteCapture(_record.id);
    } catch (e) {
      debugPrint('❌ [CaptureDetail] DB delete failed: $e');
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

    Navigator.of(context).pop({
      'deletedId': _record.id,
    });
  }

  Widget _buildEditLevelRow({
    required String label,
    required String value,
    required TextStyle labelStyle,
    required TextStyle valueStyle,
  }) {
    final displayValue = value.trim().isEmpty ? '' : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFD7E6CF),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(label, style: labelStyle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            displayValue,
            style: valueStyle,
          ),
        ),
      ],
    );
  }

  Future<void> _openSearchSheet(BuildContext context) async {
    final strings = AppStrings.instance;
    final searchController = _searchController;
    searchController.text = '';
    bool isSuggesting = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFAABEA5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final query = searchController.text.trim();
            final searchItems = _materialIndex;
            final defaultTerms = _defaultSearchTerms();
            String? statusMessage;
            final filtered = query.isEmpty
                ? searchItems.where((item) => _matchesTerms(item, defaultTerms)).toList()
                : searchItems
                    .where((item) {
                      final q = query.toLowerCase();
                      if (item.keyword.toLowerCase().contains(q)) {
                        return true;
                      }
                      return item.aliases.any((alias) => alias.toLowerCase().contains(q));
                    })
                    .toList();

            final viewInsets = MediaQuery.of(context).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 12,
                bottom: 12 + viewInsets,
              ),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.7,
                minChildSize: 0.45,
                maxChildSize: 0.9,
                builder: (context, scrollController) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: strings.get('edit_search_hint'),
                          prefixIcon: const Icon(Icons.search, size: 18),
                          prefixIconConstraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: const Color(0xFFC9D6C2)),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: const Color(0xFFD3DFCC)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(18),
                            borderSide: BorderSide(color: const Color(0xFFB6C7AE), width: 1.2),
                          ),
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          fillColor: const Color(0xFFF4F7F2),
                          filled: true,
                        ),
                        style: const TextStyle(fontSize: 12),
                        minLines: 1,
                        maxLines: 1,
                        onChanged: (_) => setLocalState(() {}),
                      ),
                      const SizedBox(height: 8),
                      if (isSuggesting)
                        Row(
                          children: [
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              strings.get('edit_ai_searching'),
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(fontWeight: FontWeight.w600, color: const Color(0xFF2E5E3F)) ?? const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF2E5E3F)),
                            ),
                          ],
                        )
                      else if (statusMessage != null)
                        Text(
                          statusMessage!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Colors.black54) ?? const TextStyle(color: Color(0xFF999999)),
                        ),
                      if (isSuggesting || statusMessage != null)
                        const SizedBox(height: 8),
                      Expanded(
                        child: Container(
                          decoration: BoxDecoration(
                            color: const Color(0xFFEFF5EC),
                            border: Border.all(color: const Color(0xFFD8E4D2)),
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.06),
                                blurRadius: 6,
                                spreadRadius: 0.2,
                                offset: const Offset(0, 1),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                          child: Column(
                            children: [
                              if (query.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 6),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: OutlinedButton.icon(
                                      icon: const Icon(Icons.add),
                                      label: Text('${strings.get('edit_add_suggest')} "$query"'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: const Color(0xFF2E5E3F),
                                        side: const BorderSide(color: Color(0xFFBFD3B5)),
                                        backgroundColor: const Color(0xFFE6F0E1),
                                      ),
                                      onPressed: () async {
                                        setLocalState(() {
                                          isSuggesting = true;
                                          statusMessage = null;
                                        });
                                        try {
                                          final added = await _suggestAndMergeFromQuery(context, query, filtered);
                                          setLocalState(() {
                                            isSuggesting = false;
                                            statusMessage = added
                                                ? strings.get('edit_ai_added', params: {'query': query})
                                                : strings.get('edit_ai_no_candidates');
                                          });
                                        } catch (_) {
                                          setLocalState(() {
                                            isSuggesting = false;
                                            statusMessage = strings.get('edit_ai_add_error');
                                          });
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: filtered.isEmpty
                                    ? Center(child: Text(strings.get('edit_search_empty')))
                                    : Scrollbar(
                                        controller: scrollController,
                                        thumbVisibility: true,
                                      thickness: 4,
                                      radius: const Radius.circular(8),
                                        child: ListView.separated(
                                          controller: scrollController,
                                        padding: const EdgeInsets.symmetric(vertical: 6),
                                          itemCount: filtered.length,
                                        separatorBuilder: (_, __) => Divider(
                                          height: 10,
                                          color: Colors.black.withValues(alpha: 0.05),
                                          thickness: 1,
                                        ),
                                          itemBuilder: (context, index) {
                                            final item = filtered[index];
                                            final isSelected =
                                              _selectedMaterial?.keyword == item.keyword;
                                            return Material(
                                              color: Colors.transparent,
                                              child: InkWell(
                                                borderRadius: BorderRadius.circular(10),
                                                onTap: () {
                                                  setState(() {
                                                    _selectedMaterial = item;
                                                  });
                                                  Navigator.of(context).pop();
                                                },
                                                child: Ink(
                                                  decoration: BoxDecoration(
                                                    color: isSelected
                                                        ? const Color(0xFFEFF3F6)
                                                        : Colors.white,
                                                    borderRadius: BorderRadius.circular(10),
                                                  ),
                                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 15),
                                                  child: Row(
                                                    children: [
                                                      Container(
                                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                        decoration: BoxDecoration(
                                                          color: const Color(0xFFF0F3F6),
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Text(
                                                          item.categoryLabel,
                                                          style: const TextStyle(
                                                            fontSize: 10,
                                                            fontWeight: FontWeight.w600,
                                                            color: Color(0xFF5F6B75),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 10),
                                                      Expanded(
                                                        child: Text(
                                                          item.secondaryLabel.isNotEmpty &&
                                                                  item.secondaryLabel != item.keyword
                                                              ? '${item.keyword} · ${item.secondaryLabel}'
                                                              : item.keyword,
                                                          style: const TextStyle(
                                                            fontSize: 14,
                                                            fontWeight: FontWeight.w600,
                                                            color: Color(0xFF1C232B),
                                                          ),
                                                        ),
                                                      ),
                                                      const SizedBox(width: 6),
                                                      const Icon(
                                                        Icons.chevron_right,
                                                        size: 18,
                                                        color: Color(0xFF9AA4AE),
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  List<_MaterialItem> _buildSearchItems(List<Map<String, dynamic>> materials) {
    final cfg = AppConfig.instance;
    return materials.map((item) {
      final keyword = item['keyword'].toString();
      final category = item['category'].toString();
      final primary = item['primaryLabel'].toString();
      final secondary = item['secondaryLabel'].toString();
      final tags = (item['stateTags'] as List<dynamic>).map((e) => e.toString()).toList();
      final aliases = (item['aliases'] as List<dynamic>).map((e) => e.toString()).toList();
      final source = item['source'].toString();
      final categoryLabel = cfg.categoryDisplayMap[category] ?? category;
      final display = [keyword, if (secondary.isNotEmpty) secondary]
          .toSet()
          .join(' · ');
      return _MaterialItem(
        keyword: keyword,
        category: category,
        categoryLabel: categoryLabel,
        primaryLabel: primary,
        secondaryLabel: secondary,
        stateTags: tags,
        aliases: aliases,
        source: source,
        display: '$display  [$categoryLabel]',
      );
    }).toList();
  }

  List<String> _defaultSearchTerms() {
    final terms = <String>[];
    final selected = _selectedMaterial;
    if (selected != null) {
      terms.addAll([
        selected.primaryLabel,
        selected.categoryLabel,
        if (selected.secondaryLabel.isNotEmpty) selected.secondaryLabel,
      ]);
    } else {
      terms.addAll([
        _record.primaryLabel,
        if (_record.secondaryLabel != null && _record.secondaryLabel!.isNotEmpty)
          _record.secondaryLabel!,
        AppConfig.instance.categoryDisplayMap[_record.category] ?? _record.category,
      ]);
    }
    return terms
        .map((t) => t.trim().toLowerCase())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
  }

  bool _matchesTerms(_MaterialItem item, List<String> terms) {
    if (terms.isEmpty) {
      return true;
    }
    final keyword = item.keyword.toLowerCase();
    final primary = item.primaryLabel.toLowerCase();
    final secondary = (item.secondaryLabel).toLowerCase();
    final category = item.categoryLabel.toLowerCase();
    final aliases = item.aliases.map((e) => e.toLowerCase()).toList();
    return terms.any((term) {
      if (keyword.contains(term)) return true;
      if (primary.contains(term)) return true;
      if (secondary.contains(term)) return true;
      if (category.contains(term)) return true;
      return aliases.any((alias) => alias.contains(term));
    });
  }

  Future<bool> _suggestAndMergeFromQuery(
    BuildContext context,
    String query,
    List<_MaterialItem> topHits,
  ) async {
    final trimmed = _normalizeQuery(query);
    if (trimmed.isEmpty) {
      return false;
    }

    final cfg = AppConfig.instance;
    if (!cfg.aiEnabled || cfg.aiApiKey.isEmpty) {
      return false;
    }

    final creditProvider = context.read<CreditProvider>();
    final costInfo = creditProvider.getCostInfo(CreditPackage.ingredientScan);
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
        print('📱 [CaptureDetail] Showing rewarded ad...');
        bool rewardCallbackFired = false;
        final rewardAmount = 0.5;
        final rewardEarned = await adService.showRewardedAd(
          onReward: (amount) {
            rewardCallbackFired = true;
            print('🎁 [CaptureDetail] Reward callback called: $amount');
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
        
        print('📱 [CaptureDetail] Ad finished. Reward earned: $rewardEarned');
        
        // Check if context is still valid (user didn't navigate away)
        if (!mounted) {
          print('⚠️ [CaptureDetail] Context deactivated, skipping notification');
          return;
        }
        
        if (!rewardEarned) {
          print('❌ [CaptureDetail] No reward earned, user closed ad early');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(creditProvider.getUIString('snackbar_ad_failed')),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        
        print('✅ [CaptureDetail] User earned reward, reward screen shown on ad dismiss');
      },
    );

    if (confirmed != true) {
      return false;
    }

    final hint = topHits.take(10).map((item) {
      return {
        'keyword': item.keyword,
        'category': item.category,
        'primaryLabel': item.primaryLabel,
        'secondaryLabel': item.secondaryLabel,
        'stateTags': item.stateTags,
        'aliases': item.aliases,
        'source': item.source,
      };
    }).toList();

    List<Map<String, dynamic>> candidates;
    try {
      candidates = await AiRecognitionService.instance.suggestMaterialCandidates(
        query: trimmed,
        topHits: hint,
      );
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 분석 실패로 크레딧이 차감되지 않았습니다')),
        );
      }
      return false;
    }

    if (candidates.isEmpty) {
      return false;
    }

    final authToken = await creditProvider.deductCredits(CreditPackage.ingredientScan);
    if (authToken == null || authToken.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(creditProvider.getUIString('snackbar_deduct_failed'))),
      );
      return false;
    }

    final merged = _mergeMaterialCandidates(_materialIndex, candidates);
    setState(() {
      _materialIndex = merged;
      _selectedMaterial = merged.firstWhere(
        (item) => _normalizeKey(item.keyword) == _normalizeKey(trimmed),
        orElse: () => _selectedMaterial!,
      );
    });

    await _persistMaterialIndexJson(merged);
    await _persistMaterialIndexDb(merged);
    return true;
  }

  List<_MaterialItem> _mergeMaterialCandidates(
    List<_MaterialItem> existing,
    List<Map<String, dynamic>> candidates,
  ) {
    final byKey = <String, _MaterialItem>{
      for (final item in existing) _normalizeKey(item.keyword): item,
    };

    for (final raw in candidates) {
      final keywordDisplay = _normalizeQuery(raw['keyword'].toString());
      final keywordKey = _normalizeKey(keywordDisplay);
      if (keywordKey.isEmpty) {
        continue;
      }
      final category = raw['category'].toString();
      final primary = raw['primaryLabel'].toString();
      final secondary = raw['secondaryLabel'].toString();
      final stateTags = (raw['stateTags'] as List<dynamic>).map((e) => e.toString()).toList();
      final aliases = (raw['aliases'] as List<dynamic>).map((e) => e.toString()).toList();
      final source = raw['source'].toString();

      final normalizedAliases = _normalizeAliases(aliases);
      final aliasForOverlap = _mergeAliases(normalizedAliases, [keywordDisplay]);
      final existingItem = byKey[keywordKey] ?? _findByAliasOverlap(byKey, aliasForOverlap);

      if (existingItem != null) {
        final mergedAliases = _mergeAliases(existingItem.aliases, normalizedAliases);
        byKey[_normalizeKey(existingItem.keyword)] = existingItem.copyWith(
          aliases: mergedAliases,
          source: existingItem.source.isNotEmpty ? existingItem.source : source,
        );
        continue;
      }

      final categoryLabel = AppConfig.instance.categoryDisplayMap[category] ?? category;
        final display = [keywordDisplay, if (secondary.isNotEmpty) secondary]
          .toSet()
          .join(' · ');
      byKey[keywordKey] = _MaterialItem(
        keyword: keywordDisplay,
        category: category,
        categoryLabel: categoryLabel,
        primaryLabel: primary,
        secondaryLabel: secondary,
        stateTags: stateTags,
        aliases: normalizedAliases,
        source: source,
        display: '$display  [$categoryLabel]',
      );
    }

    return byKey.values.toList();
  }

  _MaterialItem? _findByAliasOverlap(
    Map<String, _MaterialItem> items,
    List<String> aliases,
  ) {
    if (aliases.isEmpty) {
      return null;
    }
    final normalized = aliases.map(_normalizeKey).toSet();
    for (final item in items.values) {
      final existing = item.aliases.map(_normalizeKey).toSet();
      if (existing.intersection(normalized).isNotEmpty) {
        return item;
      }
    }
    return null;
  }

  String _normalizeKey(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
  }

  String _normalizeQuery(String value) {
    return value.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  List<String> _normalizeAliases(List<String> aliases) {
    final seen = <String>{};
    final result = <String>[];
    for (final alias in aliases) {
      final normalized = _normalizeQuery(alias);
      if (normalized.isEmpty) {
        continue;
      }
      final lower = _normalizeKey(normalized);
      if (seen.add(lower)) {
        result.add(normalized);
      }
    }
    return result;
  }

  List<String> _mergeAliases(List<String> existing, List<String> incoming) {
    return _normalizeAliases([...existing, ...incoming]);
  }

  Future<void> _persistMaterialIndexDb(List<_MaterialItem> items) async {
    for (final item in items) {
      await _dao.upsertMaterialIndex(
        keyword: item.keyword,
        category: item.category,
        primaryLabel: item.primaryLabel,
        secondaryLabel: item.secondaryLabel,
        stateTags: item.stateTags,
        aliases: item.aliases,
        source: item.source,
      );
    }
  }

  Future<void> _persistMaterialIndexJson(List<_MaterialItem> items) async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/material_index.json');
    final data = items
        .map((item) => {
              'keyword': item.keyword,
              'category': item.category,
              'primaryLabel': item.primaryLabel,
              'secondaryLabel': item.secondaryLabel,
              'stateTags': item.stateTags,
              'aliases': item.aliases,
              'source': item.source,
            })
        .toList();
    await file.writeAsString(jsonEncode(data));
  }

  Future<void> _applyClassification(BuildContext context) async {
    final strings = AppStrings.instance;
    final selection = _selectedMaterial;
    if (selection == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(strings.get('edit_search_empty'))),
      );
      return;
    }

    await _dao.updateManualClassification(
      captureId: _record.id,
      category: selection.category,
      primaryLabel: selection.primaryLabel,
      secondaryLabel: selection.secondaryLabel,
      stateTags: selection.stateTags,
    );

    final updated = await _dao.getCapture(_record.id);

    if (!mounted) return;
    setState(() {
      _record = updated;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(strings.editUpdated)),
    );
  }

  Future<void> _loadUserMaterialIndex() async {
    try {
      final rows = await _dao.getMaterialIndex();
      if (!mounted) {
        return;
      }
      final userItems = _buildSearchItems(rows);
      final merged = <String, _MaterialItem>{
        for (final item in _materialIndex) item.keyword: item,
      };
      for (final item in userItems) {
        merged[item.keyword] = item;
      }
      setState(() {
        _materialIndex = merged.values.toList();
      });
    } catch (_) {}
  }

  _MaterialItem? _findMaterialForRecord() {
    final cfg = AppConfig.instance;
    final items = _buildSearchItems(cfg.materialIndex);
    for (final item in items) {
      if (item.category == _record.category &&
          item.primaryLabel == _record.primaryLabel &&
          item.secondaryLabel == _record.secondaryLabel) {
        return item;
      }
    }
    return null;
  }
}

class _MaterialItem {
  final String keyword;
  final String category;
  final String categoryLabel;
  final String primaryLabel;
  final String secondaryLabel;
  final List<String> stateTags;
  final List<String> aliases;
  final String source;
  final String display;

  const _MaterialItem({
    required this.keyword,
    required this.category,
    required this.categoryLabel,
    required this.primaryLabel,
    required this.secondaryLabel,
    required this.stateTags,
    required this.aliases,
    required this.source,
    required this.display,
  });

  _MaterialItem copyWith({
    List<String>? aliases,
    String? source,
  }) {
    return _MaterialItem(
      keyword: keyword,
      category: category,
      categoryLabel: categoryLabel,
      primaryLabel: primaryLabel,
      secondaryLabel: secondaryLabel,
      stateTags: stateTags,
      aliases: aliases ?? this.aliases,
      source: source ?? this.source,
      display: display,
    );
  }
}

