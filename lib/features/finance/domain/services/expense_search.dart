import '../../../reconciliation/domain/services/statement_text.dart';
import '../entities/house_expense.dart';

/// Busca nos lançamentos do ciclo: cada palavra digitada precisa aparecer no
/// título, na categoria, em quem pagou, na forma de pagamento, nos itens, na
/// observação ou no valor. Ignora maiúsculas, acentos e pontuação, então
/// "312,40" acha R$ 312,40.
bool expenseMatchesSearch(
  HouseExpense expense,
  String query, {
  String? categoryName,
  String? payerName,
  String? paymentMethodName,
}) {
  final words = StatementText.normalize(query).split(' ').where((w) => w.isNotEmpty);
  if (words.isEmpty) return true;

  final text = StatementText.normalize([
    expense.title,
    expense.description ?? '',
    categoryName ?? '',
    payerName ?? '',
    paymentMethodName ?? '',
    expense.notes ?? '',
    for (final item in expense.items) item.title,
    expense.amount.format(includeSymbol: false),
  ].join(' '));
  return words.every(text.contains);
}
