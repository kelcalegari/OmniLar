import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../finance/domain/entities/savings_vault.dart';
import '../../domain/entities/super_pix_transfer.dart';
import '../../domain/entities/transfer_settlement_resolution.dart';

class PartialPaymentDialog extends StatefulWidget {
  final SuperPixTransfer transfer;
  final List<SavingsVault> vaults;
  final TransferSettlementResolution? initialResolution;
  final ValueChanged<TransferSettlementResolution> onSave;
  final VoidCallback? onRemove;

  /// Padrão da casa para a diferença (0094). Sem ele, vira empréstimo.
  final ShortfallAction? defaultShortfallAction;

  const PartialPaymentDialog({
    super.key,
    required this.transfer,
    required this.vaults,
    this.initialResolution,
    required this.onSave,
    this.onRemove,
    this.defaultShortfallAction,
  });

  static Future<void> show({
    required BuildContext context,
    required SuperPixTransfer transfer,
    required List<SavingsVault> vaults,
    TransferSettlementResolution? initialResolution,
    required ValueChanged<TransferSettlementResolution> onSave,
    VoidCallback? onRemove,
    ShortfallAction? defaultShortfallAction,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => PartialPaymentDialog(
        transfer: transfer,
        vaults: vaults,
        initialResolution: initialResolution,
        onSave: onSave,
        onRemove: onRemove,
        defaultShortfallAction: defaultShortfallAction,
      ),
    );
  }

  @override
  State<PartialPaymentDialog> createState() => _PartialPaymentDialogState();
}

class _PartialPaymentDialogState extends State<PartialPaymentDialog> {
  late final TextEditingController _amountController;
  late ShortfallAction _selectedAction;
  late int _installmentsCount;
  late bool _loanHasNoDueDate;
  late VaultRepaymentMode _vaultRepaymentMode;
  late String? _selectedVaultId;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    final initRes = widget.initialResolution;
    if (initRes != null && initRes.isPartialPayment) {
      _amountController = TextEditingController(
        text: (initRes.amountPaid.cents / 100).toStringAsFixed(2),
      );
      _selectedAction = initRes.shortfallAction;
      _installmentsCount = initRes.loanInstallmentsCount;
      _loanHasNoDueDate = initRes.loanHasNoDueDate;
      _vaultRepaymentMode = initRes.vaultRepaymentMode;
      _selectedVaultId = initRes.vaultId ?? widget.vaults.firstOrNull?.id;
    } else {
      // Sugere pagar metade arredondada como ponto de partida
      final halfCents = (widget.transfer.amount.cents / 2).round();
      _amountController = TextEditingController(
        text: (halfCents / 100).toStringAsFixed(2),
      );
      // Padrão da casa; cobrir com caixinha só se houver caixinha
      final preferred = widget.defaultShortfallAction;
      _selectedAction = preferred == null ||
              (preferred == ShortfallAction.deductFromVault && widget.vaults.isEmpty)
          ? ShortfallAction.createP2PLoan
          : preferred;
      _installmentsCount = 1;
      _loanHasNoDueDate = false;
      _vaultRepaymentMode = VaultRepaymentMode.grant;
      _selectedVaultId = widget.vaults.firstOrNull?.id;
    }
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Money _parseInputAmount() {
    return Money.parse(_amountController.text);
  }

  void _submit() {
    final paid = _parseInputAmount();
    final total = widget.transfer.amount;

    if (paid.cents <= 0) {
      setState(() => _errorMessage = 'Informe um valor maior que zero.');
      return;
    }

    if (paid.cents >= total.cents) {
      setState(
        () => _errorMessage =
            'O valor parcial deve ser menor que o total (${total.formatted}). Para pagar tudo, feche este diálogo.',
      );
      return;
    }

    final resolution = TransferSettlementResolution(
      transferId: widget.transfer.id,
      amountExpected: total,
      amountPaid: paid,
      shortfallAction: _selectedAction,
      loanInstallmentsCount: _installmentsCount,
      loanHasNoDueDate: _loanHasNoDueDate,
      vaultId: _selectedAction == ShortfallAction.deductFromVault
          ? _selectedVaultId
          : null,
      vaultRepaymentMode: _selectedAction == ShortfallAction.deductFromVault
          ? _vaultRepaymentMode
          : VaultRepaymentMode.grant,
    );

    widget.onSave(resolution);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);
    final paid = _parseInputAmount();
    final total = widget.transfer.amount;
    final shortfallCents = total.cents - paid.cents;
    final shortfall = shortfallCents > 0
        ? Money(shortfallCents)
        : const Money.zero();

    return Padding(
      padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(maxHeight: mediaQuery.size.height * 0.88),
        decoration: BoxDecoration(
          color: theme.scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // Barra de arraste
            Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            // Cabeçalho
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.payments_outlined,
                          color: AppColors.primary,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Pagamento Parcial do Super Pix',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 16,
                            ),
                          ),
                          Text(
                            '${widget.transfer.fromMemberName} ➔ ${widget.transfer.toMemberName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            // Conteúdo Rolável
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Card de Resumo de Valores
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.grey.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Valor Calculado do Ciclo:',
                              style: TextStyle(
                                color: Colors.grey,
                                fontSize: 13,
                              ),
                            ),
                            Text(
                              total.formatted,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Campo de entrada
                        TextField(
                          controller: _amountController,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'^\d+[\.,]?\d{0,2}'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Valor Efetivamente Pago (R\$)',
                            hintText: '0,00',
                            prefixText: 'R\$ ',
                            errorText: _errorMessage,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                          ),
                          onChanged: (_) {
                            setState(() {
                              _errorMessage = null;
                            });
                          },
                        ),
                        const SizedBox(height: 12),
                        // Diferença Restante
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: shortfall.cents > 0
                                ? AppColors.debtRed.withValues(alpha: 0.08)
                                : Colors.grey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                shortfall.cents > 0
                                    ? 'Diferença não coberta:'
                                    : 'Sem diferença:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: shortfall.cents > 0
                                      ? AppColors.debtRed
                                      : Colors.grey,
                                ),
                              ),
                              Text(
                                shortfall.formatted,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                  color: shortfall.cents > 0
                                      ? AppColors.debtRed
                                      : Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Título da Seção de Resolução
                  const Text(
                    'Como resolver a diferença restante?',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Escolha o destino contábil para os ${shortfall.formatted} que faltam:',
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 12),

                  // OPÇÃO 1: Empréstimo P2P com quem recebeu (Recomendado)
                  _buildActionOption(
                    action: ShortfallAction.createP2PLoan,
                    title: 'Quem recebeu cobriu a diferença (Recomendado)',
                    subtitle:
                        '${widget.transfer.toMemberName} pagou o total e financia os ${shortfall.formatted} para ${widget.transfer.fromMemberName} via Empréstimo P2P.',
                    icon: Icons.handshake_rounded,
                    color: AppColors.primary,
                    extraWidget:
                        _selectedAction == ShortfallAction.createP2PLoan
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Checkbox(
                                      value: _loanHasNoDueDate,
                                      onChanged: (val) {
                                        setState(() {
                                          _loanHasNoDueDate = val ?? false;
                                        });
                                      },
                                    ),
                                    const Expanded(
                                      child: Text(
                                        'Sem vencimento fixo (pagar quando puder)',
                                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                  ],
                                ),
                                if (!_loanHasNoDueDate)
                                  Row(
                                    children: [
                                      const Text(
                                        'Parcelar em:',
                                        style: TextStyle(fontSize: 12),
                                      ),
                                      const SizedBox(width: 8),
                                      DropdownButton<int>(
                                        value: _installmentsCount,
                                        isDense: true,
                                        items: [1, 2, 3, 4, 6, 10, 12].map((n) {
                                          final perParcel = shortfallCents > 0
                                              ? Money(
                                                  (shortfallCents / n).round(),
                                                ).formatted
                                              : '0,00';
                                          return DropdownMenuItem<int>(
                                            value: n,
                                            child: Text(
                                              '$n x de $perParcel',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() => _installmentsCount = val);
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),

                  // OPÇÃO 2: Cobrir com Caixinha da Casa
                  _buildActionOption(
                    action: ShortfallAction.deductFromVault,
                    title: 'Cobrir com Caixinha da Casa',
                    subtitle:
                        'Retira os ${shortfall.formatted} temporariamente da Caixinha da Casa para não onerar nenhum membro agora.',
                    icon: Icons.savings_rounded,
                    color: Colors.teal,
                    extraWidget:
                        _selectedAction == ShortfallAction.deductFromVault
                        ? Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                widget.vaults.isEmpty
                                    ? const Text(
                                        'Nenhuma caixinha disponível para saque.',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.orange,
                                        ),
                                      )
                                    : DropdownButtonFormField<String>(
                                        value: _selectedVaultId,
                                        decoration: const InputDecoration(
                                          labelText: 'Caixinha de Saque',
                                          border: OutlineInputBorder(),
                                          isDense: true,
                                          contentPadding: EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 8,
                                          ),
                                        ),
                                        items: widget.vaults.map((v) {
                                          return DropdownMenuItem<String>(
                                            value: v.id,
                                            child: Text(
                                              '${v.name} (Saldo: ${v.currentBalance.formatted})',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          );
                                        }).toList(),
                                        onChanged: (val) {
                                          setState(() => _selectedVaultId = val);
                                        },
                                      ),
                                const SizedBox(height: 10),
                                const Text(
                                  'Acordo de Reposição:',
                                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 4),
                                RadioListTile<VaultRepaymentMode>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text('Fundo Perdido (não gerar dívida nem reposição)', style: TextStyle(fontSize: 12)),
                                  value: VaultRepaymentMode.grant,
                                  groupValue: _vaultRepaymentMode,
                                  onChanged: (val) => setState(() => _vaultRepaymentMode = val!),
                                ),
                                RadioListTile<VaultRepaymentMode>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text('Sem Vencimento Fixo (ir pagando à caixinha quando puder)', style: TextStyle(fontSize: 12)),
                                  value: VaultRepaymentMode.openEnded,
                                  groupValue: _vaultRepaymentMode,
                                  onChanged: (val) => setState(() => _vaultRepaymentMode = val!),
                                ),
                                RadioListTile<VaultRepaymentMode>(
                                  contentPadding: EdgeInsets.zero,
                                  dense: true,
                                  title: const Text('Parcelar Reposição (cobrado nos próximos ciclos)', style: TextStyle(fontSize: 12)),
                                  value: VaultRepaymentMode.installments,
                                  groupValue: _vaultRepaymentMode,
                                  onChanged: (val) => setState(() => _vaultRepaymentMode = val!),
                                ),
                                if (_vaultRepaymentMode == VaultRepaymentMode.installments)
                                  Padding(
                                    padding: const EdgeInsets.only(left: 12, bottom: 8),
                                    child: Row(
                                      children: [
                                        const Text('Repor em:', style: TextStyle(fontSize: 12)),
                                        const SizedBox(width: 8),
                                        DropdownButton<int>(
                                          value: _installmentsCount,
                                          isDense: true,
                                          items: [1, 2, 3, 4, 6, 10, 12].map((n) {
                                            final perParcel = shortfallCents > 0
                                                ? Money((shortfallCents / n).round()).formatted
                                                : '0,00';
                                            return DropdownMenuItem<int>(
                                              value: n,
                                              child: Text('$n x de $perParcel', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                            );
                                          }).toList(),
                                          onChanged: (val) {
                                            if (val != null) setState(() => _installmentsCount = val);
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(height: 10),

                  // OPÇÃO 3: Manter como pendência para o próximo ciclo
                  _buildActionOption(
                    action: ShortfallAction.rolloverPending,
                    title: 'Manter como pendência no próximo ciclo',
                    subtitle:
                        'O saldo de ${shortfall.formatted} não é financiado hoje e será cobrado no próximo fechamento.',
                    icon: Icons.schedule_rounded,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(height: 10),

                  // OPÇÃO 4: O credor perdoou o valor
                  _buildActionOption(
                    action: ShortfallAction.forgiveRemainder,
                    title: 'O credor perdoou o valor restante (Anistia)',
                    subtitle:
                        '${widget.transfer.toMemberName} concorda em perdoar e isentar ${widget.transfer.fromMemberName} da diferença.',
                    icon: Icons.favorite_rounded,
                    color: AppColors.creditGreen,
                  ),
                  const SizedBox(height: 24),

                  // Botão de salvar
                  FilledButton.icon(
                    onPressed: _submit,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text(
                      'Confirmar Pagamento Parcial',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),

                  // Botão de remover ajuste (se já existia)
                  if (widget.initialResolution != null &&
                      widget.onRemove != null) ...[
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: () {
                        widget.onRemove!();
                        Navigator.of(context).pop();
                      },
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.grey,
                      ),
                      label: const Text(
                        'Restaurar Pagamento Integral (100%)',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionOption({
    required ShortfallAction action,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    Widget? extraWidget,
  }) {
    final isSelected = _selectedAction == action;

    return InkWell(
      onTap: () => setState(() => _selectedAction = action),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? color.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.grey.withValues(alpha: 0.25),
            width: isSelected ? 1.5 : 1.0,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSelected ? color : null,
                    ),
                  ),
                ),
                Radio<ShortfallAction>(
                  value: action,
                  groupValue: _selectedAction,
                  activeColor: color,
                  onChanged: (val) {
                    if (val != null) setState(() => _selectedAction = val);
                  },
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28),
              child: Text(
                subtitle,
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ),
            if (extraWidget != null)
              Padding(
                padding: const EdgeInsets.only(left: 28),
                child: extraWidget,
              ),
          ],
        ),
      ),
    );
  }
}
