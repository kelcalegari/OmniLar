import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/omni_logo.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../p2p/presentation/cubit/p2p_cubit.dart';

class WebLandingPage extends StatelessWidget {
  const WebLandingPage({super.key});

  Future<void> _startDemo(BuildContext context) async {
    await context.read<AuthCubit>().signInDemo(memberId: 'member_carlos');
    if (context.mounted) {
      context.read<FinanceCubit>().loadCycleData();
      context.read<P2PCubit>().loadLoans();
      context.go('/casa');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0B0F19) : const Color(0xFFF8FAFC),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(72),
        child: Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF0F172A).withValues(alpha: 0.95) : Colors.white.withValues(alpha: 0.95),
            border: Border(
              bottom: BorderSide(
                color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0),
              ),
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1240),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Logo e Nome
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const OmniLogo.icon(width: 34, height: 34),
                          const SizedBox(width: 12),
                          Text(
                            'Omni Lar',
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                              letterSpacing: -0.6,
                              color: isDark ? Colors.white : const Color(0xFF0F172A),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text(
                              'WEB',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: AppColors.primary,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                      // Ações Topo
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const ThemeToggleButton(),
                          const SizedBox(width: 12),
                          TextButton(
                            onPressed: () => context.push('/login'),
                            style: TextButton.styleFrom(
                              foregroundColor: isDark ? Colors.white : const Color(0xFF1E293B),
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            ),
                            child: const Text(
                              'Entrar',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton.icon(
                            onPressed: () => _startDemo(context),
                            icon: const Icon(Icons.flash_on_rounded, size: 16),
                            label: const Text(
                              'Testar Demo Online ⚡',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            style: FilledButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              elevation: 0,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1240),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const SizedBox(height: 56),

                  // 1. HERO SECTION CENTRALIZADA
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(30),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded, size: 16, color: AppColors.primary),
                        SizedBox(width: 8),
                        Text(
                          'A nova forma de viver junto sem atrito financeiro',
                          style: TextStyle(
                            color: AppColors.primary,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 860),
                    child: Text(
                      'Gestão Financeira Familiar com Super Pix & Rateio Justo',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 48,
                        letterSpacing: -1.2,
                        height: 1.15,
                        color: isDark ? Colors.white : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: Text(
                      'Elimine planilhas confusas e conversas desconfortáveis sobre dinheiro. O Omni Lar equilibra despesas compartilhadas, dívidas no cartão e metas da casa — liquidando tudo no fim do ciclo com apenas uma transferência Pix.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        height: 1.6,
                        color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                      ),
                    ),
                  ),
                  const SizedBox(height: 36),

                  // Botões de Ação Hero
                  Wrap(
                    spacing: 16,
                    runSpacing: 12,
                    alignment: WrapAlignment.center,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _startDemo(context),
                        icon: const Icon(Icons.flash_on_rounded, size: 20),
                        label: const Text(
                          'Experimentar Demo em 1 Clique',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 4,
                          shadowColor: AppColors.primary.withValues(alpha: 0.4),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => context.push('/login'),
                        icon: const Icon(Icons.login_rounded, size: 18),
                        label: const Text(
                          'Acessar Minha Casa',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: isDark ? Colors.white : const Color(0xFF0F172A),
                          side: BorderSide(
                            color: isDark ? const Color(0xFF334155) : const Color(0xFFCBD5E1),
                            width: 1.5,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 56),

                  // 2. MOCKUP INTERATIVO DO PRODUTO (PREVIEW DO DASHBOARD)
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 1040),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E293B) : Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
                          blurRadius: 36,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      children: [
                        // Barra Superior do Mockup
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFEF4444)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF59E0B)),
                                ),
                                const SizedBox(width: 8),
                                Container(
                                  width: 12,
                                  height: 12,
                                  decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF10B981)),
                                ),
                                const SizedBox(width: 16),
                                Text(
                                  'Omni Lar • Demonstração Viva',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.green.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.circle, size: 8, color: Colors.green),
                                  SizedBox(width: 6),
                                  Text(
                                    'Ciclo Ativo • Saldo Balanceado',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 36),

                        // Linha de KPIs Simulados do Lar
                        LayoutBuilder(
                          builder: (context, constraints) {
                            final isWide = constraints.maxWidth > 700;
                            return Flex(
                              direction: isWide ? Axis.horizontal : Axis.vertical,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildMockupKPI(
                                  title: 'FÔLEGO DO CAIXA',
                                  value: 'R\$ 4.820,00',
                                  subtitle: '78% da meta do mês',
                                  color: AppColors.creditGreen,
                                  icon: Icons.savings_outlined,
                                  isDark: isDark,
                                ),
                                if (isWide) const SizedBox(width: 16) else const SizedBox(height: 12),
                                _buildMockupKPI(
                                  title: 'SUPER PIX DESTE CICLO',
                                  value: 'R\$ 425,50',
                                  subtitle: 'Marina transfere para Carlos',
                                  color: AppColors.primary,
                                  icon: Icons.flash_on_rounded,
                                  isDark: isDark,
                                ),
                                if (isWide) const SizedBox(width: 16) else const SizedBox(height: 12),
                                _buildMockupKPI(
                                  title: 'EMPRÉSTIMOS P2P',
                                  value: 'R\$ 320,00',
                                  subtitle: 'Fatura de Cartão Pessoal',
                                  color: AppColors.accent,
                                  icon: Icons.handshake_outlined,
                                  isDark: isDark,
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),

                  // 3. PILARES & FUNCIONALIDADES EM GRID BALANCEADA
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 600),
                    child: Column(
                      children: [
                        Text(
                          'Tudo o que sua casa precisa em um só lugar',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            letterSpacing: -0.8,
                            color: isDark ? Colors.white : const Color(0xFF0F172A),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Projetado especificamente para casais, repúblicas e famílias que compartilham a vida e as contas.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 16,
                            color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 48),

                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isDesktop = constraints.maxWidth > 850;
                      return Wrap(
                        spacing: 24,
                        runSpacing: 24,
                        alignment: WrapAlignment.center,
                        children: [
                          SizedBox(
                            width: isDesktop ? (constraints.maxWidth - 48) / 3 : double.infinity,
                            child: _buildFeatureCard(
                              theme,
                              isDark: isDark,
                              icon: Icons.flash_on_rounded,
                              iconColor: AppColors.primary,
                              title: 'Super Pix',
                              desc: 'O motor compensa todas as despesas da casa, compras no cartão e empréstimos mútuos. Todos acertam o mês inteiro com uma única transferência Pix.',
                            ),
                          ),
                          SizedBox(
                            width: isDesktop ? (constraints.maxWidth - 48) / 3 : double.infinity,
                            child: _buildFeatureCard(
                              theme,
                              isDark: isDark,
                              icon: Icons.balance_rounded,
                              iconColor: AppColors.accent,
                              title: 'Rateio Justo & Balde Comum',
                              desc: 'Escolha divisão proporcional aos rendimentos, cota igualitária ou aportes fixos no balde com proteção total da reserva de emergência da casa.',
                            ),
                          ),
                          SizedBox(
                            width: isDesktop ? (constraints.maxWidth - 48) / 3 : double.infinity,
                            child: _buildFeatureCard(
                              theme,
                              isDark: isDark,
                              icon: Icons.handshake_rounded,
                              iconColor: AppColors.creditGreen,
                              title: 'Empréstimos P2P sem Conflito',
                              desc: 'Passou a compra pessoal no cartão do parceiro? O Omni Lar cria a dívida com parcelas, juros, amortização livre ou pagamento direto na caixinha.',
                            ),
                          ),
                          SizedBox(
                            width: isDesktop ? (constraints.maxWidth - 48) / 3 : double.infinity,
                            child: _buildFeatureCard(
                              theme,
                              isDark: isDark,
                              icon: Icons.call_split_rounded,
                              iconColor: Colors.deepPurple,
                              title: 'Segmentação de Boletos',
                              desc: 'Boletos com condomínio, água, gás e fundo de obras? Desmembre cada linha atribuindo responsáveis e donos diferentes sem criar lançamentos duplicados.',
                            ),
                          ),
                          SizedBox(
                            width: isDesktop ? (constraints.maxWidth - 48) / 3 : double.infinity,
                            child: _buildFeatureCard(
                              theme,
                              isDark: isDark,
                              icon: Icons.file_upload_outlined,
                              iconColor: Colors.teal,
                              title: 'Importação OFX & CSV',
                              desc: 'Importe faturas e extratos bancários instantaneamente. O app detecta os gastos da casa e sugere quem deve o quê antes de confirmar.',
                            ),
                          ),
                          SizedBox(
                            width: isDesktop ? (constraints.maxWidth - 48) / 3 : double.infinity,
                            child: _buildFeatureCard(
                              theme,
                              isDark: isDark,
                              icon: Icons.wifi_off_rounded,
                              iconColor: Colors.orange,
                              title: 'Offline-First com Criptografia',
                              desc: 'Funcione perfeitamente mesmo sem internet. Suas despesas são salvas em cofre seguro de hardware e sincronizam assim que houver rede.',
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 80),

                  // 4. BANNER CTA FINAL
                  Container(
                    width: double.infinity,
                    constraints: const BoxConstraints(maxWidth: 1040),
                    padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary,
                          AppColors.primary.withValues(alpha: 0.8),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.3),
                          blurRadius: 30,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Column(
                      children: [
                        const Text(
                          'Pronto para transformar as finanças da sua casa?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.white,
                            letterSpacing: -0.6,
                          ),
                        ),
                        const SizedBox(height: 14),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 640),
                          child: const Text(
                            'Experimente o modo de demonstração agora mesmo direto no seu navegador, sem precisar preencher formulários.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16, color: Colors.white70, height: 1.5),
                          ),
                        ),
                        const SizedBox(height: 28),
                        FilledButton(
                          onPressed: () => _startDemo(context),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: AppColors.primary,
                            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            elevation: 0,
                          ),
                          child: const Text(
                            'Iniciar Demonstração Gratuita ⚡',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 80),

                  // 5. RODAPÉ INSTITUCIONAL
                  Divider(color: isDark ? const Color(0xFF1E293B) : const Color(0xFFE2E8F0)),
                  const SizedBox(height: 28),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const OmniLogo.icon(width: 22, height: 22),
                            const SizedBox(width: 8),
                            Text(
                              'Omni Lar',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Text(
                          '© 2026 Omni Lar • Construído para harmonia e paz financeira.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[500] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMockupKPI({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w900,
                      color: isDark ? Colors.white : const Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    ThemeData theme, {
    required bool isDark,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isDark ? const Color(0xFF334155) : const Color(0xFFE2E8F0),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.03),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 19,
              letterSpacing: -0.4,
              color: isDark ? Colors.white : const Color(0xFF0F172A),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            desc,
            style: TextStyle(
              color: isDark ? const Color(0xFF94A3B8) : const Color(0xFF64748B),
              fontSize: 14,
              height: 1.55,
            ),
          ),
        ],
      ),
    );
  }
}
