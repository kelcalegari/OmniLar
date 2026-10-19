import 'package:flutter/material.dart';
import '../../../finance/domain/entities/house_permissions.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../../core/di/service_locator.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../finance/domain/entities/house_member.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/entities/p2p_installment.dart';
import '../../domain/services/p2p_calculator.dart';
import '../cubit/p2p_cubit.dart';

class CreateLoanPage extends StatefulWidget {
  const CreateLoanPage({super.key});

  @override
  State<CreateLoanPage> createState() => _CreateLoanPageState();
}

class _CreateLoanPageState extends State<CreateLoanPage> {
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  int _cents = 0;
  int _installmentsCount = 1;
  DateTime _firstDueDate = DateTime.now().add(const Duration(days: 30));
  late String _borrowerId;
  late String _lenderId;

  bool _initializedParties = false;

  // Controle de empréstimo antigo / pregressos
  bool _isHistorical = false;
  bool _settleInCycle = true;
  int _paidInstallmentsCount = 0;

  // Lista editável de parcelas
  List<P2PInstallment> _installments = [];

  // Modalidade: parcelado (padrão) ou livre / sem prazo
  LoanRepaymentMode _repaymentMode = LoanRepaymentMode.installments;
  bool _openEndedHasPriorPayments = false;
  int _openEndedPaidCents = 0;

  bool get _isOpenEnded => _repaymentMode == LoanRepaymentMode.openEnded;

  // Empréstimo do Caixa da Casa: de onde sai o dinheiro (0086)
  HouseLoanFunding _houseFunding = HouseLoanFunding.cycle;
  String? _fundingVaultId;

  bool get _fromHouse => _lenderId == P2PLoan.houseLenderId;

  /// Empresta dinheiro da Casa quem tem a permissão (administradores sempre).
  bool _canLendFromHouse(FinanceState state) {
    final auth = sl<AuthRepository>();
    final me = auth.isDemoMode ? 'member_carlos' : auth.currentUser?.id;
    return state.canDo(HousePermissionAction.houseLoans, me);
  }

  /// Quanto o Caixa do ciclo ou a Caixinha escolhida tem para emprestar.
  Money? _fundingAvailable(FinanceState state) {
    if (_houseFunding == HouseLoanFunding.cycle) return state.summary?.folego;
    return state.savingsVaults.where((v) => v.id == _fundingVaultId).firstOrNull?.currentBalance;
  }

  /// Confere a origem do dinheiro antes de gravar. Mensagem de erro ou null.
  String? _fundingError() {
    if (!_fromHouse) return null;
    final state = context.read<FinanceCubit>().state;
    if (_houseFunding == HouseLoanFunding.vault && _fundingVaultId == null) {
      return 'Escolha de qual caixinha sai o dinheiro.';
    }
    final available = _fundingAvailable(state);
    if (available != null && available.cents < _cents) {
      return _houseFunding == HouseLoanFunding.cycle
          ? 'O Caixa do ciclo tem só ${available.format()} livres. Use uma caixinha ou um valor menor.'
          : 'A caixinha tem só ${available.format()}.';
    }
    return null;
  }

  /// Marca de onde o dinheiro do Caixa saiu (e para onde os pagamentos voltam).
  P2PLoan _withFunding(P2PLoan loan) {
    if (!_fromHouse) return loan;
    final now = DateTime.now();
    return loan.copyWith(
      houseFunding: _houseFunding,
      fundedOn: DateTime(now.year, now.month, now.day),
      repayToVaultId: _houseFunding == HouseLoanFunding.vault ? _fundingVaultId : null,
    );
  }

  @override
  void initState() {
    super.initState();
    final authRepo = sl<AuthRepository>();
    final isDemo = authRepo.isDemoMode;
    final currentUserId = authRepo.currentUser?.id;

    if (!isDemo && currentUserId != null) {
      _lenderId = currentUserId;
      _borrowerId = '';
    } else {
      _lenderId = 'member_carlos';
      _borrowerId = 'member_marina';
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initializedParties) {
      final authRepo = sl<AuthRepository>();
      final isDemo = authRepo.isDemoMode;
      final currentUserId = authRepo.currentUser?.id;

      if (!isDemo && currentUserId != null) {
        _lenderId = currentUserId;
        try {
          final members = context.read<FinanceCubit>().state.members;
          final otherMember = members.where((m) => m.id != currentUserId).firstOrNull;
          if (otherMember != null) {
            _borrowerId = otherMember.id;
          }
        } catch (_) {}
      }
      _initializedParties = true;
    }
  }

  void _swapParties() {
    if (_lenderId.isEmpty && _borrowerId.isEmpty) return;
    if (_fromHouse) return; // O Caixa não toma empréstimo
    setState(() {
      final temp = _lenderId;
      _lenderId = _borrowerId;
      _borrowerId = temp;
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  void _regenerateInstallments() {
    if (_cents <= 0) {
      setState(() {
        _installments = [];
      });
      return;
    }

    final newInstallments = P2PCalculator.generateInstallments(
      loanId: 'temp_loan',
      totalAmount: Money(_cents),
      installmentsCount: _installmentsCount,
      firstDueDate: _firstDueDate,
      paidInstallmentsCount: _isHistorical ? _paidInstallmentsCount : 0,
    );

    setState(() {
      _installments = newInstallments;
    });
  }

  Future<void> _pickFirstDueDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _firstDueDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Data do 1º Vencimento',
    );
    if (picked != null) {
      setState(() {
        _firstDueDate = picked;
      });
      _regenerateInstallments();
    }
  }

  Future<void> _pickInstallmentDueDate(int index) async {
    final current = _installments[index].dueDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Vencimento da Parcela ${_installments[index].number}',
    );
    if (picked != null) {
      setState(() {
        _installments[index] = _installments[index].copyWith(dueDate: picked);
      });
    }
  }

  Future<void> _editInstallmentAmount(int index) async {
    final current = _installments[index];
    int tempCents = current.amount.cents;

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Valor da Parcela ${current.number}/${current.totalCount}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MoneyInputField(
              label: 'Novo Valor Nominal',
              initialValue: Money(tempCents),
              primaryColor: AppColors.accent,
              onChanged: (money) {
                tempCents = money.cents;
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (tempCents > 0) {
                setState(() {
                  final isPaid = _installments[index].isFullyPaid;
                  _installments[index] = _installments[index].copyWith(
                    amount: Money(tempCents),
                    paidAmount: isPaid ? Money(tempCents) : _installments[index].paidAmount,
                  );
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
  }

  void _toggleInstallmentPaidStatus(int index) {
    final current = _installments[index];
    final currentlyPaid = current.isFullyPaid;
    setState(() {
      if (currentlyPaid) {
        _installments[index] = current.copyWith(
          paidAmount: const Money.zero(),
          paidAt: null,
        );
      } else {
        _installments[index] = current.copyWith(
          paidAmount: current.amount,
          paidAt: current.dueDate,
        );
      }
      _paidInstallmentsCount = _installments.where((i) => i.isFullyPaid).length;
    });
  }

  void _balanceInstallments() {
    setState(() {
      _installments = P2PCalculator.balanceLastInstallment(
        installments: _installments,
        totalAmount: Money(_cents),
      );
    });
  }

  void _submit() {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, informe a descrição do empréstimo')),
      );
      return;
    }

    if (_cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O valor deve ser maior que zero')),
      );
      return;
    }

    if (_lenderId.isEmpty || _borrowerId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Selecione quem emprestou e quem tomou o empréstimo')),
      );
      return;
    }

    if (_lenderId == _borrowerId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('O credor (quem emprestou) e o devedor (quem tomou) não podem ser a mesma pessoa.'),
          backgroundColor: AppColors.debtRed,
        ),
      );
      return;
    }

    final fundingError = _fundingError();
    if (fundingError != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(fundingError), backgroundColor: AppColors.debtRed),
      );
      return;
    }

    if (_isOpenEnded) {
      _submitOpenEnded();
      return;
    }

    if (_installments.isEmpty) {
      _regenerateInstallments();
    }

    final totalAmount = Money(_cents);
    final installmentsSum = P2PCalculator.sumInstallments(_installments);

    if (installmentsSum.cents != totalAmount.cents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'A soma das parcelas (${installmentsSum.format()}) difere do total (${totalAmount.format()}). Clique em "Equilibrar" para ajustar.',
          ),
          action: SnackBarAction(
            label: 'Equilibrar',
            onPressed: _balanceInstallments,
          ),
        ),
      );
      return;
    }

    final loanId = 'loan_${DateTime.now().millisecondsSinceEpoch}';
    final allPaid = _installments.every((i) => i.isFullyPaid);

    final finalInstallments = [
      for (int i = 0; i < _installments.length; i++)
        P2PInstallment(
          id: '${loanId}_inst_${i + 1}',
          loanId: loanId,
          number: i + 1,
          totalCount: _installments.length,
          amount: _installments[i].amount,
          paidAmount: _installments[i].paidAmount,
          dueDate: _installments[i].dueDate,
          paidAt: _installments[i].paidAt,
        ),
    ];

    final loan = P2PLoan(
      id: loanId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
      totalAmount: totalAmount,
      lenderMemberId: _lenderId,
      borrowerMemberId: _borrowerId,
      installmentsCount: finalInstallments.length,
      createdAt: _isHistorical ? _firstDueDate : DateTime.now(),
      firstDueDate: _firstDueDate,
      status: allPaid ? LoanStatus.paid : LoanStatus.active,
      installments: finalInstallments,
      settleInCycle: _settleInCycle,
    );

    _saveLoan(_withFunding(loan), 'Empréstimo registrado com sucesso! 🎉');
  }

  /// Aguarda a gravação e só então fecha a tela e confirma ao usuário.
  Future<void> _saveLoan(P2PLoan loan, String successMessage) async {
    final cubit = context.read<P2PCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    final ok = await cubit.createLoan(loan);
    if (ok) {
      if (mounted) navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(cubit.state.errorMessage ?? 'Não foi possível registrar o empréstimo.'),
          backgroundColor: AppColors.debtRed,
        ),
      );
    }
  }

  /// Cria um empréstimo livre (sem prazo): uma única parcela de "saldo aberto"
  /// que o devedor vai abatendo com o valor que puder, sem vencimento.
  void _submitOpenEnded() {
    final totalAmount = Money(_cents);
    final paidCents = _openEndedHasPriorPayments ? _openEndedPaidCents : 0;

    if (paidCents > totalAmount.cents) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'O valor já abatido (${Money(paidCents).format()}) não pode ser maior que o total (${totalAmount.format()}).',
          ),
          backgroundColor: AppColors.debtRed,
        ),
      );
      return;
    }

    final loanId = 'loan_${DateTime.now().millisecondsSinceEpoch}';
    final installments = P2PCalculator.buildOpenEndedInstallment(
      loanId: loanId,
      totalAmount: totalAmount,
      alreadyPaid: Money(paidCents),
    );
    final isFullyPaid = paidCents == totalAmount.cents;

    final loan = P2PLoan(
      id: loanId,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isNotEmpty ? _descriptionController.text.trim() : null,
      totalAmount: totalAmount,
      lenderMemberId: _lenderId,
      borrowerMemberId: _borrowerId,
      installmentsCount: 1,
      createdAt: DateTime.now(),
      firstDueDate: P2PLoan.openEndedPlaceholderDueDate,
      status: isFullyPaid ? LoanStatus.paid : LoanStatus.active,
      installments: installments,
      repaymentMode: LoanRepaymentMode.openEnded,
    );

    _saveLoan(_withFunding(loan), 'Empréstimo sem prazo registrado! O devedor pode abater quando puder.');
  }

  /// De onde sai o dinheiro do Caixa da Casa: do ciclo em andamento ou de uma caixinha.
  Widget _buildHouseFunding(ThemeData theme) {
    return BlocBuilder<FinanceCubit, FinanceState>(
      builder: (context, state) {
        final vaults = state.savingsVaults;
        final available = _fundingAvailable(state);
        final short = available != null && _cents > 0 && available.cents < _cents;
        return Column(
          key: const Key('loan_house_funding'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('De onde sai o dinheiro?', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: SegmentedButton<HouseLoanFunding>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: HouseLoanFunding.cycle,
                    icon: Icon(Icons.account_balance_wallet_outlined),
                    label: Text('Caixa do ciclo'),
                  ),
                  ButtonSegment(
                    value: HouseLoanFunding.vault,
                    icon: Icon(Icons.savings_outlined),
                    label: Text('Caixinha'),
                  ),
                ],
                selected: {_houseFunding},
                onSelectionChanged: (selection) => setState(() {
                  _houseFunding = selection.first;
                  if (_houseFunding == HouseLoanFunding.vault && _fundingVaultId == null && vaults.isNotEmpty) {
                    _fundingVaultId = vaults.first.id;
                  }
                }),
              ),
            ),
            if (_houseFunding == HouseLoanFunding.vault) ...[
              const SizedBox(height: 12),
              if (vaults.isEmpty)
                const Text('A casa ainda não tem caixinha.', style: TextStyle(fontSize: 12, color: AppColors.debtRed))
              else
                DropdownButtonFormField<String>(
                  key: const Key('loan_funding_vault'),
                  initialValue: vaults.any((v) => v.id == _fundingVaultId) ? _fundingVaultId : null,
                  decoration: const InputDecoration(labelText: 'Caixinha', border: OutlineInputBorder()),
                  items: [
                    for (final vault in vaults)
                      DropdownMenuItem(
                        value: vault.id,
                        child: Text('${vault.name} • ${vault.currentBalance.format()}'),
                      ),
                  ],
                  onChanged: (id) => setState(() => _fundingVaultId = id),
                ),
            ],
            const SizedBox(height: 8),
            Text(
              _houseFunding == HouseLoanFunding.cycle
                  ? 'Sai da sobra deste ciclo${available != null ? ' (livre agora: ${available.format()})' : ''}. '
                      'O que for pago volta ao Caixa nos fechamentos.'
                  : 'Sai da caixinha agora, e cada pagamento volta para ela.',
              style: TextStyle(fontSize: 12, color: short ? AppColors.debtRed : Colors.grey.shade600),
            ),
          ],
        );
      },
    );
  }

  Widget _buildRepaymentModeSelector(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Forma de pagamento', style: theme.textTheme.titleSmall),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<LoanRepaymentMode>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(
                value: LoanRepaymentMode.installments,
                icon: Icon(Icons.calendar_month_rounded),
                label: Text('Parcelado'),
              ),
              ButtonSegment(
                value: LoanRepaymentMode.openEnded,
                icon: Icon(Icons.all_inclusive_rounded),
                label: Text('Sem prazo'),
              ),
            ],
            selected: {_repaymentMode},
            onSelectionChanged: (selection) {
              setState(() {
                _repaymentMode = selection.first;
              });
              if (!_isOpenEnded) _regenerateInstallments();
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOpenEndedSection(ThemeData theme) {
    final totalCents = _cents;
    final paidCents = _openEndedHasPriorPayments ? _openEndedPaidCents : 0;
    final openCents = totalCents > paidCents ? totalCents - paidCents : 0;
    final exceedsTotal = paidCents > totalCents && totalCents > 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Explicação da modalidade
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline_rounded, size: 20, color: AppColors.primary),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sem parcelas e sem vencimento: o devedor abate o valor que puder, quando puder. '
                  'Este empréstimo não entra no Fechamento do Ciclo e nunca fica "vencido".',
                  style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Abatimentos anteriores ao Omni Lar (não há no dinheiro que sai agora do Caixa)
        if (!_fromHouse)
        Material(
          color: _openEndedHasPriorPayments
              ? AppColors.accent.withValues(alpha: 0.08)
              : (theme.brightness == Brightness.dark ? AppColors.surfaceDark : Colors.grey.shade50),
          shape: RoundedRectangleBorder(
            side: BorderSide(
              color: _openEndedHasPriorPayments ? AppColors.accent : theme.dividerColor,
              width: _openEndedHasPriorPayments ? 1.5 : 1,
            ),
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SwitchListTile(
                title: const Text(
                  'Já houve abatimentos?',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text(
                  'Registrar o que o devedor já pagou antes de usar o Omni Lar',
                  style: TextStyle(fontSize: 12),
                ),
                secondary: Icon(
                  Icons.history_rounded,
                  color: _openEndedHasPriorPayments ? AppColors.accent : Colors.grey,
                ),
                value: _openEndedHasPriorPayments,
                onChanged: (val) {
                  setState(() {
                    _openEndedHasPriorPayments = val;
                    if (!val) _openEndedPaidCents = 0;
                  });
                },
              ),
              if (_openEndedHasPriorPayments)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: MoneyInputField(
                    label: 'Valor já abatido',
                    initialValue: Money(_openEndedPaidCents),
                    primaryColor: AppColors.creditGreen,
                    onChanged: (money) {
                      setState(() {
                        _openEndedPaidCents = money.cents;
                      });
                    },
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Resumo
        if (totalCents > 0)
          Card(
            elevation: 0,
            color: theme.brightness == Brightness.dark ? AppColors.surfaceDark : Colors.grey.shade100,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Text('Total', style: theme.textTheme.bodySmall),
                      Text(Money(totalCents).format(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    ],
                  ),
                  Container(height: 28, width: 1, color: theme.dividerColor),
                  Column(
                    children: [
                      Text('Já abatido', style: theme.textTheme.bodySmall),
                      Text(
                        Money(paidCents).format(),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: exceedsTotal ? AppColors.debtRed : AppColors.creditGreen,
                        ),
                      ),
                    ],
                  ),
                  Container(height: 28, width: 1, color: theme.dividerColor),
                  Column(
                    children: [
                      Text('Saldo devedor', style: theme.textTheme.bodySmall),
                      Text(
                        Money(openCents).format(),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.accent),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (exceedsTotal)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'O valor já abatido não pode ser maior que o total do empréstimo.',
              style: TextStyle(fontSize: 12, color: AppColors.debtRed, fontWeight: FontWeight.w600),
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('dd/MM/yyyy');

    // Cálculos de resumo
    final totalMoney = Money(_cents);
    final currentSum = P2PCalculator.sumInstallments(_installments);
    final hasSumMismatch = _cents > 0 && _installments.isNotEmpty && currentSum.cents != _cents;

    int paidCents = 0;
    int paidCount = 0;
    for (final inst in _installments) {
      if (inst.isFullyPaid) {
        paidCents += inst.amount.cents;
        paidCount++;
      }
    }
    final openCount = _installments.length - paidCount;
    final openCents = _cents > paidCents ? _cents - paidCents : 0;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Novo Empréstimo P2P', style: TextStyle(fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Campo Contínuo de Valor Total
          MoneyInputField(
            label: 'Valor Total do Empréstimo',
            initialValue: Money(_cents),
            primaryColor: AppColors.accent,
            quickAddCents: const [5000, 10000, 20000, 50000],
            onChanged: (money) {
              setState(() {
                _cents = money.cents;
              });
              _regenerateInstallments();
            },
          ),
          const SizedBox(height: 20),

          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Título do Empréstimo',
              hintText: 'Ex: Celular Novo, Camisa Zara, Conserto do Carro',
              prefixIcon: const Icon(Icons.title_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: 'Descrição / Observações (Opcional)',
              hintText: 'Ex: Compra parcelada no cartão Smiles',
              prefixIcon: const Icon(Icons.notes_rounded),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          const SizedBox(height: 20),

          BlocBuilder<FinanceCubit, FinanceState>(
            builder: (context, finState) {
              final isDemo = sl<AuthRepository>().isDemoMode;
              final members = finState.members;
              final displayMembers = (!isDemo && members.isNotEmpty)
                  ? members
                  : (!isDemo && sl<AuthRepository>().currentUser != null
                      ? [
                          HouseMember(
                            id: sl<AuthRepository>().currentUser!.id,
                            name: sl<AuthRepository>().currentUser!.fullName.isNotEmpty
                                ? sl<AuthRepository>().currentUser!.fullName
                                : 'Você',
                          )
                        ]
                      : const [
                          HouseMember(id: 'member_carlos', name: 'Carlos'),
                          HouseMember(id: 'member_marina', name: 'Marina'),
                        ]);

              final lenderName = _fromHouse
                  ? 'O Caixa da Casa'
                  : displayMembers.where((m) => m.id == _lenderId).firstOrNull?.name ??
                      (isDemo && _lenderId == 'member_carlos' ? 'Carlos' : 'Selecione');
              final canLendFromHouse = _canLendFromHouse(finState);
              final borrowerName = displayMembers.where((m) => m.id == _borrowerId).firstOrNull?.name ??
                  (isDemo && _borrowerId == 'member_marina' ? 'Marina' : 'Selecione');
              final hasSamePartyError = _lenderId.isNotEmpty && _lenderId == _borrowerId;

              return Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.cardColor,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: hasSamePartyError ? AppColors.debtRed : theme.dividerColor,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // 1. Quem emprestou (Credor)
                    Row(
                      children: [
                        const Icon(Icons.arrow_downward_rounded, color: AppColors.creditGreen, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Quem emprestou? (Credor)',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (canLendFromHouse)
                          ChoiceChip(
                            key: const Key('loan_lender_house'),
                            selected: _fromHouse,
                            avatar: const Icon(Icons.home_rounded, size: 18),
                            label: const Text('Caixa da Casa'),
                            selectedColor: AppColors.creditGreen.withValues(alpha: 0.2),
                            side: BorderSide(
                              color: _fromHouse ? AppColors.creditGreen : theme.dividerColor,
                            ),
                            onSelected: (val) {
                              if (!val) return;
                              setState(() {
                                _lenderId = P2PLoan.houseLenderId;
                                _isHistorical = false;
                                _paidInstallmentsCount = 0;
                                _openEndedHasPriorPayments = false;
                                if (_borrowerId.isEmpty && displayMembers.isNotEmpty) {
                                  _borrowerId = displayMembers.first.id;
                                }
                              });
                              _regenerateInstallments();
                            },
                          ),
                        ...displayMembers.map((m) {
                        final isSelected = _lenderId == m.id;
                        return ChoiceChip(
                          selected: isSelected,
                          label: Text(m.name),
                          selectedColor: AppColors.creditGreen.withValues(alpha: 0.2),
                          side: BorderSide(
                            color: isSelected ? AppColors.creditGreen : theme.dividerColor,
                          ),
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _lenderId = m.id;
                                if (_borrowerId == m.id) {
                                  final other = displayMembers.where((x) => x.id != m.id).firstOrNull;
                                  if (other != null) _borrowerId = other.id;
                                }
                              });
                            }
                          },
                        );
                      }),
                      ],
                    ),
                    const SizedBox(height: 12),

                    // Botão Inverter
                    Center(
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: AppColors.primary,
                        ),
                        icon: const Icon(Icons.swap_vert_rounded, size: 18),
                        label: const Text('Inverter Credor e Devedor', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                        onPressed: _fromHouse ? null : _swapParties,
                      ),
                    ),
                    const SizedBox(height: 4),

                    // 2. Quem tomou (Devedor)
                    Row(
                      children: [
                        const Icon(Icons.arrow_upward_rounded, color: AppColors.debtRed, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          'Quem tomou o empréstimo? (Devedor)',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: displayMembers.map((m) {
                        final isSelected = _borrowerId == m.id;
                        return ChoiceChip(
                          selected: isSelected,
                          label: Text(m.name),
                          selectedColor: AppColors.debtRed.withValues(alpha: 0.2),
                          side: BorderSide(
                            color: isSelected ? AppColors.debtRed : theme.dividerColor,
                          ),
                          onSelected: (val) {
                            if (val) {
                              setState(() {
                                _borrowerId = m.id;
                                if (_lenderId == m.id) {
                                  final other = displayMembers.where((x) => x.id != m.id).firstOrNull;
                                  if (other != null) _lenderId = other.id;
                                }
                              });
                            }
                          },
                        );
                      }).toList(),
                    ),

                    const SizedBox(height: 14),

                    // Resumo visual
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: hasSamePartyError
                            ? AppColors.debtRed.withValues(alpha: 0.1)
                            : AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            hasSamePartyError ? Icons.error_outline_rounded : Icons.sync_alt_rounded,
                            size: 18,
                            color: hasSamePartyError ? AppColors.debtRed : AppColors.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              hasSamePartyError
                                  ? 'Atenção: O credor e o devedor devem ser membros diferentes.'
                                  : '$lenderName emprestou para $borrowerName',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: hasSamePartyError ? AppColors.debtRed : AppColors.primary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 24),

          if (_fromHouse) ...[
            _buildHouseFunding(theme),
            const SizedBox(height: 20),
          ],

          // Modalidade: Parcelado x Sem prazo
          _buildRepaymentModeSelector(theme),
          const SizedBox(height: 20),

          if (_isOpenEnded)
            _buildOpenEndedSection(theme)
          else ...[

          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Cobrar no Fechamento do Ciclo'),
            subtitle: Text(
              _settleInCycle
                  ? 'Cada parcela entra no fechamento do ciclo em que vence. Dá para antecipar quando quiser.'
                  : 'As datas servem só de lembrete: o pagamento é sempre manual.',
            ),
            value: _settleInCycle,
            onChanged: (value) => setState(() => _settleInCycle = value),
          ),
          const SizedBox(height: 12),

          // Quantidade de Parcelas
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Número de Parcelas', style: theme.textTheme.titleSmall),
              Text(
                '$_installmentsCount${_installmentsCount > 1 ? " parcelas" : " parcela"}',
                style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.accent),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [1, 2, 3, 4, 5, 6, 10, 12, 18, 24].map((count) {
                final isSelected = _installmentsCount == count;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${count}x'),
                    selected: isSelected,
                    selectedColor: AppColors.accent.withValues(alpha: 0.2),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() {
                          _installmentsCount = count;
                          if (_paidInstallmentsCount > count) {
                            _paidInstallmentsCount = count;
                          }
                        });
                        _regenerateInstallments();
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 20),

          // Data do 1º Vencimento
          InkWell(
            onTap: _pickFirstDueDate,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(Icons.calendar_month_rounded, color: AppColors.accent),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Vencimento da 1ª Parcela', style: theme.textTheme.bodySmall),
                        Text(
                          dateFmt.format(_firstDueDate),
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_drop_down_rounded),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Switch: Empréstimo Iniciado no Passado (Opção 1). O Caixa empresta agora.
          if (!_fromHouse)
          Material(
            color: _isHistorical
                ? AppColors.accent.withValues(alpha: 0.08)
                : (theme.brightness == Brightness.dark ? AppColors.surfaceDark : Colors.grey.shade50),
            shape: RoundedRectangleBorder(
              side: BorderSide(
                color: _isHistorical ? AppColors.accent : theme.dividerColor,
                width: _isHistorical ? 1.5 : 1,
              ),
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                SwitchListTile(
                  title: const Text(
                    'Empréstimo iniciado no passado?',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Cadastrar contrato com parcelas já quitadas antes de usar o Omni Lar',
                    style: TextStyle(fontSize: 12),
                  ),
                  secondary: Icon(
                    Icons.history_rounded,
                    color: _isHistorical ? AppColors.accent : Colors.grey,
                  ),
                  value: _isHistorical,
                  onChanged: (val) {
                    setState(() {
                      _isHistorical = val;
                      if (!_isHistorical) {
                        _paidInstallmentsCount = 0;
                      } else if (_paidInstallmentsCount == 0 && _installmentsCount > 1) {
                        _paidInstallmentsCount = 1;
                      }
                    });
                    _regenerateInstallments();
                  },
                ),
                if (_isHistorical) ...[
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Parcelas já quitadas anteriormente:',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            Text(
                              '$_paidInstallmentsCount de $_installmentsCount pagas',
                              style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.creditGreen),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            IconButton.outlined(
                              icon: const Icon(Icons.remove_rounded),
                              onPressed: _paidInstallmentsCount > 0
                                  ? () {
                                      setState(() {
                                        _paidInstallmentsCount--;
                                      });
                                      _regenerateInstallments();
                                    }
                                  : null,
                            ),
                            Expanded(
                              child: Slider(
                                value: _paidInstallmentsCount.toDouble(),
                                min: 0,
                                max: _installmentsCount.toDouble(),
                                divisions: _installmentsCount > 0 ? _installmentsCount : 1,
                                activeColor: AppColors.creditGreen,
                                onChanged: (val) {
                                  setState(() {
                                    _paidInstallmentsCount = val.round();
                                  });
                                  _regenerateInstallments();
                                },
                              ),
                            ),
                            IconButton.outlined(
                              icon: const Icon(Icons.add_rounded),
                              onPressed: _paidInstallmentsCount < _installmentsCount
                                  ? () {
                                      setState(() {
                                        _paidInstallmentsCount++;
                                      });
                                      _regenerateInstallments();
                                    }
                                  : null,
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.creditGreen.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.info_outline_rounded, size: 18, color: AppColors.creditGreen),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '$_paidInstallmentsCount parcelas serão registradas como pagas no passado (sem debitar ou creditar o caixa atual). Restam ${_installmentsCount - _paidInstallmentsCount} parcelas em aberto.',
                                  style: const TextStyle(fontSize: 12, color: AppColors.creditGreen),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Seção: Detalhamento e Edição Parcela por Parcela (Opção 2)
          if (_cents > 0 && _installments.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Detalhamento das Parcelas',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.refresh_rounded, size: 16),
                  label: const Text('Dividir igualmente', style: TextStyle(fontSize: 12)),
                  onPressed: _regenerateInstallments,
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Card Resumo das Parcelas
            Card(
              elevation: 0,
              color: theme.brightness == Brightness.dark ? AppColors.surfaceDark : Colors.grey.shade100,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    Column(
                      children: [
                        Text('Total', style: theme.textTheme.bodySmall),
                        Text(totalMoney.format(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    Container(height: 28, width: 1, color: theme.dividerColor),
                    Column(
                      children: [
                        Text('Já Pago', style: theme.textTheme.bodySmall),
                        Text(
                          Money(paidCents).format(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.creditGreen),
                        ),
                        Text('$paidCount parcelas', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                    Container(height: 28, width: 1, color: theme.dividerColor),
                    Column(
                      children: [
                        Text('Em Aberto', style: theme.textTheme.bodySmall),
                        Text(
                          Money(openCents).format(),
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppColors.accent),
                        ),
                        Text('$openCount parcelas', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Alerta de Divergência de Centavos / Soma
            if (hasSumMismatch)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  border: Border.all(color: Colors.amber.shade700),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.warning_amber_rounded, color: Colors.amber.shade900, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Soma das parcelas (${currentSum.format()}) difere do total (${totalMoney.format()})',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: Colors.amber.shade900),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.amber.shade800,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            visualDensity: VisualDensity.compact,
                          ),
                          icon: const Icon(Icons.auto_fix_high_rounded, size: 16),
                          label: const Text('Equilibrar na última', style: TextStyle(fontSize: 12)),
                          onPressed: _balanceInstallments,
                        ),
                      ],
                    ),
                  ],
                ),
              ),

            // Lista Interativa de Parcelas
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _installments.length,
              separatorBuilder: (_, _) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final inst = _installments[index];
                final isPaid = inst.isFullyPaid;
                final isOverdue = !isPaid && inst.isPastDue;

                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: isPaid
                        ? AppColors.creditGreen.withValues(alpha: 0.05)
                        : (isOverdue ? AppColors.debtRed.withValues(alpha: 0.05) : theme.cardColor),
                    border: Border.all(
                      color: isPaid
                          ? AppColors.creditGreen.withValues(alpha: 0.3)
                          : (isOverdue ? AppColors.debtRed.withValues(alpha: 0.3) : theme.dividerColor),
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      // Número da Parcela
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: isPaid
                            ? AppColors.creditGreen.withValues(alpha: 0.15)
                            : (isOverdue ? AppColors.debtRed.withValues(alpha: 0.15) : AppColors.accent.withValues(alpha: 0.1)),
                        child: Text(
                          '${inst.number}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isPaid
                                ? AppColors.creditGreen
                                : (isOverdue ? AppColors.debtRed : AppColors.accent),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      // Detalhes: Data e Valor
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                InkWell(
                                  onTap: () => _pickInstallmentDueDate(index),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(Icons.calendar_today_rounded, size: 13, color: Colors.grey.shade600),
                                      const SizedBox(width: 4),
                                      Text(
                                        dateFmt.format(inst.dueDate),
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          decoration: TextDecoration.underline,
                                          decorationStyle: TextDecorationStyle.dotted,
                                          color: isOverdue ? AppColors.debtRed : null,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                InkWell(
                                  onTap: () => _editInstallmentAmount(index),
                                  borderRadius: BorderRadius.circular(4),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.edit_rounded, size: 13, color: AppColors.accent),
                                      const SizedBox(width: 4),
                                      Text(
                                        inst.amount.format(),
                                        style: const TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                          color: AppColors.accent,
                                          decoration: TextDecoration.underline,
                                          decorationStyle: TextDecorationStyle.dotted,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Chip Interativo de Status
                      InkWell(
                        onTap: () => _toggleInstallmentPaidStatus(index),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: isPaid
                                ? AppColors.creditGreen.withValues(alpha: 0.15)
                                : (isOverdue ? AppColors.debtRed.withValues(alpha: 0.15) : Colors.grey.withValues(alpha: 0.15)),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPaid
                                    ? Icons.check_circle_rounded
                                    : (isOverdue ? Icons.error_outline_rounded : Icons.radio_button_unchecked_rounded),
                                size: 14,
                                color: isPaid
                                    ? AppColors.creditGreen
                                    : (isOverdue ? AppColors.debtRed : Colors.grey.shade700),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPaid
                                    ? 'Paga'
                                    : (isOverdue ? 'Vencida' : 'Em aberto'),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isPaid
                                      ? AppColors.creditGreen
                                      : (isOverdue ? AppColors.debtRed : Colors.grey.shade800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
          ],
          const SizedBox(height: 32),

          // Botão Confirmar Empréstimo
          SizedBox(
            height: 52,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
              onPressed: _submit,
              child: const Text(
                'Confirmar Empréstimo',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
