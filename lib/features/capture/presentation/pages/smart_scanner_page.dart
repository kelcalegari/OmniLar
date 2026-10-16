import '../../../finance/domain/services/cycle_expense_grouping.dart';
import 'package:intl/intl.dart';
import '../../../../core/utils/clipboard_helper.dart';
import '../../../../core/utils/uuid.dart';
import '../../../../core/errors/failures.dart';
import '../../../finance/domain/repositories/finance_repository.dart';
import '../../../finance/domain/services/pending_payment.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../domain/services/boleto_code.dart';
import '../../../finance/domain/services/expense_launch_defaults.dart';
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
import '../utils/camera_release.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/house_expense.dart';
import '../../../finance/domain/entities/house_expense_item.dart';
import '../../../finance/domain/entities/split_rule.dart';
import '../../../../core/widgets/save_feedback.dart';

class SmartScannerPage extends StatefulWidget {
  final void Function(CaptureProposal proposal)? onProposalReady;

  /// Abre direto na revisão desta proposta (usado nos testes).
  @visibleForTesting
  final CaptureProposal? initialProposal;

  const SmartScannerPage({super.key, this.onProposalReady, this.initialProposal});

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

class _SmartScannerPageState extends State<SmartScannerPage> with WidgetsBindingObserver {
  final _barcodeController = TextEditingController();
  int _activeTabIndex = 0; // 0 = Câmera/Captura, 1 = Digitar Linha do Boleto
  CaptureProposal? _currentProposal;
  bool _isProcessing = false;
  String _processingMessage = 'Processando documento...';
  bool _isSubmitting = false;
  String? _selectedPaymentMethodId;
  // Título e categoria editados na revisão; voltam ao sugerido a cada documento lido
  final _titleController = TextEditingController();
  String? _selectedCategoryId;
  String? _reviewedProposalId;

  // Boleto: vencimento, se já foi pago e a conta já prevista no app
  DateTime? _dueDate;
  // Boleto nasce a pagar; nota e cupom, já pagos (os dois podem ser trocados)
  bool _alreadyPaid = false;

  /// Nota e cupom: dia da compra (já paga) ou do vencimento (a pagar).
  DateTime _documentDate = DateTime.now();
  DateTime _paidOn = DateTime.now();
  List<HouseExpense> _knownBills = const [];
  HouseExpense? _useKnownBill;
  bool _knownBillDismissed = false;

  /// Fatura de cartão em aberto que parece ser a deste boleto: o código vai
  /// para a fatura, sem lançar despesa.
  List<CardInvoiceEntry> _knownInvoices = const [];
  CardInvoiceEntry? _useInvoice;
  bool _invoiceDismissed = false;

  MobileScannerController? _scannerController;
  bool _isCameraActive = false;

  /// Celular: câmera traseira, a que lê nota e boleto. Trocada só pelo botão.
  CameraFacing _cameraFacing = CameraFacing.back;

  /// Câmera ligando, desligando ou trocando: as próximas ordens esperam.
  Future<void> _cameraWork = Future.value();
  bool _isClosing = false;

  /// Câmera ligada por esta tela. Não confia no estado da biblioteca, que na
  /// web às vezes marca parada com a câmera ainda ligada.
  bool _cameraOn = false;
  bool _isInBackground = false;

  /// A câmera só fica ligada enquanto o visor está na tela.
  bool get _wantsCamera =>
      !_isClosing && !_isInBackground && mounted && _activeTabIndex == 0 && _currentProposal == null && !_isProcessing;

  bool get _isLiveCameraSupported {
    if (kIsWeb) return true;
    return Platform.isAndroid || Platform.isIOS || Platform.isMacOS;
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentProposal = widget.initialProposal;
    if (_isLiveCameraSupported) {
      _initCamera();
    }
  }

  /// Cria o controle da câmera. Quem liga e desliga é [_syncCamera], depois
  /// de o visor entrar na tela; assim a câmera não fica ligada sem visor.
  void _initCamera() {
    watchBrowserCamera();
    final old = _scannerController;
    _scannerController = MobileScannerController(
      autoStart: false,
      detectionSpeed: DetectionSpeed.noDuplicates,
      facing: _cameraFacing,
    );
    if (old != null) _queueCamera(() => _releaseCamera(old));
    setState(() => _isCameraActive = true);
  }

  /// Uma ordem de câmera por vez: ligar no meio de um desligar trava o
  /// navegador e deixa a câmera presa ligada.
  void _queueCamera(Future<void> Function() work) {
    _cameraWork = _cameraWork.then((_) => work()).catchError((_) {});
  }

  Future<void> _stopCamera(MobileScannerController controller) async {
    _cameraOn = false;
    try {
      await controller.stop();
    } finally {
      releaseBrowserCamera();
    }
  }

  Future<void> _releaseCamera(MobileScannerController controller) async {
    try {
      await _stopCamera(controller);
    } catch (_) {}
    await controller.dispose();
    releaseBrowserCamera();
  }

  /// Liga a câmera quando o visor aparece e desliga quando some (revisão,
  /// linha digitável, processando ou tela fechada).
  void _syncCamera() {
    final controller = _scannerController;
    if (controller == null) return;
    _queueCamera(() async {
      if (!identical(controller, _scannerController)) return;
      if (_wantsCamera && !_cameraOn) {
        try {
          await controller.start(cameraDirection: _cameraFacing);
          _cameraOn = true;
        } catch (_) {
          if (mounted) setState(() => _isCameraActive = false);
        }
        // Visor fechado enquanto a câmera ligava: desliga já
        if (!_wantsCamera) await _stopCamera(controller);
      } else if (!_wantsCamera && _cameraOn) {
        await _stopCamera(controller);
      }
    });
  }

  /// Troca frontal/traseira pela direção guardada aqui: no Safari a câmera
  /// não informa a direção e a troca automática da biblioteca não funciona.
  void _switchCamera() {
    final controller = _scannerController;
    if (controller == null) return;
    _cameraFacing = _cameraFacing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
    _queueCamera(() async {
      if (!identical(controller, _scannerController) || !_wantsCamera) return;
      await _stopCamera(controller);
      try {
        await controller.start(cameraDirection: _cameraFacing);
        _cameraOn = true;
      } catch (_) {
        // Aparelho sem a outra câmera: volta para a que funcionava
        _cameraFacing = _cameraFacing == CameraFacing.back ? CameraFacing.front : CameraFacing.back;
        await controller.start(cameraDirection: _cameraFacing);
        _cameraOn = true;
      }
      if (!_wantsCamera) await _stopCamera(controller);
    });
  }

  /// App ou aba do site em segundo plano: a câmera desliga e volta ao retornar.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isInBackground = state == AppLifecycleState.hidden || state == AppLifecycleState.paused;
    _syncCamera();
  }

  @override
  void dispose() {
    _barcodeController.dispose();
    _titleController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    _isClosing = true;
    final controller = _scannerController;
    _scannerController = null;
    if (controller != null) _queueCamera(() => _releaseCamera(controller));
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
          if (proposal.totalAmount.cents == 0) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('O QR da nota não traz valor nem itens. Digite o valor ou fotografe o cupom para a IA ler.'),
              ),
            );
          }
          break;
        } else if (const {44, 47, 48}.contains(BoletoCodeReader.digitsOf(raw).length)) {
          final proposal = _proposalFromCode(raw, quiet: true);
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
    final proposal = BoletoParser.demoNfceProposal();
    setState(() {
      _currentProposal = proposal;
    });
  }

  void _processManualBoleto() {
    final line = _barcodeController.text.trim();
    if (line.isEmpty) return;

    final proposal = _proposalFromCode(line);
    if (proposal != null) {
      setState(() {
        _currentProposal = proposal;
      });
    }
  }

  /// Boleto a partir do código (lido pela câmera, digitado ou colado). Código
  /// com número errado não vira proposta: o usuário é avisado.
  CaptureProposal? _proposalFromCode(String raw, {bool quiet = false}) {
    try {
      final code = BoletoCodeReader.read(raw);
      return CaptureProposal(
        id: 'prop_boleto_${DateTime.now().millisecondsSinceEpoch}',
        documentType: DocumentType.boleto,
        title: code.suggestedTitle,
        totalAmount: code.amount ?? const Money(0),
        date: DateTime.now(),
        dueDate: code.dueDate,
        rawCode: code.digitableLine,
        capturedAt: DateTime.now(),
      );
    } on BoletoCodeError catch (e) {
      if (!quiet && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.debtRed, content: Text(e.message)),
        );
      }
      return null;
    }
  }

  /// Procura a conta já prevista no app (ex.: a internet recorrente) que
  /// parece ser este boleto.
  Future<void> _lookForKnownBill(CaptureProposal proposal) async {
    final dueDate = _dueDate;
    if (dueDate == null || proposal.documentType != DocumentType.boleto) {
      setState(() {
        _knownBills = const [];
        _useKnownBill = null;
        _knownInvoices = const [];
        _useInvoice = null;
      });
      return;
    }
    final financeCubit = context.read<FinanceCubit>();
    final cycle = financeCubit.cycleSchedule.cycleFor(dueDate);
    var expenses = financeCubit.state.expenses;
    try {
      expenses = [...expenses, ...await sl<FinanceRepository>().getExpensesForCycle(cycle)];
    } catch (_) {}
    if (!mounted || _currentProposal?.id != proposal.id) return;
    final unique = {for (final e in expenses) e.id: e}.values.toList();
    final found = knownBillsFor(
      unique,
      dueDate: dueDate,
      amount: proposal.totalAmount,
      barcode: proposal.rawCode,
      paymentMethods: financeCubit.state.paymentMethods,
    );
    final invoices = knownInvoicesFor(
      unique,
      dueDate: dueDate,
      amount: proposal.totalAmount,
      paymentMethods: financeCubit.state.paymentMethods,
    );
    setState(() {
      _knownBills = found;
      if (_useKnownBill != null && !found.any((e) => e.id == _useKnownBill!.id)) _useKnownBill = null;
      _knownInvoices = invoices;
      if (_useInvoice != null && !invoices.any((i) => i.key == _useInvoice!.key)) _useInvoice = null;
    });
  }

  Future<void> _pickDueDate(CaptureProposal proposal) async {
    final initial = _dueDate ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(initial.year - 1),
      lastDate: DateTime(initial.year + 2, 12, 31),
      helpText: 'Vencimento do boleto',
    );
    if (picked == null || !mounted) return;
    setState(() => _dueDate = picked);
    await _lookForKnownBill(proposal);
  }

  Future<void> _pickPaidOn() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _paidOn,
      firstDate: DateTime(_paidOn.year - 1),
      lastDate: DateTime.now(),
      helpText: 'Dia do pagamento',
    );
    if (picked != null && mounted) setState(() => _paidOn = DateTime(picked.year, picked.month, picked.day, 12));
  }

  /// Boleto: nasce como conta a pagar (ou já paga, com o meio escolhido), com
  /// o vencimento e o código. Conta já prevista é atualizada em vez de duplicada.
  Future<void> _confirmBoleto(CaptureProposal proposal) async {
    final financeCubit = context.read<FinanceCubit>();
    final invoice = _useInvoice;
    if (invoice != null) {
      // Boleto da fatura: o código fica guardado nela, as compras já estão lá
      final ok = await financeCubit.saveCardInvoiceCode(
        paymentMethodId: invoice.card.id,
        invoiceDueDate: invoice.dueDate,
        barcode: proposal.rawCode,
      );
      if (!ok) throw financeCubit.state.errorMessage ?? 'Não foi possível guardar o código da fatura.';
      widget.onProposalReady?.call(proposal);
      return;
    }
    final state = financeCubit.state;
    final dueDate = _dueDate!;
    final dueAt = DateTime(dueDate.year, dueDate.month, dueDate.day, 12);
    final method = state.paymentMethods.where((p) => p.id == _selectedPaymentMethodId).firstOrNull ??
        ExpenseLaunchDefaults.houseAccount(state.paymentMethods) ??
        state.paymentMethods.firstOrNull;
    final typedTitle = _titleController.text.trim();

    final known = _useKnownBill;
    final HouseExpense pending;
    if (known != null) {
      pending = known.copyWith(
        amount: proposal.totalAmount,
        date: dueAt,
        dueDate: dueAt,
        barcode: proposal.rawCode,
      );
    } else {
      final categoryId = state.categories.any((c) => c.id == _selectedCategoryId)
          ? _selectedCategoryId!
          : (_suggestedCategoryId(proposal, state.categories) ?? '');
      final category = state.categories.where((c) => c.id == categoryId).firstOrNull;
      final payer = sl<AuthRepository>().currentUser?.id ??
          (state.members.isNotEmpty ? state.members.first.id : 'member_carlos');
      final house = ExpenseLaunchDefaults.houseAccount(state.paymentMethods);
      pending = HouseExpense(
        id: generateUuidV4(),
        title: typedTitle.isNotEmpty ? typedTitle : proposal.title,
        amount: proposal.totalAmount,
        date: dueAt,
        dueDate: dueAt,
        categoryId: categoryId,
        paidByMemberId: payer,
        // A pagar: o meio é escolhido ao pagar; até lá, o da casa
        paymentMethodId: house?.id ?? method?.id ?? '',
        splitRule: ExpenseLaunchDefaults.splitRule(
          category: category,
          members: state.members,
          paidByMemberId: payer,
        ),
        status: ExpenseStatus.pending,
        notes: proposal.merchantOrBeneficiary,
        barcode: proposal.rawCode,
      );
    }

    final expense = _alreadyPaid
        ? paidWith(pending, paidOn: _paidOn, method: method, amount: proposal.totalAmount)
        : pending;
    final ok = known != null
        ? await financeCubit.updateExpense(expense)
        : await financeCubit.addExpense(expense);
    if (!ok) {
      throw ValidationFailure(financeCubit.state.errorMessage ?? kSaveFailedMessage);
    }
    widget.onProposalReady?.call(proposal);
  }

  void _editProposalDetails() {
    final proposal = _currentProposal;
    if (proposal == null) return;

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
                  title: Text(isPersonal ? 'Item Pessoal' : 'Gasto da Casa (Compartilhado)'),
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

  /// Boleto cai em "Contas" e nota em "Mercado"; sem categoria parecida, a primeira da casa.
  String? _suggestedCategoryId(CaptureProposal proposal, List<ExpenseCategory> categories) {
    if (categories.isEmpty) return null;
    final keyword = proposal.documentType == DocumentType.boleto ? 'conta' : 'mercado';
    final found = categories.where((c) => c.name.toLowerCase().contains(keyword)).firstOrNull;
    return (found ?? categories.first).id;
  }

  Future<void> _confirmProposal() async {
    if (_currentProposal == null || _isSubmitting) return;
    final proposal = _currentProposal!;

    setState(() {
      _isSubmitting = true;
    });

    if (proposal.documentType == DocumentType.boleto) {
      try {
        await _confirmBoleto(proposal);
        if (!mounted) return;
        final financeState = context.read<FinanceCubit>().state;
        if (financeState.status == FinanceStatus.failure && financeState.errorMessage != null) {
          throw financeState.errorMessage!;
        }
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.creditGreen,
            content: Text(
              _useInvoice != null
                  ? 'Código guardado na fatura ${_useInvoice!.card.name} que vence em '
                      '${DateFormat('dd/MM').format(_useInvoice!.dueDate)}.'
                  : _alreadyPaid
                  ? 'Boleto lançado como pago (${proposal.totalAmount.format()}).'
                  : 'Boleto lançado como conta a pagar, vence em ${DateFormat('dd/MM').format(_dueDate!)}.',
            ),
          ),
        );
      } catch (err) {
        if (mounted) {
          setState(() => _isSubmitting = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(backgroundColor: AppColors.debtRed, content: Text('Erro ao lançar o boleto: $err')),
          );
        }
      }
      return;
    }

    try {
      final financeCubit = context.read<FinanceCubit>();
      final state = financeCubit.state;
      final currentUserId = sl<AuthRepository>().currentUser?.id;
      final isPayable = !_alreadyPaid;
      // A pagar: o meio é escolhido ao pagar; até lá, o da casa
      final selectedPm = isPayable
          ? (ExpenseLaunchDefaults.houseAccount(state.paymentMethods) ?? state.paymentMethods.firstOrNull)
          : state.paymentMethods
                  .where((p) => p.id == _selectedPaymentMethodId)
                  .firstOrNull ??
              state.paymentMethods.firstOrNull;
      // Meio de pagamento pessoal: quem pagou é o dono dele e a Casa reembolsa
      final paidByMemberId = (isPayable ? null : selectedPm?.ownerMemberId) ??
          currentUserId ??
          (state.members.isNotEmpty ? state.members.first.id : 'member_carlos');
      final paidOutOfPocket = !isPayable &&
          selectedPm != null &&
          selectedPm.ownerMemberId != null &&
          selectedPm.id != 'pm_caixa';

      // 1. Categoria escolhida na revisão; sem escolha, a sugerida pelo tipo do documento
      final matchedCategoryId = state.categories.any((c) => c.id == _selectedCategoryId)
          ? _selectedCategoryId
          : _suggestedCategoryId(proposal, state.categories);
      final typedTitle = _titleController.text.trim();
      final title = typedTitle.isNotEmpty ? typedTitle : proposal.title;

      // 2. Forma de Pagamento escolhida na revisão
      final matchedPaymentMethodId = selectedPm?.id;

      // 3. Regra de rateio entre membros
      // (categoria com dono vai 100% para o dono, como nos outros lançamentos)
      final splitRule = ExpenseLaunchDefaults.splitRule(
        category: state.categories.where((c) => c.id == matchedCategoryId).firstOrNull,
        members: state.members,
        paidByMemberId: paidByMemberId,
      );

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

      final finalCategoryId = matchedCategoryId ?? (state.categories.isNotEmpty ? state.categories.first.id : '');
      final finalPaymentMethodId = matchedPaymentMethodId ?? state.paymentMethods.firstOrNull?.id;
      if (finalPaymentMethodId == null) {
        throw const ValidationFailure('Cadastre uma forma de pagamento em Ajustes antes de lançar.');
      }

      final scannedMethod =
          state.paymentMethods.where((p) => p.id == finalPaymentMethodId).firstOrNull;
      // No cartão, a compra entra na fatura (o vencimento é calculado ao gravar)
      final waitsForInvoice = !isPayable && ExpenseLaunchDefaults.waitsForInvoice(scannedMethod);
      final documentDate = _documentDate;

      final expense = HouseExpense(
        id: expenseId,
        title: title,
        amount: proposal.totalAmount,
        date: documentDate,
        dueDate: waitsForInvoice ? null : documentDate,
        categoryId: finalCategoryId,
        paidByMemberId: paidByMemberId,
        paymentMethodId: finalPaymentMethodId,
        splitRule: splitRule,
        paidOutOfPocket: waitsForInvoice ? false : paidOutOfPocket,
        status: waitsForInvoice || isPayable ? ExpenseStatus.pending : ExpenseStatus.paid,
        notes: proposal.merchantOrBeneficiary,
        items: expenseItems,
      );

      // Persistir no repositório (espera o Supabase concluir)
      if (!await financeCubit.addExpense(expense)) {
        throw ValidationFailure(financeCubit.state.errorMessage ?? kSaveFailedMessage);
      }

      widget.onProposalReady?.call(proposal);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: AppColors.creditGreen,
            content: Text(
              isPayable
                  ? 'Conta "$title" lançada a pagar, vence em ${DateFormat('dd/MM').format(documentDate)}.'
                  : 'Proposta "$title" confirmada! Despesa de ${proposal.houseAmount.format()} lançada. 📋✅',
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
    // Depois do quadro: o visor já entrou (ou saiu) da tela
    if (_scannerController != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncCamera());
    }

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
      // Rola e sobe com o teclado: a revisão tem campo de texto
      return SingleChildScrollView(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
        child: _buildReviewProposalView(theme),
      );
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
                            onPressed: _switchCamera,
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
    final isBoleto = proposal.documentType == DocumentType.boleto;
    if (_reviewedProposalId != proposal.id) {
      _reviewedProposalId = proposal.id;
      _titleController.text = proposal.title;
      _selectedCategoryId = null;
      _dueDate = isBoleto ? proposal.dueDate : null;
      _alreadyPaid = !isBoleto;
      _documentDate = proposal.date;
      _paidOn = DateTime.now();
      _knownBills = const [];
      _useKnownBill = null;
      _knownBillDismissed = false;
      _knownInvoices = const [];
      _useInvoice = null;
      _invoiceDismissed = false;
      if (isBoleto && _dueDate != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _lookForKnownBill(proposal);
        });
      }
    }

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
                    'Revisar Lançamento',
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

          TextField(
            controller: _titleController,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: 'Título do gasto',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              prefixIcon: const Icon(Icons.edit_note_rounded),
            ),
          ),
          const SizedBox(height: 12),

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
                      const Text('Valor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
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
                      tooltip: 'Ajustar valor',
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

          // Lista os itens reconhecidos com toggle de "Item Pessoal"
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

          if (isBoleto) ..._boletoFields(theme, proposal) else ..._documentFields(theme),

          // Categoria (conta já prevista mantém a dela; fatura não vira despesa)
          if (_useKnownBill == null && _useInvoice == null)
          Builder(
            builder: (context) {
              final categories = context.watch<FinanceCubit>().state.categories;
              if (categories.isEmpty) return const SizedBox.shrink();
              final currentId = categories.any((c) => c.id == _selectedCategoryId)
                  ? _selectedCategoryId
                  : _suggestedCategoryId(proposal, categories);

              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: DropdownButtonFormField<String>(
                  key: ValueKey('scan_category_${proposal.id}'),
                  initialValue: currentId,
                  decoration: InputDecoration(
                    labelText: 'Categoria',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.category_outlined),
                  ),
                  items: categories.map((c) {
                    return DropdownMenuItem(value: c.id, child: Text(c.name));
                  }).toList(),
                  onChanged: (val) => setState(() => _selectedCategoryId = val),
                ),
              );
            },
          ),

          // Forma de Pagamento (conta a pagar: o meio é escolhido ao pagar)
          if (_alreadyPaid)
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
                  onPressed: _isSubmitting || (isBoleto && (_dueDate == null || proposal.totalAmount.cents <= 0))
                      ? null
                      : _confirmProposal,
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

  Future<void> _pickDocumentDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _documentDate,
      firstDate: DateTime(_documentDate.year - 1),
      lastDate: _alreadyPaid ? DateTime.now() : DateTime(_documentDate.year + 2, 12, 31),
      helpText: _alreadyPaid ? 'Dia da compra' : 'Vencimento',
    );
    if (picked != null && mounted) {
      setState(() => _documentDate = DateTime(picked.year, picked.month, picked.day, 12));
    }
  }

  /// Nota e cupom: já pagos (na data da compra) ou a pagar (com vencimento).
  List<Widget> _documentFields(ThemeData theme) {
    final dayFormat = DateFormat('dd/MM/yyyy');
    return [
      SegmentedButton<bool>(
        key: const Key('scan_paid_choice'),
        segments: const [
          ButtonSegment(value: true, label: Text('Já paguei'), icon: Icon(Icons.check_circle_outline, size: 16)),
          ButtonSegment(value: false, label: Text('A pagar'), icon: Icon(Icons.schedule_rounded, size: 16)),
        ],
        selected: {_alreadyPaid},
        onSelectionChanged: _isSubmitting
            ? null
            : (value) => setState(() {
                  _alreadyPaid = value.first;
                  // Já paga não pode ficar no futuro
                  final now = DateTime.now();
                  if (_alreadyPaid && _documentDate.isAfter(now)) {
                    _documentDate = DateTime(now.year, now.month, now.day, 12);
                  }
                }),
      ),
      const SizedBox(height: 8),
      OutlinedButton.icon(
        key: const Key('scan_document_date'),
        icon: Icon(_alreadyPaid ? Icons.event_available_rounded : Icons.event_rounded, size: 18),
        label: Text(
          _alreadyPaid
              ? 'Compra em ${dayFormat.format(_documentDate)}'
              : 'Vence em ${dayFormat.format(_documentDate)}',
        ),
        onPressed: _isSubmitting ? null : _pickDocumentDate,
      ),
      if (!_alreadyPaid)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Fica em "A Vencer" até ser paga. Ao pagar, você escolhe o meio de pagamento.',
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
          ),
        ),
      const SizedBox(height: 12),
    ];
  }

  /// Código para copiar, vencimento, situação e conta já prevista.
  List<Widget> _boletoFields(ThemeData theme, CaptureProposal proposal) {
    final dayFormat = DateFormat('dd/MM/yyyy');
    final knownBill = _knownBills.firstOrNull;
    final knownInvoice = _knownInvoices.firstOrNull;
    return [
      if (proposal.rawCode != null) ...[
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.primary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  proposal.rawCode!,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'Copiar código',
                onPressed: () => copyWithFeedback(
                  context,
                  proposal.rawCode!,
                  onCopied: const SnackBar(content: Text('Código do boleto copiado.')),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
      ],
      OutlinedButton.icon(
        key: const Key('scan_due_date'),
        icon: const Icon(Icons.event_rounded, size: 18),
        label: Text(_dueDate == null ? 'Informar vencimento' : 'Vence em ${dayFormat.format(_dueDate!)}'),
        style: OutlinedButton.styleFrom(
          foregroundColor: _dueDate == null ? AppColors.debtRed : null,
        ),
        onPressed: _isSubmitting ? null : () => _pickDueDate(proposal),
      ),
      if (_dueDate == null)
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Text(
            'Este código não traz o vencimento: informe a data impressa no boleto.',
            style: TextStyle(fontSize: 12, color: AppColors.debtRed),
          ),
        ),
      const SizedBox(height: 12),
      if (knownInvoice != null && !_invoiceDismissed)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (_useInvoice != null ? AppColors.creditGreen : AppColors.folegoWarning).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _useInvoice != null
                    ? 'Vai guardar o código na fatura ${knownInvoice.card.name}, sem lançar despesa: '
                        'as compras já estão nela. Para pagar, use "Pagar" na fatura.'
                    : 'Parece o boleto da fatura ${knownInvoice.card.name} '
                        '(vence ${DateFormat('dd/MM').format(knownInvoice.dueDate)}, ${knownInvoice.total.format()} no app).',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (_useInvoice == null)
                    TextButton(
                      key: const Key('scan_use_invoice'),
                      onPressed: () => setState(() {
                        _useInvoice = knownInvoice;
                        _useKnownBill = null;
                        _alreadyPaid = false;
                      }),
                      child: const Text('É esta fatura'),
                    ),
                  TextButton(
                    onPressed: () => setState(() {
                      _useInvoice = null;
                      _invoiceDismissed = true;
                    }),
                    child: const Text('Não é fatura'),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (_useInvoice == null && knownBill != null && !_knownBillDismissed)
        Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (_useKnownBill != null ? AppColors.creditGreen : AppColors.folegoWarning).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _useKnownBill != null
                    ? 'Vai atualizar a conta "${knownBill.title}" já prevista (valor, vencimento e código), sem lançar outra.'
                    : 'Parece a conta "${knownBill.title}" já prevista '
                        '(vence ${DateFormat('dd/MM').format(knownBill.effectiveDueDate)}, ${knownBill.amount.format()}).',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              Wrap(
                spacing: 8,
                children: [
                  if (_useKnownBill == null)
                    TextButton(
                      key: const Key('scan_use_known_bill'),
                      onPressed: () => setState(() => _useKnownBill = knownBill),
                      child: const Text('É esta conta'),
                    ),
                  TextButton(
                    onPressed: () => setState(() {
                      _useKnownBill = null;
                      _knownBillDismissed = true;
                    }),
                    child: const Text('É outra conta'),
                  ),
                ],
              ),
            ],
          ),
        ),
      if (_useInvoice == null) ...[
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(value: false, label: Text('A pagar'), icon: Icon(Icons.schedule_rounded, size: 16)),
          ButtonSegment(value: true, label: Text('Já paga'), icon: Icon(Icons.check_circle_outline, size: 16)),
        ],
        selected: {_alreadyPaid},
        onSelectionChanged: _isSubmitting ? null : (value) => setState(() => _alreadyPaid = value.first),
      ),
      const SizedBox(height: 8),
      if (_alreadyPaid)
        OutlinedButton.icon(
          icon: const Icon(Icons.event_available_rounded, size: 18),
          label: Text('Paga em ${dayFormat.format(_paidOn)}'),
          onPressed: _isSubmitting ? null : _pickPaidOn,
        )
      else
        Text(
          'Fica em "A Vencer" até ser paga. Ao pagar, você escolhe o meio de pagamento: '
          'o da casa sai do caixa; o de um morador, ele é reembolsado no fechamento.',
          style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
        ),
      const SizedBox(height: 12),
      ],
    ];
  }
}
