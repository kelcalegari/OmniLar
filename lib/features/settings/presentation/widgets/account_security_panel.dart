import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';

final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// "Conta e segurança" nos Ajustes: e-mail de acesso (com a troca pendente,
/// se houver), formas de entrar e troca de senha.
class AccountSecurityPanel extends StatefulWidget {
  const AccountSecurityPanel({super.key});

  @override
  State<AccountSecurityPanel> createState() => _AccountSecurityPanelState();
}

class _AccountSecurityPanelState extends State<AccountSecurityPanel> {
  Future<void> _openEmailChange({String? pendingEmail}) async {
    await showAdaptiveModal(
      context: context,
      maxWidth: 480,
      child: ChangeEmailSheet(pendingEmail: pendingEmail),
    );
    // A troca pode ter ficado pendente sem mudar o estado do login
    if (mounted) setState(() {});
  }

  void _openPasswordChange() {
    showAdaptiveModal(
      context: context,
      maxWidth: 480,
      child: const ChangePasswordSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AuthCubit, AuthState>(
      builder: (context, state) {
        final cubit = context.read<AuthCubit>();
        final email = state.user?.email ?? '';
        final pending = cubit.pendingEmailChange;
        final providers = cubit.signInProviders;
        final hasPassword = providers.contains('email');

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _card(
              context,
              title: 'E-mail de acesso',
              actionLabel: 'Alterar',
              onAction: _openEmailChange,
              children: [
                _infoRow('E-mail', email),
                if (pending != null)
                  Container(
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: Colors.amber.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.hourglass_top_rounded,
                          color: Colors.amber,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Troca para $pending aguardando o código.',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              _openEmailChange(pendingEmail: pending),
                          child: const Text('Digitar código'),
                        ),
                      ],
                    ),
                  ),
                _infoRow(
                  'Formas de entrar',
                  providers.map(_providerLabel).join(' • '),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _card(
              context,
              title: 'Senha',
              actionLabel: hasPassword ? 'Alterar' : null,
              onAction: hasPassword ? _openPasswordChange : null,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 6,
                  ),
                  child: Text(
                    hasPassword
                        ? 'Para trocar, informe a senha atual e a nova. Esqueceu a atual? Saia da conta e use "Esqueci minha senha".'
                        : 'Sua conta entra só pelo Google e não tem senha.',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  static String _providerLabel(String provider) => switch (provider) {
    'email' => 'E-mail e senha',
    'google' => 'Google',
    _ => provider,
  };

  Widget _infoRow(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Row(
        children: [
          Text(title, style: const TextStyle(fontSize: 14)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Mesmo desenho dos blocos dos Ajustes (título, ação e conteúdo).
  Widget _card(
    BuildContext context, {
    required String title,
    String? actionLabel,
    VoidCallback? onAction,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            InkWell(
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (actionLabel != null)
                      TextButton(onPressed: onAction, child: Text(actionLabel))
                    else
                      const SizedBox(height: 40),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ...children,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

/// Moldura comum das duas folhas: título, texto e conteúdo com rolagem.
class _SheetFrame extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final List<Widget> children;

  const _SheetFrame({
    required this.icon,
    required this.title,
    required this.description,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                description,
                style: const TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _decoration(String label, IconData icon) => InputDecoration(
  labelText: label,
  prefixIcon: Icon(icon),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
);

Widget _actions(
  BuildContext context, {
  required bool isSaving,
  required String label,
  required VoidCallback onSave,
}) {
  return Row(
    children: [
      Expanded(
        child: OutlinedButton(
          onPressed: isSaving ? null : () => Navigator.pop(context),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: const Text('Cancelar'),
        ),
      ),
      const SizedBox(width: 12),
      Expanded(
        child: FilledButton(
          onPressed: isSaving ? null : onSave,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          child: isSaving
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
      ),
    ],
  );
}

void _showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(e.toString()), backgroundColor: AppColors.debtRed),
  );
}

/// Troca de senha de quem está logado: senha atual + nova + confirmação.
class ChangePasswordSheet extends StatefulWidget {
  const ChangePasswordSheet({super.key});

  @override
  State<ChangePasswordSheet> createState() => _ChangePasswordSheetState();
}

class _ChangePasswordSheetState extends State<ChangePasswordSheet> {
  final _formKey = GlobalKey<FormState>();
  final _currentController = TextEditingController();
  final _newController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isSaving = false;
  bool _obscure = true;

  @override
  void dispose() {
    _currentController.dispose();
    _newController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await context.read<AuthCubit>().changePassword(
        currentPassword: _currentController.text,
        newPassword: _newController.text,
      );
      navigator.pop();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Senha alterada.'),
          backgroundColor: AppColors.primary,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final toggle = IconButton(
      icon: Icon(
        _obscure ? Icons.visibility_off_outlined : Icons.visibility_outlined,
      ),
      onPressed: () => setState(() => _obscure = !_obscure),
    );
    return _SheetFrame(
      icon: Icons.password_rounded,
      title: 'Alterar senha',
      description: 'Use pelo menos 6 caracteres.',
      children: [
        Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _currentController,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.password],
                decoration: _decoration(
                  'Senha atual',
                  Icons.lock_outline_rounded,
                ).copyWith(suffixIcon: toggle),
                validator: (val) => (val == null || val.isEmpty)
                    ? 'Informe a senha atual'
                    : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _newController,
                obscureText: _obscure,
                autofillHints: const [AutofillHints.newPassword],
                decoration: _decoration(
                  'Nova senha',
                  Icons.lock_reset_rounded,
                ).copyWith(suffixIcon: toggle),
                validator: (val) {
                  if (val == null || val.length < 6) {
                    return 'A senha deve ter no mínimo 6 caracteres';
                  }
                  if (val == _currentController.text) {
                    return 'A nova senha precisa ser diferente da atual';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _confirmController,
                obscureText: _obscure,
                decoration: _decoration(
                  'Confirme a nova senha',
                  Icons.lock_reset_rounded,
                ).copyWith(suffixIcon: toggle),
                validator: (val) => val != _newController.text
                    ? 'As senhas não conferem'
                    : null,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _actions(
          context,
          isSaving: _isSaving,
          label: 'Salvar',
          onSave: _save,
        ),
      ],
    );
  }
}

/// Troca do e-mail de acesso: pede o novo e confere o(s) código(s). Com a
/// troca segura do Supabase chegam dois códigos, um em cada endereço.
class ChangeEmailSheet extends StatefulWidget {
  /// Troca já pedida antes: abre direto no passo do código.
  final String? pendingEmail;

  const ChangeEmailSheet({super.key, this.pendingEmail});

  @override
  State<ChangeEmailSheet> createState() => _ChangeEmailSheetState();
}

class _ChangeEmailSheetState extends State<ChangeEmailSheet> {
  final _emailFormKey = GlobalKey<FormState>();
  final _codeFormKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.pendingEmail ?? '',
  );
  final _codeController = TextEditingController();
  late bool _codeStep = widget.pendingEmail != null;

  /// Depois do primeiro código aceito, falta o enviado ao e-mail atual.
  bool _waitingCurrentEmailCode = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  Future<void> _request() async {
    if (!_emailFormKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await context.read<AuthCubit>().requestEmailChange(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _codeStep = true;
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError(context, e);
    }
  }

  Future<void> _confirm() async {
    if (!_codeFormKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    final cubit = context.read<AuthCubit>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final codeEmail = _waitingCurrentEmailCode
        ? (cubit.state.user?.email ?? '')
        : _emailController.text.trim();
    try {
      final done = await cubit.confirmEmailChange(
        email: codeEmail,
        code: _codeController.text,
      );
      if (!mounted) return;
      if (done) {
        navigator.pop();
        messenger.showSnackBar(
          SnackBar(
            content: Text('E-mail alterado para ${cubit.state.user?.email}.'),
            backgroundColor: AppColors.primary,
          ),
        );
        return;
      }
      setState(() {
        _waitingCurrentEmailCode = true;
        _codeController.clear();
        _isSaving = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      _showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentEmail = context.read<AuthCubit>().state.user?.email ?? '';
    final newEmail = _emailController.text.trim();

    if (!_codeStep) {
      return _SheetFrame(
        icon: Icons.alternate_email_rounded,
        title: 'Alterar e-mail',
        description:
            'Enviamos um código para o novo e-mail (e, se pedido, outro para o atual, $currentEmail). A troca só vale depois da confirmação.',
        children: [
          Form(
            key: _emailFormKey,
            child: TextFormField(
              controller: _emailController,
              autofocus: true,
              keyboardType: TextInputType.emailAddress,
              autocorrect: false,
              decoration: _decoration('Novo e-mail', Icons.email_outlined),
              validator: (val) {
                if (val == null || !_emailPattern.hasMatch(val.trim())) {
                  return 'Informe um e-mail válido';
                }
                if (val.trim().toLowerCase() == currentEmail.toLowerCase()) {
                  return 'Este já é o seu e-mail de acesso';
                }
                return null;
              },
            ),
          ),
          const SizedBox(height: 24),
          _actions(
            context,
            isSaving: _isSaving,
            label: 'Enviar código',
            onSave: _request,
          ),
        ],
      );
    }

    final target = _waitingCurrentEmailCode ? currentEmail : newEmail;
    return _SheetFrame(
      icon: Icons.mark_email_read_outlined,
      title: 'Confirmar novo e-mail',
      description: _waitingCurrentEmailCode
          ? 'Primeiro código aceito. Agora digite o código enviado para o e-mail atual, $target.'
          : 'Digite o código enviado para $target. Confira também a caixa de spam.',
      children: [
        Form(
          key: _codeFormKey,
          child: TextFormField(
            key: ValueKey(target),
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: _decoration('Código', Icons.pin_outlined),
            validator: (val) => (val == null || val.trim().length < 6)
                ? 'Digite o código de 6 dígitos'
                : null,
          ),
        ),
        const SizedBox(height: 8),
        if (!_waitingCurrentEmailCode)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _isSaving
                  ? null
                  : () => setState(() {
                      _codeStep = false;
                      _codeController.clear();
                    }),
              child: const Text('Usar outro e-mail ou reenviar'),
            ),
          ),
        const SizedBox(height: 16),
        _actions(
          context,
          isSaving: _isSaving,
          label: 'Confirmar',
          onSave: _confirm,
        ),
      ],
    );
  }
}
