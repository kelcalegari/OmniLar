import 'package:intl/intl.dart';

import '../../../finance/domain/entities/card_invoice.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../entities/imported_statement_line.dart';
import '../repositories/import_repository.dart';
import 'statement_text.dart';

enum ExtraActionType {
  /// Saída da conta que paga a fatura de um cartão.
  payInvoice,

  /// Entrada na conta da casa que é o aporte de um morador.
  contribution,

  /// Entrada que abate um empréstimo de quem é dono da conta.
  loanPayment,
}

/// O que uma linha que não é compra pode virar no app: nada disso é despesa
/// nova, só o registro de um movimento que o app já esperava.
class ExtraAction {
  final ExtraActionType type;

  /// Identifica a opção entre as de uma linha.
  final String key;
  final String label;

  /// O valor (ou o nome na descrição) indica que é esta a opção certa.
  final bool suggested;
  final String? paymentMethodId;
  final DateTime? invoiceDueDate;
  final String? memberId;
  final String? loanId;

  const ExtraAction({
    required this.type,
    required this.key,
    required this.label,
    this.suggested = false,
    this.paymentMethodId,
    this.invoiceDueDate,
    this.memberId,
    this.loanId,
  });
}

/// Monta, para as linhas de um extrato de conta que não são compra, o que cada
/// uma pode ser: pagamento de fatura, aporte ou abatimento de empréstimo.
class StatementExtras {
  const StatementExtras._();

  static final _day = DateFormat('dd/MM');

  /// Um pagamento de fatura cai perto do vencimento dela.
  static const int invoiceWindowDays = 45;

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static bool _mentions(String description, String name) {
    final first = StatementText.normalize(name).split(' ').first;
    return first.length >= 3 && StatementText.normalize(description).split(' ').contains(first);
  }

  static Map<String, List<ExtraAction>> optionsFor({
    required List<ImportedStatementLine> lines,
    required PaymentMethod source,
    required String payerMemberId,
    required List<HouseMember> members,
    required List<PaymentMethod> cards,
    required List<CardInvoice> openInvoices,
    required List<ImportBatch> history,
    required List<P2PLoan> loans,
  }) {
    if (source.isCreditCard) return const {};
    final names = {for (final m in members) m.id: m.name.split(' ').first};
    final cardNames = {for (final c in cards) c.id: c.name};
    final options = <String, List<ExtraAction>>{};

    for (final line in lines) {
      final found = <ExtraAction>[];

      if (line.kind == StatementLineKind.payment) {
        for (final invoice in openInvoices) {
          final cardName = cardNames[invoice.paymentMethodId];
          if (cardName == null) continue;
          if (line.date.difference(invoice.dueDate).inDays.abs() > invoiceWindowDays) continue;

          // O banco cobra a fatura inteira; o app só conhece a parte da casa.
          // O total do arquivo importado daquela fatura é o que mais se aproxima.
          final matchesImport = history.any((batch) =>
              !batch.isUndone &&
              batch.paymentMethodId == invoice.paymentMethodId &&
              batch.invoiceDueDate != null &&
              _sameDay(batch.invoiceDueDate!, invoice.dueDate) &&
              batch.total.cents == line.amount.cents);
          found.add(
            ExtraAction(
              type: ExtraActionType.payInvoice,
              key: 'invoice:${invoice.paymentMethodId}:${invoice.dueDate.toIso8601String()}',
              label: 'Pagamento da fatura $cardName de ${_day.format(invoice.dueDate)}',
              suggested: matchesImport || invoice.total.cents == line.amount.cents,
              paymentMethodId: invoice.paymentMethodId,
              invoiceDueDate: invoice.dueDate,
            ),
          );
        }
      }

      if (line.kind == StatementLineKind.income) {
        // Só entrada na conta da casa é aporte; na conta de um morador, não
        if (source.ownerMemberId == null) {
          for (final member in members) {
            found.add(
              ExtraAction(
                type: ExtraActionType.contribution,
                key: 'contribution:${member.id}',
                label: 'Aporte de ${names[member.id]}',
                suggested: _mentions(line.description, member.name),
                memberId: member.id,
              ),
            );
          }
        }

        for (final loan in loans) {
          if (loan.lenderMemberId != payerMemberId) continue;
          if (loan.status != LoanStatus.active) continue;
          if (loan.remainingAmount.cents < line.amount.cents) continue;
          final borrower = members.where((m) => m.id == loan.borrowerMemberId).firstOrNull;
          final exactInstallment =
              loan.openInstallments.any((i) => i.remainingAmount.cents == line.amount.cents);
          found.add(
            ExtraAction(
              type: ExtraActionType.loanPayment,
              key: 'loan:${loan.id}',
              label: 'Abate "${loan.title}"${borrower == null ? '' : ' (${names[borrower.id]})'}',
              suggested: exactInstallment &&
                  (borrower == null || _mentions(line.description, borrower.name) || loans.length == 1),
              loanId: loan.id,
            ),
          );
        }
      }

      if (found.isNotEmpty) options[line.id] = found;
    }
    return options;
  }
}
