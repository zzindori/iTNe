import 'package:flutter/material.dart';
import '../main.dart';
import '../screens/reward_claim_screen.dart';

/// Simple reward notification helper - not actually shown as a widget
class AdRewardClaimDialog {
  static Future<bool> show(
    BuildContext context, {
    required double rewardAmount,
    required String symbol,
  }) async {
    print('🔔 [Notification] Showing reward notification');
    
    try {
      // Use root overlay from NavigatorState instead of context
      final navigatorState = navigatorKey.currentState;
      if (navigatorState == null) {
        print('❌ [Notification] Navigator state not available');
        return false;
      }

      late OverlayEntry overlayEntry;
      overlayEntry = OverlayEntry(
        builder: (context) => Positioned(
          top: MediaQuery.of(context).padding.top + 16,
          right: 16,
          child: AdRewardNotification(
            onClose: () {
              print('✅ [Notification] X button tapped, removing overlay');
              overlayEntry.remove();
              print('✅ [Notification] Navigating to RewardClaimScreen via global navigator');
              // Use global navigator key for context-free navigation
              navigatorKey.currentState?.push(
                MaterialPageRoute(
                  builder: (_) => RewardClaimScreen(
                    rewardAmount: rewardAmount,
                    symbol: symbol,
                  ),
                ),
              );
            },
          ),
        ),
      );

      // Insert into root overlay
      navigatorState.overlay!.insert(overlayEntry);
      print('🔔 [Notification] Notification inserted into root overlay');
      return true;
    } catch (e) {
      print('⚠️ [Notification] Overlay error: $e. Attempting direct navigation...');
      // Fallback: directly navigate using global navigator
      try {
        navigatorKey.currentState?.push(
          MaterialPageRoute(
            builder: (_) => RewardClaimScreen(
              rewardAmount: rewardAmount,
              symbol: symbol,
            ),
          ),
        );
        print('✅ [Notification] Direct navigation successful via global navigator');
        return true;
      } catch (navError) {
        print('❌ [Notification] Navigation error: $navError');
        return false;
      }
    }
  }
}

class AdRewardNotification extends StatefulWidget {
  final VoidCallback onClose;

  const AdRewardNotification({
    Key? key,
    required this.onClose,
  }) : super(key: key);

  @override
  State<AdRewardNotification> createState() => _AdRewardNotificationState();
}

class _AdRewardNotificationState extends State<AdRewardNotification>
    with SingleTickerProviderStateMixin {
  late AnimationController _slideController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _slideController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideController, curve: Curves.easeOut));

    _slideController.forward();
  }

  @override
  void dispose() {
    _slideController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.green.shade700,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '리워드 지급됨',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                _slideController.reverse().then((_) {
                  widget.onClose();
                });
              },
              child: const Icon(Icons.close, color: Colors.white, size: 18),
            ),
          ],
        ),
      ),
    );
  }
}

