import 'package:flutter/material.dart';
import '../domain/enums/recurrence.dart';
import '../theme/app_colors.dart';
import '../utils/responsive.dart';

/// Diálogo padronizado para escolher o escopo de alteração ou exclusão de um item recorrente.
Future<RecurrenceScope?> showRecurrenceScopeDialog({
  required BuildContext context,
  required String itemTitle,
  required bool isDelete,
  bool isExpense = false,
}) {
  return showAdaptiveModal<RecurrenceScope>(
    context: context,
    maxWidth: 480,
    child: _RecurrenceScopeDialogContent(
      itemTitle: itemTitle,
      isDelete: isDelete,
      isExpense: isExpense,
    ),
  );
}

class _RecurrenceScopeDialogContent extends StatelessWidget {
  final String itemTitle;
  final bool isDelete;
  final bool isExpense;

  const _RecurrenceScopeDialogContent({
    required this.itemTitle,
    required this.isDelete,
    required this.isExpense,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = isDelete ? AppColors.debtRed : AppColors.primary;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Alça de arraste
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Cabeçalho
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isDelete ? Icons.delete_sweep_rounded : Icons.edit_calendar_rounded,
                  color: accentColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isDelete
                          ? (isExpense ? 'Excluir Despesa Recorrente' : 'Excluir Evento Recorrente')
                          : (isExpense ? 'Editar Despesa Recorrente' : 'Editar Evento Recorrente'),
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      itemTitle,
                      style: const TextStyle(color: Colors.grey, fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          Text(
            isDelete
                ? 'Este item faz parte de uma série que se repete. Como você deseja excluir?'
                : 'Este item faz parte de uma série que se repete. Onde você deseja aplicar a alteração?',
            style: const TextStyle(fontSize: 13, color: Colors.grey),
          ),
          const SizedBox(height: 16),

          // Opção 1: Apenas esta ocorrência
          _buildScopeOption(
            context: context,
            theme: theme,
            scope: RecurrenceScope.thisInstanceOnly,
            icon: Icons.calendar_today_rounded,
            title: isExpense
                ? RecurrenceScope.thisInstanceOnly.expenseTitle(isDelete: isDelete)
                : RecurrenceScope.thisInstanceOnly.title(isDelete: isDelete),
            subtitle: isExpense
                ? (isDelete
                    ? 'Exclui somente a cobrança deste ciclo. Próximos meses continuam normais.'
                    : 'Altera o valor/detalhes somente deste ciclo atual.')
                : RecurrenceScope.thisInstanceOnly.description(isDelete: isDelete),
            accentColor: accentColor,
          ),
          const SizedBox(height: 10),

          // Opção 2: Esta e as futuras ocorrências
          _buildScopeOption(
            context: context,
            theme: theme,
            scope: RecurrenceScope.thisAndFuture,
            icon: Icons.fast_forward_rounded,
            title: isExpense
                ? RecurrenceScope.thisAndFuture.expenseTitle(isDelete: isDelete)
                : RecurrenceScope.thisAndFuture.title(isDelete: isDelete),
            subtitle: isExpense
                ? (isDelete
                    ? 'Cancela a assinatura a partir deste mês. Mantém o histórico dos ciclos passados.'
                    : 'Aplica a alteração a partir deste ciclo para todos os meses futuros.')
                : RecurrenceScope.thisAndFuture.description(isDelete: isDelete),
            accentColor: accentColor,
          ),
          const SizedBox(height: 10),

          // Opção 3: Todas as ocorrências
          _buildScopeOption(
            context: context,
            theme: theme,
            scope: RecurrenceScope.allInstances,
            icon: Icons.all_inclusive_rounded,
            title: isExpense
                ? RecurrenceScope.allInstances.expenseTitle(isDelete: isDelete)
                : RecurrenceScope.allInstances.title(isDelete: isDelete),
            subtitle: isExpense
                ? (isDelete
                    ? 'Exclui completamente a assinatura e todas as cobranças registradas.'
                    : 'Atualiza o cadastro mestre e todas as cobranças vinculadas.')
                : RecurrenceScope.allInstances.description(isDelete: isDelete),
            accentColor: accentColor,
          ),
          const SizedBox(height: 16),

          // Botão Cancelar
          SizedBox(
            height: 44,
            child: TextButton(
              onPressed: () => Navigator.pop(context, null),
              child: const Text('Cancelar', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScopeOption({
    required BuildContext context,
    required ThemeData theme,
    required RecurrenceScope scope,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accentColor,
  }) {
    return InkWell(
      onTap: () => Navigator.pop(context, scope),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: accentColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.grey, size: 18),
          ],
        ),
      ),
    );
  }
}
