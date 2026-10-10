import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _showMembersModal(BuildContext context, String houseName, String houseId) {
    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Membros de $houseName',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Todos os participantes dividem o Caixa e a rotina da casa.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // Cartão do Código de Convite
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Código de Convite:',
                              style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'LAR123',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                        tooltip: 'Copiar Código',
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: 'LAR123'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código LAR123 copiado para a área de transferência!')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Membros Ativos (2):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 10),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text('C', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: const Text('Carlos Eduardo', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('carlos@omnilar.com • 50% de rateio'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Proprietário', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.accent,
                    child: Text('M', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: const Text('Marina Silva', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('marina@omnilar.com • 50% de rateio'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Admin', style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    }

  void _showAssistantPreferencesModal(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Row(
                children: [
                  Icon(Icons.auto_awesome_rounded, color: Colors.purple, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Assistente & Privacidade',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Controle a inteligência artificial da casa e a proteção dos seus dados.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Assistente Ativo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Permite consultas e propostas por linguagem natural'),
                value: true,
                onChanged: (val) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Preferência de assistente atualizada.')),
                  );
                },
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Resumos e Alertas Proativos', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Receber alertas de fôlego do ciclo e tarefas atrasadas'),
                value: true,
                onChanged: (val) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alertas proativos atualizados.')),
                  );
                },
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Horário Silencioso', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('22:00 às 08:00 (Nenhum aviso emitido)'),
                trailing: Icon(Icons.bedtime_outlined, color: Colors.purple),
              ),
              const Divider(),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Privacidade LGPD: seus dados bancários, CPF e números de cartão são mascarados no dispositivo antes de qualquer processamento.',
                        style: TextStyle(fontSize: 12, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sair do Omni Lar?'),
        content: const Text('Você precisará entrar com seu e-mail e senha novamente para acessar os dados da casa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.read<AuthCubit>().signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.debtRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sair da Conta'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes da Casa', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          final user = authState.user;
          final house = authState.house;

          final userName = user?.fullName ?? 'Usuário';
          final userEmail = user?.email ?? 'sem e-mail';
          final houseName = house?.name ?? 'Minha Casa';
          final cycleDay = house?.cycleStartDay ?? 5;

          return SingleChildScrollView(
            child: ResponsiveContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card do Perfil e Casa Ativa
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              userEmail,
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.home_outlined, size: 14, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '$houseName (Ciclo dia $cycleDay)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              ListTile(
                leading: const Icon(Icons.people_outline_rounded, color: AppColors.primary),
                title: const Text('Membros da Casa e Convites'),
                subtitle: const Text('Carlos, Marina • Código LAR123'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showMembersModal(context, houseName, house?.id ?? ''),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.tune_rounded, color: AppColors.accent),
                title: const Text('Modelos de Rateio'),
                subtitle: const Text('Porcentagem (50/50), fixo ou categoria'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Configuração de rateio: 50% Carlos / 50% Marina')),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.credit_card_rounded, color: Colors.orange),
                title: const Text('Cartões e Formas de Pagamento'),
                subtitle: const Text('Nubank Carlos, Inter Marina, VR Alelo'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('3 formas de pagamento ativas na casa')),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined, color: Colors.teal),
                title: const Text('Ciclo Financeiro'),
                subtitle: Text('Dia $cycleDay ao dia ${cycleDay == 1 ? 31 : cycleDay - 1}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ciclo atual: Todo dia $cycleDay')),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: Colors.purple),
                title: const Text('Assistente IA'),
                subtitle: const Text('Preferências e consentimento LGPD'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showAssistantPreferencesModal(context),
              ),
              const Divider(),
              const SizedBox(height: 16),

              // Botão Sair da Conta
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () => _confirmSignOut(context),
                  icon: const Icon(Icons.logout_rounded, color: AppColors.debtRed),
                  label: const Text(
                    'Sair da Conta',
                    style: TextStyle(color: AppColors.debtRed, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppColors.debtRed.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    },
  ),
);
  }
}
