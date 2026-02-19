import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/credit_provider.dart';

class RewardClaimScreen extends StatefulWidget {
  final double rewardAmount;
  final String symbol;

  const RewardClaimScreen({
    Key? key,
    required this.rewardAmount,
    required this.symbol,
  }) : super(key: key);

  @override
  State<RewardClaimScreen> createState() => _RewardClaimScreenState();
}

class _RewardClaimScreenState extends State<RewardClaimScreen> {
  bool _isProcessing = false;

  Future<void> _claimReward() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final provider = context.read<CreditProvider>();
      await provider.addCreditsFromReward(widget.rewardAmount);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '크레딧이 지급되었습니다 +${widget.rewardAmount.toStringAsFixed(1)} ${widget.symbol}',
            ),
            duration: const Duration(seconds: 2),
            backgroundColor: Colors.green,
          ),
        );

        // 약간의 지연 후 메인으로 돌아가기
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
      }
    } catch (e) {
      setState(() {
        _isProcessing = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('크레딧 추가 실패: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('리워드 지급'),
        centerTitle: true,
        automaticallyImplyLeading: true,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // 리워드 아이콘
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.amber.shade300,
                    Colors.orange.shade400,
                  ],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.amber.withValues(alpha: 0.5),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: const Icon(
                Icons.card_giftcard,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 40),
            // 제목
            const Text(
              '광고를 끝까지 시청했어요! 🎉',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            // 리워드 금액
            Text(
              '+${widget.rewardAmount.toStringAsFixed(1)} ${widget.symbol}',
              style: const TextStyle(
                fontSize: 48,
                fontWeight: FontWeight.bold,
                color: Colors.cyan,
              ),
            ),
            const SizedBox(height: 40),
            // 안내 문구
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                '아래 버튼을 눌러 크레딧을 받으세요!',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 40),
            // 크레딧 받기 버튼
            SizedBox(
              width: 200,
              height: 60,
              child: ElevatedButton(
                onPressed: _isProcessing ? null : _claimReward,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : const Text(
                        '크레딧 받기',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 20),
            // 돌아가기 버튼
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('나중에 받기'),
            ),
          ],
        ),
      ),
    );
  }
}
