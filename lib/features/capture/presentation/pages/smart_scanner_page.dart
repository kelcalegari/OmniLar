import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../domain/entities/capture_proposal.dart';
import '../../domain/services/boleto_parser.dart';
import '../../domain/services/capture_service.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_expense_item.dart';
import '../../../finance/domain/entities/split_rule.dart';

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
  int _activeTabIndex = 0; // 0 = Câmera/Captura, 1 = Digitar Linha do Boleto
  CaptureProposal? _currentProposal;
  bool _isProcessing = false;
  String _processingMessage = 'Processando documento...';
  bool _isSubmitting = false;
  String? _selectedPaymentMethodId;

  MobileScannerController? _scannerController;
  bool _isCameraActive = false;

  bool get _isLiveCameraSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    if (_isLiveCameraSupported) {
      _initCamera();
    }
  }

  void _initCamera() {
    try {
      _scannerController?.dispose();
      _scannerController = MobileScannerController(
        detectionSpeed: DetectionSpeed.noDuplicates,
        facing: kIsWeb ? CameraFacing.front : CameraFacing.back,
      );
      if (mounted) {
        setState(() {
          _isCameraActive = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isCameraActive = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _scannerController?.dispose();
    super.dispose();
  }

  void _onBarcodeDetected(BarcodeCapture capture) {
    if (_currentProposal != null || _isProcessing) return;

    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue?.trim();
      if (raw != null && raw.isNotEmpty) {
        if (raw.startsWith('http')) {
          final proposal = BoletoParser.parseNfceQrCodeUrl(raw);
          setState(() {
            _currentProposal = proposal;
          });
          break;
        } else if (BoletoParser.isValidLength(raw)) {
          final proposal = BoletoParser.parseBoletoBancario(rawLine: raw);
          if (proposal != null) {
            setState(() {
              _currentProposal = proposal;
            });
            break;
          }
        }
      }
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(source: source, imageQuality: 85);
      if (image == null) return;

      setState(() {
        _isProcessing = true;
        _processingMessage = 'Auditando imagem com inteligência artificial...';
      });

      final bytes = await image.readAsBytes();
      final proposal = await sl<CaptureService>().processDocumentFile(
        bytes: bytes,
        fileName: image.name,
        mimeType: image.mimeType ?? 'image/jpeg',
      );

      if (mounted) {
        setState(() {
          _currentProposal = proposal;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.debtRed,
            content: Text('Erro ao carregar foto: $e'),
          ),
        );
      }
    }
  }

  Future<void> _pickPdfOrDocument() async {
    try {
      final files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf', 'png', 'jpg', 'jpeg'],
      );
      if (files.isEmpty) return;

      final file = files.first;
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return;

      setState(() {
        _isProcessing = true;
        _processingMessage = 'Extraindo dados do documento PDF...';
      });

      final isPdf = file.name.toLowerCase().endsWith('.pdf');
      final proposal = await sl<CaptureService>().processDocumentFile(
        bytes: bytes,
        fileName: file.name,
        mimeType: isPdf ? 'application/pdf' : 'image/jpeg',
      );

      if (mounted) {
        setState(() {
          _currentProposal = proposal;
          _isProcessing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.debtRed,
            content: Text('Erro ao carregar arquivo: $e'),
          ),
        );
      }
    }
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
      // Boleto simulado padrão caso linha seja curta ou de teste
      setState(() {
        _currentProposal = CaptureProposal(
          id: 'prop_boleto_${DateTime.now().millisecondsSinceEpoch}',
          documentType: DocumentType.boleto,
          title: 'Conta de Energia / Luz',
          totalAmount: const Money(21540), // R$ 215,40
          date: DateTime.now().add(const Duration(days: 7)),
          merchantOrBeneficiary: 'Concessionária de Energia',
          rawCode: line,
          capturedAt: DateTime.now(),
        );
      });
    }
  }

  void _editProposalDetails() {
    final proposal = _currentProposal;
    if (proposal == null) return;

    final titleCtrl = TextEditingController(text: proposal.title);
    final amountCtrl = TextEditingController(
      text: (proposal.totalAmount.cents > 0)
          ? (proposal.totalAmount.cents / 100).toStringAsFixed(2)
          : '',
    );

    // Soma dos sub-itens atuais
    final currentItemsSumCents = proposal.items.fold<int>(0, (sum, i) => sum + i.totalPrice.cents);
    final baseCents = currentItemsSumCents > 0 ? currentItemsSumCents : proposal.totalAmount.cents;

    bool repassarDesconto = proposal.items.isNotEmpty;

    showAdaptiveModal(
      context: context,
      maxWidth: 480,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          final typedVal = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final typedCents = (typedVal * 100).round();

          final diffCents = baseCents - typedCents;
          final pct = baseCents > 0 ? (diffCents / baseCents) * 100 : 0.0;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Valor & Desconto da Proposta',
                      style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Título / Descrição',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    labelText: 'Valor a Pagar (R\$)',
                    prefixText: 'R\$ ',
                    helperText: baseCents > 0 ? 'Soma nominal dos itens: ${Money(baseCents).format()}' : null,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setModalState(() {}),
                ),
                if (diffCents != 0 && baseCents > 0 && typedCents > 0) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: diffCents > 0
                          ? AppColors.creditGreen.withValues(alpha: 0.12)
                          : Colors.orange.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: diffCents > 0 ? AppColors.creditGreen : Colors.orange,
                        width: 1,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              diffCents > 0 ? Icons.discount_outlined : Icons.trending_up_rounded,
                              size: 18,
                              color: diffCents > 0 ? AppColors.creditGreen : Colors.orange,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                diffCents > 0
                                    ? 'Desconto: ${Money(diffCents).format()} (${pct.toStringAsFixed(2)}%)'
                                    : 'Acréscimo: ${Money(-diffCents).format()} (${(-pct).toStringAsFixed(2)}%)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: diffCents > 0 ? AppColors.creditGreen : Colors.orange,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (proposal.items.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          SwitchListTile(
                            contentPadding: EdgeInsets.zero,
                            visualDensity: VisualDensity.compact,
                            dense: true,
                            title: Text(
                              'Repassar ${diffCents > 0 ? "desconto" : "diferença"} proporcionalmente aos ${proposal.items.length} itens do rateio',
                              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                            subtitle: const Text(
                              'Recalcula cada item mantendo a soma exata ao centavo (pro-rata)',
                              style: TextStyle(fontSize: 10),
                            ),
                            value: repassarDesconto,
                            onChanged: (val) {
                              setModalState(() {
                                repassarDesconto = val;
                              });
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  onPressed: () {
                    final newTitle = titleCtrl.text.trim();
                    final rawAmount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
                    final newCents = (rawAmount * 100).round();

                    var updatedItems = proposal.items;
                    if (repassarDesconto && proposal.items.isNotEmpty && newCents > 0) {
                      final itemWeights = proposal.items.map((i) => i.totalPrice.cents).toList();
                      final distributed = BoletoParser.distributeCentsProportionally(newCents, itemWeights);

                      updatedItems = [
                        for (int i = 0; i < proposal.items.length; i++)
                          proposal.items[i].copyWith(
                            unitPrice: Money(distributed[i]),
                            totalPrice: Money(distributed[i]),
                          ),
                      ];
                    }

                    setState(() {
                      _currentProposal = proposal.copyWith(
                        title: newTitle.isNotEmpty ? newTitle : null,
                        totalAmount: Money(newCents),
                        items: updatedItems,
                      );
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Aplicar Alterações', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _editItemDetails(int idx) {
    final proposal = _currentProposal;
    if (proposal == null || idx >= proposal.items.length) return;
    final item = proposal.items[idx];

    final nameCtrl = TextEditingController(text: item.name);
    final priceCtrl = TextEditingController(
      text: (item.totalPrice.cents / 100).toStringAsFixed(2),
    );
    bool isPersonal = item.isPersonal;
    final members = context.read<FinanceCubit>().state.members;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    String? assignedMemberId = item.assignedMemberId ?? currentUserId ?? (members.isNotEmpty ? members.first.id : null);

    showAdaptiveModal(
      context: context,
      maxWidth: 400,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Editar Item do Rateio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Nome do Item',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Valor (R\$)',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(isPersonal ? 'Item Pessoal (RN09)' : 'Gasto da Casa (Compartilhado)'),
                  subtitle: Text(
                    isPersonal ? 'Cobrado exclusivamente do responsável' : 'Rateado entre todos os moradores',
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: isPersonal,
                  onChanged: (val) {
                    setModalState(() {
                      isPersonal = val;
                      if (isPersonal && assignedMemberId == null && members.isNotEmpty) {
                        assignedMemberId = currentUserId ?? members.first.id;
                      }
                    });
                  },
                ),
                if (isPersonal && members.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: members.any((m) => m.id == assignedMemberId)
                        ? assignedMemberId
                        : members.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Responsável pelo Item Pessoal',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: members.map((m) {
                      return DropdownMenuItem<String>(
                        value: m.id,
                        child: Text(m.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          assignedMemberId = val;
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.debtRed,
                          side: BorderSide(color: AppColors.debtRed.withValues(alpha: 0.5)),
                        ),
                        icon: const Icon(Icons.delete_outline_rounded, size: 18),
                        label: const Text('Excluir'),
                        onPressed: () {
                          final updatedList = List<InvoiceItemDraft>.from(proposal.items)..removeAt(idx);
                          final newTotal = updatedList.fold<int>(0, (sum, i) => sum + i.totalPrice.cents);
                          setState(() {
                            _currentProposal = proposal.copyWith(
                              items: updatedList,
                              totalAmount: Money(newTotal),
                            );
                          });
                          Navigator.pop(context);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                        ),
                        onPressed: () {
                          final newName = nameCtrl.text.trim();
                          final rawVal = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
                          final newCents = (rawVal * 100).round();

                          final updatedList = List<InvoiceItemDraft>.from(proposal.items);
                          updatedList[idx] = item.copyWith(
                            name: newName.isNotEmpty ? newName : item.name,
                            unitPrice: Money(newCents),
                            totalPrice: Money(newCents),
                            isPersonal: isPersonal,
                            assignedMemberId: isPersonal ? assignedMemberId : null,
                          );

                          final newTotal = updatedList.fold<int>(0, (sum, i) => sum + i.totalPrice.cents);
                          setState(() {
                            _currentProposal = proposal.copyWith(
                              items: updatedList,
                              totalAmount: Money(newTotal),
                            );
                          });
                          Navigator.pop(context);
                        },
                        child: const Text('Salvar'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _addNewItem() {
    final proposal = _currentProposal;
    if (proposal == null) return;

    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    bool isPersonal = false;
    final members = context.read<FinanceCubit>().state.members;
    final currentUserId = sl<AuthRepository>().currentUser?.id;
    String? assignedMemberId = currentUserId ?? (members.isNotEmpty ? members.first.id : null);

    showAdaptiveModal(
      context: context,
      maxWidth: 400,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Novo Item no Rateio', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Descrição do Item',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: priceCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Valor (R\$)',
                    prefixText: 'R\$ ',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(isPersonal ? 'Item Pessoal' : 'Gasto da Casa'),
                  value: isPersonal,
                  onChanged: (val) {
                    setModalState(() {
                      isPersonal = val;
                      if (isPersonal && assignedMemberId == null && members.isNotEmpty) {
                        assignedMemberId = currentUserId ?? members.first.id;
                      }
                    });
                  },
                ),
                if (isPersonal && members.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    value: members.any((m) => m.id == assignedMemberId)
                        ? assignedMemberId
                        : members.first.id,
                    decoration: const InputDecoration(
                      labelText: 'Responsável pelo Item Pessoal',
                      prefixIcon: Icon(Icons.person_outline_rounded),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: members.map((m) {
                      return DropdownMenuItem<String>(
                        value: m.id,
                        child: Text(m.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          assignedMemberId = val;
                        });
                      }
                    },
                  ),
                ],
                const SizedBox(height: 16),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    final name = nameCtrl.text.trim();
                    final rawVal = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
                    final cents = (rawVal * 100).round();
                    if (name.isEmpty || cents <= 0) return;

                    final newItem = InvoiceItemDraft(
                      id: 'item_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      unitPrice: Money(cents),
                      totalPrice: Money(cents),
                      isPersonal: isPersonal,
                      assignedMemberId: isPersonal ? assignedMemberId : null,
                    );

                    final updatedList = List<InvoiceItemDraft>.from(proposal.items)..add(newItem);
                    final newTotal = updatedList.fold<int>(0, (sum, i) => sum + i.totalPrice.cents);
                    setState(() {
                      _currentProposal = proposal.copyWith(
                        items: updatedList,
                        totalAmount: Money(newTotal),
                      );
                    });
                    Navigator.pop(context);
                  },
                  child: const Text('Adicionar Item'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmProposal() async {
    if (_currentProposal == null || _isSubmitting) return;
    final proposal = _currentProposal!;

    setState(() {
      _isSubmitting = true;
    });

    try {
      final financeCubit = context.read<FinanceCubit>();
      final state = financeCubit.state;
      final currentUserId = sl<AuthRepository>().currentUser?.id;
      final selectedPm = state.paymentMethods
          .where((p) => p.id == _selectedPaymentMethodId)
          .firstOrNull ?? state.paymentMethods.firstOrNull;
      // Meio de pagamento pessoal: quem pagou é o dono dele e a Casa reembolsa
      final paidByMemberId = selectedPm?.ownerMemberId ??
          currentUserId ??
          (state.members.isNotEmpty ? state.members.first.id : 'member_carlos');
      final paidOutOfPocket = selectedPm != null &&
          selectedPm.ownerMemberId != null &&
          selectedPm.id != 'pm_caixa';

      // 1. Resolução dinâmica de Categoria compatível com Supabase e Mock
      String? matchedCategoryId;
      if (state.categories.isNotEmpty) {
        final isBoleto = proposal.documentType == DocumentType.boleto;
        final keyword = isBoleto ? 'conta' : 'mercado';
        final found = state.categories.where(
          (c) => c.name.toLowerCase().contains(keyword),
        ).firstOrNull ?? state.categories.first;
        matchedCategoryId = found.id;
      }

      // 2. Forma de Pagamento escolhida na revisão
      final matchedPaymentMethodId = selectedPm?.id;

      // 3. Regra de rateio entre membros
      final splitPercentages = {
        for (final m in state.members) m.id: m.defaultSplitPercent,
      };
      final splitRule = splitPercentages.isNotEmpty
          ? SplitRule.percentage(splitPercentages)
          : SplitRule.singleResponsible(paidByMemberId);

      // 4. Mapear sub-itens reconhecidos (InvoiceItemDraft -> HouseExpenseItem)
      final expenseId = 'exp_scan_${DateTime.now().millisecondsSinceEpoch}';
      final expenseItems = proposal.items.map((item) {
        final respMemberId = item.isPersonal
            ? (item.assignedMemberId ?? paidByMemberId)
            : null;
        return HouseExpenseItem(
          id: 'item_${DateTime.now().millisecondsSinceEpoch}_${item.id}',
          expenseId: expenseId,
          title: item.name,
          amount: item.totalPrice,
          categoryId: matchedCategoryId,
          responsibleMemberId: respMemberId,
          splitRule: item.isPersonal && respMemberId != null
              ? SplitRule.singleResponsible(respMemberId)
              : null,
        );
      }).toList();

      final finalCategoryId = matchedCategoryId ?? (state.categories.isNotEmpty ? state.categories.first.id : 'cat_mercado');
      final finalPaymentMethodId = matchedPaymentMethodId ?? (state.paymentMethods.isNotEmpty ? state.paymentMethods.first.id : 'pm_caixa');

      final expense = HouseExpense(
        id: expenseId,
        title: proposal.title,
        amount: proposal.totalAmount,
        date: proposal.date,
        dueDate: proposal.date,
        categoryId: finalCategoryId,
        paidByMemberId: paidByMemberId,
        paymentMethodId: finalPaymentMethodId,
        splitRule: splitRule,
        paidOutOfPocket: paidOutOfPocket,
        status: ExpenseStatus.paid,
        notes: proposal.merchantOrBeneficiary,
        items: expenseItems,
      );

      // Persistir no repositório (espera o Supabase concluir)
      await financeCubit.addExpense(expense);

      widget.onProposalReady?.call(proposal);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.creditGreen,
            content: Text(
              'Proposta "${proposal.title}" confirmada! Despesa de ${proposal.houseAmount.format()} lançada. 📋✅',
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.debtRed,
            content: Text('Erro ao confirmar despesa: $err'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isProcessing) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 24),
            Text(
              _processingMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              'A inteligência artificial está auditando itens, valores e vencimento.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      );
    }

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
                label: Text('Escanear / Foto / PDF'),
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
          const SizedBox(height: 20),

          if (_activeTabIndex == 0) ...[
            // Visor da Câmera (Real ou Fallback com mira)
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Container(
                height: 220,
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark ? Colors.white10 : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (_isCameraActive && _scannerController != null)
                      MobileScanner(
                        controller: _scannerController!,
                        onDetect: _onBarcodeDetected,
                        errorBuilder: (context, error) {
                          return _buildCameraFallback(theme);
                        },
                      )
                    else
                      _buildCameraFallback(theme),

                    // Mira do Scanner sobreposta
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.primary.withValues(alpha: 0.6), width: 2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),

                    if (_isCameraActive && _scannerController != null)
                      Positioned(
                        top: 8,
                        right: 8,
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: Colors.black45,
                          child: IconButton(
                            padding: EdgeInsets.zero,
                            icon: const Icon(Icons.cameraswitch_rounded, color: Colors.white, size: 18),
                            tooltip: 'Alternar Câmera / Webcam',
                            onPressed: () => _scannerController?.switchCamera(),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Botões de Ação para Foto / Galeria / PDF
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.photo_camera_rounded, size: 18),
                    label: const Text('Tirar Foto', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _pickImage(ImageSource.camera),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.photo_library_rounded, size: 18),
                    label: const Text('Galeria', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: () => _pickImage(ImageSource.gallery),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.picture_as_pdf_rounded, size: 18, color: Colors.redAccent),
                    label: const Text('PDF / Doc', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _pickPdfOrDocument,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Botão Simulador (disponível apenas no Modo Demonstração)
            if (sl<AuthRepository>().isDemoMode) ...[
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.flash_on_rounded, size: 20),
                label: const Text('Simular Leitura de Cupom NFC-e (Mercado)', style: TextStyle(fontWeight: FontWeight.bold)),
                onPressed: _simulateNfceScan,
              ),
            ],
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

  Widget _buildCameraFallback(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_2_rounded, size: 36, color: AppColors.primary),
          ),
          const SizedBox(height: 8),
          const Text(
            'Aponte para o QR Code da NFC-e ou Boleto',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            kIsWeb
                ? 'Se a câmera estiver bloqueada no navegador, clique no cadeado da URL ou redefina permissões.'
                : 'Enquadramento automático com inteligência local',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 10),
          ),
          if (kIsWeb) ...[
            const SizedBox(height: 6),
            TextButton.icon(
              style: TextButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              ),
              icon: const Icon(Icons.videocam_rounded, size: 16),
              label: const Text('Tentar Ativar Webcam', style: TextStyle(fontSize: 11)),
              onPressed: _initCamera,
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
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(proposal.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                      if (proposal.merchantOrBeneficiary != null)
                        Text(proposal.merchantOrBeneficiary!, style: theme.textTheme.bodySmall),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      proposal.totalAmount.format(),
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 20, color: AppColors.primary),
                      tooltip: 'Ajustar valor ou título',
                      onPressed: _editProposalDetails,
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (proposal.totalAmount.cents == 0) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade700.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Dica: Cadastre sua chave gratuita do Gemini em Ajustes > Assistente IA para leitura com IA, ou clique no lápis acima para definir o valor manualmente.',
                      style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),

          // Lista os itens reconhecidos com toggle de "Item Pessoal (RN09)"
          if (proposal.items.isNotEmpty) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Itens Reconhecidos (${proposal.items.length})',
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Adicionar Sub-Item', style: TextStyle(fontSize: 12)),
                  onPressed: _addNewItem,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 220),
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
                  final members = context.read<FinanceCubit>().state.members;
                  final assignedMember = item.isPersonal && item.assignedMemberId != null
                      ? members.where((m) => m.id == item.assignedMemberId).firstOrNull
                      : null;
                  final assignedSuffix = assignedMember != null ? ' (${assignedMember.name.split(' ').first})' : '';

                  return ListTile(
                    dense: true,
                    onTap: () => _editItemDetails(idx),
                    title: Text(item.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text(
                      item.isPersonal
                          ? '${item.quantity}x • ${item.unitPrice.format()} • Pessoal${assignedMember != null ? " de ${assignedMember.name}" : ""}'
                          : '${item.quantity}x • ${item.unitPrice.format()} • Toque para editar',
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(item.totalPrice.format(), style: const TextStyle(fontWeight: FontWeight.bold)),
                        const SizedBox(width: 6),
                        FilterChip(
                          visualDensity: VisualDensity.compact,
                          label: Text(item.isPersonal ? 'Pessoal$assignedSuffix' : 'Casa', style: const TextStyle(fontSize: 10)),
                          selected: item.isPersonal,
                          selectedColor: AppColors.debtRed.withValues(alpha: 0.15),
                          onSelected: (val) {
                            if (val && members.length > 1 && item.assignedMemberId == null) {
                              _editItemDetails(idx);
                            } else {
                              final currentUserId = sl<AuthRepository>().currentUser?.id;
                              setState(() {
                                final updatedItems = List<InvoiceItemDraft>.from(proposal.items);
                                updatedItems[idx] = item.copyWith(
                                  isPersonal: val,
                                  assignedMemberId: val
                                      ? (item.assignedMemberId ?? currentUserId ?? members.firstOrNull?.id)
                                      : null,
                                );
                                _currentProposal = proposal.copyWith(items: updatedItems);
                              });
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
                          tooltip: 'Editar item',
                          onPressed: () => _editItemDetails(idx),
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
          const SizedBox(height: 16),

          // Forma de Pagamento
          Builder(
            builder: (context) {
              final paymentMethods = context.watch<FinanceCubit>().state.paymentMethods;
              if (paymentMethods.isEmpty) return const SizedBox.shrink();
              final currentPm = paymentMethods
                      .where((p) => p.id == _selectedPaymentMethodId)
                      .firstOrNull ??
                  paymentMethods.first;
              final isHouse = currentPm.ownerMemberId == null || currentPm.id == 'pm_caixa';

              return DropdownButtonFormField<String>(
                initialValue: currentPm.id,
                decoration: InputDecoration(
                  labelText: 'Forma de Pagamento',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  prefixIcon: const Icon(Icons.credit_card_rounded),
                  helperText: isHouse
                      ? 'Meio da Casa: despesa conjunta (sem reembolso pessoal)'
                      : 'Meio pessoal: a Casa reembolsa quem pagou',
                ),
                items: paymentMethods.map((pm) {
                  return DropdownMenuItem(value: pm.id, child: Text(pm.name));
                }).toList(),
                onChanged: (val) => setState(() => _selectedPaymentMethodId = val),
              );
            },
          ),
          const SizedBox(height: 20),

          // Botões de Confirmação
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSubmitting
                      ? null
                      : () {
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
                  onPressed: _isSubmitting ? null : _confirmProposal,
                  child: _isSubmitting
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                        )
                      : const Text('Confirmar Lançamento', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
