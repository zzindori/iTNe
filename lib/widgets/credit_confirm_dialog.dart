import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../data/services/credit_service.dart';
import '../models/credit_provider.dart';

/// Dialog to confirm credit cost before executing an action
class CreditConfirmDialog extends StatelessWidget {
  final CreditCostInfo costInfo;
  final double currentCredits;
  final VoidCallback onConfirm;
  final VoidCallback? onCharge;
  final bool isLoading;

  const CreditConfirmDialog({
    Key? key,
    required this.costInfo,
    required this.currentCredits,
    required this.onConfirm,
    this.onCharge,
    this.isLoading = false,
  }) : super(key: key);

  /// Show dialog for credit cost confirmation
  static Future<bool> show(
    BuildContext context, {
    required CreditCostInfo costInfo,
    required double currentCredits,
    required VoidCallback onConfirm,
    VoidCallback? onCharge,
  }) async {
    // Check if alert should be shown
    final creditProvider = context.read<CreditProvider>();
    if (!creditProvider.showCreditConsumeAlert) {
      // Alert is disabled, directly execute onConfirm
      onConfirm();
      return true;
    }

    // Alert is enabled, show the dialog
    return (await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => CreditConfirmDialog(
        costInfo: costInfo,
        currentCredits: currentCredits,
        onConfirm: onConfirm,
        onCharge: onCharge,
      ),
    )) ??
        false;
  }

  bool get hasEnoughCredits => currentCredits >= costInfo.costCredits;
  double get remainingCredits => currentCredits - costInfo.costCredits;

  @override
  Widget build(BuildContext context) {
    final creditService = CreditService();
    final title = creditService.getUIString('confirm_modal_title');
    final executeButton = creditService.getUIString('button_execute');
    final cancelButton = creditService.getUIString('button_cancel');
    final chargeButton = creditService.getUIString('button_charge');

    return Material(
      type: MaterialType.transparency,
      child: Center(
        child: Container(
          width: 420,
          margin: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            color: const Color(0xFFC0C0C0), // Windows 95/98 gray
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.4),
                blurRadius: 0,
                offset: const Offset(4, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Title bar with Windows classic style
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF000080), Color(0xFF1084D0)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: isLoading ? null : () => Navigator.pop(context, false),
                      child: Container(
                        width: 16,
                        height: 14,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC0C0C0),
                          border: Border.all(color: Colors.white, width: 1),
                        ),
                        child: const Center(
                          child: Text(
                            '×',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                              height: 0.8,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 2),
                  ],
                ),
              ),
              // Content area with Windows classic gray background
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Main message
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Information icon
                        Container(
                          width: 32,
                          height: 32,
                          margin: const EdgeInsets.only(right: 10, top: 2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF000080),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Text(
                              'i',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                fontStyle: FontStyle.italic,
                                fontFamily: 'serif',
                              ),
                            ),
                          ),
                        ),
                        // Message text
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  costInfo.name,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  '이 작업을 실행하시겠습니까?',
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    // Credit info box with Windows sunken style
                    Container(
                      margin: const EdgeInsets.only(left: 42),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        border: Border(
                          top: BorderSide(color: Colors.grey.shade600, width: 1),
                          left: BorderSide(color: Colors.grey.shade600, width: 1),
                          right: BorderSide(color: Colors.grey.shade300, width: 1),
                          bottom: BorderSide(color: Colors.grey.shade300, width: 1),
                        ),
                      ),
                      child: hasEnoughCredits
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildInfoRow('소모 크레딧:', '${costInfo.costCredits.toStringAsFixed(1)} ☕'),
                                const SizedBox(height: 6),
                                _buildInfoRow('현재 잔액:', '${currentCredits.toStringAsFixed(1)} ☕'),
                                const SizedBox(height: 6),
                                Divider(height: 1, color: Colors.grey.shade400),
                                const SizedBox(height: 6),
                                _buildInfoRow(
                                  '실행 후 잔액:',
                                  '${remainingCredits.toStringAsFixed(1)} ☕',
                                  valueColor: remainingCredits < 5 ? const Color(0xFFB20000) : const Color(0xFF008000),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  color: Color(0xFFB20000),
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '크레딧이 부족합니다!\n현재 잔액: ${currentCredits.toStringAsFixed(1)} ☕\n필요한 크레딧: ${costInfo.costCredits.toStringAsFixed(1)} ☕',
                                    style: const TextStyle(
                                      color: Color(0xFFB20000),
                                      fontSize: 12,
                                      height: 1.4,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ],
                ),
              ),
              // Button area
              Container(
                padding: const EdgeInsets.only(right: 12, bottom: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    _buildClassicButton(
                      label: cancelButton,
                      onPressed: isLoading ? null : () => Navigator.pop(context, false),
                    ),
                    if (!hasEnoughCredits && onCharge != null) ...[
                      const SizedBox(width: 8),
                      _buildClassicButton(
                        label: chargeButton,
                        onPressed: isLoading ? null : onCharge,
                      ),
                    ],
                    if (hasEnoughCredits) ...[
                      const SizedBox(width: 8),
                      _buildClassicButton(
                        label: executeButton,
                        onPressed: isLoading
                            ? null
                            : () {
                                onConfirm();
                                Navigator.pop(context, true);
                              },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Windows classic button style
  Widget _buildClassicButton({
    required String label,
    required VoidCallback? onPressed,
  }) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFC0C0C0),
          border: Border.all(
            color: Colors.black,
            width: 1,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.white,
              offset: Offset(-1, -1),
              blurRadius: 0,
              spreadRadius: 0,
            ),
            BoxShadow(
              color: Color(0xFF808080),
              offset: Offset(1, 1),
              blurRadius: 0,
              spreadRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.black,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  // Helper method to build info rows
  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black87,
            fontSize: 12,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? Colors.black,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
