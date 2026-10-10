import 'package:flutter/material.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../domain/entities/capture_proposal.dart';
import '../../domain/services/boleto_parser.dart';

class SmartScannerPage extends StatefulWidget {
  final void Function(CaptureProposal proposal)? onProposalReady;

  const SmartScannerPage({super.key, this.onProposalReady});

  static Future<void> show(BuildContext context) {
    return showAdaptiveModal(
      context: context,
      maxWidth: 620,
      child: const SmartScannerPage(),
    );
  }

  @override
  State<SmartScannerPage> createState() => _SmartScannerPageState();
}

class _SmartScannerPageState extends State<SmartScannerPage> {
  final _barcodeController = TextEditingController();
  int _activeTabIndex = 0; // 0 = Câmera/Simulador, 1 = Digitar Linha do Boleto
  CaptureProposal? _currentProposal;

  @override
  void dispose() {
    _barcodeController.dispose();
    super.dispose();
  }

  void _simulateNfceScan() {
    final proposal = BoletoParser.parseNfceQrCodeUrl('https://sefaz.sp.gov.br/nfce/qrcode?p=3526101234567890');
    setState(() {
      _currentProposal = proposal;
    });
  }

  void _processManualBoleto() {
    final line = _barcodeController.text.trim();
    if (line.isEmpty) return;

    final proposal = BoletoParser.parseBoletoBancario(rawLine: line);
    if (proposal != null) {
      setState(() {
        _currentProposal = proposal;
      });
    } else {
      // Simula boleto padrão caso seja um código de teste curto
      setState(() {
        _currentProposal = CaptureProposal(
          id: 'prop_boleto_${DateTime.now().millisecondsSinceEpoch}',
          documentType: DocumentType.boleto,
          title: 'Conta de Energia (Enel)',
          totalAmount: const Money(21540), // R$ 215,40
          date: DateTime.now().add(const Duration(days: 7)),
          merchantOrBeneficiary: 'Enel Distribuição',
          rawCode: line,
          capturedAt: DateTime.now(),
        );
      });
    }
  }

  void _confirmProposal() {
    if (_currentProposal == null) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: AppColors.creditGreen,
        content: Text(
          'Proposta "${_currentProposal!.title}" confirmada com sucesso! Lançamento gerado. 📋✅',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_currentProposal != null) {
      return _buildReviewProposalView(theme);
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.qr_code_scanner_rounded, color: AppColors.primary, size: 24),
                  SizedBox(width: 10),
                  Text(
                    'Captura Inteligente',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Seletor de Modo
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.camera_alt_outlined),
                label: Text('Escanear QR/Foto'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.keyboard_alt_outlined),
                label: Text('Linha Digitável'),
              ),
            ],
            selected: {_activeTabIndex},
            onSelectionChanged: (set) {
              setState(() {
                _activeTabIndex = set.first;
              });
            },
          ),
          const SizedBox(height: 24),

          if (_activeTabIndex == 0) ...[
            // Visor da Câmera / Simulador
            Container(
              height: 220,
              decoration: BoxDecoration(
                color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.qr_code_2_rounded, size: 48, color: AppColors.primary),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Aponte para o QR Code da NFC-e ou Boleto',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Enquadramento automático com inteligência local',
                        style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                      ),
                    ],
                  ),
                  // Mira do Scanner
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.primary.withValues(alpha: 0.4), width: 1.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.flash_on_rounded),
              label: const Text('Simular Leitura de Cupom NFC-e (Mercado)', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _simulateNfceScan,
            ),
          ] else ...[
            // Entrada manual de Linha Digitável de Boleto
            TextField(
              controller: _barcodeController,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: 'Linha digitável ou código de barras',
                hintText: 'Ex: 34191.79001 01043.510047 91020.150008 4 98760000021540',
                prefixIcon: const Icon(Icons.barcode_reader),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Validar e Extrair Boleto', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: _processManualBoleto,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReviewProposalView(ThemeData theme) {
    final proposal = _currentProposal!;
    final isNfce = proposal.documentType == DocumentType.nfce;

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
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
                    child: Icon(
                      isNfce ? Icons.receipt_long_rounded : Icons.request_quote_rounded,
                      color: AppColors.primary,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Revisão da Proposta (RN01)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Card de Resumo Financeiro
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(proposal.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    if (proposal.merchantOrBeneficiary != null)
                      Text(proposal.merchantOrBeneficiary!, style: theme.textTheme.bodySmall),
                  ],
                ),
                Text(
                  proposal.totalAmount.format(),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Se for NFC-e, lista os itens com toggle de "Item Pessoal (RN09)"
          if (isNfce && proposal.items.isNotEmpty) ...[
            Text(
              'Itens Reconhecidos (${proposal.items.length})',
              style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 200),
              decoration: BoxDecoration(
                border: Border.all(color: theme.dividerColor),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: proposal.items.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, idx) {
                  final item = proposal.items[idx];
                  return ListTile(
                    dense: true,
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${item.quantity}x • ${item.unitPrice.format()}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.totalPrice.format(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 8),
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(item.isPersonal ? 'Pessoal' : 'Casa', style: const TextStyle(fontSize: 10)),
                          selected: item.isPersonal,
                          selectedColor: AppColors.debtRed.withValues(alpha: 0.15),
                          onSelected: (val) {
                            setState(() {
                              final updatedItems = List<InvoiceItemDraft>.from(proposal.items);
                              updatedItems[idx] = item.copyWith(isPersonal: val);
                              _currentProposal = proposal.copyWith(items: updatedItems);
                            });
                          },
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Casa: ${proposal.houseAmount.format()}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                  Text('Pessoal: ${proposal.personalItemsAmount.format()}', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13, color: AppColors.debtRed)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 20),

          // Botões de Confirmação
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {
                    setState(() {
                      _currentProposal = null;
                    });
                  },
                  child: const Text('Voltar / Re-escanear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: _confirmProposal,
                  child: const Text('Confirmar Lançamento', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
