import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

/// Permissão para a leitura por IA (migration 0085): ligar pede a mesma
/// confirmação da primeira leitura; desligar retira o consentimento.
class AiConsentTile extends StatelessWidget {
  const AiConsentTile({super.key});

  Future<void> _change(BuildContext context, bool given) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await context.read<AuthCubit>().setAiConsent(given);
      messenger.showSnackBar(SnackBar(
        content: Text(given ? 'Leitura por IA permitida.' : 'Permissão da IA retirada.'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e'), backgroundColor: AppColors.debtRed));
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final user = state.user;
        if (user == null || !user.legalStatusKnown) return const SizedBox.shrink();
        return SwitchListTile(
          key: const Key('ai_consent_switch'),
          title: const Text('Permitir a leitura por IA'),
          subtitle: Text(
            user.hasAiConsent
                ? 'Fotos, arquivos e mensagens do Assistente podem ir para a IA do Google.'
                : 'Sem a permissão, nada é enviado à IA: o Assistente usa só o entendimento do próprio app.',
          ),
          value: user.hasAiConsent,
          onChanged: (on) => _change(context, on),
        );
      },
    );
  }
}
