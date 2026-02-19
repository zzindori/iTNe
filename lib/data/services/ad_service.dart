import 'dart:async';
import 'dart:io';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Service to manage AdMob rewarded ads
class AdService {
  static final AdService _instance = AdService._internal();
  factory AdService() => _instance;
  AdService._internal();

  RewardedAd? _rewardedAd;
  bool _isAdLoading = false;
  bool _isAdReady = false;
  Completer<void>? _adDismissedCompleter;
  bool _rewardEarned = false;

  // Test Ad Unit IDs (replace with your actual IDs in production)
  static const String _androidRewardedAdUnitId = 'ca-app-pub-3940256099942544/5224354917'; // Test ID
  static const String _iosRewardedAdUnitId = 'ca-app-pub-3940256099942544/1712485313'; // Test ID

  // Production Ad Unit IDs (uncomment and use in production)
  // static const String _androidRewardedAdUnitId = 'YOUR_ANDROID_AD_UNIT_ID';
  // static const String _iosRewardedAdUnitId = 'YOUR_IOS_AD_UNIT_ID';

  /// Get the appropriate ad unit ID for the current platform
  String get _rewardedAdUnitId {
    if (Platform.isAndroid) {
      return _androidRewardedAdUnitId;
    } else if (Platform.isIOS) {
      return _iosRewardedAdUnitId;
    }
    throw UnsupportedError('Unsupported platform');
  }

  /// Initialize the Mobile Ads SDK
  static Future<void> initialize() async {
    await MobileAds.instance.initialize();
  }

  /// Load a rewarded ad
  Future<void> loadRewardedAd() async {
    if (_isAdLoading || _isAdReady) {
      return; // Already loading or ready
    }

    _isAdLoading = true;

    await RewardedAd.load(
      adUnitId: _rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          print('Rewarded ad loaded successfully');
          _rewardedAd = ad;
          _isAdReady = true;
          _isAdLoading = false;
        },
        onAdFailedToLoad: (error) {
          print('Rewarded ad failed to load: $error');
          _isAdLoading = false;
          _isAdReady = false;
        },
      ),
    );
  }

  /// Show the rewarded ad and execute callback on reward
  Future<bool> showRewardedAd({
    required Function(double amount) onReward,
    Function()? onAdDismissed,
  }) async {
    if (!_isAdReady || _rewardedAd == null) {
      print('Rewarded ad is not ready yet');
      return false;
    }

    // Create completer to wait for ad dismissal
    _adDismissedCompleter = Completer<void>();
    _rewardEarned = false;

    // Set up full screen content callback BEFORE showing ad
    _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
        print('Ad showed full screen content');
      },
      onAdDismissedFullScreenContent: (ad) {
        print('Ad dismissed full screen content');
        if (onAdDismissed != null) {
          onAdDismissed();
        }
        ad.dispose();
        _rewardedAd = null;
        _isAdReady = false;
        
        // Complete the completer to signal dismissal
        if (!_adDismissedCompleter!.isCompleted) {
          _adDismissedCompleter!.complete();
        }
        
        // Preload next ad
        loadRewardedAd();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        print('Ad failed to show full screen content: $error');
        if (onAdDismissed != null) {
          onAdDismissed();
        }
        ad.dispose();
        _rewardedAd = null;
        _isAdReady = false;
        
        // Complete the completer even on failure
        if (!_adDismissedCompleter!.isCompleted) {
          _adDismissedCompleter!.complete();
        }
        
        // Preload next ad
        loadRewardedAd();
      },
    );

    // Show the ad
    print('🎬 [AdService] Showing ad...');
    try {
      await _rewardedAd!.show(
        onUserEarnedReward: (ad, reward) {
          print('🎁 [AdService] User earned reward: ${reward.amount} ${reward.type}');
          _rewardEarned = true;
          onReward(reward.amount.toDouble());
        },
      );
    } catch (e) {
      print('❌ [AdService] Ad show error: $e');
      _rewardEarned = false;
    }

    print('⏳ [AdService] Waiting for ad to be dismissed...');
    // Wait for ad to be dismissed
    try {
      await _adDismissedCompleter!.future.timeout(
        const Duration(seconds: 30),
        onTimeout: () {
          print('⚠️ [AdService] Ad dismissal timeout after 30s');
        },
      );
    } catch (e) {
      print('❌ [AdService] Ad dismissal error: $e');
    }
    print('✅ [AdService] Ad dismissed. Reward earned: $_rewardEarned');
    
    return _rewardEarned;
  }

  /// Check if ad is ready to show
  bool get isAdReady => _isAdReady;

  /// Check if ad is currently loading
  bool get isAdLoading => _isAdLoading;

  /// Dispose of the current ad
  void dispose() {
    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isAdReady = false;
  }
}
