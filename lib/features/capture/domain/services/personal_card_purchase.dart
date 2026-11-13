import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/capture_proposal.dart';

/// Nota escaneada que é toda de um morador, paga no cartão: vira empréstimo,
/// como a mesma compra vira ao importar a fatura (linha "pessoal" de um
/// morador), e não uma despesa da Casa cobrada no fechamento.
class PersonalCardPurchase {
  const PersonalCardPurchase._();

  /// O morador que deve a nota, ou null quando ela segue como despesa comum.
  ///
  /// Vale só para a nota já paga (não a conta a pagar), num cartão com os
  /// dias de fechamento e vencimento, paga com um meio só, em que todos os
  /// itens são pessoais do mesmo morador e ele não é o dono do cartão (o
  /// dono não deve para si mesmo). Item pessoal sem responsável é de quem
  /// lançou ([launcherId]). Nota com itens da Casa e pessoais continua como
  /// despesa: o pessoal é cobrado do responsável no fechamento.
  static String? debtorOf({
    required List<InvoiceItemDraft> items,
    required PaymentMethod? card,
    required bool alreadyPaid,
    required bool hasOtherPayments,
    required String? launcherId,
  }) {
    if (!alreadyPaid || hasOtherPayments || items.isEmpty) return null;
    if (!ExpenseLaunchDefaults.waitsForInvoice(card)) return null;
    final debtors = <String?>{
      for (final item in items) item.isPersonal ? (item.assignedMemberId ?? launcherId) : null,
    };
    if (debtors.length != 1) return null;
    final debtor = debtors.single;
    if (debtor == null) return null;
    final lender = card!.ownerMemberId ?? P2PLoan.houseLenderId;
    return debtor == lender ? null : debtor;
  }
}
