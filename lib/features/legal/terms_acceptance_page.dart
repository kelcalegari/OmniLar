import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../auth/presentation/cubit/auth_cubit.dart';
import 'legal_texts.dart';

/// Aceite dos Termos e da Política, pedido na entrada quando a versão aceita
/// pela pessoa não é a atual (contas antigas ou texto novo).
class TermsAcceptancePage extends StatefulWidget {
  const TermsAcceptancePage({super.key});

  @override
  State<TermsAcceptancePage> createState() => _TermsAcceptancePageState();
}

class _TermsAcceptancePageState extends State<TermsAcceptancePage> {
  bool _checked = false;
  bool _saving = false;

  Future<void> _accept() async {
    setState(() => _saving = true);
    try {
      await context.read<AuthCubit>().acceptTerms(kLegalVersion);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: AppColors.debtRed),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final link = TextStyle(color: AppColors.primary, fontWeight: FontWeight.w600, decoration: TextDecoration.underline);
    return Scaffold(
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(Icons.gavel_rounded, size: 48, color: AppColors.primary),
                const SizedBox(height: 16),
                Text(
                  'Termos de uso e privacidade',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Text(
                  'Para continuar usando o Omni Lar, leia e aceite os Termos de uso e a Política de privacidade '
                  '(versão de $kLegalVersionLabel). Eles explicam o que o app faz, quais dados usa e como você '
                  'pode baixar ou excluir os seus dados.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 20),
                CheckboxListTile(
                  key: const Key('terms_accept_checkbox'),
                  value: _checked,
                  onChanged: _saving ? null : (v) => setState(() => _checked = v ?? false),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  title: Text.rich(
                    TextSpan(
                      text: 'Li e aceito os ',
                      children: [
                        TextSpan(
                          text: 'Termos de uso',
                          style: link,
                          recognizer: TapGestureRecognizer()..onTap = () => context.push('/termos'),
                        ),
                        const TextSpan(text: ' e a '),
                        TextSpan(
                          text: 'Política de privacidade',
                          style: link,
                          recognizer: TapGestureRecognizer()..onTap = () => context.push('/privacidade'),
                        ),
                        const TextSpan(text: '.'),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const Key('terms_accept_button'),
                  onPressed: _checked && !_saving ? _accept : null,
                  style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                  child: _saving
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('Aceitar e continuar', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _saving ? null : () => context.read<AuthCubit>().signOut(),
                  child: const Text('Agora não (sair da conta)'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
