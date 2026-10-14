import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../capture/domain/services/boleto_code.dart';

/// Código do boleto de uma conta ou fatura: mostra para copiar e deixa
/// informar, trocar ou apagar. O código é conferido antes de ir para [onSave].
class BillCodeField extends StatefulWidget {
  /// Linha digitável guardada (null = sem código).
  final String? code;

  /// Grava a linha digitável conferida, ou null para apagar. Devolve se gravou.
  final Future<bool> Function(String? line) onSave;
  final bool enabled;

  const BillCodeField({super.key, required this.code, required this.onSave, this.enabled = true});

  @override
  State<BillCodeField> createState() => _BillCodeFieldState();
}

class _BillCodeFieldState extends State<BillCodeField> {
  late String? _code = widget.code;
  final _controller = TextEditingController();
  bool _editing = false;
  bool _saving = false;
  String? _error;

  @override
  void didUpdateWidget(BillCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code && !_editing) _code = widget.code;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _startEditing() => setState(() {
        _controller.text = _code ?? '';
        _error = null;
        _editing = true;
      });

  Future<void> _save() async {
    final digits = BoletoCodeReader.digitsOf(_controller.text);
    String? line;
    if (digits.isNotEmpty) {
      try {
        line = BoletoCodeReader.read(digits).digitableLine;
      } on BoletoCodeError catch (e) {
        setState(() => _error = e.message);
        return;
      }
    }
    setState(() => _saving = true);
    final ok = await widget.onSave(line);
    if (!mounted) return;
    setState(() {
      _saving = false;
      if (ok) {
        _code = line;
        _editing = false;
      } else {
        _error = 'Não foi possível guardar o código.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.enabled && !_saving;
    if (_editing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const Key('bill_code_input'),
            controller: _controller,
            enabled: enabled,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: 'Código do boleto',
              hintText: 'Cole a linha digitável (vazio apaga)',
              prefixIcon: const Icon(Icons.qr_code_2_rounded),
              errorText: _error,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: enabled ? () => setState(() => _editing = false) : null,
                child: const Text('Cancelar'),
              ),
              FilledButton.tonal(
                key: const Key('bill_code_save'),
                onPressed: enabled ? _save : null,
                child: Text(_saving ? 'Guardando...' : 'Guardar código'),
              ),
            ],
          ),
        ],
      );
    }

    final code = _code;
    if (code == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('bill_code_add'),
          icon: const Icon(Icons.qr_code_2_rounded, size: 18),
          label: const Text('Informar código do boleto'),
          onPressed: enabled ? _startEditing : null,
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: SelectableText(code, style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
          IconButton(
            key: const Key('bill_code_copy'),
            tooltip: 'Copiar código',
            icon: const Icon(Icons.copy_rounded, size: 18),
            onPressed: () => copyWithFeedback(
              context,
              code,
              onCopied: const SnackBar(content: Text('Código do boleto copiado.')),
            ),
          ),
          IconButton(
            key: const Key('bill_code_edit'),
            tooltip: 'Trocar ou apagar o código',
            icon: const Icon(Icons.edit_rounded, size: 18),
            onPressed: enabled ? _startEditing : null,
          ),
        ],
      ),
    );
  }
}
