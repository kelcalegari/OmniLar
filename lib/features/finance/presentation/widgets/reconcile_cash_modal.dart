import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/theme/app_colors.dart';
import '../cubit/finance_cubit.dart';

enum ReconcileImpact {
  cashAndStatementOnly,
  cycleShared,
}

/// Modal para conciliar o saldo do Caixa da Casa com o saldo real do banco.
///
/// Permite ao usuário informar o saldo atual exibido no app do seu banco.
/// Oferece duas modalidades:
/// 1. Apenas Caixa e Extrato: Ajusta o saldo bancário e o extrato sem alterar
///    a divisão ou cobrança entre os moradores no fechamento.
/// 2. Ratear no Ciclo: Registra o ajuste como despesa/entrada compartilhada da
///    casa, entrando no rateio entre os moradores no fechamento.
class ReconcileCashModal extends StatefulWidget {
  final Money currentBalance;
  final VoidCallback? onSuccess;

  const ReconcileCashModal({
    super.key,
    required this.currentBalance,
    this.onSuccess,
  });

  static Future<void> show(
    BuildContext context, {
    required Money currentBalance,
    VoidCallback? onSuccess,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(ctx).viewInsets.bottom,
        ),
        child: ReconcileCashModal(
          currentBalance: currentBalance,
          onSuccess: onSuccess,
        ),
      ),
    );
  }

  @override
  State<ReconcileCashModal> createState() => _ReconcileCashModalState();
}

class _ReconcileCashModalState extends State<ReconcileCashModal> {
  late Money _targetBalance;
  final TextEditingController _reasonController = TextEditingController(
    text: 'Conciliação com o saldo bancário',
  );
  DateTime _selectedDate = DateTime.now();
  ReconcileImpact _impact = ReconcileImpact.cashAndStatementOnly;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _targetBalance = widget.currentBalance;
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  int get _diffCents => _targetBalance.cents - widget.currentBalance.cents;

  Future<void> _handleSave() async {
    if (_diffCents == 0) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);
    final cubit = context.read<FinanceCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final success = await cubit.reconcileCashBalance(
      targetBalance: _targetBalance,
      currentBalance: widget.currentBalance,
      reason: _reasonController.text.trim(),
      date: _selectedDate,
      impactCycleSettlement: _impact == ReconcileImpact.cycleShared,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (success) {
      navigator.pop();
      widget.onSuccess?.call();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Saldo do Caixa da Casa conciliado com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(cubit.state.errorMessage ?? 'Erro ao conciliar saldo.'),
          backgroundColor: AppColors.debtRed,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E222A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Puxador visual
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Título e Ícone
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.account_balance_wallet_outlined,
                  color: AppColors.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Conciliar Saldo do Caixa',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'Ajuste o saldo do app para bater com a conta bancária',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: isDark ? Colors.white60 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),

          // Box com o saldo registrado no app atualmente
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF2A2E39) : const Color(0xFFF4F6F9),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Saldo no app agora:',
                      style: TextStyle(
                        fontSize: 13,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ],
                ),
                Text(
                  widget.currentBalance.format(),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Campo: Saldo real no banco
          MoneyTextFormField(
            key: const ValueKey('reconcile_target_cash_field'),
            initialValue: _targetBalance,
            labelText: 'Saldo real na conta bancária hoje',
            helperText: 'O valor exato que aparece no extrato do seu banco.',
            prefixIcon: const Icon(Icons.account_balance_outlined),
            onChanged: (m) => setState(() => _targetBalance = m),
          ),
          const SizedBox(height: 12),

          // Feedback da Diferença
          if (_diffCents != 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _diffCents > 0
                    ? Colors.green.withValues(alpha: 0.12)
                    : Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _diffCents > 0 ? Colors.green : AppColors.debtRed,
                  width: 0.8,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    _diffCents > 0
                        ? Icons.arrow_downward_rounded
                        : Icons.arrow_upward_rounded,
                    size: 18,
                    color: _diffCents > 0 ? Colors.green : AppColors.debtRed,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _diffCents > 0
                          ? 'Entrada de ajuste no Caixa: + ${Money(_diffCents).format()}'
                          : 'Saída de ajuste no Caixa: - ${Money(-_diffCents).format()}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: _diffCents > 0
                            ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                            : (isDark ? Colors.red.shade300 : AppColors.debtRed),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Seletor de Impacto (Extrato vs Ciclo)
          Text(
            'Destino do ajuste:',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          SegmentedButton<ReconcileImpact>(
            segments: const [
              ButtonSegment<ReconcileImpact>(
                value: ReconcileImpact.cashAndStatementOnly,
                icon: Icon(Icons.account_balance_outlined, size: 18),
                label: Text(
                  'Apenas Caixa',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
              ButtonSegment<ReconcileImpact>(
                value: ReconcileImpact.cycleShared,
                icon: Icon(Icons.pie_chart_outline_rounded, size: 18),
                label: Text(
                  'Ratear no Ciclo',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
              ),
            ],
            selected: {_impact},
            onSelectionChanged: (newSelection) {
              setState(() {
                _impact = newSelection.first;
              });
            },
          ),
          const SizedBox(height: 6),
          Text(
            _impact == ReconcileImpact.cashAndStatementOnly
                ? '• Corrige o saldo e o extrato sem gerar cobrança para moradores no Fechamento.'
                : '• Entra nas despesas/entradas da casa e é rateado entre todos no Fechamento.',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11,
              color: isDark ? Colors.white60 : Colors.black54,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 14),

          // Data do ajuste
          InkWell(
            onTap: () async {
              final picked = await showDatePicker(
                context: context,
                initialDate: _selectedDate,
                firstDate: DateTime(2020),
                lastDate: DateTime(2035),
              );
              if (picked != null) {
                setState(() => _selectedDate = picked);
              }
            },
            borderRadius: BorderRadius.circular(12),
            child: InputDecorator(
              decoration: InputDecoration(
                labelText: 'Data do ajuste',
                prefixIcon: const Icon(Icons.calendar_today_outlined),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                isDense: true,
              ),
              child: Text(
                '${_selectedDate.day.toString().padLeft(2, '0')}/${_selectedDate.month.toString().padLeft(2, '0')}/${_selectedDate.year}',
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Campo: Motivo do ajuste
          TextField(
            controller: _reasonController,
            decoration: InputDecoration(
              labelText: 'Motivo do ajuste',
              hintText: 'Ex: Acerto de fatura, tarifa ou rendimento',
              prefixIcon: const Icon(Icons.edit_note_outlined),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
          const SizedBox(height: 20),

          // Botões de Ação
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Cancelar'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                flex: 2,
                child: FilledButton(
                  onPressed: _isSaving || _diffCents == 0 ? null : _handleSave,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Confirmar Ajuste',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
