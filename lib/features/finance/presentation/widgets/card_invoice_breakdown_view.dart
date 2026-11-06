import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../domain/entities/card_invoice_breakdown.dart';

/// Carrega a fatura inteira uma vez por [reloadKey] e entrega ao [builder]
/// (null enquanto carrega ou se falhar: a tela segue só com a parte da Casa).
class CardInvoiceBreakdownLoader extends StatefulWidget {
  final Object reloadKey;
  final Future<CardInvoiceBreakdown> Function()? load;
  final Widget Function(BuildContext context, CardInvoiceBreakdown? breakdown) builder;

  const CardInvoiceBreakdownLoader({super.key, required this.reloadKey, required this.load, required this.builder});

  @override
  State<CardInvoiceBreakdownLoader> createState() => _CardInvoiceBreakdownLoaderState();
}

class _CardInvoiceBreakdownLoaderState extends State<CardInvoiceBreakdownLoader> {
  Future<CardInvoiceBreakdown?>? _future;

  @override
  void initState() {
    super.initState();
    _future = _start();
  }

  @override
  void didUpdateWidget(CardInvoiceBreakdownLoader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reloadKey != widget.reloadKey) _future = _start();
  }

  Future<CardInvoiceBreakdown?>? _start() {
    final load = widget.load;
    if (load == null) return null;
    return load().then<CardInvoiceBreakdown?>((b) => b).catchError((Object _) => null);
  }

  @override
  Widget build(BuildContext context) {
    if (_future == null) return widget.builder(context, null);
    return FutureBuilder<CardInvoiceBreakdown?>(
      future: _future,
      builder: (context, snapshot) => widget.builder(context, snapshot.data),
    );
  }
}

/// A fatura inteira, parte por parte, com o total para conferir com o banco.
class CardInvoiceBreakdownView extends StatelessWidget {
  final CardInvoiceBreakdown breakdown;

  /// Nomes dos moradores, pelo id.
  final Map<String, String> memberNames;

  /// Mostra o campo para digitar o valor do banco e ver a diferença.
  final bool showBankCheck;

  const CardInvoiceBreakdownView({
    super.key,
    required this.breakdown,
    this.memberNames = const {},
    this.showBankCheck = true,
  });

  String _name(String? id) => (id == null ? null : memberNames[id]) ?? 'morador';

  static String _count(int n, String one, String many) => '$n ${n == 1 ? one : many}';

  String _label(InvoicePart part) {
    if (part.outsideFile) return 'Casa, lançado só no app';
    if (part.isRefunds) return 'Estornos e créditos';
    return switch (part.kind!) {
      InvoicePartKind.house => 'Casa',
      InvoicePartKind.loan => 'Empréstimo a ${_name(part.memberId)}',
      InvoicePartKind.personal => 'Pessoal de ${_name(part.memberId)}',
      InvoicePartKind.thirdParty => 'Pago por terceiros',
      InvoicePartKind.ignored => 'Ignorado na importação',
      InvoicePartKind.skipped => 'Fora (ciclo fechado)',
    };
  }

  String _detail(InvoicePart part) {
    if (part.outsideFile) {
      return '${_count(part.count, 'compra', 'compras')} que não ${part.count == 1 ? 'está' : 'estão'} no arquivo importado';
    }
    if (part.isRefunds) return _count(part.count, 'linha', 'linhas');
    return _count(part.count, 'compra', 'compras');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall?.copyWith(fontSize: 11, color: Colors.grey);

    if (!breakdown.hasImport) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          'Fatura ainda não importada: o app só conhece a parte da Casa '
          '(${breakdown.houseInApp.format()}). Importe o arquivo do cartão para ver a fatura inteira.',
          style: small,
        ),
      );
    }

    return Container(
      key: const Key('invoice_breakdown'),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Fatura inteira', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          for (final part in breakdown.parts)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_label(part), style: const TextStyle(fontSize: 13)),
                        Text(_detail(part), style: small),
                      ],
                    ),
                  ),
                  Text(
                    part.amount.format(),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: part.outsideFile ? AppColors.folegoWarning : null,
                    ),
                  ),
                ],
              ),
            ),
          const Divider(height: 14),
          Row(
            children: [
              const Expanded(
                child: Text('Total da fatura', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              ),
              Text(
                breakdown.total.format(),
                key: const Key('invoice_breakdown_total'),
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
            ],
          ),
          if (showBankCheck) ...[const SizedBox(height: 10), BankAmountCheck(total: breakdown.total)],
        ],
      ),
    );
  }
}

/// Campo para digitar o valor que o banco cobra e ver se bate com o app.
class BankAmountCheck extends StatefulWidget {
  final Money total;

  const BankAmountCheck({super.key, required this.total});

  @override
  State<BankAmountCheck> createState() => _BankAmountCheckState();
}

class _BankAmountCheckState extends State<BankAmountCheck> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final bank = text.isEmpty ? null : Money.parse(text);
    final difference = bank == null ? null : bank - widget.total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('invoice_bank_amount'),
          controller: _controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Valor da fatura no banco',
            hintText: 'Ex.: 3.691,72',
            prefixText: 'R\$ ',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() {}),
        ),
        if (difference != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Icon(
                difference.isZero ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                size: 16,
                color: difference.isZero ? AppColors.creditGreen : AppColors.debtRed,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  difference.isZero
                      ? 'Bate com o app.'
                      : 'Diferença de ${difference.abs().format()}: o banco cobra '
                            '${difference.isPositive ? 'mais' : 'menos'} que o app.',
                  key: const Key('invoice_bank_difference'),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: difference.isZero ? AppColors.creditGreen : AppColors.debtRed,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
