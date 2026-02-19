import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import '../config/app_config.dart';
import '../config/app_strings.dart';
import '../data/dao/capture_dao.dart';
import '../data/services/ai_recognition_service.dart';
import '../data/services/credit_service.dart';
import '../data/services/ad_service.dart';
import '../models/captured_photo.dart';
import '../models/capture_record.dart';
import '../models/credit_provider.dart';
import '../main.dart';
import 'capture_history_screen.dart';
import 'recipe_recommendation_screen.dart';
import 'reward_claim_screen.dart';
import '../widgets/camera_preview_section.dart';
import '../widgets/photo_gallery_section.dart';
import '../widgets/credit_balance_widget.dart';
import '../widgets/credit_confirm_dialog.dart';

class SplitCameraScreen extends StatefulWidget {
  final List<CameraDescription> cameras;

  const SplitCameraScreen({
    super.key,
    required this.cameras,
  });

  @override
  State<SplitCameraScreen> createState() => _SplitCameraScreenState();
}

class _SplitCameraScreenState extends State<SplitCameraScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _errorMessage;
  final List<CapturedPhoto> _capturedPhotos = [];
  bool _isCapturing = false;
  final GlobalKey _galleryKey = GlobalKey();
  final CaptureDao _captureDao = CaptureDao();
  bool _deletePending = false;
  FlashMode _flashMode = FlashMode.off;
  bool _isDisposingController = false;
  double _minZoom = 1.0;
  double _maxZoom = 1.0;
  double _currentZoom = 1.0;
  static const double _desiredMinZoom = 0.6;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
    _loadCapturedHistory();
  }

  Future<bool> _showDeleteCountdownDialog(BuildContext context) async {
    final strings = AppStrings.instance;
    int remaining = 3;
    bool canceled = false;
    bool started = false;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setLocalState) {
            if (!started) {
              started = true;
              () async {
                while (remaining > 0 && !canceled && mounted) {
                  await Future.delayed(const Duration(seconds: 1));
                  if (!mounted || canceled) {
                    return;
                  }
                  remaining -= 1;
                  setLocalState(() {});
                }
                if (Navigator.of(context).canPop()) {
                  Navigator.of(context).pop(canceled);
                }
              }();
            }

            return Material(
              type: MaterialType.transparency,
              child: Stack(
                children: [
                  Positioned(
                    left: 24,
                    right: 24,
                    bottom: 40,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        canceled = true;
                        Navigator.of(context).pop(true);
                      },
                      child: Container(
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
                                  child: const Center(
                                    child: Icon(Icons.close, size: 12, color: Colors.white),
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
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 5),
                                    child: Text(
                                      strings.get('delete_pending_countdown', params: {
                                        'seconds': remaining.toString(),
                                      }),
                                      textAlign: TextAlign.left,
                                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                            color: Colors.black87,
                                          ),
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
                                    onPressed: () {
                                      canceled = true;
                                      Navigator.of(context).pop(true);
                                    },
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.black87,
                                      side: const BorderSide(color: Colors.black26),
                                      backgroundColor: const Color(0xFFEDEDED),
                                      padding: const EdgeInsets.symmetric(horizontal: 20),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                                    ),
                                    child: Text(strings.cancelButton),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    return result ?? false;
  }

  Future<void> _loadCapturedHistory() async {
    try {
      final records = await _captureDao.getAllCaptures();
      final items = <CapturedPhoto>[];
      for (final record in records) {
        final file = File(record.filePath);
        if (await file.exists()) {
          items.add(CapturedPhoto(
            id: record.id,
            file: file,
            capturedAt: record.createdAt,
          ));
        }
      }
      if (!mounted) {
        return;
      }
      setState(() {
        _capturedPhotos
          ..clear()
          ..addAll(items);
      });
    } catch (e) {
      debugPrint('�스�리 로드 �류: $e');
    }
  }

  Future<void> _initializeCamera() async {
    try {
      if (_isDisposingController || _isInitializing) {
        return;
      }
      _isInitializing = true;
      if (mounted) {
        setState(() {
          _errorMessage = null;
          _isInitialized = false;
        });
      } else {
        _errorMessage = null;
        _isInitialized = false;
      }

      if (_controller != null) {
        await _disposeController();
      }
      debugPrint('카메라 초기화 시작 작업...');
      
      if (widget.cameras.isEmpty) {
        debugPrint('사용 가능한 카메라가 없음');
        setState(() {
          _errorMessage = AppStrings.instance.cameraError;
        });
        return;
      }

      debugPrint('✅ 카메라 컨트롤러 생성...');
      _controller = CameraController(
        widget.cameras[0],
        AppConfig.instance.cameraResolution,
      );

      debugPrint('✅ 카메라 초기화 시작..');
      await _controller!.initialize();

      try {
        _minZoom = await _controller!.getMinZoomLevel();
        _minZoom = _minZoom < _desiredMinZoom ? _desiredMinZoom : _minZoom;
        _maxZoom = await _controller!.getMaxZoomLevel();
        if (_maxZoom > 6.0) {
          _maxZoom = 6.0;
        }
        _currentZoom = _currentZoom.clamp(_minZoom, _maxZoom);
        await _controller!.setZoomLevel(_currentZoom);
      } catch (_) {
        _minZoom = _desiredMinZoom;
        _maxZoom = 1.0;
        _currentZoom = 1.0;
      }

      try {
        await _controller!.setFlashMode(_flashMode);
      } catch (_) {
        // ignore flash unsupported
      }

      if (!mounted) {
        debugPrint('⚠️ Widget unmounted during camera initialization');
        return;
      }

      debugPrint('카메라 초기화 시작 완료');
      setState(() {
        _isInitialized = true;
      });
    } catch (e) {
      debugPrint('카메라 초기화 실패: $e');
      if (mounted) {
        setState(() {
          _isInitialized = false;
          _errorMessage = AppStrings.instance.cameraError;
        });
      } else {
        _isInitialized = false;
        _errorMessage = AppStrings.instance.cameraError;
      }
    } finally {
      _isInitializing = false;
    }
  }

  Future<void> _toggleFlashMode() async {
    if (_isDisposingController || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    final next = _flashMode == FlashMode.off
        ? FlashMode.auto
        : _flashMode == FlashMode.auto
            ? FlashMode.torch
            : FlashMode.off;

    try {
      await _controller!.setFlashMode(next);
      setState(() {
        _flashMode = next;
      });
    } catch (e) {
      debugPrint('�래변��패: $e');
    }
  }

  Future<void> _setZoom(double value) async {
    if (_isDisposingController || _controller == null || !_controller!.value.isInitialized) {
      return;
    }
    final next = value.clamp(_minZoom, _maxZoom);
    try {
      await _controller!.setZoomLevel(next);
      if (mounted) {
        setState(() {
          _currentZoom = next;
        });
      }
    } catch (e) {
      debugPrint('�변��패: $e');
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _disposeController();
    super.dispose();
  }

  @override
  void reassemble() {
    super.reassemble();
    _disposeController();
    _initializeCamera();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _handleLifecycle(state);
  }

  Future<void> _handleLifecycle(AppLifecycleState state) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      if (state == AppLifecycleState.resumed) {
        _initializeCamera();
      }
      return;
    }

    if (state == AppLifecycleState.inactive || state == AppLifecycleState.paused) {
      await _disposeController();
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera();
    }
  }

  Future<void> _disposeController() async {
    if (_isDisposingController) {
      return;
    }
    _isDisposingController = true;
    final controller = _controller;
    _controller = null;
    if (mounted) {
      setState(() {
        _isInitialized = false;
      });
    } else {
      _isInitialized = false;
    }
    try {
      await controller?.dispose();
    } catch (_) {
      // ignore dispose errors
    } finally {
      _isDisposingController = false;
    }
  }

  Future<void> _takePicture() async {
    if (_isDisposingController || _controller == null || !_controller!.value.isInitialized) {
      return;
    }

    if (_capturedPhotos.length >= AppConfig.instance.maxPhotos) {
      _showMaxPhotosWarning();
      return;
    }

    try {
      setState(() {
        _isCapturing = true;
      });

      if (AppConfig.instance.hapticFeedback) {
        HapticFeedback.mediumImpact();
      }

      final image = await _controller!.takePicture();
      
      // �쪽 50% �역��롭�서 �
      final croppedFile = await _cropImageToTop50Percent(File(image.path));
      
      final photo = CapturedPhoto(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        file: croppedFile,
        capturedAt: DateTime.now(),
      );

      final record = CaptureRecord(
        id: photo.id,
        filePath: croppedFile.path,
        thumbnailPath: '',
        createdAt: photo.capturedAt,
        category: 'ETC',
        primaryLabel: AppConfig.instance.defaultPrimaryLabel,
        secondaryLabel: '',
        secondaryLabelGuess: false,
        stateTags: const [],
        freshnessHint: '',
        shelfLifeDays: 0,
        amountLabel: '',
        usageRole: '',
        confidence: 0.0,
        modelVersion: '',
        aiRawJson: {},
      );

      try {
        await _captureDao.insertCapture(record);
      } catch (e) {
        debugPrint('DB ��류: $e');
      }

      final canProceed = await _confirmAndDeductIngredientScan();
      if (canProceed) {
        AiRecognitionService.instance
            .enqueueRecognitionAndWait(
              captureId: photo.id,
              filePath: croppedFile.path,
            )
            .then((success) async {
              if (!mounted) {
                return;
              }
              if (!success) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('AI 분석 실패로 크레딧이 차감되지 않았습니다')),
                );
                return;
              }

              final creditProvider = context.read<CreditProvider>();
              final authToken =
                  await creditProvider.deductCredits(CreditPackage.ingredientScan);
              if (!mounted) {
                return;
              }
              if (authToken == null || authToken.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(creditProvider.getUIString('snackbar_deduct_failed')),
                  ),
                );
              }
            });
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('AI 분석건너�니')),
        );
      }

      setState(() {
        _capturedPhotos.insert(0, photo);
        _isCapturing = false;
      });

      // 로딩 �료 갤러리� 마���진�로 �동 �크�
      WidgetsBinding.instance.addPostFrameCallback((_) {
        dynamic state = _galleryKey.currentState;
        if (state != null && state.scrollToLast is Function) {
          state.scrollToLast();
        }
      });

      debugPrint('�� �진 촬영: ${image.path}');
    } catch (e) {
      setState(() {
        _isCapturing = false;
      });
      debugPrint('�진 촬영 �류: $e');
    }
  }

  /// �본 ��지�9:16 비율 �쪽 50%��롭
  Future<File> _cropImageToTop50Percent(File imageFile) async {
    try {
      final imageData = await imageFile.readAsBytes();
      final image = img.decodeImage(imageData);
      
      if (image == null) return imageFile;
      
      final width = image.width;
      final height = image.height;
      
      // ��지�9:16�로 �롭 (중앙 기�)
      const targetAspect = 9 / 16;
      int targetWidth = width;
      int targetHeight = height;
      
      if (width / height > targetAspect) {
        targetWidth = (height * targetAspect).round();
      } else if (width / height < targetAspect) {
        targetHeight = (width / targetAspect).round();
      }
      
      // 중앙 기� �롭
      final cropX = ((width - targetWidth) / 2).round();
      final cropY = ((height - targetHeight) / 2).round();
      
      final cropped9x16 = img.copyCrop(
        image,
        x: cropX,
        y: cropY,
        width: targetWidth,
        height: targetHeight,
      );
      
      // 9:16 ��지�쪽 50%�추출
      final half = (cropped9x16.height / 2).round();
      final croppedTop50 = img.copyCrop(
        cropped9x16,
        x: 0,
        y: 0,
        width: cropped9x16.width,
        height: half,
      );
      
      final croppedData = img.encodeJpg(croppedTop50, quality: 95);
      await imageFile.writeAsBytes(croppedData);
      
      return imageFile;
    } catch (e) {
      debugPrint('��지 �롭 �류: $e');
      return imageFile;
    }
  }

  Future<bool> _confirmAndDeductIngredientScan() async {
    if (!mounted) {
      return false;
    }
    final cfg = AppConfig.instance;
    if (!cfg.aiEnabled || cfg.aiApiKey.isEmpty) {
      return true;
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
        print('📱 [Camera] Showing rewarded ad...');
        bool rewardCallbackFired = false;
        final rewardAmount = 0.5;
        final rewardEarned = await adService.showRewardedAd(
          onReward: (amount) {
            rewardCallbackFired = true;
            print('🎁 [Camera] Reward callback called: $amount');
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
        
        print('📱 [Camera] Ad finished. Reward earned: $rewardEarned');
        
        // Check if context is still valid (user didn't navigate away)
        if (!mounted) {
          print('⚠️ [Camera] Context deactivated, skipping notification');
          return;
        }
        
        if (!rewardEarned) {
          print('❌ [Camera] No reward earned, user closed ad early');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(creditProvider.getUIString('snackbar_ad_failed')),
              duration: const Duration(seconds: 2),
            ),
          );
          return;
        }
        
        print('✅ [Camera] User earned reward, reward screen shown on ad dismiss');
      },
    );

    if (confirmed != true) {
      return false;
    }

    return true;
  }

  CapturedPhoto? _getCurrentGalleryPhoto() {
    final dynamic state = _galleryKey.currentState;
    if (state == null) {
      return null;
    }
    final dynamic getter = state.getCurrentPhoto;
    if (getter is Function) {
      return getter() as CapturedPhoto;
    }
    return null;
  }

  Future<void> _deleteCurrentPhoto([CapturedPhoto? selectedPhoto]) async {
    if (_deletePending) return;

    final photo = selectedPhoto ?? _getCurrentGalleryPhoto();
    if (photo == null) {
      return;
    }
    
    _deletePending = true;
    final canceled = await _showDeleteCountdownDialog(context);
    if (!mounted || canceled || _capturedPhotos.isEmpty) {
      _deletePending = false;
      return;
    }

    final index = _capturedPhotos.indexWhere((item) => item.id == photo.id);
    if (index == -1) {
      _deletePending = false;
      return;
    }

    bool deleted = false;
    try {
      deleted = await _captureDao.deleteCapture(photo.id);
      if (!deleted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('삭제에 실패했습니다. 다시 시도해 주세요.')),
        );
        _deletePending = false;
        return;
      }
    } catch (e) {
      debugPrint('DB �� �류: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('삭제에 실패했습니다. 다시 시도해 주세요.')),
      );
      _deletePending = false;
      return;
    }

    _capturedPhotos.removeAt(index);
    setState(() {});

    try {
      if (await photo.file.exists()) {
        await photo.file.delete();
      }
    } catch (e) {
      debugPrint('�일 �� �류: $e');
    }

    if (AppConfig.instance.hapticFeedback) {
      HapticFeedback.lightImpact();
    }

    _deletePending = false;
  }

  void _showMaxPhotosWarning() {
    final strings = AppStrings.instance;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(strings.maxPhotosWarning(AppConfig.instance.maxPhotos)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // �체 �면 카메라�리�
          Positioned.fill(
            child: CameraPreviewSection(
              controller: _controller,
              isInitialized: _isInitialized,
              errorMessage: _errorMessage,
              minZoom: _minZoom,
              maxZoom: _maxZoom,
              currentZoom: _currentZoom,
              onZoomChanged: _setZoom,
            ),
          ),

          // �래모드 (�른�
          Positioned(
            top: 28,
            right: 16,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.4),
                shape: BoxShape.circle,
              ),
              child: SizedBox(
                width: 44,
                height: 44,
                child: IconButton(
                  icon: Icon(
                    _flashMode == FlashMode.off
                        ? Icons.flash_off
                        : _flashMode == FlashMode.auto
                            ? Icons.flash_auto
                            : Icons.flash_on,
                    color: Colors.white,
                  ),
                  onPressed: _toggleFlashMode,
                ),
              ),
            ),
          ),

          // �컨트�(�단 중앙)
          Positioned(
            top: 28,
            left: 16,
            right: 72,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.45),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(
                children: [
                  Text(
                    '${_minZoom.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                        overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                      ),
                      child: Slider(
                        value: _currentZoom.clamp(_minZoom, _maxZoom),
                        min: _minZoom,
                        max: _maxZoom,
                        divisions: _maxZoom > _minZoom
                            ? ((_maxZoom - _minZoom) / 0.1).round()
                            : null,
                        onChanged: _maxZoom > _minZoom ? (value) => _setZoom(value) : null,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '${_currentZoom.toStringAsFixed(1)}x',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  TextButton(
                    onPressed: _currentZoom != 1.0 ? () => _setZoom(1.0) : null,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      minimumSize: const Size(0, 0),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text(
                      '1x',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // �단 �라�드 갤러��버�이
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            height: MediaQuery.of(context).size.height * AppConfig.instance.splitRatio,
            child: PhotoGallerySection(
              key: _galleryKey,
              photos: _capturedPhotos,
              onDeleteCurrent: (photo) { _deleteCurrentPhoto(photo); },
              onRefreshRequested: _loadCapturedHistory,
            ),
          ),
        ],
      ),
      floatingActionButton: _isInitialized && _errorMessage == null
          ? Consumer<CreditProvider>(
              builder: (context, creditProvider, _) {
                final creditService = CreditService();
                final balanceText =
                    creditProvider.balance?.credits.toStringAsFixed(1) ?? '--';
                return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.small(
                    heroTag: 'history_fab',
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => CaptureHistoryScreen(),
                        ),
                      );
                      if (!mounted) {
                        return;
                      }
                      await _loadCapturedHistory();
                    },
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    child: const Icon(Icons.photo_library, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.small(
                    heroTag: 'recipe_fab',
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => RecipeRecommendationScreen(),
                        ),
                      );
                    },
                    tooltip: AppStrings.instance.recipeButtonTooltip,
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    child: const Icon(Icons.restaurant_menu, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton(
                    onPressed: _isCapturing ? null : _takePicture,
                    tooltip: AppStrings.instance.captureButtonTooltip,
                    backgroundColor: Colors.grey[400]!.withValues(alpha: 0.7),
                    shape: const CircleBorder(),
                    child: _isCapturing
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Icon(Icons.camera_alt, size: 32, color: Colors.white),
                  ),
                  const SizedBox(width: 16),
                  FloatingActionButton.small(
                    heroTag: 'credit_fab',
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
                                  final creditService = CreditService();
                                  
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
                                  bool rewardCallbackFired = false;
                                  final rewardAmount = 0.5;
                                  final rewardEarned = await adService.showRewardedAd(
                                    onReward: (amount) {
                                      rewardCallbackFired = true;
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
                                  
                                  if (!rewardEarned) {
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
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    child: Text(
                      balanceText,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FloatingActionButton.small(
                    heroTag: 'delete_fab',
                    onPressed: _capturedPhotos.isEmpty ? null : () { _deleteCurrentPhoto(); },
                    backgroundColor: Colors.black.withValues(alpha: 0.6),
                    child: const Icon(Icons.delete, color: Colors.white),
                  ),
                ],
              );
            })
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

