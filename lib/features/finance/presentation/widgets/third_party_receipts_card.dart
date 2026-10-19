import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/save_feedback.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/entities/third_party_receipt.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';

final _day = DateFormat('dd/MM/yyyy');

/// Nome do cartão com o dono, para as listas de repasse.
String _cardLabel(PaymentMethod card, FinanceState state) {
  final owner = state.members.where((m) => m.id == card.ownerMemberId).firstOrNull;
  return owner == null ? '${card.name} (da casa)' : '${card.name} (${owner.name.split(' ').first})';
}

String _vaultName(FinanceState state, String vaultId) =>
    state.savingsVaults.where((v) => v.id == vaultId).firstOrNull?.name ?? 'Caixinha';

/// Repasses de terceiros: o dinheiro de fora que entrou na conta da Casa para
/// pagar uma compra (ex.: o Pix das marmitas) e fica guardado numa caixinha
/// até a fatura ser paga. Não é aporte de ninguém e não entra no Fôlego.
class ThirdPartyReceiptsCard extends StatelessWidget {
  final FinanceState state;
  final FinanceCubit cubit;

  const ThirdPartyReceiptsCard({super.key, required this.state, required this.cubit});

  @override
  Widget build(BuildContext context) {
    final held = state.heldThirdPartyReceipts;
    final used = state.thirdPartyReceipts.where((r) => r.isUsed).toList();
    final total = ThirdPartyReceipt.total(held);

    return Card(
      key: const Key('third_party_receipts_card'),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.call_received_rounded, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Repasses de terceiros',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                TextButton.icon(
                  key: const Key('add_third_party_receipt'),
                  onPressed: () => showThirdPartyReceiptForm(context, cubit, state),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Registrar'),
                ),
              ],
            ),
            const Text(
              'Dinheiro de quem não mora na casa para pagar uma compra no cartão (ex.: o Pix das marmitas). '
              'Fica guardado na caixinha até a fatura ser paga e não vira aporte de ninguém.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const Text('Guardado para faturas: ', style: TextStyle(fontSize: 13)),
                PrivacySensitiveText(
                  total.formatted,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (held.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Nenhum repasse guardado no momento.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              )
            else
              for (final receipt in held)
                ListTile(
                  key: ValueKey('held_receipt_${receipt.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${receipt.payerName} • ${receipt.amount.formatted}'),
                  subtitle: Text(_describe(receipt), style: const TextStyle(fontSize: 12)),
                  trailing: PopupMenuButton<String>(
                    key: ValueKey('held_receipt_menu_${receipt.id}'),
                    onSelected: (action) {
                      if (action == 'use') _showUseDialog(context, receipt);
                      if (action == 'delete') _confirmDelete(context, receipt);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'use', child: Text('Usar na fatura')),
                      PopupMenuItem(value: 'delete', child: Text('Excluir')),
                    ],
                  ),
                ),
            if (used.isNotEmpty) ...[
              const Divider(height: 24),
              const Text('Usados recentemente', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              for (final receipt in used)
                ListTile(
                  key: ValueKey('used_receipt_${receipt.id}'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text('${receipt.payerName} • ${receipt.amount.formatted}'),
                  subtitle: Text(_describeUse(receipt), style: const TextStyle(fontSize: 12)),
                  trailing: TextButton(
                    onPressed: () => _reopen(context, receipt),
                    child: const Text('Desfazer'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  String _describe(ThirdPartyReceipt receipt) {
    final card = state.paymentMethods.where((p) => p.id == receipt.paymentMethodId).firstOrNull;
    return [
      _day.format(receipt.receivedOn),
      _vaultName(state, receipt.vaultId),
      card == null ? 'sem cartão definido' : 'para ${_cardLabel(card, state)}',
      if (receipt.description != null) receipt.description!,
    ].join(' • ');
  }

  String _describeUse(ThirdPartyReceipt receipt) {
    final card = state.paymentMethods.where((p) => p.id == receipt.usedPaymentMethodId).firstOrNull;
    final how = receipt.use == ThirdPartyReceiptUse.housePaid
        ? 'usado pela Casa na fatura'
        : 'repassado a quem pagou a fatura';
    return [
      how,
      if (card != null) card.name,
      if (receipt.usedDueDate != null) 'venc. ${_day.format(receipt.usedDueDate!)}',
    ].join(' • ');
  }

  Future<void> _reopen(BuildContext context, ThirdPartyReceipt receipt) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await cubit.reopenThirdPartyReceipt(receipt.id);
    showSaveFeedback(
      messenger,
      ok: ok,
      success: 'O repasse de ${receipt.payerName} voltou para a caixinha.',
      failure: cubit.state.errorMessage,
    );
  }

  Future<void> _confirmDelete(BuildContext context, ThirdPartyReceipt receipt) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Excluir repasse?'),
        content: Text(
          'Os ${receipt.amount.formatted} de ${receipt.payerName} saem da caixinha '
          '${_vaultName(state, receipt.vaultId)}. Use quando o registro foi um engano ou o dinheiro foi devolvido.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.debtRed),
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await cubit.deleteThirdPartyReceipt(receipt.id);
    showSaveFeedback(messenger, ok: ok, success: 'Repasse excluído.', failure: cubit.state.errorMessage);
  }

  Future<void> _showUseDialog(BuildContext context, ThirdPartyReceipt receipt) async {
    final cards = state.paymentMethods.where((p) => p.isCreditCard).toList();
    String? cardId = cards.any((c) => c.id == receipt.paymentMethodId) ? receipt.paymentMethodId : null;
    ThirdPartyReceiptUse? use;
    final messenger = ScaffoldMessenger.of(context);

    ThirdPartyReceiptUse suggestedUse(String? id) {
      final card = cards.where((c) => c.id == id).firstOrNull;
      return card != null && card.ownerMemberId != null
          ? ThirdPartyReceiptUse.passedToOwner
          : ThirdPartyReceiptUse.housePaid;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          final chosenUse = use ?? suggestedUse(cardId);
          final owner = state.members
              .where((m) => m.id == cards.where((c) => c.id == cardId).firstOrNull?.ownerMemberId)
              .firstOrNull;
          return AlertDialog(
            title: Text('Usar o repasse de ${receipt.payerName}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String?>(
                    key: const Key('use_receipt_card'),
                    initialValue: cardId,
                    decoration: const InputDecoration(labelText: 'Fatura do cartão'),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Outro pagamento')),
                      for (final card in cards)
                        DropdownMenuItem<String?>(value: card.id, child: Text(_cardLabel(card, state))),
                    ],
                    onChanged: (value) => setDialogState(() {
                      cardId = value;
                      use = null;
                    }),
                  ),
                  const SizedBox(height: 16),
                  SegmentedButton<ThirdPartyReceiptUse>(
                    segments: const [
                      ButtonSegment(value: ThirdPartyReceiptUse.housePaid, label: Text('A Casa pagou')),
                      ButtonSegment(value: ThirdPartyReceiptUse.passedToOwner, label: Text('Repassei')),
                    ],
                    selected: {chosenUse},
                    onSelectionChanged: (s) => setDialogState(() => use = s.first),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    chosenUse == ThirdPartyReceiptUse.housePaid
                        ? 'A conta da Casa pagou: os ${receipt.amount.formatted} saem da caixinha, sem voltar ao Caixa do ciclo.'
                        : 'Os ${receipt.amount.formatted} saem da caixinha e vão para '
                            '${owner?.name.split(' ').first ?? 'quem pagou a fatura'}.',
                    style: const TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
              FilledButton(
                key: const Key('use_receipt_confirm'),
                onPressed: () {
                  use = chosenUse;
                  Navigator.pop(dialogCtx, true);
                },
                child: const Text('Usar'),
              ),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;
    final ok = await cubit.useThirdPartyReceipts(
      receiptIds: [receipt.id],
      use: use ?? suggestedUse(cardId),
      paymentMethodId: cardId,
    );
    showSaveFeedback(
      messenger,
      ok: ok,
      success: 'Repasse de ${receipt.payerName} usado: ${receipt.amount.formatted} saíram da caixinha.',
      failure: cubit.state.errorMessage,
    );
  }
}

/// Formulário para registrar uma entrada de terceiros.
Future<bool> showThirdPartyReceiptForm(
  BuildContext context,
  FinanceCubit cubit,
  FinanceState state,
) async {
  final vaults = state.savingsVaults;
  final cards = state.paymentMethods.where((p) => p.isCreditCard).toList();
  final messenger = ScaffoldMessenger.of(context);

  if (vaults.isEmpty) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Crie uma caixinha (ex.: "Repasses") para guardar o dinheiro de terceiros.')),
    );
    return false;
  }

  final payerController = TextEditingController();
  final descriptionController = TextEditingController();
  var cents = 0;
  var day = DateTime.now();
  // De saída, a caixinha que já tem cara de repasse
  var vaultId = (vaults.where((v) => v.name.toLowerCase().contains('repasse')).firstOrNull ?? vaults.first).id;
  String? cardId;
  String? error;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: const Text('Entrada de terceiros'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                key: const Key('receipt_payer'),
                controller: payerController,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(labelText: 'Quem pagou', errorText: error),
                onChanged: (_) {
                  if (error != null) setDialogState(() => error = null);
                },
              ),
              const SizedBox(height: 12),
              MoneyInputField(
                key: const Key('receipt_amount'),
                initialValue: Money(cents),
                onChanged: (value) => cents = value.cents,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: day,
                    firstDate: DateTime(day.year - 1),
                    lastDate: DateTime.now(),
                  );
                  if (picked != null) setDialogState(() => day = picked);
                },
                icon: const Icon(Icons.event_rounded, size: 18),
                label: Text('Entrou em ${_day.format(day)}'),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: const Key('receipt_vault'),
                initialValue: vaultId,
                decoration: const InputDecoration(labelText: 'Guardar na caixinha'),
                items: [
                  for (final vault in vaults) DropdownMenuItem(value: vault.id, child: Text(vault.name)),
                ],
                onChanged: (value) => setDialogState(() => vaultId = value ?? vaultId),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                key: const Key('receipt_card'),
                initialValue: cardId,
                decoration: const InputDecoration(labelText: 'Para a fatura do cartão'),
                items: [
                  const DropdownMenuItem<String?>(value: null, child: Text('Ainda não sei')),
                  for (final card in cards)
                    DropdownMenuItem<String?>(value: card.id, child: Text(_cardLabel(card, state))),
                ],
                onChanged: (value) => setDialogState(() => cardId = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Do que é (opcional)',
                  hintText: 'Ex.: marmitas de sábado',
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Não vira aporte de ninguém e não entra no Caixa do ciclo. Quando a fatura for paga, '
                'o valor sai da caixinha.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx, false), child: const Text('Cancelar')),
          FilledButton(
            key: const Key('receipt_save'),
            onPressed: () {
              if (payerController.text.trim().isEmpty) {
                setDialogState(() => error = 'Informe quem pagou.');
                return;
              }
              if (cents <= 0) {
                setDialogState(() => error = 'Informe o valor.');
                return;
              }
              Navigator.pop(dialogCtx, true);
            },
            child: const Text('Guardar'),
          ),
        ],
      ),
    ),
  );
  if (confirmed != true) return false;

  final payer = payerController.text.trim();
  final ok = await cubit.registerThirdPartyReceipt(
    payerName: payer,
    amount: Money(cents),
    receivedOn: day,
    vaultId: vaultId,
    paymentMethodId: cardId,
    description: descriptionController.text,
  );
  showSaveFeedback(
    messenger,
    ok: ok,
    success: 'Repasse de $payer guardado em ${_vaultName(cubit.state, vaultId)}.',
    failure: cubit.state.errorMessage,
  );
  return ok;
}
