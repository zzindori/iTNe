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
          margin: const EdgeInsets.symmetric(horizontal: 24),
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
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: isLoading ? null : () => Navigator.pop(context, false),
                      child: Container(
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
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      costInfo.name,
                      style: const TextStyle(
                        color: Colors.black87,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (hasEnoughCredits)
                      _buildCostRow(
                        label: creditService.getUIString('deduct_label'),
                        value:
                            '${currentCredits.toStringAsFixed(1)} → ${remainingCredits.toStringAsFixed(1)}',
                        valueColor: Colors.black87,
                      )
                    else
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF4F4),
                          border: Border.all(color: const Color(0xFFB20000), width: 1),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.warning_amber_rounded,
                              color: Color(0xFFB20000),
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${creditService.getUIString('insufficient_prefix')} ${currentCredits.toStringAsFixed(1)}',
                                style: const TextStyle(
                                  color: Color(0xFFB20000),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 8),
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
                        onPressed: isLoading ? null : () => Navigator.pop(context, false),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.black87,
                          side: const BorderSide(color: Colors.black26),
                          backgroundColor: const Color(0xFFEDEDED),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                        ),
                        child: Text(cancelButton),
                      ),
                    ),
                    if (!hasEnoughCredits && onCharge != null) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        child: OutlinedButton(
                          onPressed: isLoading ? null : onCharge,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black26),
                            backgroundColor: const Color(0xFFEDEDED),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                          ),
                          child: Text(chargeButton),
                        ),
                      ),
                    ],
                    if (hasEnoughCredits) ...[
                      const SizedBox(width: 8),
                      SizedBox(
                        height: 34,
                        child: OutlinedButton(
                          onPressed: isLoading
                              ? null
                              : () {
                                  onConfirm();
                                  Navigator.pop(context, true);
                                },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.black87,
                            side: const BorderSide(color: Colors.black26),
                            backgroundColor: const Color(0xFFEDEDED),
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(2)),
                          ),
                          child: Text(executeButton),
                        ),
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

  Widget _buildCostRow({
    required String label,
    required String value,
    required Color valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Colors.black54,
            fontSize: 13,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: valueColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            fontFamily: 'monospace',
          ),
        ),
      ],
    );
  }
}
