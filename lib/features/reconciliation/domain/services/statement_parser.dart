import '../../../../core/domain/value_objects/money.dart';
import '../entities/imported_statement_line.dart';

class StatementParser {
  StatementParser._();

  /// Parser para extratos/faturas em formato CSV simples (data,descrição,valor)
  static List<ImportedStatementLine> parseCsv(String csvContent) {
    final lines = csvContent.split('\n');
    final result = <ImportedStatementLine>[];

    for (int i = 0; i < lines.length; i++) {
      final rawLine = lines[i].trim();
      if (rawLine.isEmpty || rawLine.toLowerCase().startsWith('data') || rawLine.toLowerCase().startsWith('date')) {
        continue;
      }

      final parts = rawLine.split(',');
      if (parts.length >= 3) {
        final dateStr = parts[0].trim();
        final desc = parts[1].trim();
        final amountStr = parts[2].trim();

        DateTime date = DateTime.tryParse(dateStr) ?? DateTime.now();
        final cleanAmount = amountStr.replaceAll(RegExp(r'[^0-9.-]'), '');
        final doubleVal = double.tryParse(cleanAmount) ?? 0.0;
        final cents = (doubleVal.abs() * 100).round();

        result.add(
          ImportedStatementLine(
            id: 'line_${DateTime.now().millisecondsSinceEpoch}_$i',
            date: date,
            description: desc,
            amount: Money(cents),
            destination: _inferDestination(desc),
            assignedMemberId: _inferAssignedMember(desc),
          ),
        );
      }
    }

    return result;
  }

  /// Calcula o fechamento da fatura com divisão matemática por destino (RN09)
  static InvoiceSplitResult calculateSplit(List<ImportedStatementLine> lines) {
    int totalCents = 0;
    int houseCents = 0;
    int personalOwnerCents = 0;
    final p2pMap = <String, int>{};

    for (final line in lines) {
      if (line.destination == LineDestination.ignored) continue;

      totalCents += line.amount.cents;

      switch (line.destination) {
        case LineDestination.house:
          houseCents += line.amount.cents;
          break;
        case LineDestination.cardOwnerPersonal:
          personalOwnerCents += line.amount.cents;
          break;
        case LineDestination.splitP2P:
          final debtor = line.assignedMemberId ?? 'member_marina';
          p2pMap[debtor] = (p2pMap[debtor] ?? 0) + line.amount.cents;
          break;
        case LineDestination.ignored:
          break;
      }
    }

    final p2pMoneyMap = <String, Money>{};
    p2pMap.forEach((member, cents) {
      p2pMoneyMap[member] = Money(cents);
    });

    return InvoiceSplitResult(
      totalAmount: Money(totalCents),
      houseAmount: Money(houseCents),
      personalOwnerAmount: Money(personalOwnerCents),
      p2pDebtsByMember: p2pMoneyMap,
    );
  }

  static LineDestination _inferDestination(String desc) {
    final lower = desc.toLowerCase();
    if (lower.contains('zara') || lower.contains('shein') || lower.contains('farm')) {
      return LineDestination.splitP2P;
    }
    if (lower.contains('steam') || lower.contains('playstation') || lower.contains('uber pessoal')) {
      return LineDestination.cardOwnerPersonal;
    }
    return LineDestination.house;
  }

  static String? _inferAssignedMember(String desc) {
    final lower = desc.toLowerCase();
    if (lower.contains('zara') || lower.contains('shein') || lower.contains('farm')) {
      return 'member_marina';
    }
    return null;
  }
}
