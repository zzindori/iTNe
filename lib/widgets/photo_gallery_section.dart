
import 'package:flutter/material.dart';
import '../models/captured_photo.dart';
import '../config/app_strings.dart';
import '../config/app_config.dart';
import '../data/dao/capture_dao.dart';
import '../data/services/ai_recognition_service.dart';
import '../models/capture_record.dart';
import '../screens/capture_detail_screen.dart';

class PhotoGallerySection extends StatefulWidget {
  final List<CapturedPhoto> photos;
  final ValueChanged<CapturedPhoto>? onDeleteCurrent;

  const PhotoGallerySection({
    super.key,
    required this.photos,
    this.onDeleteCurrent,
  });

  @override
  State<PhotoGallerySection> createState() => _PhotoGallerySectionState();
}

class _PhotoGallerySectionState extends State<PhotoGallerySection> {
  late PageController _pageController;
  final Map<String, ScrollController> _statusScrollControllers = {};
  int _currentPage = 0;
  bool _isPhotoInteracting = false;
  final CaptureDao _captureDao = CaptureDao();
  double _panelHeight = 0;
  double _panelFontScale = 1.4;
  double _panelScaleStart = 1.0;

  // 외부에서 호출할 수 있는 메서드
  void scrollToLast() {
    if (widget.photos.isNotEmpty && _pageController.hasClients) {
      _pageController.animateToPage(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );
      setState(() {
        _currentPage = 0;
      });
    }
  }

  CapturedPhoto? getCurrentPhoto() {
    if (widget.photos.isEmpty) {
      return null;
    }
    final index = _currentPage.clamp(0, widget.photos.length - 1);
    return widget.photos[index];
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController(keepPage: true);
    // 초기화 페이지를 마지막 사진으로 설정
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.photos.isNotEmpty && _pageController.hasClients) {
        _pageController.jumpToPage(0);
        setState(() {
          _currentPage = 0;
        });
      }
    });
  }

  @override
  void didUpdateWidget(PhotoGallerySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    
    // 새 사진이 추가되었는지 확인
    if (widget.photos.length > oldWidget.photos.length) {
      // 프레임 렌더링 후 마지막 페이지로 이동
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_pageController.hasClients) {
          // jumpToPage 대신 animateToPage를 사용하여 
          // 사진이 찍히고 갤러리가 업데이트되는 것을 시각적으로 보여줍니다.
          _pageController.animateToPage(
            0,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
          
          setState(() {
            _currentPage = 0;
          });
        }
      });
    }

    final activeIds = widget.photos.map((photo) => photo.id).toSet();
    final staleIds = _statusScrollControllers.keys.where((id) => !activeIds.contains(id)).toList();
    for (final id in staleIds) {
      _statusScrollControllers.remove(id)?.dispose();
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _statusScrollControllers.values) {
      controller.dispose();
    }
    _statusScrollControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.photos.isEmpty) {
      return Container(
        color: Colors.grey[900],
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.image_outlined,
                size: 80,
                color: Colors.grey[600],
              ),
              const SizedBox(height: 16),
              Text(
                AppStrings.instance.emptyGalleryMessage,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      color: Colors.grey[900],
      child: Stack(
        children: [
          // 사진 슬라이드
          PageView.builder(
            key: const PageStorageKey<String>('photo_gallery'),
            controller: _pageController,
            physics: _isPhotoInteracting
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
            onPageChanged: (index) {
              setState(() {
                _currentPage = index;
              });
            },
            itemCount: widget.photos.length,
            itemBuilder: (context, index) {
              final photo = widget.photos[index];
              return GestureDetector(
                onLongPress: () => _showPhotoOptions(context, photo),
                child: ValueListenableBuilder<int>(
                  valueListenable: AiRecognitionService.instance.revision,
                  builder: (context, _, __) {
                    return FutureBuilder<CaptureRecord>(
                      future: _captureDao.getCapture(photo.id),
                      builder: (context, snapshot) {
                        return Stack(
                          children: [
                            Positioned.fill(
                              child: InteractiveViewer(
                                minScale: 1.0,
                                maxScale: 4.0,
                                panEnabled: true,
                                scaleEnabled: true,
                                onInteractionStart: (_) {
                                  if (!_isPhotoInteracting) {
                                    setState(() {
                                      _isPhotoInteracting = true;
                                    });
                                  }
                                },
                                onInteractionEnd: (_) {
                                  if (_isPhotoInteracting) {
                                    setState(() {
                                      _isPhotoInteracting = false;
                                    });
                                  }
                                },
                                child: Image.file(
                                  photo.file,
                                  fit: BoxFit.contain,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.black54,
                                      child: const Center(
                                        child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
                                      ),
                                    );
                                  },
                                ),
                              ),
                            ),
                            Positioned(
                              top: 12,
                              left: 12,
                              right: 12,
                              bottom: 120,
                              child: _buildOverlayWidget(snapshot.data, context),
                            ),
                          ],
                        );
                      },
                    );
                  },
                ),
              );
            },
          ),

          // 페이지 인디케이터
          if (AppConfig.instance.galleryPageIndicator && widget.photos.length > 1)
            Positioned(
              bottom: 16,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      '${_currentPage + 1} / ${widget.photos.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildOverlayWidget(CaptureRecord? record, BuildContext context) {
    if (record == null) {
      return const SizedBox.shrink();
    }
    final isAnalyzed = (record.modelVersion?.isNotEmpty ?? false) ||
        record.aiRawJson != null ||
        record.confidence != null ||
        record.category != 'ETC' ||
        record.primaryLabel != AppConfig.instance.defaultPrimaryLabel;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxHeight = constraints.maxHeight.clamp(160.0, constraints.maxHeight);
        _panelHeight = maxHeight;
        return isAnalyzed
            ? _buildStatusPanel(record, context, maxHeight)
            : _buildAnalyzingPanel(context, maxHeight);
      },
    );
  }

  Widget _buildAnalyzingPanel(BuildContext context, double maxHeight) {
    final strings = AppStrings.instance;
    const panelBg = Color(0xFF000000);
    const panelBorder = Color(0xFF00FF66);
    const panelText = Color(0xFF7CFF9A);
    return Container(
      width: double.infinity,
      height: maxHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
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
      child: Center(
        child: DefaultTextStyle(
          style: const TextStyle(
            color: panelText,
            fontSize: 14,
            height: 1.4,
            fontFamily: 'monospace',
            shadows: [
              Shadow(color: panelBorder, blurRadius: 6),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  valueColor: AlwaysStoppedAnimation<Color>(panelText),
                ),
              ),
              const SizedBox(width: 10),
              Text(strings.get('status_value_analyzing')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusPanel(CaptureRecord record, BuildContext context, double maxHeight) {
    final strings = AppStrings.instance;
    final cfg = AppConfig.instance;
    final none = strings.get('status_value_none');
    const panelBg = Color(0xFF000000);
    const panelBorder = Color(0xFF00FF66);
    const panelText = Color(0xFF7CFF9A);
    final scrollController = _statusScrollControllers.putIfAbsent(
      record.id,
      () => ScrollController(),
    );

    final category = cfg.categoryDisplayMap[record.category] ?? record.category;
    final effectiveFreshness = record.effectiveFreshnessHint();
    final freshness = cfg.freshnessDisplayMap[effectiveFreshness] ??
      effectiveFreshness;
    final amount = record.amountLabel == null
      ? none
      : (cfg.amountDisplayMap[record.amountLabel] ?? record.amountLabel);
    final role = record.usageRole == null
      ? none
      : (cfg.usageRoleDisplayMap[record.usageRole] ?? record.usageRole);
    final countdown = record.shelfLifeCountdownLabel();
    final secondary = record.secondaryLabel ?? none;
    final tagLabels = record.stateTags
      .map((tag) => cfg.stateTagDisplayMap[tag] ?? tag)
      .toList();
    final tags = tagLabels.isEmpty ? none : tagLabels.join(', ');
    final rcConfidence = record.confidence;
    final confidence = rcConfidence == null
      ? none
      : rcConfidence.toStringAsFixed(2);
    final description = _extractDescription(record.aiRawJson) ?? none;

    final time = _formatDateTime(record.createdAt);

    final textLines = <String>[];
    final primaryLine = '${strings.get('status_label_primary')}: ${record.primaryLabel}';
    final categoryLine = '${strings.get('status_label_category')}: $category';
    final secondaryLine = '${strings.get('status_label_secondary')}: $secondary';
    final tagsLine = '${strings.get('status_label_tags')}: $tags';
    final roleLine = '${strings.get('status_label_role')}: $role';
    final descriptionLine = '${strings.get('status_label_description')}: $description';

    if (!_shouldHideValue(record.primaryLabel, none)) {
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

    final currentHeight =
      (_panelHeight == 0 ? maxHeight : _panelHeight).clamp(160.0, maxHeight);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onScaleStart: (details) {
        if (details.pointerCount >= 2) {
          _panelScaleStart = _panelFontScale;
        }
      },
      onVerticalDragUpdate: (details) {
        setState(() {
          final baseHeight = _panelHeight == 0 ? currentHeight : _panelHeight;
          final next = baseHeight + details.delta.dy;
          _panelHeight = next.clamp(160.0, maxHeight);
        });
      },
      onScaleUpdate: (details) {
        if (details.pointerCount < 2) {
          return;
        }
        setState(() {
          _panelFontScale = (_panelScaleStart * details.scale).clamp(0.8, 2.0);
        });
      },
      child: Container(
        width: double.infinity,
        height: currentHeight,
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
              style: TextStyle(
                color: panelText,
                fontSize: 10 * _panelFontScale,
                height: 1.3,
                fontFamily: 'monospace',
                shadows: const [
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
                      controller: scrollController,
                      child: SingleChildScrollView(
                        controller: scrollController,
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
                                    _amountLevel(record.amountLabel),
                                    3,
                                  ),
                                if (!_shouldHideValue(confidence, none))
                                  _buildMetricBar(
                                    strings.get('status_label_confidence'),
                                    _metricLabel(confidence, none),
                                    _confidenceLevel(record.confidence),
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
                        style: TextStyle(
                          color: panelText,
                          fontSize: 9,
                          fontFamily: 'monospace',
                          shadows: const [
                            Shadow(color: panelBorder, blurRadius: 6),
                          ],
                        ),
                      ),
                      if (countdown != null) ...[
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
                              fontSize: 8.5,
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
            Positioned(
              top: 5,
              right: 0,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.remove, size: 16, color: panelText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      setState(() {
                        _panelFontScale = (_panelFontScale - 0.1).clamp(0.8, 2.0);
                      });
                    },
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Text(
                      (10 * _panelFontScale).toStringAsFixed(0),
                      style: const TextStyle(
                        color: panelText,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        shadows: [
                          Shadow(color: panelBorder, blurRadius: 6),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add, size: 16, color: panelText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () {
                      setState(() {
                        _panelFontScale = (_panelFontScale + 0.1).clamp(0.8, 2.0);
                      });
                    },
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: panelText, width: 1),
                  color: panelBg.withValues(alpha: 0.35),
                ),
                child: Center(
                  child: IconButton(
                    icon: const Icon(Icons.edit, size: 14, color: panelText),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CaptureDetailScreen(record: record),
                        ),
                      );
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDateTime(DateTime time) {
    final y = time.year.toString().padLeft(4, '0');
    final m = time.month.toString().padLeft(2, '0');
    final d = time.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
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
    if (_shouldHideValue(value, noneLabel)) {
      return '';
    }
    return value ?? '';
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
                      color: active
                          ? const Color(0xFF7CFF9A)
                          : const Color(0xFF0B1A0E),
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


  void _showPhotoOptions(BuildContext context, CapturedPhoto photo) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey[850],
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.undo, color: Colors.white70),
                title: Text(
                  AppStrings.instance.markIncorrect,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _markIncorrect(photo);
                },
              ),
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  AppStrings.instance.deleteButton,
                  style: const TextStyle(color: Colors.white),
                ),
                onTap: () {
                  Navigator.pop(context);
                  widget.onDeleteCurrent?.call(photo);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _markIncorrect(CapturedPhoto photo) async {
    await _captureDao.fallbackToTop(
      photo.id,
      AppConfig.instance.defaultPrimaryLabel,
    );
    if (mounted) {
      setState(() {});
    }
  }
}
