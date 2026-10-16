import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../domain/entities/account_access.dart';
import '../cubit/account_access_cubit.dart';

/// Tela de quem ainda não tem a conta liberada: em análise, recusada ou
/// suspensa. Muda sozinha quando o administrador aprova; com um convite
/// válido de uma casa, a conta em análise é aprovada na hora.
class AccountPendingPage extends StatefulWidget {
  const AccountPendingPage({super.key});

  @override
  State<AccountPendingPage> createState() => _AccountPendingPageState();
}

class _AccountPendingPageState extends State<AccountPendingPage> {
  final _codeController = TextEditingController();
  bool _joining = false;
  String? _codeError;

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _codeController.text.trim();
    if (code.isEmpty) {
      setState(() => _codeError = 'Digite o código do convite');
      return;
    }
    setState(() {
      _joining = true;
      _codeError = null;
    });
    final auth = sl<AuthCubit>();
    await auth.joinHouseWithInvite(code);
    await sl<AccountAccessCubit>().refresh();
    if (!mounted) return;
    setState(() {
      _joining = false;
      if (auth.state.errorMessage != null) _codeError = auth.state.errorMessage;
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AccountAccessCubit, AccountAccessState>(
      bloc: sl<AccountAccessCubit>(),
      builder: (context, state) {
        final access = state.access;
        final status = access?.status ?? AccountStatus.pending;
        final email = sl<AuthCubit>().state.user?.email ?? '';
        final (icon, color, title, text) = switch (status) {
          AccountStatus.rejected => (
              Icons.block_rounded,
              AppColors.debtRed,
              'Seu acesso não foi aprovado',
              'A administração do Omni Lar não aprovou esta conta.',
            ),
          AccountStatus.suspended => (
              Icons.pause_circle_outline_rounded,
              AppColors.debtRed,
              'Sua conta está suspensa',
              'Seus dados continuam guardados. Fale com a administração do Omni Lar para reativar.',
            ),
          _ => (
              Icons.hourglass_top_rounded,
              AppColors.primary,
              'Sua conta está em análise',
              'Assim que a administração do Omni Lar aprovar, esta tela muda sozinha. '
                  'Se alguém te convidou para uma casa, use o código abaixo para entrar já.',
            ),
        };

        return Scaffold(
          body: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Icon(icon, size: 56, color: color),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.grey)),
                    if (access?.reason != null && access!.reason!.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Motivo: ${access.reason}', textAlign: TextAlign.center),
                      ),
                    ],
                    if (email.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Text('Conta: $email', textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
                    ],
                    if (status == AccountStatus.pending) ...[
                      const SizedBox(height: 28),
                      TextField(
                        controller: _codeController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          labelText: 'Código de convite de uma casa',
                          errorText: _codeError,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        onSubmitted: (_) => _join(),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: _joining ? null : _join,
                        child: _joining
                            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Entrar com o convite'),
                      ),
                    ],
                    const SizedBox(height: 20),
                    TextButton.icon(
                      onPressed: () => sl<AuthCubit>().signOut(),
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Sair'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
