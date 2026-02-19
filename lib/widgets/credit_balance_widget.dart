import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/credit_provider.dart';
import '../data/services/credit_service.dart';
import '../data/services/in_app_purchase_service.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

/// Floating button to display and manage credit balance
class CreditBalanceButton extends StatelessWidget {
  final CreditProvider creditProvider;
  final VoidCallback onPressed;

  const CreditBalanceButton({
    Key? key,
    required this.creditProvider,
    required this.onPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.6),
          border: Border.all(
            color: Colors.amber.withValues(alpha: 0.5),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.amber.withValues(alpha: 0.3),
              blurRadius: 8,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (creditProvider.balance != null)
                  Text(
                    creditProvider.balance!.credits.toStringAsFixed(1),
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  )
                else
                  const Text(
                    '',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 10,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Panel to show credit balance and options
class CreditBalancePanel extends StatefulWidget {
  final CreditProvider creditProvider;
  final VoidCallback onWatchAd;
  final VoidCallback onPurchase;

  const CreditBalancePanel({
    Key? key,
    required this.creditProvider,
    required this.onWatchAd,
    required this.onPurchase,
  }) : super(key: key);

  @override
  State<CreditBalancePanel> createState() => _CreditBalancePanelState();
}

class _CreditBalancePanelState extends State<CreditBalancePanel> {
  static bool _developerCreditUnlocked = false;
  int _unlockStep = 0;
  int _usageTapCount = 0;
  int _chargeTapCount = 0;
  late InAppPurchaseService _iapService;
  List<ProductDetails> _subscriptionProducts = [];
  bool _isLoadingProducts = false;

  @override
  void initState() {
    super.initState();
    _iapService = InAppPurchaseService();
    _loadSubscriptionProducts();
  }

  Future<void> _loadSubscriptionProducts() async {
    setState(() {
      _isLoadingProducts = true;
    });
    final products = await _iapService.fetchProducts(
      {
        InAppPurchaseService.monthlySubscriptionId,
        InAppPurchaseService.yearlySubscriptionId,
      },
    );
    if (mounted) {
      setState(() {
        _subscriptionProducts = products;
        _isLoadingProducts = false;
      });
    }
  }

  Future<void> _showSubscriptionOptions() async {
    debugPrint('🛒 [Purchase] showing subscription options, loaded: ${_subscriptionProducts.length}, loading: $_isLoadingProducts');
    
    if (_isLoadingProducts) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구독 옵션을 불러오는 중...')),
      );
      return;
    }

    // Fallback to test options if no products loaded from IAP
    final productsToShow = _subscriptionProducts.isNotEmpty
        ? _subscriptionProducts
        : _getTestSubscriptionOptions();

    if (productsToShow.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('구독 옵션을 불러올 수 없습니다.')),
      );
      return;
    }

    final selected = await showDialog<ProductDetails>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          '🎁 구독 요금제',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
              ...productsToShow.map((product) {
                final isYearly = product.id.contains('yearly');
                return GestureDetector(
                  onTap: () {
                    debugPrint('📱 [Dialog] Selected: ${product.id}');
                    Navigator.pop(dialogContext, product);
                  },
                  child: Card(
                    elevation: 2,
                    margin: const EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: isYearly
                              ? [
                                  Colors.green.withValues(alpha: 0.15),
                                  Colors.teal.withValues(alpha: 0.1),
                                ]
                              : [
                                  Colors.blue.withValues(alpha: 0.1),
                                  Colors.cyan.withValues(alpha: 0.05),
                                ],
                        ),
                      ),
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  product.title,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF1F2B22),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  product.description,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF666666),
                                    height: 1.3,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                product.price,
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isYearly ? Colors.green : Colors.blue,
                                ),
                              ),
                              if (isYearly)
                                Container(
                                  margin: const EdgeInsets.only(top: 3),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.green.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(3),
                                  ),
                                  child: const Text(
                                    '할인',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
              const SizedBox(height: 8),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              debugPrint('📱 [Dialog] Cancelled');
              Navigator.pop(dialogContext);
            },
            child: const Text('취소'),
          ),
        ],
      ),
    );

    if (selected != null && mounted) {
      debugPrint('✅ [Purchase] Selected product: ${selected.id}, calling _purchaseSubscription');
      await _purchaseSubscription(selected);
    } else {
      debugPrint('⚠️ [Purchase] No selection or unmounted');
    }
  }

  List<ProductDetails> _getTestSubscriptionOptions() {
    // Fallback test options if IAP products not loaded
    return [
      _createTestProductDetails(
        id: 'monthly_subscription',
        title: '한달 무제한',
        description: '한 달간 모든 AI 기능 무제한 사용',
        price: '\$6.99',
      ),
      _createTestProductDetails(
        id: 'yearly_subscription',
        title: '1년 무제한 (연간 할인)',
        description: '1년간 모든 AI 기능 무제한 사용',
        price: '\$59.99',
      ),
    ];
  }

  ProductDetails _createTestProductDetails({
    required String id,
    required String title,
    required String description,
    required String price,
  }) {
    // Create a dummy ProductDetails for testing
    return _TestProductDetails(
      id: id,
      title: title,
      description: description,
      price: price,
    );
  }

  Future<void> _resetSubscriptionForDebug() async {
    try {
      debugPrint('🔄 [Debug] Resetting subscription for debug...');
      
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: Colors.red),
          ),
        );
      }

      await Future.delayed(const Duration(seconds: 1));
      await widget.creditProvider.cancelSubscription();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        await Future.delayed(const Duration(milliseconds: 300));
        
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ 구매 상태가 초기화되었습니다. (테스트 모드)'),
            backgroundColor: Colors.red,
            duration: Duration(seconds: 2),
          ),
        );
        
        debugPrint('✅ [Debug] Subscription reset completed');
      }
    } catch (e) {
      debugPrint('❌ [Debug] Reset error: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if visible
        await Future.delayed(const Duration(milliseconds: 300));
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('초기화 오류: $e'),
            backgroundColor: Colors.red.shade700,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _purchaseSubscription(ProductDetails product) async {
    try {
      debugPrint('💳 [Purchase] Starting subscription for ${product.id}');
      
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => const Center(
            child: CircularProgressIndicator(color: Colors.amber),
          ),
        );
      }

      // For test ProductDetails, show simulation
      if (product is _TestProductDetails) {
        debugPrint('🧪 [Purchase] Test mode - simulating purchase for ${product.id}');
        await Future.delayed(const Duration(seconds: 2));
        
        if (mounted) {
          Navigator.pop(context); // Close loading dialog
          await Future.delayed(const Duration(milliseconds: 300));
          
          // Set subscription based on product ID
          final subscriptionType = product.id.contains('yearly')
              ? SubscriptionType.yearly
              : SubscriptionType.monthly;
          
          await widget.creditProvider.setSubscription(subscriptionType);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${product.title} 구독 완료!'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          
          debugPrint('✅ [Purchase] Test purchase completed for ${product.id}');
        }
        return;
      }
      
      final success = await _iapService.purchaseSubscription(product);
      
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        await Future.delayed(const Duration(milliseconds: 300));
        
        if (success) {
          final subscriptionType = product.id.contains('yearly')
              ? SubscriptionType.yearly
              : SubscriptionType.monthly;
          
          await widget.creditProvider.setSubscription(subscriptionType);
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ ${product.title} 구독 완료! 무제한 사용을 즐기세요.'),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
          debugPrint('✅ [Purchase] Real purchase completed for ${product.id}');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('❌ 구독에 실패했습니다. 다시 시도해주세요.'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ [Purchase] Error: $e');
      if (mounted) {
        Navigator.pop(context); // Close loading dialog if still visible
        await Future.delayed(const Duration(milliseconds: 300));
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('구독 오류: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  void _onUsageSectionTap() {
    if (_developerCreditUnlocked) {
      return;
    }
    if (_unlockStep == 0) {
      _usageTapCount++;
      if (_usageTapCount >= 5) {
        _unlockStep = 1;
      }
    } else if (_unlockStep == 2) {
      _usageTapCount++;
      if (_chargeTapCount >= 1) {
        _unlockDeveloperCreditsIfNeeded();
      }
      return;
    }
    _unlockDeveloperCreditsIfNeeded();
  }

  void _onChargeSectionTap() {
    if (_developerCreditUnlocked) {
      return;
    }
    if (_unlockStep == 1) {
      _chargeTapCount++;
      if (_chargeTapCount >= 1) {
        _unlockStep = 2;
      }
    }
    _unlockDeveloperCreditsIfNeeded();
  }

  void _unlockDeveloperCreditsIfNeeded() {
    if (_unlockStep == 2 && _usageTapCount >= 6 && _chargeTapCount >= 1) {
      setState(() {
        _developerCreditUnlocked = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final creditService = CreditService();
    final creditProvider = context.watch<CreditProvider>();
    
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF2A2A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.amber.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '크레딧 ${creditProvider.balance?.displayString ?? '--'}',
                  style: const TextStyle(
                    color: Colors.amber,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'monospace',
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Consumer<CreditProvider>(
                builder: (context, provider, _) => GestureDetector(
                  onTap: provider.hasActiveSubscription
                      ? null
                      : () {
                          provider.setShowCreditConsumeAlert(!provider.showCreditConsumeAlert);
                        },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: provider.hasActiveSubscription
                          ? Colors.grey.withValues(alpha: 0.35)
                          : provider.showCreditConsumeAlert
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.red.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: provider.hasActiveSubscription
                            ? Colors.grey.withValues(alpha: 0.6)
                            : provider.showCreditConsumeAlert
                                ? Colors.green.withValues(alpha: 0.5)
                                : Colors.red.withValues(alpha: 0.5),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      provider.hasActiveSubscription
                          ? '알림OFF (구독중)'
                          : provider.showCreditConsumeAlert
                              ? '알림ON'
                              : '알림OFF',
                      style: TextStyle(
                        color: provider.hasActiveSubscription
                            ? Colors.white70
                            : provider.showCreditConsumeAlert
                                ? Colors.greenAccent
                                : Colors.redAccent,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (creditProvider.hasActiveSubscription)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
              decoration: BoxDecoration(
                color: creditProvider.subscriptionType == SubscriptionType.yearly
                    ? Colors.orange.withValues(alpha: 0.15)
                    : Colors.green.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: creditProvider.subscriptionType == SubscriptionType.yearly
                      ? Colors.orange.withValues(alpha: 0.4)
                      : Colors.green.withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    alignment: WrapAlignment.center,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 6,
                    runSpacing: 4,
                    children: [
                      Icon(
                        Icons.check_circle,
                        color: creditProvider.subscriptionType == SubscriptionType.yearly
                            ? Colors.orange
                            : Colors.green,
                        size: 16,
                      ),
                      Text(
                        '${creditProvider.subscriptionLabel} 이용 중',
                        style: TextStyle(
                          color: creditProvider.subscriptionType == SubscriptionType.yearly
                              ? Colors.orange
                              : Colors.green,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  if (creditProvider.subscriptionEndDate != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      '${creditProvider.subscriptionEndDate!.year}년 ${creditProvider.subscriptionEndDate!.month}월 ${creditProvider.subscriptionEndDate!.day}일 만료',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: (creditProvider.subscriptionType == SubscriptionType.yearly
                                ? Colors.orange
                                : Colors.green)
                            .withValues(alpha: 0.7),
                        fontSize: 10,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (creditProvider.balance != null)
            Expanded(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Usage info
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _onUsageSectionTap,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.grey.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              creditService.getUIString('usage_section_title'),
                              style: const TextStyle(
                                color: Color(0xFFB0B0B0),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              creditService.getUIString('usage_description'),
                              style: const TextStyle(
                                color: Color(0xFF909090),
                                fontSize: 11,
                                height: 1.5,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Pricing info
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _onChargeSectionTap,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              creditService.getUIString('charge_section_title'),
                              style: const TextStyle(
                                color: Color(0xFFB0B0B0),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildPricingRow(creditService.getUIString('ad_watch_option'), '${creditService.getUIString('symbol')} 1'),
                            _buildPricingRow('AI 셸프에게 커피 한 잔 ☕', '\$3.99 = ${creditService.getUIString('symbol')} 100'),
                            _buildPricingRow('한달 무제한', '\$6.99 / month'),
                            _buildPricingRow('1년 무제한 (연간 할인)', '\$59.99 / year'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            const Align(
              alignment: Alignment.center,
              child: CircularProgressIndicator(
                color: Colors.amber,
              ),
            ),
          const SizedBox(height: 20),

          if (_developerCreditUnlocked) ...[
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      final ok = await creditProvider.addCreditsForDebug(50);
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              ok
                                  ? '✅ 개발자 충전: +50.0'
                                  : '❌ 개발자 충전에 실패했습니다',
                            ),
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.orange.withValues(alpha: 0.6)),
                      foregroundColor: Colors.orangeAccent,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      '크레딧 +50',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () async {
                      await _resetSubscriptionForDebug();
                    },
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: Colors.red.withValues(alpha: 0.6)),
                      foregroundColor: Colors.redAccent,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text(
                      '구매 취소',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],

          // Action buttons (fixed at bottom)
          if (creditProvider.balance != null && !creditProvider.hasActiveSubscription)
            Row(
              children: [
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: widget.onWatchAd,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.blue.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              creditService.getUIString('symbol'),
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              creditService.getUIString('button_watch_ad'),
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              '+${creditService.getUIString('symbol')} ${creditProvider.getAdRewardCredits().toStringAsFixed(1)}',
                              style: const TextStyle(
                                color: Colors.blue,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _showSubscriptionOptions,
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: Colors.green.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              creditService.getUIString('symbol'),
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              creditService.getUIString('button_purchase'),
                              style: const TextStyle(
                                color: Colors.green,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              creditService.getUIString('not_available'),
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 9,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildPricingRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF909090),
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 2,
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Colors.lightBlue,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// Test ProductDetails implementation for fallback when IAP products are not available
class _TestProductDetails implements ProductDetails {
  @override
  final String id;
  @override
  final String title;
  @override
  final String description;
  @override
  final String price;
  @override
  final double rawPrice = 0.0;
  @override
  final String currencyCode = 'USD';
  @override
  final String currencySymbol = '\$';

  _TestProductDetails({
    required this.id,
    required this.title,
    required this.description,
    required this.price,
  });

  bool get isConsumable => false;

  List<PurchaseDetails> get pendingPurchase => [];
}


