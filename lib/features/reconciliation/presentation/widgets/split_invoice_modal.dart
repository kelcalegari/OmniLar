import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/imported_statement_line.dart';
import '../../domain/services/statement_parser.dart';

class SplitInvoiceModal extends StatefulWidget {
  final String cardName;
  final String ownerName;

  const SplitInvoiceModal({
    super.key,
    this.cardName = 'Nubank Carlos',
    this.ownerName = 'Carlos',
  });

  static Future<void> show(BuildContext context) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 720,
      child: const SplitInvoiceModal(),
    );
  }

  @override
  State<SplitInvoiceModal> createState() => _SplitInvoiceModalState();
}

class _SplitInvoiceModalState extends State<SplitInvoiceModal> {
  late List<ImportedStatementLine> _lines;

  @override
  void initState() {
    super.initState();
    // Exemplo representativo de fatura mista importada (RN09)
    _lines = [
      ImportedStatementLine(
        id: '1',
        date: DateTime.now().subtract(const Duration(days: 2)),
        description: 'Pão de Açúcar Mercado',
        amount: const Money(48560), // R$ 485,60
        destination: LineDestination.house,
      ),
      ImportedStatementLine(
        id: '2',
        date: DateTime.now().subtract(const Duration(days: 4)),
        description: 'Camisa Zara (Marina)',
        amount: const Money(18000), // R$ 180,00
        destination: LineDestination.splitP2P,
        assignedMemberId: 'member_marina',
      ),
      ImportedStatementLine(
        id: '3',
        date: DateTime.now().subtract(const Duration(days: 6)),
        description: 'Farm Rio Vestido (Marina)',
        amount: const Money(32000), // R$ 320,00
        destination: LineDestination.splitP2P,
        assignedMemberId: 'member_marina',
      ),
      ImportedStatementLine(
        id: '4',
        date: DateTime.now().subtract(const Duration(days: 8)),
        description: 'Jogo Steam (Carlos Pessoal)',
        amount: const Money(15000), // R$ 150,00
        destination: LineDestination.cardOwnerPersonal,
      ),
      ImportedStatementLine(
        id: '5',
        date: DateTime.now().subtract(const Duration(days: 10)),
        description: 'Enel Energia Elétrica',
        amount: const Money(21000), // R$ 210,00
        destination: LineDestination.house,
      ),
    ];
  }

  void _confirmSplit() {
    final split = StatementParser.calculateSplit(_lines);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.creditGreen,
        content: Text(
          'Fatura processada! Casa: ${split.houseAmount.format()} | Empréstimo Marina: ${split.p2pDebtsByMember['member_marina']?.format() ?? "R\$ 0,00"} 💳🤝',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final split = StatementParser.calculateSplit(_lines);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.call_split_rounded, color: AppColors.accent, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Rachar a Fatura',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        '${widget.cardName} • Titular: ${widget.ownerName}',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Resumo da Divisão Visual (RN09)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSummaryCol('Total Fatura', split.totalAmount.format(), Colors.grey),
                _buildSummaryCol('Despesa Casa', split.houseAmount.format(), AppColors.primary),
                _buildSummaryCol(
                  'Dívida Marina',
                  split.p2pDebtsByMember['member_marina']?.format() ?? 'R\$ 0,00',
                  AppColors.debtRed,
                ),
                _buildSummaryCol('Pessoal ${widget.ownerName}', split.personalOwnerAmount.format(), Colors.blueGrey),
              ],
            ),
          ),
          const SizedBox(height: 16),

          Text(
            'Distribuição dos Lançamentos da Fatura',
            style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),

          // Lista de Transações da Fatura
          Container(
            constraints: const BoxConstraints(maxHeight: 260),
            decoration: BoxDecoration(
              border: Border.all(color: theme.dividerColor),
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: _lines.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, idx) {
                final line = _lines[idx];

                return ListTile(
                  dense: true,
                  title: Text(line.description, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text(
                    '${line.date.day.toString().padLeft(2, '0')}/${line.date.month.toString().padLeft(2, '0')}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        line.amount.format(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(width: 8),
                      DropdownButton<LineDestination>(
                        value: line.destination,
                        underline: const SizedBox.shrink(),
                        icon: const Icon(Icons.arrow_drop_down, size: 18),
                        onChanged: (newDest) {
                          if (newDest != null) {
                            setState(() {
                              _lines[idx] = line.copyWith(
                                destination: newDest,
                                assignedMemberId: newDest == LineDestination.splitP2P ? 'member_marina' : null,
                              );
                            });
                          }
                        },
                        items: const [
                          DropdownMenuItem(
                            value: LineDestination.house,
                            child: Text('Casa', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          DropdownMenuItem(
                            value: LineDestination.splitP2P,
                            child: Text('Marina (P2P)', style: TextStyle(color: AppColors.debtRed, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          DropdownMenuItem(
                            value: LineDestination.cardOwnerPersonal,
                            child: Text('Pessoal Carlos', style: TextStyle(color: Colors.blueGrey, fontSize: 12)),
                          ),
                          DropdownMenuItem(
                            value: LineDestination.ignored,
                            child: Text('Ignorar', style: TextStyle(color: Colors.grey, fontSize: 12)),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Ao confirmar: Linhas da Casa viram Despesa da Casa com rateio; Linhas da Marina viram Empréstimo P2P onde Carlos é o credor.',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey),
          ),
          const SizedBox(height: 20),

          SizedBox(
            height: 48,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Confirmar Divisão da Fatura', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _confirmSplit,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCol(String label, String value, Color color) {
    return Column(
      children: [
        Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w500)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: color)),
      ],
    );
  }
}
