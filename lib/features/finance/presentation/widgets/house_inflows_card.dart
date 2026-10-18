import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/save_feedback.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_inflow.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';

final _day = DateFormat('dd/MM/yyyy');

/// Morador logado; null fora da sessão (testes, modo sem login).
String? _signedInMemberId() {
  try {
    return sl<AuthRepository>().currentUser?.id;
  } catch (_) {
    return null;
  }
}

bool _isAdmin(FinanceState state, String? memberId) {
  final me = state.members.where((m) => m.id == memberId).firstOrNull;
  return me?.role == 'owner' || me?.role == 'admin';
}

/// Despesas do ciclo que uma entrada pode reembolsar (as da casa, mais novas primeiro).
List<HouseExpense> _refundableExpenses(FinanceState state) =>
    state.expenses.where((e) => !e.isProjectExpense).toList()..sort((a, b) => b.date.compareTo(a.date));

/// Entradas de fora do ciclo: dinheiro que entrou no Caixa da Casa sem ser
/// aporte de um morador (Pix de terceiro, reembolso, devolução). Somam no
/// Caixa do ciclo e seguem a regra "Entrada de fora" da casa no rateio.
class HouseInflowsCard extends StatelessWidget {
  final FinanceState state;
  final FinanceCubit cubit;

  /// Morador logado (quem lançou corrige e exclui). Sem ele, vale o da sessão.
  final String? currentMemberId;

  const HouseInflowsCard({super.key, required this.state, required this.cubit, this.currentMemberId});

  @override
  Widget build(BuildContext context) {
    final me = currentMemberId ?? _signedInMemberId();
    final isAdmin = _isAdmin(state, me);
    final inflows = state.houseInflows;

    return Card(
      key: const Key('house_inflows_card'),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.south_west_rounded, color: AppColors.creditGreen, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Entradas de fora',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                TextButton.icon(
                  key: const Key('add_house_inflow'),
                  onPressed: () => showHouseInflowForm(context, cubit, state, currentMemberId: me),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Lançar'),
                ),
              ],
            ),
            const Text(
              'Dinheiro que entrou no Caixa sem ser aporte de um morador: Pix de alguém de fora, reembolso, devolução de loja.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (inflows.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Text('Entrou neste ciclo: ', style: TextStyle(fontSize: 13)),
                  PrivacySensitiveText(
                    state.houseInflowsTotal.formatted,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: AppColors.creditGreen),
                  ),
                ],
              ),
              for (final inflow in inflows)
                ListTile(
                  key: ValueKey('house_inflow_${inflow.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${inflow.description} • ${inflow.amount.formatted}'),
                  subtitle: Text(_describe(inflow), style: const TextStyle(fontSize: 12)),
                  trailing: inflow.canEdit(memberId: me, isAdmin: isAdmin)
                      ? PopupMenuButton<String>(
                          key: ValueKey('house_inflow_menu_${inflow.id}'),
                          onSelected: (action) {
                            if (action == 'edit') {
                              showHouseInflowForm(context, cubit, state, editing: inflow, currentMemberId: me);
                            }
                            if (action == 'delete') _confirmDelete(context, inflow);
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(value: 'edit', child: Text('Editar')),
                            PopupMenuItem(value: 'delete', child: Text('Excluir')),
                          ],
                        )
                      : null,
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _describe(HouseInflow inflow) {
    final expense = state.expenses.where((e) => e.id == inflow.expenseId).firstOrNull;
    final author = state.members.where((m) => m.id == inflow.createdBy).firstOrNull;
    return [
      _day.format(inflow.receivedOn),
      inflow.source.label,
      if (expense != null) 'reembolsa ${expense.title}',
      if (author != null) 'lançado por ${author.name.split(' ').first}',
    ].join(' • ');
  }

  Future<void> _confirmDelete(BuildContext context, HouseInflow inflow) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir entrada?'),
        content: Text('Os ${inflow.amount.formatted} de "${inflow.description}" saem do Caixa do ciclo.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('house_inflow_delete_confirm'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await cubit.deleteHouseInflow(inflow.id);
    showSaveFeedback(messenger, ok: ok, success: 'Entrada excluída.', failure: cubit.state.errorMessage);
  }
}

/// Formulário para lançar (ou, com [editing], corrigir) uma entrada de fora.
Future<bool> showHouseInflowForm(
  BuildContext context,
  FinanceCubit cubit,
  FinanceState state, {
  HouseInflow? editing,
  String? currentMemberId,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  final expenses = _refundableExpenses(state);
  final descriptionController = TextEditingController(text: editing?.description ?? '');
  var cents = editing?.amount.cents ?? 0;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  var day = editing?.receivedOn ?? (state.currentCycle.contains(today) ? today : state.currentCycle.startDate);
  var source = editing?.source ?? HouseInflowSource.thirdPartyPix;
  String? expenseId = editing?.expenseId;
  // Despesa reembolsada que não está no ciclo carregado: fica como estava
  final keepsOtherExpense = expenseId != null && !expenses.any((e) => e.id == expenseId);
  String? error;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(editing == null ? 'Entrada de fora' : 'Editar entrada de fora'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              MoneyInputField(
                key: const Key('house_inflow_amount'),
                primaryColor: AppColors.creditGreen,
                initialValue: Money(cents),
                onChanged: (value) {
                  cents = value.cents;
                  if (error != null) setDialogState(() => error = null);
                },
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('house_inflow_description'),
                controller: descriptionController,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: 'Do que é',
                  hintText: 'Ex.: Pix do João pela pizza',
                  errorText: error,
                ),
                onChanged: (_) {
                  if (error != null) setDialogState(() => error = null);
                },
              ),
              const SizedBox(height: 12),
              const Text('De onde veio', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
              const SizedBox(height: 4),
              Wrap(
                spacing: 6,
                children: [
                  for (final option in HouseInflowSource.values)
                    ChoiceChip(
                      key: ValueKey('house_inflow_source_${option.dbValue}'),
                      label: Text(option.label),
                      selected: source == option,
                      onSelected: (_) => setDialogState(() => source = option),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(day.year - 1),
                    lastDate: today.isAfter(day) ? today : day,
                  );
                  if (picked != null) setDialogState(() => day = picked);
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Entrou em ${_day.format(day)}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('house_inflow_expense'),
                initialValue: expenseId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Reembolsa uma despesa? (opcional)'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Nenhuma')),
                  if (keepsOtherExpense)
                    DropdownMenuItem<String?>(value: expenseId, child: const Text('Despesa de outro ciclo')),
                  for (final expense in expenses)
                    DropdownMenuItem<String?>(
                      value: expense.id,
                      child: Text('${expense.title} • ${expense.amount.formatted}', overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) => setDialogState(() => expenseId = value),
              ),
              const SizedBox(height: 8),
              const Text(
                'Entra no Caixa do ciclo do dia em que caiu e não vira aporte de ninguém. '
                'Pix para pagar a fatura de um cartão vai em Repasses de terceiros, nas Caixinhas.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('house_inflow_save'),
            style: FilledButton.styleFrom(backgroundColor: AppColors.creditGreen),
            onPressed: () {
              if (cents <= 0) {
                setDialogState(() => error = 'Informe o valor.');
                return;
              }
              if (descriptionController.text.trim().isEmpty) {
                setDialogState(() => error = 'Diga do que é a entrada.');
                return;
              }
              Navigator.pop(dialogCtx, true);
            },
            child: Text(editing == null ? 'Lançar' : 'Salvar'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return false;

  final inflow = HouseInflow(
    id: editing?.id ?? 'inflow_${DateTime.now().millisecondsSinceEpoch}',
    amount: Money(cents),
    receivedOn: DateTime(day.year, day.month, day.day),
    description: descriptionController.text.trim(),
    source: source,
    expenseId: expenseId,
    createdBy: editing?.createdBy ?? currentMemberId ?? _signedInMemberId(),
  );
  final ok = editing == null ? await cubit.addHouseInflow(inflow) : await cubit.updateHouseInflow(inflow);
  showSaveFeedback(
    messenger,
    ok: ok,
    success: editing == null
        ? 'Entrada de ${inflow.amount.formatted} lançada no Caixa.'
        : 'Entrada corrigida.',
    failure: cubit.state.errorMessage,
  );
  return ok;
}
