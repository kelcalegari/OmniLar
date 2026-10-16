import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_colors.dart';
import '../cubit/auth_cubit.dart';

/// "Esqueci minha senha": pede o e-mail, envia um código e troca a senha com
/// ele. Ao terminar, a pessoa já entra (o roteador leva para a casa).
class ResetPasswordPage extends StatefulWidget {
  final String? initialEmail;

  const ResetPasswordPage({super.key, this.initialEmail});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  static const _resendCooldown = 60;
  static final _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

  final _emailFormKey = GlobalKey<FormState>();
  final _resetFormKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail ?? '',
  );
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  bool _codeSent = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  Timer? _timer;
  int _secondsLeft = 0;

  @override
  void dispose() {
    _timer?.cancel();
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _startCooldown() {
    _timer?.cancel();
    setState(() => _secondsLeft = _resendCooldown);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _secondsLeft--);
      if (_secondsLeft <= 0) timer.cancel();
    });
  }

  void _showError(Object e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(e.toString()), backgroundColor: AppColors.debtRed),
    );
  }

  Future<void> _sendCode() async {
    if (!(_emailFormKey.currentState?.validate() ?? true)) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthCubit>().requestPasswordReset(
        _emailController.text.trim(),
      );
      if (!mounted) return;
      setState(() => _codeSent = true);
      _startCooldown();
    } catch (e) {
      if (mounted) _showError(e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _resetPassword() async {
    if (!_resetFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      await context.read<AuthCubit>().resetPasswordWithCode(
        email: _emailController.text.trim(),
        code: _codeController.text,
        newPassword: _passwordController.text,
      );
      // Sucesso: o roteador sai desta tela sozinho
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError(e);
    }
  }

  InputDecoration _decoration(String label, IconData icon) => InputDecoration(
    labelText: label,
    prefixIcon: Icon(icon),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
  );

  Widget _primaryButton(String label, VoidCallback onPressed) {
    return ElevatedButton(
      onPressed: _isLoading ? null : onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        elevation: 0,
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }

  List<Widget> _emailStep() => [
    const Text(
      'Digite o e-mail da sua conta. Se ele estiver cadastrado, enviamos um código para você criar uma senha nova.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 14, color: Colors.grey),
    ),
    const SizedBox(height: 28),
    Form(
      key: _emailFormKey,
      child: TextFormField(
        controller: _emailController,
        autofocus: true,
        keyboardType: TextInputType.emailAddress,
        autocorrect: false,
        autofillHints: const [AutofillHints.email],
        decoration: _decoration('E-mail', Icons.email_outlined),
        validator: (val) {
          if (val == null || !_emailPattern.hasMatch(val.trim())) {
            return 'Informe um e-mail válido';
          }
          return null;
        },
        onFieldSubmitted: (_) => _isLoading ? null : _sendCode(),
      ),
    ),
    const SizedBox(height: 20),
    _primaryButton('Enviar código', _sendCode),
  ];

  List<Widget> _resetStep() => [
    Text.rich(
      TextSpan(
        text: 'Se houver uma conta com ',
        children: [
          TextSpan(
            text: _emailController.text.trim(),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const TextSpan(
            text:
                ', enviamos um código para ela. Confira também a caixa de spam.',
          ),
        ],
      ),
      textAlign: TextAlign.center,
      style: const TextStyle(fontSize: 14, color: Colors.grey),
    ),
    const SizedBox(height: 28),
    Form(
      key: _resetFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _codeController,
            autofocus: true,
            keyboardType: TextInputType.number,
            autofillHints: const [AutofillHints.oneTimeCode],
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: _decoration('Código', Icons.pin_outlined),
            validator: (val) {
              if (val == null || val.trim().length < 6) {
                return 'Digite o código de 6 dígitos';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _passwordController,
            obscureText: _obscurePassword,
            autofillHints: const [AutofillHints.newPassword],
            decoration: _decoration('Nova senha', Icons.lock_outline_rounded)
                .copyWith(
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                ),
            validator: (val) {
              if (val == null || val.length < 6) {
                return 'A senha deve ter no mínimo 6 caracteres';
              }
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscurePassword,
            decoration: _decoration(
              'Confirme a nova senha',
              Icons.lock_outline_rounded,
            ),
            validator: (val) {
              if (val != _passwordController.text) {
                return 'As senhas não conferem';
              }
              return null;
            },
            onFieldSubmitted: (_) => _isLoading ? null : _resetPassword(),
          ),
        ],
      ),
    ),
    const SizedBox(height: 20),
    _primaryButton('Salvar senha e entrar', _resetPassword),
    const SizedBox(height: 12),
    TextButton(
      onPressed: _isLoading || _secondsLeft > 0 ? null : _sendCode,
      child: Text(
        _secondsLeft > 0
            ? 'Reenviar código em ${_secondsLeft}s'
            : 'Reenviar código',
      ),
    ),
    TextButton(
      onPressed: _isLoading
          ? null
          : () => setState(() {
              _codeSent = false;
              _codeController.clear();
            }),
      child: const Text('Usar outro e-mail'),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
          tooltip: 'Voltar',
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/login'),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.lock_reset_rounded,
                    size: 64,
                    color: AppColors.primary,
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Esqueci minha senha',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 10),
                  ...(_codeSent ? _resetStep() : _emailStep()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
