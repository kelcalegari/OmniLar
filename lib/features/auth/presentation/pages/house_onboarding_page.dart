import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../cubit/auth_cubit.dart';
import '../cubit/auth_state.dart';

class HouseOnboardingPage extends StatefulWidget {
  final bool allowBack;
  final int initialTab;

  const HouseOnboardingPage({
    super.key,
    this.allowBack = false,
    this.initialTab = 0,
  });

  @override
  State<HouseOnboardingPage> createState() => _HouseOnboardingPageState();
}

class _HouseOnboardingPageState extends State<HouseOnboardingPage> {
  late int _selectedTab;

  // Criar Casa
  final _createFormKey = GlobalKey<FormState>();
  final _houseNameController = TextEditingController(text: 'Nossa Casa');
  int _cycleStartDay = 5;

  // Dinheiro que a casa já tem (opcional): reserva guardada e saldo na conta
  bool _showInitialBalance = false;
  Money _initialReserve = const Money.zero();
  Money _initialCash = const Money.zero();

  // Entrar com Convite
  final _joinFormKey = GlobalKey<FormState>();
  final _inviteCodeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTab;
  }

  @override
  void dispose() {
    _houseNameController.dispose();
    _inviteCodeController.dispose();
    super.dispose();
  }

  void _submitCreate() {
    if (!_createFormKey.currentState!.validate()) return;
    context.read<AuthCubit>().createHouse(
      name: _houseNameController.text,
      cycleStartDay: _cycleStartDay,
      initialReserveCents: _initialReserve.cents,
      initialCashCents: _initialCash.cents,
    );
  }

  /// Passo opcional: o dinheiro que a casa já tem ao começar.
  Widget _initialBalanceStep(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _showInitialBalance = !_showInitialBalance),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  const Icon(Icons.savings_outlined, color: AppColors.primary),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'A casa já tem dinheiro? (opcional)',
                          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                        ),
                        SizedBox(height: 2),
                        Text(
                          'Reserva guardada e saldo na conta da casa. Dá para informar depois em Ajustes.',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  Icon(_showInitialBalance ? Icons.expand_less_rounded : Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
          if (_showInitialBalance)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  MoneyTextFormField(
                    key: const ValueKey('onboarding_initial_reserve'),
                    initialValue: _initialReserve,
                    labelText: 'Reserva guardada',
                    helperText: 'Dinheiro já guardado. Entra na Reserva da Casa.',
                    prefixIcon: const Icon(Icons.savings_outlined),
                    onChanged: (m) => _initialReserve = m,
                  ),
                  const SizedBox(height: 12),
                  MoneyTextFormField(
                    key: const ValueKey('onboarding_initial_cash'),
                    initialValue: _initialCash,
                    labelText: 'Saldo na conta da casa',
                    helperText: 'O que já está no Caixa hoje. Vale como a sobra do primeiro ciclo.',
                    prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                    onChanged: (m) => _initialCash = m,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _submitJoin() {
    if (!_joinFormKey.currentState!.validate()) return;
    context.read<AuthCubit>().joinHouseWithInvite(_inviteCodeController.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: widget.allowBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: Text(
          widget.allowBack ? 'Nova Casa' : 'Configuração da Casa',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          if (!widget.allowBack)
            TextButton.icon(
              onPressed: () => context.read<AuthCubit>().signOut(),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('Sair'),
              style: TextButton.styleFrom(foregroundColor: AppColors.debtRed),
            ),
        ],
      ),
      body: BlocConsumer<AuthCubit, AuthState>(
        listener: (context, state) {
          if (state.status == AuthStatus.failure &&
              state.errorMessage != null) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.errorMessage!),
                backgroundColor: AppColors.debtRed,
              ),
            );
          } else if (state.status == AuthStatus.authenticatedWithHouse && widget.allowBack) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          }
        },
        builder: (context, state) {
          final isLoading = state.status == AuthStatus.loading;
          final userName = state.user?.fullName.split(' ').first ?? 'Bem-vindo';

          return SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Boas-vindas
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primary.withValues(alpha: 0.2),
                          ),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundColor: AppColors.primary,
                              child: Text(
                                userName.isNotEmpty
                                    ? userName[0].toUpperCase()
                                    : 'U',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Olá, $userName!',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 16,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const Text(
                                    'Para começar a organizar as contas e a rotina, você precisa se conectar a uma Casa.',
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),

                      // Seletor de Modo (Criar vs Entrar)
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(
                                child: Text('Criar Nova Casa'),
                              ),
                              selected: _selectedTab == 0,
                              onSelected: (val) =>
                                  setState(() => _selectedTab = 0),
                              selectedColor: AppColors.primary.withValues(
                                alpha: 0.15,
                              ),
                              labelStyle: TextStyle(
                                fontWeight: _selectedTab == 0
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _selectedTab == 0
                                    ? AppColors.primary
                                    : Colors.grey,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(
                                child: Text('Tenho um Convite'),
                              ),
                              selected: _selectedTab == 1,
                              onSelected: (val) =>
                                  setState(() => _selectedTab = 1),
                              selectedColor: AppColors.primary.withValues(
                                alpha: 0.15,
                              ),
                              labelStyle: TextStyle(
                                fontWeight: _selectedTab == 1
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: _selectedTab == 1
                                    ? AppColors.primary
                                    : Colors.grey,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),

                      // Formulário 1: Criar Casa
                      if (_selectedTab == 0) ...[
                        Form(
                          key: _createFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _houseNameController,
                                decoration: InputDecoration(
                                  labelText: 'Nome do Lar / Casa',
                                  hintText:
                                      'Ex: Nosso Apto, Casa da Praia, República 42',
                                  prefixIcon: const Icon(Icons.home_outlined),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Dê um nome para a sua casa';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 20),

                              // Seletor do Dia do Ciclo Financeiro
                              Container(
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  color: theme.cardColor,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Expanded(
                                          child: Text(
                                            'Início do Ciclo Financeiro:',
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: 14,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: AppColors.primary.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            'Todo dia $_cycleStartDay',
                                            style: const TextStyle(
                                              color: AppColors.primary,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Geralmente o dia em que o salário cai (ex: dia 05 ao dia 04 do mês seguinte).',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Slider(
                                      value: _cycleStartDay.toDouble(),
                                      min: 1,
                                      max: 31,
                                      divisions: 30,
                                      label: 'Dia $_cycleStartDay',
                                      activeColor: AppColors.primary,
                                      onChanged: (val) => setState(
                                        () => _cycleStartDay = val.round(),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 16),

                              _initialBalanceStep(theme),
                              const SizedBox(height: 16),

                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: AppColors.primary.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.15,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    const Icon(
                                      Icons.auto_awesome_rounded,
                                      color: AppColors.primary,
                                      size: 20,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'Já deixamos tudo pronto: Caixa da Casa, Pix, Dinheiro e categorias essenciais (Supermercado, Moradia, Contas...).',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey.shade700,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),

                              ElevatedButton(
                                onPressed: isLoading ? null : _submitCreate,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.primary,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Criar Casa e Entrar',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      // Formulário 2: Entrar com Código de Convite
                      if (_selectedTab == 1) ...[
                        Form(
                          key: _joinFormKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              TextFormField(
                                controller: _inviteCodeController,
                                textCapitalization:
                                    TextCapitalization.characters,
                                decoration: InputDecoration(
                                  labelText: 'Código do Convite',
                                  hintText: 'Ex: LAR123',
                                  prefixIcon: const Icon(
                                    Icons.vpn_key_outlined,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                validator: (val) {
                                  if (val == null || val.trim().isEmpty) {
                                    return 'Digite o código recebido pelo outro morador';
                                  }
                                  return null;
                                },
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Peça ao administrador da casa o código de convite disponível na aba Ajustes.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                              const SizedBox(height: 24),

                              ElevatedButton(
                                onPressed: isLoading ? null : _submitJoin,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.accent,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                ),
                                child: isLoading
                                    ? const SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Text(
                                        'Validar Código e Entrar',
                                        style: TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
