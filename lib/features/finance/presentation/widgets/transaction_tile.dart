import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_transaction.dart';
import '../../domain/entities/split_rule.dart';

class TransactionTile extends StatelessWidget {
  final HouseTransaction transaction;
  final VoidCallback? onTap;

  const TransactionTile({
    super.key,
    required this.transaction,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isExpense = transaction.isExpense;
    final raw = transaction.rawEntity;
    final bool isSingleResponsibleToOther = raw is HouseExpense &&
        raw.splitRule.type == SplitType.categoryOwner &&
        raw.splitRule.singleResponsibleMemberId != null &&
        raw.splitRule.singleResponsibleMemberId != raw.paidByMemberId;

    // Determina a cor e o ícone da categoria ou tipo
    Color iconColor;
    if (transaction.categoryColorHex != null && transaction.categoryColorHex!.isNotEmpty) {
      try {
        final hex = transaction.categoryColorHex!.replaceAll('#', '');
        iconColor = Color(int.parse('FF$hex', radix: 16));
      } catch (_) {
        iconColor = isExpense ? AppColors.debtRed : AppColors.primary;
      }
    } else {
      iconColor = isExpense ? AppColors.debtRed : AppColors.primary;
    }

    final IconData iconData = transaction.origin == TransactionOrigin.loanRepayment
        ? Icons.handshake_rounded
        : (isExpense
            ? Icons.shopping_bag_outlined
            : (transaction.origin == TransactionOrigin.contribution
                ? Icons.savings_outlined
                : Icons.arrow_downward_rounded));

    if (transaction.origin == TransactionOrigin.loanRepayment) {
      iconColor = AppColors.primary;
    }

    final amountColor = isExpense
        ? (isDark ? Colors.red.shade300 : AppColors.debtRed)
        : (isDark ? Colors.green.shade300 : Colors.green.shade700);

    final sign = isExpense ? '- ' : '+ ';

    // Monta o subtítulo
    final List<String> details = [];
    if (transaction.memberName != null && transaction.memberName!.isNotEmpty) {
      details.add(transaction.memberName!.split(' ').first);
    }
    if (transaction.paymentMethodName != null && transaction.paymentMethodName!.isNotEmpty) {
      details.add(transaction.paymentMethodName!);
    }
    if (transaction.categoryName != null && transaction.categoryName!.isNotEmpty) {
      details.add(transaction.categoryName!);
    }

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Ícone da Categoria ou Tipo
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: isDark ? 0.2 : 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                iconData,
                color: iconColor,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            // Informações da Transação
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          transaction.title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isSingleResponsibleToOther) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            '100% individual',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                      if (transaction.isPending) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Pendente',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.amber.shade800,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    details.isNotEmpty ? details.join(' • ') : (isExpense ? 'Despesa' : 'Entrada'),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Valor Monetário
            Text(
              '$sign${transaction.amount.format()}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: amountColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
