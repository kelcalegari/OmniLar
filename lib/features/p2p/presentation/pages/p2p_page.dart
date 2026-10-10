import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../domain/entities/p2p_loan.dart';
import '../cubit/p2p_cubit.dart';
import '../cubit/p2p_state.dart';
import '../widgets/loan_card.dart';

class P2PPage extends StatelessWidget {
  const P2PPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const _P2PPageContent();
  }
}

class _P2PPageContent extends StatelessWidget {
  const _P2PPageContent();

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
              title: const Text('Empréstimos P2P (Visão Geral)', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
            body: SingleChildScrollView(
              child: ResponsiveContainer(
                child: Column(
                  children: [
                    _buildBalanceCard(netBalance, isNetPositive),
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
                                    ...state.loansIDowe.map((l) => LoanCard(loan: l, isDebtor: true)),
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
                                    ...state.loansTheyOweMe.map((l) => LoanCard(loan: l, isDebtor: false)),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
          );
        }

        // Layout Mobile (Abas clássicas Eu Devo / Me Devem)
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Empréstimos P2P', style: TextStyle(fontWeight: FontWeight.bold)),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(130),
                child: Column(
                  children: [
                    _buildBalanceCard(netBalance, isNetPositive),
                    const SizedBox(height: 12),
                    TabBar(
                      indicatorColor: AppColors.primary,
                      labelColor: Theme.of(context).colorScheme.primary,
                      unselectedLabelColor: Theme.of(context).textTheme.bodySmall?.color,
                      tabs: [
                        Tab(
                          icon: const Icon(Icons.arrow_upward_rounded, color: AppColors.debtRed),
                          text: 'Eu Devo (${state.totalIDowe.format()})',
                        ),
                        Tab(
                          icon: const Icon(Icons.arrow_downward_rounded, color: AppColors.creditGreen),
                          text: 'Me Devem (${state.totalTheyOweMe.format()})',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            body: TabBarView(
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
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildBalanceCard(dynamic netBalance, bool isNetPositive) {
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
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Saldo Pessoal Líquido',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey),
                ),
                const SizedBox(height: 2),
                Text(
                  netBalance.formatSigned(),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isNetPositive ? AppColors.creditGreen : AppColors.debtRed,
                  ),
                ),
              ],
            ),
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

    return RefreshIndicator(
      onRefresh: () => context.read<P2PCubit>().loadLoans(),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: loans.length,
        itemBuilder: (context, index) {
          return LoanCard(
            loan: loans[index],
            isDebtor: isDebtor,
          );
        },
      ),
    );
  }
}
