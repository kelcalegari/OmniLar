import '../../../../core/domain/value_objects/money.dart';

enum LineDestination {
  house, // Vira Gasto da Casa
  splitP2P, // Vira Empréstimo P2P (outro membro deve para o dono do cartão)
  cardOwnerPersonal, // Gasto pessoal do dono (não afeta as contas da casa nem gera dívida)
  ignored, // Ignorado / duplicado
}

/// De onde veio o arquivo: muda a leitura do sinal dos valores.
enum StatementSourceType { creditCard, bankAccount }

/// O que a linha representa no arquivo. Só [purchase] vira lançamento.
enum StatementLineKind {
  purchase, // Compra no cartão ou saída da conta
  refund, // Estorno ou crédito na fatura
  payment, // Pagamento da fatura (na fatura ou no extrato da conta)
  income, // Entrada na conta
}

class ImportedStatementLine {
  final String id;
  final DateTime date;
  final String description;

  /// Sempre positivo: o sentido da linha está em [kind].
  final Money amount;
  final LineDestination destination;
  final StatementLineKind kind;

  /// Identificador da transação no arquivo (FITID do OFX), quando existe.
  final String? externalId;

  /// Identifica a linha entre importações do mesmo cartão ou conta: data,
  /// valor e descrição do arquivo, mais a ordem entre linhas iguais.
  final String? signature;

  /// Nome dado pelo usuário na revisão (null = usa a descrição limpa).
  final String? title;
  final String? categoryId;
  final String? assignedMemberId; // Devedor no caso de splitP2P
  final int? installmentNumber;
  final int? installmentsTotal;
  final bool isDuplicate;

  const ImportedStatementLine({
    required this.id,
    required this.date,
    required this.description,
    required this.amount,
    this.destination = LineDestination.house,
    this.kind = StatementLineKind.purchase,
    this.externalId,
    this.signature,
    this.title,
    this.categoryId,
    this.assignedMemberId,
    this.installmentNumber,
    this.installmentsTotal,
    this.isDuplicate = false,
  });

  bool get isPurchase => kind == StatementLineKind.purchase;
  bool get isInstallment => installmentNumber != null && installmentsTotal != null;

  ImportedStatementLine copyWith({
    DateTime? date,
    LineDestination? destination,
    String? title,
    String? categoryId,
    String? assignedMemberId,
    bool clearAssignedMember = false,
    bool? isDuplicate,
  }) {
    return ImportedStatementLine(
      id: id,
      date: date ?? this.date,
      description: description,
      amount: amount,
      destination: destination ?? this.destination,
      kind: kind,
      externalId: externalId,
      signature: signature,
      title: title ?? this.title,
      categoryId: categoryId ?? this.categoryId,
      assignedMemberId: clearAssignedMember ? null : (assignedMemberId ?? this.assignedMemberId),
      installmentNumber: installmentNumber,
      installmentsTotal: installmentsTotal,
      isDuplicate: isDuplicate ?? this.isDuplicate,
    );
  }
}

class InvoiceSplitResult {
  final Money totalAmount;
  final Money houseAmount;
  final Money personalOwnerAmount;
  final Map<String, Money> p2pDebtsByMember; // membroDevedor -> valor que deve ao dono do cartão

  const InvoiceSplitResult({
    required this.totalAmount,
    required this.houseAmount,
    required this.personalOwnerAmount,
    required this.p2pDebtsByMember,
  });

  Money get p2pAmount =>
      p2pDebtsByMember.values.fold(const Money.zero(), (total, m) => total + m);
}
