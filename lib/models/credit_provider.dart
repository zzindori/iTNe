import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/services/credit_service.dart';

/// Manages credit state and notifies listeners
class CreditProvider extends ChangeNotifier {
  final CreditService _service = CreditService();
  CreditBalance? _balance;
  bool _isLoading = true;
  String? _error;
  bool _showCreditConsumeAlert = true;
  SharedPreferences? _prefs;

  CreditBalance? get balance => _balance;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get showCreditConsumeAlert => _showCreditConsumeAlert;

  /// Initialize provider
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      _showCreditConsumeAlert = _prefs?.getBool('show_credit_consume_alert') ?? true;
      
      await _service.initialize();
      await _refreshBalance();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
    }
  }

  /// Toggle credit consume alert setting
  Future<void> setShowCreditConsumeAlert(bool value) async {
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
