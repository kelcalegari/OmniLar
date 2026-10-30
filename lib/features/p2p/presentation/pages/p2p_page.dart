import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../domain/entities/p2p_loan.dart';
import '../../domain/services/installment_loan_groups.dart';
import '../cubit/p2p_cubit.dart';
import '../cubit/p2p_state.dart';
import '../widgets/installment_group_card.dart';
import '../widgets/loan_card.dart';
import 'create_loan_page.dart';

class P2PPage extends StatelessWidget {
  /// Empréstimo a abrir ao entrar (deeplink `/pessoal/emprestimo/{id}`).
  final String? openLoanId;

  const P2PPage({super.key, this.openLoanId});

  @override
  Widget build(BuildContext context) {
    return _P2PPageContent(openLoanId: openLoanId);
  }
}

class _P2PPageContent extends StatefulWidget {
  final String? openLoanId;

  const _P2PPageContent({this.openLoanId});

  @override
  State<_P2PPageContent> createState() => _P2PPageContentState();
}

class _P2PPageContentState extends State<_P2PPageContent> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final requested = widget.openLoanId;
        if (requested != null) {
          _openRequestedLoan(requested);
        } else {
          context.read<P2PCubit>().loadLoans();
        }
      }
    });
  }

  @override
  void didUpdateWidget(covariant _P2PPageContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final requested = widget.openLoanId;
    if (requested != null && requested != oldWidget.openLoanId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openRequestedLoan(requested);
      });
    }
  }

  /// Abre o empréstimo pedido pelo deeplink. Ao fechar, limpa o pedido do
  /// endereço (trocar o endereço com o painel aberto o fecharia), para a mesma
  /// notificação poder abrir de novo.
  Future<void> _openRequestedLoan(String loanId) async {
    final cubit = context.read<P2PCubit>();
    await cubit.loadLoans();
    if (!mounted) return;
    final state = cubit.state;
    final loan = state.allLoans.where((l) => l.id == loanId).firstOrNull;
    if (loan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Este item não existe mais.')),
      );
    } else {
      await showLoanDetails(context, loan, isDebtor: loan.borrowerMemberId == state.currentUserId);
    }
    if (mounted && widget.openLoanId == loanId) context.go('/pessoal');
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<P2PCubit, P2PState>(
      builder: (context, state) {
        if (state.status == P2PStatus.loading && state.allLoans.isEmpty) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final netBalance = state.netBalance;
        final isNetPositive = netBalance.cents >= 0;
        final isWide = context.isDesktop;

        if (isWide) {
          // Layout Desktop (Duas colunas simultâneas: Eu Devo à esquerda, Me Devem à direita)
          return Scaffold(
            appBar: AppBar(
              title: const Text('Empréstimos P2P', style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Novo Empréstimo',
                  onPressed: () {
                    showAdaptiveModal(
                      context: context,
                      maxWidth: 540,
                      child: const CreateLoanPage(),
                    );
                  },
                ),
                const PrivacyToggleButton(),
              ],
            ),
            body: SingleChildScrollView(
              child: ResponsiveContainer(
                child: Column(
                  children: [
                    _buildBalanceCard(netBalance, isNetPositive, houseLoansTotal: state.totalHouseLoansPending),
                    const SizedBox(height: 24),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Coluna 1: Eu Devo
                        Expanded(
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: AppColors.debtRed.withValues(alpha: 0.2)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.arrow_upward_rounded, color: AppColors.debtRed, size: 20),
                                          SizedBox(width: 8),
                                          Text('Eu Devo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        ],
                                      ),
                                      Text(
                                        state.totalIDowe.format(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.debtRed),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (state.loansIDowe.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(child: Text('Você não tem nenhuma dívida pendente 🎉')),
                                    )
                                  else
                                    ..._loanTiles(state.loansIDowe, all: state.allLoans, isDebtor: (_) => true),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
                        // Coluna 2: Me Devem
                        Expanded(
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(color: AppColors.creditGreen.withValues(alpha: 0.2)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      const Row(
                                        children: [
                                          Icon(Icons.arrow_downward_rounded, color: AppColors.creditGreen, size: 20),
                                          SizedBox(width: 8),
                                          Text('Me Devem', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                        ],
                                      ),
                                      Text(
                                        state.totalTheyOweMe.format(),
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.creditGreen),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  if (state.loansTheyOweMe.isEmpty)
                                    const Padding(
                                      padding: EdgeInsets.all(24),
                                      child: Center(child: Text('Nenhum valor a receber no momento')),
                                    )
                                  else
                                    ..._loanTiles(state.loansTheyOweMe, all: state.allLoans, isDebtor: (_) => false),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (state.allLoans.any((l) =>
                        l.status != LoanStatus.paid &&
                        l.status != LoanStatus.forgiven &&
                        l.remainingAmount.cents > 0 &&
                        l.borrowerMemberId != state.currentUserId &&
                        l.lenderMemberId != state.currentUserId)) ...[
                      const SizedBox(height: 24),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: AppColors.primary.withValues(alpha: 0.2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.people_alt_outlined, color: AppColors.primary, size: 20),
                                  SizedBox(width: 8),
                                  Text(
                                    'Outros Empréstimos da Casa',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ..._loanTiles(
                                state.allLoans
                                    .where((l) =>
                                        l.status != LoanStatus.paid &&
                                        l.status != LoanStatus.forgiven &&
                                        l.remainingAmount.cents > 0 &&
                                        l.borrowerMemberId != state.currentUserId &&
                                        l.lenderMemberId != state.currentUserId)
                                    .toList(),
                                all: state.allLoans,
                                isDebtor: (_) => false,
                                showBothParties: true,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    if (state.settledLoans.isNotEmpty) ...[
                      const SizedBox(height: 24),
                      Card(
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.check_circle_outline_rounded, color: Colors.grey, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    'Histórico / Quitados (${state.settledLoans.length})',
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ..._loanTiles(
                                state.settledLoans,
                                all: state.allLoans,
                                isDebtor: (l) => l.borrowerMemberId == state.currentUserId,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        }

        // Layout Mobile (Abas: Eu Devo / Me Devem / Todos / Quitados)
        final theme = Theme.of(context);
        final activeAllLoans = state.allLoans
            .where((l) =>
                l.status != LoanStatus.paid &&
                l.status != LoanStatus.forgiven &&
                l.remainingAmount.cents > 0)
            .toList();

        return DefaultTabController(
          length: 4,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Empréstimos P2P', style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  icon: const Icon(Icons.add_rounded),
                  tooltip: 'Novo Empréstimo',
                  onPressed: () {
                    showAdaptiveModal(
                      context: context,
                      maxWidth: 540,
                      child: const CreateLoanPage(),
                    );
                  },
                ),
                const PrivacyToggleButton(),
              ],
            ),
            body: Column(
              children: [
                const SizedBox(height: 8),
                _buildBalanceCard(netBalance, isNetPositive, houseLoansTotal: state.totalHouseLoansPending),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.grey.withValues(alpha: 0.15)),
                    ),
                    child: TabBar(
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorSize: TabBarIndicatorSize.tab,
                      indicator: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      labelColor: AppColors.primary,
                      unselectedLabelColor: Colors.grey,
                      labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      tabs: [
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_upward_rounded, size: 16, color: AppColors.debtRed),
                              const SizedBox(width: 4),
                              Text('Eu Devo (${state.totalIDowe.format()})'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.arrow_downward_rounded, size: 16, color: AppColors.creditGreen),
                              const SizedBox(width: 4),
                              Text('Me Devem (${state.totalTheyOweMe.format()})'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.people_alt_outlined, size: 16, color: AppColors.primary),
                              const SizedBox(width: 4),
                              Text('Todos (${activeAllLoans.length})'),
                            ],
                          ),
                        ),
                        Tab(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded, size: 16, color: Colors.grey),
                              const SizedBox(width: 4),
                              Text('Quitados (${state.settledLoans.length})'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildLoansList(
                        context,
                        loans: state.loansIDowe,
                        isDebtor: true,
                        emptyMessage: 'Você não tem nenhuma dívida pendente 🎉',
                      ),
                      _buildLoansList(
                        context,
                        loans: state.loansTheyOweMe,
                        isDebtor: false,
                        emptyMessage: 'Nenhum valor a receber no momento',
                      ),
                      _buildLoansList(
                        context,
                        loans: activeAllLoans,
                        isDebtor: false,
                        showParties: true,
                        emptyMessage: 'Nenhum empréstimo ativo na casa',
                      ),
                      _buildLoansList(
                        context,
                        loans: state.settledLoans,
                        isDebtor: false,
                        showParties: true,
                        emptyMessage: 'Nenhum empréstimo finalizado ainda',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBalanceCard(dynamic netBalance, bool isNetPositive, {dynamic houseLoansTotal}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: (isNetPositive ? AppColors.creditGreen : AppColors.debtRed).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isNetPositive ? AppColors.creditGreen : AppColors.debtRed).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Saldo Pessoal Líquido',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                  ),
                  const SizedBox(height: 2),
                  PrivacySensitiveText(
                    netBalance.formatSigned(),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: isNetPositive ? AppColors.creditGreen : AppColors.debtRed,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (isNetPositive ? AppColors.creditGreen : AppColors.debtRed).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isNetPositive ? 'A Receber' : 'A Pagar',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isNetPositive ? AppColors.creditGreen : AppColors.debtRed,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLoansList(
    BuildContext context, {
    required List<P2PLoan> loans,
    required bool isDebtor,
    required String emptyMessage,
    bool showParties = false,
  }) {
    if (loans.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                isDebtor ? Icons.sentiment_satisfied_alt_rounded : Icons.account_balance_wallet_outlined,
                size: 56,
                color: Colors.grey,
              ),
              const SizedBox(height: 16),
              Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 15, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    final state = context.read<P2PCubit>().state;
    final tiles = _loanTiles(
      loans,
      all: state.allLoans,
      isDebtor: (l) => showParties ? (l.borrowerMemberId == state.currentUserId) : isDebtor,
      showBothParties: showParties,
    );

    return RefreshIndicator(
      onRefresh: () => context.read<P2PCubit>().loadLoans(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: tiles.length,
        itemBuilder: (context, index) => tiles[index],
      ),
    );
  }

  /// Cards da lista, com as parcelas de uma mesma compra parcelada no cartão
  /// juntas em um card só.
  List<Widget> _loanTiles(
    List<P2PLoan> loans, {
    required List<P2PLoan> all,
    required bool Function(P2PLoan loan) isDebtor,
    bool showBothParties = false,
  }) {
    return [
      for (final entry in groupInstallmentLoans(loans, all: all))
        switch (entry) {
          SingleLoanEntry(:final loan) => LoanCard(
              loan: loan,
              isDebtor: isDebtor(loan),
              showBothParties: showBothParties,
            ),
          InstallmentLoanGroup() => InstallmentGroupCard(
              group: entry,
              isDebtor: isDebtor(entry.first),
              showBothParties: showBothParties,
            ),
        },
    ];
  }
}
