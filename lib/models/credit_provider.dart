import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/services/credit_service.dart';

enum SubscriptionType { none, monthly, yearly }

/// Manages credit state and notifies listeners
class CreditProvider extends ChangeNotifier {
  final CreditService _service = CreditService();
  CreditBalance? _balance;
  bool _isLoading = true;
  String? _error;
  bool _showCreditConsumeAlert = true;
  SubscriptionType _subscriptionType = SubscriptionType.none;
  DateTime? _subscriptionEndDate;
  SharedPreferences? _prefs;

  CreditBalance? get balance => _balance;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get showCreditConsumeAlert => hasActiveSubscription ? false : _showCreditConsumeAlert;
  SubscriptionType get subscriptionType => _subscriptionType;
  DateTime? get subscriptionEndDate => _subscriptionEndDate;
  bool get isCreditLocked => hasActiveSubscription;

  bool get hasActiveSubscription {
    if (_subscriptionType == SubscriptionType.none) return false;
    if (_subscriptionEndDate == null) return false;
    return DateTime.now().isBefore(_subscriptionEndDate!);
  }

  String get subscriptionLabel {
    switch (_subscriptionType) {
      case SubscriptionType.monthly:
        return '한달 무제한';
      case SubscriptionType.yearly:
        return '1년 무제한';
      default:
        return '';
    }
  }

  /// Initialize provider
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _showCreditConsumeAlert = _prefs?.getBool('show_credit_consume_alert') ?? true;
      
      // Load subscription state
      await _loadSubscriptionState();
      
      await _service.initialize();
      await _refreshBalance();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  Future<void> _loadSubscriptionState() async {
    final typeStr = _prefs?.getString('subscription_type');
    final endDateStr = _prefs?.getString('subscription_end_date');
    
    if (typeStr != null) {
      _subscriptionType = SubscriptionType.values.firstWhere(
        (e) => e.toString().endsWith(typeStr),
        orElse: () => SubscriptionType.none,
      );
    }
    
    if (endDateStr != null) {
      _subscriptionEndDate = DateTime.tryParse(endDateStr);
    }
  }

  Future<void> setSubscription(SubscriptionType type) async {
    DateTime endDate;
    
    if (type == SubscriptionType.monthly) {
      endDate = DateTime.now().add(const Duration(days: 30));
    } else if (type == SubscriptionType.yearly) {
      endDate = DateTime.now().add(const Duration(days: 365));
    } else {
      endDate = DateTime.now();
    }
    
    _subscriptionType = type;
    _subscriptionEndDate = endDate;
    _showCreditConsumeAlert = false;
    
    await _prefs?.setString('subscription_type', type.toString().split('.').last);
    await _prefs?.setString('subscription_end_date', endDate.toIso8601String());
    await _prefs?.setBool('show_credit_consume_alert', false);
    
    notifyListeners();
  }

  Future<void> cancelSubscription() async {
    _subscriptionType = SubscriptionType.none;
    _subscriptionEndDate = null;
    
    await _prefs?.remove('subscription_type');
    await _prefs?.remove('subscription_end_date');
    
    notifyListeners();
  }

  /// Toggle credit consume alert setting
  Future<void> setShowCreditConsumeAlert(bool value) async {
    if (hasActiveSubscription) {
      _showCreditConsumeAlert = false;
      await _prefs?.setBool('show_credit_consume_alert', false);
      notifyListeners();
      return;
    }
    _showCreditConsumeAlert = value;
    await _prefs?.setBool('show_credit_consume_alert', value);
    notifyListeners();
  }

  /// Refresh balance from service
  Future<void> _refreshBalance() async {
    try {
      _isLoading = true;
      notifyListeners();

      _balance = await _service.getBalance();
      _error = null;
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Deduct credits and return auth token
  Future<String?> deductCredits(CreditPackage package) async {
    if (hasActiveSubscription) {
      return 'subscription_active';
    }
    try {
      final token = await _service.deductCredits(package);
      await _refreshBalance();
      return token;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return null;
    }
  }

  /// Add credits from reward
  Future<bool> addCreditsFromReward(double credits) async {
    try {
      final result = await _service.addCreditsFromReward(credits);
      await _refreshBalance();
      return result;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> addCreditsForDebug(double credits) async {
    try {
      final result = await _service.addCreditsForDebug(credits);
      await _refreshBalance();
      return result;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Check if user has enough credits
  bool hasEnough(CreditPackage package) {
    if (hasActiveSubscription) return true;
    if (_balance == null) return false;
    final cost = _service.getCostInfo(package);
    return _balance!.credits >= cost.costCredits;
  }

  /// Get cost info
  CreditCostInfo getCostInfo(CreditPackage package) {
    return _service.getCostInfo(package);
  }

  /// Get UI string
  String getUIString(String key) {
    return _service.getUIString(key);
  }

  /// Get ad reward Credits
  double getAdRewardCredits() {
    return _service.getAdRewardCredits();
  }
}
