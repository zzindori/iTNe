import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/credit_provider.dart';
import '../data/services/credit_service.dart';

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
          // Header row with title, balance, and toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(
                creditService.getUIString('balance_title'),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              // Balance display moved here
              if (creditProvider.balance != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    creditProvider.balance!.displayString,
                    style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              Row(
                children: [
                  Text(
                    creditService.getUIString('symbol'),
                    style: const TextStyle(fontSize: 20),
                  ),
                  const SizedBox(width: 8),
                  // On/Off toggle with Consumer for real-time update
                  Consumer<CreditProvider>(
                    builder: (context, provider, _) => GestureDetector(
                      onTap: () {
                        provider.setShowCreditConsumeAlert(!provider.showCreditConsumeAlert);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: provider.showCreditConsumeAlert
                              ? Colors.green.withValues(alpha: 0.3)
                              : Colors.red.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: provider.showCreditConsumeAlert
                                ? Colors.green.withValues(alpha: 0.5)
                                : Colors.red.withValues(alpha: 0.5),
                            width: 1,
                          ),
                        ),
                        child: Text(
                          provider.showCreditConsumeAlert
                              ? creditService.getUIString('alert_on')
                              : creditService.getUIString('alert_off'),
                          style: TextStyle(
                            color: provider.showCreditConsumeAlert
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
            ],
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
                            _buildPricingRow('AI 셸프에게 커피 두 잔 ☕☕', '\$7.99 = ${creditService.getUIString('symbol')} 250'),
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
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () async {
                  final ok = await creditProvider.addCreditsForDebug(50);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          ok
                              ? '개발자 충전: +50.0'
                              : '개발자 충전에 실패했습니다',
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
                  '개발자용 크레딧 +50',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
          ],

          // Action buttons (fixed at bottom)
          if (creditProvider.balance != null)
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
                      onTap: widget.onPurchase,
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
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF909090),
              fontSize: 11,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Colors.lightBlue,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
