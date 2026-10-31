import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';
import '../../domain/repositories/import_repository.dart';

/// Pergunta e exclui a compra parcelada inteira (0118): as parcelas previstas
/// da Casa, os empréstimos dela e o plano. Devolve true se excluiu.
Future<bool> confirmDeleteInstallmentPurchase(
  BuildContext context, {
  required String planId,
  required String title,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir compra parcelada?'),
      content: Text(
        'Apaga "$title" inteira: todas as parcelas previstas da Casa e os empréstimos dela. '
        'Depois você pode lançar de novo do jeito certo.\n\n'
        'Só dá enquanto nenhuma fatura importada confirmou parcela e nenhum empréstimo dela teve pagamento.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          key: const Key('confirm_delete_installment_purchase'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.debtRed,
            foregroundColor: Colors.white,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Excluir compra'),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  FinanceCubit? finance;
  P2PCubit? p2p;
  try {
    finance = context.read<FinanceCubit>();
  } catch (_) {}
  try {
    p2p = context.read<P2PCubit>();
  } catch (_) {}

  try {
    await sl<ImportRepository>().deleteInstallmentPurchase(planId);
  } catch (e) {
    messenger.showSnackBar(
      SnackBar(backgroundColor: AppColors.debtRed, content: Text('$e')),
    );
    return false;
  }

  await Future.wait([
    if (finance != null) finance.loadCycleData(cycle: finance.state.currentCycle),
    if (p2p != null) p2p.loadLoans(),
  ]);
  messenger.showSnackBar(
    SnackBar(content: Text('Compra parcelada "$title" excluída. 🗑️')),
  );
  return true;
}
