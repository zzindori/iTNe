import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Credit package types for cost calculation
enum CreditPackage {
  ingredientScan,
  recipeGenerate,
  imageGenerate,
}

/// Credit balance model
class CreditBalance {
  final double credits; // e.g., 5.0 = 5 credits
  final DateTime lastUpdated;

  CreditBalance({
    required this.credits,
    required this.lastUpdated,
  });

  /// Formatted display string (e.g., "💳 5.0")
  String get displayString => '💳 ${credits.toStringAsFixed(1)}';

  factory CreditBalance.fromJson(Map<String, dynamic> json) {
    return CreditBalance(
      credits: (json['credits'] as num? ?? 0).toDouble(),
      lastUpdated: DateTime.parse(json['lastUpdated'] as String? ?? DateTime.now().toIso8601String()),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'credits': credits,
      'lastUpdated': lastUpdated.toIso8601String(),
    };
  }
}

/// Credit package cost info
class CreditCostInfo {
  final CreditPackage package;
  final String name;
  final String id;
  final double costCredits; // How many Credits this costs
  final double costUsd; // Cost in USD
  final String description;
  final bool isOptional;

  CreditCostInfo({
    required this.package,
    required this.name,
    required this.id,
    required this.costCredits,
    required this.costUsd,
    required this.description,
    this.isOptional = false,
  });
}

/// Manage user's credit balance and costs
class CreditService {
  static const String _configPath = 'assets/credit_config.json';
  static const String _creditBalanceKey = 'credit_balance';
  static const String _creditLastUpdatedKey = 'credit_last_updated';

  late Map<String, dynamic> _config;
  CreditBalance? _currentBalance;
  SharedPreferences? _prefs;

  bool _initialized = false;

  /// Singleton instance
  static final CreditService _instance = CreditService._internal();

  factory CreditService() {
    return _instance;
  }

  CreditService._internal();

  /// Initialize service from local config and SharedPreferences
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // Load config
      final configString = await rootBundle.loadString(_configPath);
      _config = jsonDecode(configString) as Map<String, dynamic>;
      
      // Load SharedPreferences
      _prefs = await SharedPreferences.getInstance();
      
      // Load saved balance from SharedPreferences
      final savedBalance = _prefs?.getDouble(_creditBalanceKey);
      final savedLastUpdated = _prefs?.getString(_creditLastUpdatedKey);
      
      if (savedBalance != null) {
        _currentBalance = CreditBalance(
          credits: savedBalance,
          lastUpdated: savedLastUpdated != null 
              ? DateTime.parse(savedLastUpdated)
              : DateTime.now(),
        );
        debugPrint('✅ Credit balance loaded from SharedPreferences: ${_currentBalance!.displayString}');
      }
      
      _initialized = true;
      debugPrint('✅ Credit service initialized from config');
    } catch (e) {
      debugPrint('Failed to load credit config: $e');
      _config = {};
    }
  }

  /// Get current balance (from SharedPreferences or initialize with signup bonus)
  Future<CreditBalance> getBalance() async {
    if (_currentBalance != null) {
      return _currentBalance!;
    }
    
    // First time: use signup bonus
    final signupBonus = (_config['credit']['signup_bonus']['credits'] as num? ?? 5).toDouble();
    _currentBalance = CreditBalance(
      credits: signupBonus,
      lastUpdated: DateTime.now(),
    );
    
    // Save to SharedPreferences
    await _saveBalance();
    
    return _currentBalance!;
  }

  /// Save balance to SharedPreferences
  Future<void> _saveBalance() async {
    if (_currentBalance == null || _prefs == null) return;
    
    await _prefs!.setDouble(_creditBalanceKey, _currentBalance!.credits);
    await _prefs!.setString(_creditLastUpdatedKey, _currentBalance!.lastUpdated.toIso8601String());
    debugPrint('✅ Credit balance saved: ${_currentBalance!.displayString}');
  }

  /// Get cost info for a package
  CreditCostInfo getCostInfo(CreditPackage package) {
    final credit = _config['credit'] as Map<String, dynamic>?;
    final pkgMap = credit?['packages'] as Map<String, dynamic>?;
    final packageKey = _getPackageKey(package);

    if (pkgMap == null || !pkgMap.containsKey(packageKey)) {
      throw StateError('Unknown package: $packageKey');
    }

    final pkg = pkgMap[packageKey] as Map<String, dynamic>;
    return CreditCostInfo(
      package: package,
      name: pkg['name'] as String,
      id: pkg['id'] as String,
      costCredits: (pkg['cost_credits'] as num).toDouble(),
      costUsd: (pkg['cost_usd'] as num).toDouble(),
      description: pkg['description'] as String,
      isOptional: pkg['is_optional'] as bool? ?? false,
    );
  }

  /// Check if user has enough credits for a package
  Future<bool> hasEnoughCredits(CreditPackage package) async {
    final balance = await getBalance();
    final cost = getCostInfo(package);
    return balance.credits >= cost.costCredits;
  }

  /// Get remaining credits after a package transaction
  Future<double> getRemainingCredits(CreditPackage package) async {
    final balance = await getBalance();
    final cost = getCostInfo(package);
    return balance.credits - cost.costCredits;
  }

  /// Deduct credits (server-side in production)
  /// Returns authorization token if successful
  Future<String?> deductCredits(CreditPackage package) async {
    try {
      final costInfo = getCostInfo(package);

      // TODO: In production, call server API
      // POST /api/credits/deduct
      // { "package": "ingredient_scan", "amount": 1 }

      final hasEnough = await hasEnoughCredits(package);
      if (!hasEnough) {
        debugPrint('Not enough credits: need ${costInfo.costCredits}, have ${_currentBalance?.credits}');
        return null;
      }

      final remaining = await getRemainingCredits(package);
      _currentBalance = CreditBalance(
        credits: remaining,
        lastUpdated: DateTime.now(),
      );

      // Save to SharedPreferences
      await _saveBalance();

      debugPrint('✅ Credits deducted: -${costInfo.costCredits}');
      debugPrint('   Remaining: ${_currentBalance!.displayString}');

      // In production, return the server response token
      return 'mock_token_${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      debugPrint('Failed to deduct credits: $e');
      return null;
    }
  }

  /// Server-side in production
  Future<bool> addCreditsFromReward(double credits) async {
    try {
      // TODO: Call server API to add credits
      // POST /api/credits/reward
      // { "reward_type": "ad", "amount": 0.5 }

      final newCredits = (_currentBalance?.credits ?? 0) + credits;
      _currentBalance = CreditBalance(
        credits: newCredits,
        lastUpdated: DateTime.now(),
      );

      // Save to SharedPreferences
      await _saveBalance();

      debugPrint('✅ Credits added from reward: +$credits');
      debugPrint('   Total: ${_currentBalance!.displayString}');
      return true;
    } catch (e) {
      debugPrint('Failed to add credits: $e');
      return false;
    }
  }

  /// Get reward credits from config (2 ads = 1 credit, so 0.5 per ad)
  double getAdRewardCredits() {
    return (_config['credit']['rewards']['ad_watch']['reward_credits'] as num? ?? 0.5).toDouble();
  }

  /// Check daily ad watch limit
  bool canWatchAdToday() {
    // TODO: Implement daily limit tracking
    return true;
  }

  /// Get UI strings from config
  String getUIString(String key) {
    return _config['credit']['ui'][key] as String? ?? key;
  }

  /// Private helper to get package key
  String _getPackageKey(CreditPackage package) {
    switch (package) {
      case CreditPackage.ingredientScan:
        return 'ingredient_scan';
      case CreditPackage.recipeGenerate:
        return 'recipe_generate';
      case CreditPackage.imageGenerate:
        return 'image_generate';
    }
  }
}
