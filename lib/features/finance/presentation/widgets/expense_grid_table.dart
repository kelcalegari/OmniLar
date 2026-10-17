import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/payment_method.dart';

/// Coluna pela qual a grade está ordenada.
enum ExpenseGridColumn { date, title, category, payer, method, amount, status }

/// Lançamentos do ciclo em tabela, para telas largas: uma linha por despesa
/// (as compras de cartão aparecem soltas, com a forma de pagamento), com
/// ordenação ao tocar no título da coluna. Tocar na linha seleciona a despesa.
class ExpenseGridTable extends StatefulWidget {
  final List<HouseExpense> expenses;
  final List<ExpenseCategory> categories;
  final List<HouseMember> members;
  final List<PaymentMethod> paymentMethods;
  final String? selectedExpenseId;
  final ValueChanged<String> onSelect;

  const ExpenseGridTable({
    super.key,
    required this.expenses,
    required this.categories,
    required this.members,
    required this.paymentMethods,
    required this.selectedExpenseId,
    required this.onSelect,
  });

  @override
  State<ExpenseGridTable> createState() => _ExpenseGridTableState();
}

class _ExpenseGridTableState extends State<ExpenseGridTable> {
  ExpenseGridColumn _sortBy = ExpenseGridColumn.date;
  bool _ascending = false;

  static final _dateFormat = DateFormat('dd/MM/yy');

  String _category(HouseExpense e) =>
      widget.categories.where((c) => c.id == e.categoryId).firstOrNull?.name ?? '—';

  String _payer(HouseExpense e) =>
      widget.members.where((m) => m.id == e.paidByMemberId).firstOrNull?.name.split(' ').first ?? '—';

  String _method(HouseExpense e) =>
      widget.paymentMethods.where((m) => m.id == e.paymentMethodId).firstOrNull?.name ?? '—';

  String _status(HouseExpense e) => e.isPaid ? 'Paga' : 'A pagar';

  int _compare(HouseExpense a, HouseExpense b) => switch (_sortBy) {
        ExpenseGridColumn.date => a.date.compareTo(b.date),
        ExpenseGridColumn.title => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        ExpenseGridColumn.category => _category(a).toLowerCase().compareTo(_category(b).toLowerCase()),
        ExpenseGridColumn.payer => _payer(a).toLowerCase().compareTo(_payer(b).toLowerCase()),
        ExpenseGridColumn.method => _method(a).toLowerCase().compareTo(_method(b).toLowerCase()),
        ExpenseGridColumn.amount => a.amount.cents.compareTo(b.amount.cents),
        ExpenseGridColumn.status => _status(a).compareTo(_status(b)),
      };

  void _sort(ExpenseGridColumn column, bool ascending) => setState(() {
        _sortBy = column;
        _ascending = ascending;
      });

  DataColumn _column(String label, ExpenseGridColumn column, {bool numeric = false}) => DataColumn(
        label: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        numeric: numeric,
        onSort: (_, ascending) => _sort(column, ascending),
      );

  @override
  Widget build(BuildContext context) {
    final rows = [...widget.expenses]..sort((a, b) => _ascending ? _compare(a, b) : _compare(b, a));
    final columns = ExpenseGridColumn.values;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        key: const Key('expense_grid'),
        sortColumnIndex: columns.indexOf(_sortBy),
        sortAscending: _ascending,
        showCheckboxColumn: false,
        columnSpacing: 20,
        headingRowHeight: 40,
        dataRowMinHeight: 40,
        dataRowMaxHeight: 48,
        columns: [
          _column('Data', ExpenseGridColumn.date),
          _column('Descrição', ExpenseGridColumn.title),
          _column('Categoria', ExpenseGridColumn.category),
          _column('Pagou', ExpenseGridColumn.payer),
          _column('Forma', ExpenseGridColumn.method),
          _column('Valor', ExpenseGridColumn.amount, numeric: true),
          _column('Situação', ExpenseGridColumn.status),
        ],
        rows: [
          for (final e in rows)
            DataRow(
              selected: e.id == widget.selectedExpenseId,
              onSelectChanged: (_) => widget.onSelect(e.id),
              cells: [
                DataCell(Text(_dateFormat.format(e.date))),
                DataCell(
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 220),
                    child: Text(e.title, overflow: TextOverflow.ellipsis),
                  ),
                ),
                DataCell(Text(_category(e))),
                DataCell(Text(_payer(e))),
                DataCell(Text(_method(e))),
                DataCell(Text(e.amount.formatted, style: const TextStyle(fontWeight: FontWeight.w600))),
                DataCell(
                  Text(
                    _status(e),
                    style: TextStyle(
                      color: e.isPaid ? AppColors.creditGreen : Colors.orange,
                      fontWeight: FontWeight.w600,
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
