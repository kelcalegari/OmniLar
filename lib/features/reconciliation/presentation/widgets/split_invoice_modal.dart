import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';
import '../../../p2p/domain/entities/p2p_loan.dart';
import '../../domain/entities/imported_statement_line.dart';
import '../../domain/services/statement_parser.dart';

class SplitInvoiceModal extends StatefulWidget {
  final String? cardName;
  final String? ownerName;

  const SplitInvoiceModal({
    super.key,
    this.cardName,
    this.ownerName,
  });

  static Future<void> show(BuildContext context, {String? cardName, String? ownerName}) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 720,
      child: SplitInvoiceModal(cardName: cardName, ownerName: ownerName),
    );
  }

  @override
  State<SplitInvoiceModal> createState() => _SplitInvoiceModalState();
}

class _SplitInvoiceModalState extends State<SplitInvoiceModal> {
  bool _initialized = false;
  late String _ownerName;
  late String _cardName;
  late String _partnerName;
  late String _partnerId;
  late List<ImportedStatementLine> _lines;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _initialized = true;
      final authRepo = sl<AuthRepository>();
      final isDemo = authRepo.isDemoMode;
      final currentUser = authRepo.currentUser;

      List<HouseMember> members = [];
      try {
        members = context.read<FinanceCubit>().state.members;
      } catch (_) {}

      final otherMember = members.where((m) => m.id != currentUser?.id).firstOrNull;

      _ownerName = widget.ownerName ??
          (isDemo
              ? 'Carlos'
              : (currentUser?.fullName.isNotEmpty == true ? currentUser!.fullName.split(' ').first : 'Você'));
      _cardName = widget.cardName ?? (isDemo ? 'Nubank Carlos' : 'Cartão Principal');
      _partnerName = isDemo ? 'Marina' : (otherMember != null ? otherMember.name.split(' ').first : 'Parceiro(a)');
      _partnerId = isDemo ? 'member_marina' : (otherMember?.id ?? '');

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
          description: 'Camisa Zara ($_partnerName)',
          amount: const Money(18000), // R$ 180,00
          destination: LineDestination.splitP2P,
          assignedMemberId: _partnerId,
        ),
        ImportedStatementLine(
          id: '3',
          date: DateTime.now().subtract(const Duration(days: 6)),
          description: 'Farm Rio Vestido ($_partnerName)',
          amount: const Money(32000), // R$ 320,00
          destination: LineDestination.splitP2P,
          assignedMemberId: _partnerId,
        ),
        ImportedStatementLine(
          id: '4',
          date: DateTime.now().subtract(const Duration(days: 8)),
          description: 'Jogo Steam ($_ownerName Pessoal)',
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
  }

  Future<void> _pickAndImportFile() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ofx', 'csv', 'txt'],
      );

      if (files.isNotEmpty) {
        final file = files.first;
        final bytes = await file.readAsBytes();

        if (bytes.isNotEmpty) {
          final content = utf8.decode(bytes, allowMalformed: true);
          final parsedLines = StatementParser.parseFile(content, filename: file.name);
          if (parsedLines.isNotEmpty) {
            setState(() {
              _lines = parsedLines;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  backgroundColor: AppColors.primary,
                  content: Text('Arquivo "${file.name}" importado com sucesso! (${parsedLines.length} lançamentos encontrados)'),
                ),
              );
            }
            return;
          }
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: AppColors.debtRed,
              content: Text('Nenhum lançamento válido encontrado no arquivo selecionado.'),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.debtRed,
            content: Text('Erro ao importar arquivo: $e'),
          ),
        );
      }
    }
  }

  void _confirmSplit() {
    final split = StatementParser.calculateSplit(_lines);
    final financeCubit = context.read<FinanceCubit>();
    final p2pCubit = context.read<P2PCubit>();
    final financeState = financeCubit.state;
    final now = DateTime.now();

    final currentUserId = sl<AuthRepository>().currentUser?.id;
    final paidByMemberId = currentUserId ?? (financeState.members.isNotEmpty ? financeState.members.first.id : 'member_carlos');
    final paymentMethodId = financeState.paymentMethods.isNotEmpty ? financeState.paymentMethods.first.id : 'pm_caixa';

    final splitPercentages = {
      for (final m in financeState.members) m.id: m.defaultSplitPercent,
    };
    final splitRule = splitPercentages.isNotEmpty
        ? SplitRule.percentage(splitPercentages)
        : const SplitRule.percentage(null);

    // 1. Gravar despesa da Casa (soma de todas as linhas com destination = house)
    if (!split.houseAmount.isZero) {
      final houseExpense = HouseExpense(
        id: 'exp_split_${now.millisecondsSinceEpoch}',
        title: 'Fatura $_cardName — Despesa Casa',
        amount: split.houseAmount,
        date: now,
        categoryId: 'cat_contas',
        paidByMemberId: paidByMemberId,
        paymentMethodId: paymentMethodId,
        splitRule: splitRule,
        status: ExpenseStatus.paid,
        notes: 'Divisão de fatura $_cardName',
      );
      financeCubit.addExpense(houseExpense);
    }

    // 2. Gravar empréstimo P2P para cada membro com dívida (destination = splitP2P)
    split.p2pDebtsByMember.forEach((memberId, debtAmount) {
      if (!debtAmount.isZero) {
        final loan = P2PLoan(
          id: 'loan_split_${now.millisecondsSinceEpoch}_$memberId',
          title: 'Fatura $_cardName — $_partnerName',
          description: 'Divisão de fatura: itens pessoais de $_partnerName na fatura $_cardName',
          totalAmount: debtAmount,
          lenderMemberId: paidByMemberId,
          borrowerMemberId: memberId,
          installmentsCount: 1,
          createdAt: now,
          firstDueDate: now.add(const Duration(days: 30)),
        );
        p2pCubit.createLoan(loan);
      }
    });

    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.creditGreen,
        content: Text(
          'Fatura processada! Casa: ${split.houseAmount.format()} | Empréstimo $_partnerName: ${split.p2pDebtsByMember[_partnerId]?.format() ?? "R\$ 0,00"} 💳🤝',
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
                        '$_cardName • Titular: $_ownerName',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.upload_file_rounded, size: 16),
                    label: const Text('Importar OFX/CSV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _pickAndImportFile,
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
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
                  'Dívida $_partnerName',
                  split.p2pDebtsByMember[_partnerId]?.format() ?? 'R\$ 0,00',
                  AppColors.debtRed,
                ),
                _buildSummaryCol('Pessoal $_ownerName', split.personalOwnerAmount.format(), Colors.blueGrey),
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
                                assignedMemberId: newDest == LineDestination.splitP2P ? _partnerId : null,
                              );
                            });
                          }
                        },
                        items: [
                          const DropdownMenuItem(
                            value: LineDestination.house,
                            child: Text('Casa', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          DropdownMenuItem(
                            value: LineDestination.splitP2P,
                            child: Text('$_partnerName (P2P)', style: const TextStyle(color: AppColors.debtRed, fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                          DropdownMenuItem(
                            value: LineDestination.cardOwnerPersonal,
                            child: Text('Pessoal $_ownerName', style: const TextStyle(color: Colors.blueGrey, fontSize: 12)),
                          ),
                          const DropdownMenuItem(
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
            'Ao confirmar: Linhas da Casa viram Despesa da Casa com rateio; Linhas de $_partnerName viram Empréstimo P2P onde $_ownerName é o credor.',
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
