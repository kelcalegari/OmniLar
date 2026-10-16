import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../data/push/push_service.dart';

/// "Ativar notificações" nos Ajustes. A permissão só é pedida pelo toque no
/// botão (o Safari do iPhone exige), e no iPhone fora do site instalado
/// aparece o passo a passo para instalar.
class PushSettingsBlock extends StatefulWidget {
  /// Permite trocar o serviço nos testes.
  final PushService? service;

  const PushSettingsBlock({super.key, this.service});

  @override
  State<PushSettingsBlock> createState() => _PushSettingsBlockState();
}

class _PushSettingsBlockState extends State<PushSettingsBlock> {
  late final PushService _service = widget.service ?? sl<PushService>();
  PushStatus? _status;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _service.status().then((s) {
      if (mounted) setState(() => _status = s);
    });
  }

  Future<void> _enable() async {
    setState(() => _busy = true);
    final result = await _service.enable();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = result;
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Os avisos sempre aparecem no sino da Casa. Ativando aqui, eles chegam também neste aparelho, mesmo com o app fechado.',
            style: TextStyle(color: Colors.grey, fontSize: 13),
          ),
          const SizedBox(height: 12),
          if (status == null)
            const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
          else
            ..._forStatus(context, status),
        ],
      ),
    );
  }

  List<Widget> _forStatus(BuildContext context, PushStatus status) {
    switch (status) {
      case PushStatus.enabled:
        return const [
          _Line(icon: Icons.notifications_active_rounded, color: AppColors.creditGreen,
              text: 'Notificações ativadas neste aparelho.'),
        ];
      case PushStatus.notDetermined:
        return [
          FilledButton.icon(
            onPressed: _busy ? null : _enable,
            icon: _busy
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.notifications_rounded),
            label: const Text('Ativar notificações'),
          ),
        ];
      case PushStatus.denied:
        return [
          const _Line(icon: Icons.notifications_off_rounded, color: AppColors.folegoWarning,
              text: 'As notificações foram bloqueadas neste aparelho.'),
          const SizedBox(height: 8),
          Text(_deniedHelp(), style: const TextStyle(fontSize: 13)),
        ];
      case PushStatus.needsInstall:
        return const [
          _Line(icon: Icons.ios_share_rounded, color: AppColors.primary,
              text: 'No iPhone, as notificações chegam com o Omni Lar instalado na Tela de Início (iOS 16.4 ou mais novo):'),
          SizedBox(height: 8),
          _Step(n: 1, text: 'No Safari, toque em Compartilhar (o quadrado com a seta para cima).'),
          _Step(n: 2, text: 'Escolha "Adicionar à Tela de Início" e confirme.'),
          _Step(n: 3, text: 'Abra o Omni Lar pelo ícone novo e volte a esta tela para ativar.'),
        ];
      case PushStatus.unsupported:
        return [
          _Line(
            icon: Icons.info_outline_rounded,
            color: Colors.grey,
            text: _service.isDemoMode()
                ? 'No modo demonstração as notificações ficam só no sino.'
                : 'Este aparelho não recebe notificações. Elas continuam no sino.',
          ),
        ];
    }
  }

  String _deniedHelp() {
    if (kIsWeb && _service.environment.isIos) {
      return 'Para reativar: Ajustes do iPhone › Notificações › Omni Lar › Permitir Notificações.';
    }
    if (kIsWeb) {
      return 'Para reativar: toque no cadeado ao lado do endereço do site, em Notificações escolha Permitir e recarregue a página.';
    }
    return 'Para reativar: Configurações do Android › Apps › Omni Lar › Notificações.';
  }
}

class _Line extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String text;

  const _Line({required this.icon, required this.color, required this.text});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  final int n;
  final String text;

  const _Step({required this.n, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 30, bottom: 6),
      child: Text('$n. $text', style: const TextStyle(fontSize: 13)),
    );
  }
}
