import '../../../capture/domain/services/boleto_code.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/money_input_field.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../projects/domain/entities/shared_project.dart';
import '../../../projects/domain/repositories/projects_repository.dart';
import '../../domain/entities/house_expense.dart';
import '../../domain/entities/house_expense_item.dart';
import '../../domain/entities/split_rule.dart';
import '../../domain/services/expense_launch_defaults.dart';
import '../../domain/entities/category.dart';
import '../../domain/entities/payment_method.dart';
import '../../domain/services/credit_card_invoice_calculator.dart';
import '../../../../core/domain/enums/recurrence.dart';
import '../../../../core/widgets/recurrence_scope_dialog.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';
import '../../../../core/widgets/save_feedback.dart';
import '../../../admin/presentation/cubit/account_access_cubit.dart';
import '../../domain/services/receipt_attachment_service.dart';
import '../widgets/receipt_attachment_viewer.dart';

class _DraftExpenseItem {
  final TextEditingController titleController;
  final MoneyTextEditingController amountController;
  int cents;
  String? categoryId;
  String? responsibleMemberId;

  _DraftExpenseItem({
    required String title,
    required this.cents,
    this.categoryId,
    this.responsibleMemberId,
  })  : titleController = TextEditingController(text: title),
        amountController = MoneyTextEditingController(
          initialMoney: Money(cents),
          allowEmpty: false,
        );

  void dispose() {
    titleController.dispose();
    amountController.dispose();
  }
}

class AddExpensePage extends StatefulWidget {
  final bool isRecurringDefault;
  final HouseExpense? expenseToEdit;
  final String? initialProjectId;

  const AddExpensePage({
    super.key,
    this.isRecurringDefault = false,
    this.expenseToEdit,
    this.initialProjectId,
  });

  @override
  State<AddExpensePage> createState() => _AddExpensePageState();
}

class _AddExpensePageState extends State<AddExpensePage> {
  final _titleController = TextEditingController();

  String? _selectedCategoryId;
  String? _selectedPaidByMemberId;
  String? _foreignCurrencyTag;
  String? _selectedPaymentMethodId;
  String? _selectedProjectId;
  // Gravação em andamento: evita lançar a mesma despesa duas vezes
  bool _isSaving = false;
  List<SharedProject> _availableProjects = [];
  // Divisão escolhida no formulário (despesa nova): a da casa, valores fixos
  // por morador ou um morador só
  SplitType _selectedSplitType = SplitType.percentage;
  final Map<String, int> _fixedCents = {};
  String? _singleResponsibleId;
  // Divisão padrão da categoria (0097): entra como sugestão ao escolher a
  // categoria; escolher a divisão à mão vale sempre mais
  bool _splitChosenManually = false;
  bool _splitFromCategory = false;
  String? _splitSuggestedFor;
  Map<String, double>? _categoryPercentages;
  // Os padrões de quem lança entram uma vez só, quando as listas chegam
  bool _launchDefaultsApplied = false;
  DateTime _selectedDate = DateTime.now();

  late bool _isRecurring;
  bool _isVariable = false;
  int _dueDay = DateTime.now().day;
  ExpenseStatus _expenseStatus = ExpenseStatus.paid;

  int _cents = 0;

  /// Código do boleto colado no formulário (linha digitável conferida).
  final _barcodeController = TextEditingController();
  String? _barcode;
  String? _barcodeInfo;
  String? _barcodeError;

  /// Muda quando o código preenche o valor, para o campo de valor se refazer.
  int _amountFieldVersion = 0;

  bool _isItemized = false;
  final List<_DraftExpenseItem> _draftItems = [];
  ReceiptAttachmentFile? _pendingAttachmentFile;
  String? _existingAttachmentPath;
  String? _existingAttachmentName;
  String? _existingAttachmentContentType;
  int? _existingAttachmentSizeBytes;
  bool _clearAttachment = false;

  @override
  void initState() {
    super.initState();
    final edit = widget.expenseToEdit;
    if (edit != null) {
      _titleController.text = edit.title;
      _cents = edit.amount.cents;
      if (edit.notes != null && edit.notes!.contains('[Câmbio:')) {
        final start = edit.notes!.indexOf('[Câmbio:');
        final end = edit.notes!.indexOf(']', start);
        if (end != -1) {
          _foreignCurrencyTag = edit.notes!.substring(start, end + 1);
        }
      }
      _selectedCategoryId = edit.categoryId;
      _selectedPaidByMemberId = edit.paidByMemberId;
      _selectedPaymentMethodId = edit.paymentMethodId;
      _selectedProjectId = edit.projectId;
      _existingAttachmentPath = edit.attachmentPath;
      _existingAttachmentName = edit.attachmentName;
      _existingAttachmentContentType = edit.attachmentContentType;
      _existingAttachmentSizeBytes = edit.attachmentSizeBytes;
      PaymentMethod? editPm;
      try {
        editPm = context
            .read<FinanceCubit>()
            .state
            .paymentMethods
            .where((p) => p.id == edit.paymentMethodId)
            .firstOrNull;
      } catch (_) {}
      _selectedDate = editableDateOfExpense(edit, editPm);
      _isRecurring = edit.isRecurring;
      _isVariable = edit.isVariable;
      _dueDay = edit.dueDay ?? (edit.dueDate ?? edit.date).day;
      _expenseStatus = edit.status;
      _barcode = edit.barcode;
      _barcodeController.text = edit.barcode ?? '';
      _isItemized = edit.items.isNotEmpty;
      if (edit.items.isNotEmpty) {
        _draftItems.addAll(edit.items.map((it) => _DraftExpenseItem(
          title: it.title,
          cents: it.amount.cents,
          categoryId: it.categoryId,
          responsibleMemberId: it.responsibleMemberId,
        )));
      }
    } else {
      _isRecurring = widget.isRecurringDefault;
      if (_isRecurring) {
        _expenseStatus = ExpenseStatus.pending;
      }
      _selectedProjectId = widget.initialProjectId;
    }
    _loadAvailableProjects();
  }

  /// Confere o código colado e usa o que ele traz: valor (se ainda vazio) e
  /// vencimento (a conta passa a "A Vencer").
  void _onBarcodeChanged(String text) {
    final digits = BoletoCodeReader.digitsOf(text);
    if (digits.isEmpty) {
      setState(() {
        _barcode = null;
        _barcodeInfo = null;
        _barcodeError = null;
      });
      return;
    }
    if (!const {44, 47, 48}.contains(digits.length)) {
      setState(() {
        _barcode = null;
        _barcodeInfo = null;
        _barcodeError = digits.length < 44 ? null : 'Código com ${digits.length} dígitos: confira.';
      });
      return;
    }
    try {
      final code = BoletoCodeReader.read(digits);
      setState(() {
        _barcode = code.digitableLine;
        _barcodeError = null;
        final parts = [
          if (code.amount != null) 'valor ${code.amount!.format()}',
          if (code.dueDate != null) 'vence ${DateFormat('dd/MM/yyyy').format(code.dueDate!)}',
        ];
        _barcodeInfo = parts.isEmpty ? 'Código conferido.' : 'Código conferido: ${parts.join(', ')}.';
        if (_cents == 0 && code.amount != null) {
          _cents = code.amount!.cents;
          _amountFieldVersion++;
        }
        final dueDate = code.dueDate;
        if (dueDate != null) {
          if (_isRecurring) {
            _dueDay = dueDate.day;
          } else if (widget.expenseToEdit == null) {
            _selectedDate = dueDate;
            _expenseStatus = ExpenseStatus.pending;
          }
        }
      });
    } on BoletoCodeError catch (e) {
      setState(() {
        _barcode = null;
        _barcodeInfo = null;
        _barcodeError = e.message;
      });
    }
  }

  Future<void> _loadAvailableProjects() async {
    try {
      if (sl.isRegistered<ProjectsRepository>()) {
        final auth = sl<AuthRepository>();
        final houseId = auth.isDemoMode ? 'house_demo' : (auth.currentHouse?.id ?? 'house_demo');
        final projects = await sl<ProjectsRepository>().getProjects(houseId: houseId);
        if (mounted) {
          setState(() {
            // Apenas projetos ativos ou em planejamento podem receber novas despesas.
            // Se estiver editando despesa vinculada a projeto antigo, mantém na lista.
            _availableProjects = projects.where((p) =>
              p.status == ProjectStatus.active ||
              p.status == ProjectStatus.planning ||
              p.id == _selectedProjectId
            ).toList();
          });
        }
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _titleController.dispose();
    _barcodeController.dispose();
    for (final item in _draftItems) {
      item.dispose();
    }
    super.dispose();
  }

  void _applyCondoPreset(FinanceState state) {
    for (final item in _draftItems) {
      item.dispose();
    }
    _draftItems.clear();

    final moradiaCatId = state.categories.where((c) => c.name.toLowerCase().contains('moradia')).firstOrNull?.id 
        ?? state.categories.firstOrNull?.id;
    final contasCatId = state.categories.where((c) => c.name.toLowerCase().contains('conta')).firstOrNull?.id 
        ?? state.categories.firstOrNull?.id;
    final firstMemberId = state.members.firstOrNull?.id;

    if (_cents == 85000) {
      _draftItems.addAll([
        _DraftExpenseItem(title: 'Taxa Condomínio Ordinária', cents: 50000, categoryId: moradiaCatId),
        _DraftExpenseItem(title: 'Consumo de Água', cents: 12000, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Gás Encanado', cents: 8000, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Fundo de Obras / Reserva', cents: 15000, categoryId: moradiaCatId, responsibleMemberId: firstMemberId),
      ]);
    } else if (_cents > 0) {
      final part = _cents ~/ 4;
      final rest = _cents - (part * 4);
      _draftItems.addAll([
        _DraftExpenseItem(title: 'Taxa Condomínio Ordinária', cents: part + rest, categoryId: moradiaCatId),
        _DraftExpenseItem(title: 'Consumo de Água', cents: part, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Gás Encanado', cents: part, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Fundo de Obras / Reserva', cents: part, categoryId: moradiaCatId, responsibleMemberId: firstMemberId),
      ]);
    } else {
      _draftItems.addAll([
        _DraftExpenseItem(title: 'Taxa Condomínio Ordinária', cents: 0, categoryId: moradiaCatId),
        _DraftExpenseItem(title: 'Consumo de Água', cents: 0, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Gás Encanado', cents: 0, categoryId: contasCatId),
        _DraftExpenseItem(title: 'Fundo de Obras / Reserva', cents: 0, categoryId: moradiaCatId, responsibleMemberId: firstMemberId),
      ]);
    }
  }

  Future<void> _submit() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, digite o nome da despesa')),
      );
      return;
    }

    if (_cents <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('O valor deve ser maior que zero')),
      );
      return;
    }

    if (_isItemized) {
      if (_draftItems.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Adicione pelo menos um sub-item ou desative o boleto composto.')),
        );
        return;
      }
      final itemsSumCents = _draftItems.fold<int>(0, (acc, item) => acc + item.cents);
      if (itemsSumCents != _cents) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(
              'A soma dos sub-itens (${Money(itemsSumCents).format()}) deve ser igual ao valor total do boleto (${Money(_cents).format()}).',
            ),
          ),
        );
        return;
      }
    }

    final state = context.read<FinanceCubit>().state;
    final catId = _selectedCategoryId ?? state.categories.firstOrNull?.id ?? '';
    final paidById = _selectedPaidByMemberId ?? state.members.firstOrNull?.id ?? sl<AuthRepository>().currentUser?.id ?? '';
    final selectedProj = _availableProjects.where((p) => p.id == _selectedProjectId).firstOrNull;
    final guestPayer = selectedProj?.participants.where((p) => p.isExternal && p.id == paidById).firstOrNull;
    final paidByParticipantId = guestPayer?.id;
    final pmId = _selectedPaymentMethodId ?? state.paymentMethods.firstOrNull?.id ?? '';
    final splitChoice = _splitChoiceApplies(state) ? _selectedSplitType : SplitType.percentage;

    if (splitChoice == SplitType.fixed) {
      final fixedSum = state.members.fold<int>(0, (acc, m) => acc + (_fixedCents[m.id] ?? 0));
      if (fixedSum != _cents) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red.shade700,
            content: Text(
              'A soma dos valores fixos (${Money(fixedSum).format()}) deve ser igual ao valor da despesa (${Money(_cents).format()}).',
            ),
          ),
        );
        return;
      }
    }

    // Determina a regra de rateio de forma resiliente
    final category = state.categories.where((c) => c.id == catId).firstOrNull;
    // Despesa de projeto é dividida entre os participantes do projeto: não leva
    // o rateio da casa nem o dono da categoria
    final isProjectExpense = _selectedProjectId != null;
    // Sub-item em categoria com dono é do dono, salvo se outro morador foi marcado
    String? itemResponsibleOf(_DraftExpenseItem draft) => isProjectExpense
        ? draft.responsibleMemberId
        : ExpenseLaunchDefaults.itemResponsible(
            chosenMemberId: draft.responsibleMemberId,
            itemCategory: state.categories
                .where((c) => c.id == (draft.categoryId ?? catId))
                .firstOrNull,
          );
    SplitRule rule;
    if (isProjectExpense) {
      // Sem percentuais gravados: o acerto do projeto usa os dos participantes
      rule = const SplitRule.percentage(null);
    } else if (category != null && category.hasOwner) {
      rule = SplitRule.singleResponsible(category.ownerMemberId ?? paidById);
    } else if (splitChoice == SplitType.categoryOwner) {
      // Um morador só responde pela despesa inteira
      rule = SplitRule.singleResponsible(_singleResponsibleId ?? paidById);
    } else if (splitChoice == SplitType.percentage && _categoryPercentages != null) {
      // Percentuais da categoria, só para quem ainda mora na casa
      rule = SplitRule.percentage({
        for (final m in state.members)
          if (_categoryPercentages!.containsKey(m.id)) m.id: _categoryPercentages![m.id]!,
      });
    } else if (splitChoice == SplitType.fixed) {
      rule = SplitRule.fixed({
        for (final m in state.members)
          if ((_fixedCents[m.id] ?? 0) > 0) m.id: Money(_fixedCents[m.id]!),
      });
    } else {
      if (state.members.isNotEmpty) {
        final percentMap = <String, double>{};
        for (final m in state.members) {
          percentMap[m.id] = m.defaultSplitPercent;
        }
        rule = SplitRule.percentage(percentMap);
      } else {
        rule = SplitRule.singleResponsible(paidById);
      }
    }

    final now = DateTime.now();
    DateTime expenseDate = _selectedDate;
    DateTime? dueDate;

    final selectedPm = state.paymentMethods.where((p) => p.id == pmId).firstOrNull;
    final isHouseMethod = selectedPm == null
        ? (pmId == 'pm_caixa')
        : (selectedPm.ownerMemberId == null || selectedPm.id == 'pm_caixa');
    final paidOutOfPocket = !isHouseMethod;
    // Compra no cartão fica pendente até a fatura ser paga (quem pagou se
    // decide no pagamento da fatura)
    final waitsForInvoice = !_isRecurring &&
        ExpenseLaunchDefaults.waitsForInvoice(selectedPm, projectId: _selectedProjectId);

    if (_isRecurring) {
      // Ao editar, o vencimento fica no mês da própria ocorrência (não no mês atual)
      final old = widget.expenseToEdit;
      final base = old != null ? (old.dueDate ?? old.date) : now;
      final daysInMonth = DateTime(base.year, base.month + 1, 0).day;
      final safeDay = _dueDay.clamp(1, daysInMonth);
      dueDate = DateTime(base.year, base.month, safeDay);
      expenseDate = _expenseStatus == ExpenseStatus.paid
          ? (old != null && !old.isPending ? old.date : now)
          : dueDate;
    } else if (selectedPm != null &&
        selectedPm.type == PaymentMethodType.card &&
        selectedPm.closingDay != null &&
        selectedPm.dueDay != null) {
      dueDate = CreditCardInvoiceCalculator.calculateInvoiceDueDate(
        purchaseDate: _selectedDate,
        closingDay: selectedPm.closingDay!,
        dueDay: selectedPm.dueDay!,
      );
    } else {
      if (_expenseStatus == ExpenseStatus.pending) {
        dueDate = _selectedDate;
      }
    }

    if (widget.expenseToEdit != null) {
      final oldExpense = widget.expenseToEdit!;
      RecurrenceScope chosenScope = RecurrenceScope.thisInstanceOnly;
      if (oldExpense.isRecurring) {
        final scope = await showRecurrenceScopeDialog(
          context: context,
          itemTitle: oldExpense.title,
          isDelete: false,
          isExpense: true,
        );
        if (scope == null) return;
        chosenScope = scope;
      }

      final expenseId = oldExpense.id;
      final List<HouseExpenseItem> items = _isItemized
          ? _draftItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final draft = entry.value;
              final itemTitle = draft.titleController.text.trim().isEmpty
                  ? 'Sub-item #${idx + 1}'
                  : draft.titleController.text.trim();
              return HouseExpenseItem(
                id: 'item_${expenseId}_$idx',
                expenseId: expenseId,
                title: itemTitle,
                amount: Money(draft.cents),
                categoryId: draft.categoryId ?? catId,
                responsibleMemberId: itemResponsibleOf(draft),
                splitRule: itemResponsibleOf(draft) != null
                    ? SplitRule.singleResponsible(itemResponsibleOf(draft))
                    : null,
              );
            }).toList()
          : const [];

      final oldPm = state.paymentMethods.where((p) => p.id == oldExpense.paymentMethodId).firstOrNull;
      final wasWaitingForInvoice = oldExpense.isPending &&
          ExpenseLaunchDefaults.waitsForInvoice(oldPm, projectId: oldExpense.projectId);
      final sameCard = oldExpense.paymentMethodId == pmId;
      final ExpenseStatus editedStatus;
      if (waitsForInvoice) {
        // No mesmo cartão vale o que a fatura já disse; em outro, volta a esperar a fatura
        editedStatus = sameCard ? oldExpense.status : ExpenseStatus.pending;
      } else if (wasWaitingForInvoice) {
        // Saiu do cartão: foi paga com a forma escolhida, na data da compra
        editedStatus = ExpenseStatus.paid;
      } else {
        editedStatus = _expenseStatus;
      }

      if (_isSaving) return;
      setState(() => _isSaving = true);

      String? uploadedPath;
      if (_pendingAttachmentFile != null) {
        try {
          final houseId = sl<AuthRepository>().currentHouse?.id ?? '';
          uploadedPath = await sl<ReceiptAttachmentService>().uploadReceipt(
            houseId: houseId,
            file: _pendingAttachmentFile!,
            expenseId: oldExpense.id,
          );
        } catch (e) {
          if (mounted) {
            setState(() => _isSaving = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao enviar comprovante: $e'),
                backgroundColor: AppColors.debtRed,
              ),
            );
          }
          return;
        }
      }

      final updatedExpense = oldExpense.copyWith(
        title: _titleController.text.trim(),
        amount: Money(_cents),
        date: expenseDate,
        dueDate: dueDate,
        categoryId: catId,
        paidByMemberId: paidById,
        paidByParticipantId: paidByParticipantId,
        clearPaidByParticipantId: paidByParticipantId == null,
        paymentMethodId: pmId,
        splitRule: splitRuleForEdit(oldExpense, catId, rule, newProjectId: _selectedProjectId),
        paidOutOfPocket: waitsForInvoice
            ? (sameCard && oldExpense.isPaid ? oldExpense.paidOutOfPocket : false)
            : paidOutOfPocket,
        status: editedStatus,
        // No cartão o campo some e o código que houver fica como está
        barcode: waitsForInvoice ? null : _barcode,
        // Campo apagado remove o código; código inválido mantém o que havia
        clearBarcode: !waitsForInvoice && _barcodeController.text.trim().isEmpty,
        // Conta que estava pendente e foi marcada como paga agora
        paidAt: editedStatus == ExpenseStatus.paid && oldExpense.isPending && !wasWaitingForInvoice
            ? DateTime.now()
            : null,
        clearPaidAt: editedStatus == ExpenseStatus.pending,
        isRecurring: _isRecurring,
        isVariable: _isVariable,
        dueDay: _isRecurring ? _dueDay : null,
        items: items,
        projectId: _selectedProjectId,
      notes: _foreignCurrencyTag,
        clearProjectId: _selectedProjectId == null,
        attachmentPath: uploadedPath ?? (_clearAttachment ? null : _existingAttachmentPath),
        clearAttachment: _clearAttachment,
        attachmentName: _pendingAttachmentFile?.name ?? (_clearAttachment ? null : _existingAttachmentName),
        attachmentContentType: _pendingAttachmentFile?.contentType ?? (_clearAttachment ? null : _existingAttachmentContentType),
        attachmentSizeBytes: _pendingAttachmentFile?.sizeBytes ?? (_clearAttachment ? null : _existingAttachmentSizeBytes),
      );

      if (!mounted) return;
      final cubit = context.read<FinanceCubit>();
      final ok = await cubit.updateExpense(updatedExpense, scope: chosenScope);
      if (!mounted) return;
      setState(() => _isSaving = false);
      // Falhou: o formulário fica aberto, com o que foi digitado
      if (ok) Navigator.pop(context);
      showSaveFeedback(
        ScaffoldMessenger.of(context),
        ok: ok,
        success: 'Despesa atualizada com sucesso! ✏️',
        failure: cubit.state.errorMessage,
      );
      return;
    }

    if (_isSaving) return;
    setState(() => _isSaving = true);

    final expenseId = 'exp_${DateTime.now().millisecondsSinceEpoch}';

    String? uploadedPath;
    if (_pendingAttachmentFile != null) {
      try {
        final houseId = sl<AuthRepository>().currentHouse?.id ?? '';
        uploadedPath = await sl<ReceiptAttachmentService>().uploadReceipt(
          houseId: houseId,
          file: _pendingAttachmentFile!,
          expenseId: expenseId,
        );
      } catch (e) {
        if (mounted) {
          setState(() => _isSaving = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Erro ao enviar comprovante: $e'),
              backgroundColor: AppColors.debtRed,
            ),
          );
        }
        return;
      }
    }

    final List<HouseExpenseItem> items = _isItemized
        ? _draftItems.asMap().entries.map((entry) {
              final idx = entry.key;
              final draft = entry.value;
              final itemTitle = draft.titleController.text.trim().isEmpty
                  ? 'Sub-item #${idx + 1}'
                  : draft.titleController.text.trim();
              return HouseExpenseItem(
                id: 'item_${expenseId}_$idx',
                expenseId: expenseId,
                title: itemTitle,
                amount: Money(draft.cents),
                categoryId: draft.categoryId ?? catId,
                responsibleMemberId: itemResponsibleOf(draft),
                splitRule: itemResponsibleOf(draft) != null
                    ? SplitRule.singleResponsible(itemResponsibleOf(draft))
                    : null,
              );
            }).toList()
          : const [];

    final expense = HouseExpense(
      id: expenseId,
      title: _titleController.text.trim(),
      amount: Money(_cents),
      date: expenseDate,
      dueDate: dueDate,
      categoryId: catId,
      paidByMemberId: paidById,
      paidByParticipantId: paidByParticipantId,
      paymentMethodId: pmId,
      splitRule: rule,
      paidOutOfPocket: waitsForInvoice ? false : paidOutOfPocket,
      status: waitsForInvoice ? ExpenseStatus.pending : _expenseStatus,
      barcode: waitsForInvoice ? null : _barcode,
      isRecurring: _isRecurring,
      isVariable: _isVariable,
      dueDay: _isRecurring ? _dueDay : null,
      items: items,
      projectId: _selectedProjectId,
      attachmentPath: uploadedPath,
      attachmentName: _pendingAttachmentFile?.name,
      attachmentContentType: _pendingAttachmentFile?.contentType,
      attachmentSizeBytes: _pendingAttachmentFile?.sizeBytes,
      // Quem lançou: é daqui que saem a última forma e a categoria mais usada dele
      createdBy: sl<AuthRepository>().currentUser?.id,
    );

    final cubit = context.read<FinanceCubit>();
    final ok = await cubit.addExpense(expense);
    if (!mounted) return;
    setState(() => _isSaving = false);
    // Falhou: o formulário fica aberto, com o que foi digitado
    if (ok) Navigator.pop(context);
    showSaveFeedback(
      ScaffoldMessenger.of(context),
      ok: ok,
      success: _isRecurring
          ? 'Despesa recorrente cadastrada com sucesso! 🔁'
          : (_isItemized
              ? 'Boleto composto lançado com ${items.length} sub-itens! 🏢'
              : 'Gasto da casa lançado com sucesso! 🎉'),
      failure: cubit.state.errorMessage,
    );
  }

  Future<void> _confirmAndDelete() async {
    final exp = widget.expenseToEdit;
    if (exp == null) return;

    RecurrenceScope scope = RecurrenceScope.thisInstanceOnly;
    if (exp.isRecurring) {
      final chosenScope = await showRecurrenceScopeDialog(
        context: context,
        itemTitle: exp.title,
        isDelete: true,
        isExpense: true,
      );
      if (chosenScope == null) return;
      scope = chosenScope;
    } else {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Excluir Despesa'),
          content: Text('Tem certeza que deseja excluir "${exp.title}"?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.debtRed,
                foregroundColor: Colors.white,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Excluir'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }

    if (!mounted) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final cubit = context.read<FinanceCubit>();

    final ok = await cubit.deleteExpense(exp.id, scope: scope);
    if (mounted) {
      if (!ok) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppColors.debtRed,
            content: Text(cubit.state.errorMessage ?? kSaveFailedMessage),
          ),
        );
        return;
      }
      nav.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Despesa "${exp.title}" excluída com sucesso! 🗑️')),
      );
    }
  }

  /// Despesa nova abre com os padrões de quem lança (quem pagou, forma de
  /// pagamento e categoria). O que não tiver padrão fica com o primeiro da
  /// lista, como antes. Edição mantém o que a despesa já tem.
  void _applyLaunchDefaults(BuildContext context, FinanceState state) {
    if (_launchDefaultsApplied || widget.expenseToEdit != null) return;
    if (state.members.isEmpty && state.paymentMethods.isEmpty && state.categories.isEmpty) return;
    _launchDefaultsApplied = true;
    List<HouseExpense> history;
    try {
      history = context.read<FinanceCubit>().launchHistory;
    } catch (_) {
      history = state.expenses;
    }
    String? currentUserId;
    try {
      currentUserId = sl<AuthRepository>().currentUser?.id;
    } catch (_) {}
    final defaults = ExpenseLaunchDefaults.formDefaults(
      currentUserId: currentUserId,
      members: state.members,
      paymentMethods: state.paymentMethods,
      categories: state.categories,
      expenses: history,
      settings: state.memberSettings,
    );
    _selectedPaidByMemberId ??= defaults.payerId;
    _selectedPaymentMethodId ??= defaults.paymentMethodId;
    _selectedCategoryId ??= defaults.categoryId;
  }

  /// A divisão escolhida só vale em despesa nova da casa (projeto divide entre
  /// os participantes; categoria com dono é do dono) e com mais de um morador.
  bool _splitChoiceApplies(FinanceState state) {
    if (widget.expenseToEdit != null || _selectedProjectId != null) return false;
    if (state.members.length < 2) return false;
    final category = state.categories.where((c) => c.id == _selectedCategoryId).firstOrNull;
    return category == null || !category.hasOwner;
  }

  /// Divisão padrão da categoria escolhida, como sugestão: roda quando a
  /// categoria muda e nunca passa por cima de uma divisão escolhida à mão.
  /// Categoria sem padrão volta ao que a sugestão anterior tinha trocado.
  void _syncCategorySplit(FinanceState state) {
    if (widget.expenseToEdit != null || _selectedCategoryId == _splitSuggestedFor) return;
    if (state.categories.isEmpty || state.members.isEmpty) return;
    _splitSuggestedFor = _selectedCategoryId;
    if (_splitChosenManually) return;
    if (_splitFromCategory) {
      _selectedSplitType = SplitType.percentage;
      _singleResponsibleId = null;
    }
    _categoryPercentages = null;
    _splitFromCategory = false;
    final category = state.categories.where((c) => c.id == _selectedCategoryId).firstOrNull;
    final rule = category?.defaultSplit?.toRule(state.members);
    if (rule == null) return;
    _splitFromCategory = true;
    _selectedSplitType = rule.type;
    if (rule.type == SplitType.categoryOwner) {
      _singleResponsibleId = rule.singleResponsibleMemberId;
    } else {
      _categoryPercentages = rule.percentages;
    }
  }

  /// Valores fixos começam pela divisão da casa aplicada ao valor digitado.
  void _prefillFixedAmounts(FinanceState state) {
    final rule = ExpenseLaunchDefaults.splitRule(
      category: null,
      members: state.members,
      paidByMemberId: _selectedPaidByMemberId ?? '',
    );
    final allocations = rule.calculateAllocations(
      totalAmount: Money(_cents),
      memberIds: [for (final m in state.members) m.id],
    );
    _fixedCents
      ..clear()
      ..addAll({for (final m in state.members) m.id: allocations[m.id]?.cents ?? 0});
  }

  static String _splitTypeLabel(SplitType type) => switch (type) {
        SplitType.percentage => 'Divisão da casa',
        SplitType.fixed => 'Valores fixos',
        SplitType.categoryOwner => 'Um responsável',
      };

  /// Escolha da divisão, ao lado do título "Quem pagou" (compacta, sem
  /// empurrar o resto do formulário).
  Widget _buildSplitMenu(ThemeData theme, FinanceState state) {
    return PopupMenuButton<SplitType>(
      key: const Key('expense_split_menu'),
      tooltip: 'Como dividir',
      initialValue: _selectedSplitType,
      onSelected: (type) => setState(() {
        _splitChosenManually = true;
        _splitFromCategory = false;
        _categoryPercentages = null;
        _selectedSplitType = type;
        if (type == SplitType.fixed && _fixedCents.values.every((c) => c == 0)) {
          _prefillFixedAmounts(state);
        }
        if (type == SplitType.categoryOwner) {
          _singleResponsibleId ??= _selectedPaidByMemberId;
        }
      }),
      itemBuilder: (_) => [
        for (final type in SplitType.values)
          // Valor fixo é da despesa inteira: não combina com sub-itens
          if (type != SplitType.fixed || !_isItemized)
            PopupMenuItem(value: type, child: Text(_splitTypeLabel(type))),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.call_split_rounded, size: 16, color: AppColors.primary),
            const SizedBox(width: 4),
            Text(
              _selectedSplitType == SplitType.percentage && _categoryPercentages != null
                  ? 'Divisão da categoria'
                  : _splitTypeLabel(_selectedSplitType),
              style: theme.textTheme.bodySmall?.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 18, color: AppColors.primary),
          ],
        ),
      ),
    );
  }

  /// Valores de cada morador (valores fixos) ou quem responde pela despesa.
  Widget _buildSplitDetails(ThemeData theme, FinanceState state) {
    final fixedSum = state.members.fold<int>(0, (acc, m) => acc + (_fixedCents[m.id] ?? 0));
    final fixedDiff = _cents - fixedSum;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 12),
        if (_selectedSplitType == SplitType.fixed) ...[
          Text('Quanto cada um paga', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final m in state.members)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: MoneyTextFormField(
                key: ValueKey('expense_split_fixed_${m.id}'),
                labelText: m.name,
                prefixIcon: const Icon(Icons.person_outline_rounded),
                initialValue: Money(_fixedCents[m.id] ?? 0),
                onChanged: (money) => setState(() => _fixedCents[m.id] = money.cents),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  fixedDiff == 0
                      ? 'Os valores fecham o total ✅'
                      : (fixedDiff > 0
                          ? 'Faltam ${Money(fixedDiff).format()} para fechar o total'
                          : 'Passou ${Money(-fixedDiff).format()} do total'),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: fixedDiff == 0 ? AppColors.creditGreen : AppColors.folegoWarning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _prefillFixedAmounts(state)),
                child: const Text('Pela divisão da casa'),
              ),
            ],
          ),
        ],
        if (_selectedSplitType == SplitType.categoryOwner) ...[
          Text('Quem responde pela despesa inteira', style: theme.textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final m in state.members)
                ChoiceChip(
                  key: ValueKey('expense_split_single_${m.id}'),
                  avatar: const Icon(Icons.person_rounded, size: 16),
                  label: Text(m.name),
                  selected: (_singleResponsibleId ?? _selectedPaidByMemberId) == m.id,
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  onSelected: (selected) {
                    if (selected) {
                      setState(() {
                        _splitChosenManually = true;
                        _singleResponsibleId = m.id;
                      });
                    }
                  },
                ),
            ],
          ),
          if ((_singleResponsibleId ?? _selectedPaidByMemberId) != _selectedPaidByMemberId) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Como outra pessoa pagou, o valor integral será reembolsado no acerto do ciclo mensal (Super Pix). Se preferir um empréstimo parcelado ou avulso fora do ciclo da casa, use a aba Empréstimos.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return BlocBuilder<FinanceCubit, FinanceState>(
      builder: (context, state) {
        _applyLaunchDefaults(context, state);
        final selectedProjForPayer = _availableProjects.where((p) => p.id == _selectedProjectId).firstOrNull;
        final isSelectedPaidByGuest = selectedProjForPayer?.participants.any((p) => p.isExternal && p.id == _selectedPaidByMemberId) ?? false;
        if (state.members.isNotEmpty &&
            (_selectedPaidByMemberId == null ||
                (!state.members.any((m) => m.id == _selectedPaidByMemberId) && !isSelectedPaidByGuest))) {
          _selectedPaidByMemberId = state.members.first.id;
        }
        if (state.categories.isNotEmpty &&
            (_selectedCategoryId == null ||
                !state.categories.any((c) => c.id == _selectedCategoryId))) {
          _selectedCategoryId = state.categories.first.id;
        }
        _syncCategorySplit(state);
        if (state.paymentMethods.isNotEmpty &&
            (_selectedPaymentMethodId == null ||
                !state.paymentMethods.any((pm) => pm.id == _selectedPaymentMethodId))) {
          _selectedPaymentMethodId = state.paymentMethods.first.id;
        }

        // Compra no cartão não tem boleto próprio: quem tem é a fatura
        final codeFits = _isRecurring ||
            !ExpenseLaunchDefaults.waitsForInvoice(
              state.paymentMethods.where((p) => p.id == _selectedPaymentMethodId).firstOrNull,
              projectId: _selectedProjectId,
            );

        final selectedCategory = state.categories.where(
          (c) => c.id == _selectedCategoryId,
        ).firstOrNull ?? (state.categories.isNotEmpty
            ? state.categories.first
            : const ExpenseCategory(id: '', name: '', icon: '', colorHex: ''));

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.expenseToEdit != null
                  ? 'Editar Despesa'
                  : (_isRecurring ? 'Nova Despesa Recorrente' : 'Gasto da Casa'),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            leading: IconButton(
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.pop(context),
            ),
            actions: [
              if (widget.expenseToEdit != null)
                IconButton(
                  tooltip: 'Excluir despesa',
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.debtRed),
                  onPressed: _confirmAndDelete,
                ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // Campo ATM Contínuo de Valor
              MoneyInputField(
                key: ValueKey('expense_amount_$_amountFieldVersion'),
                label: _isRecurring && _isVariable ? 'Valor Estimado do Mês' : 'Valor da Despesa',
                initialValue: Money(_cents),
                primaryColor: AppColors.primary,
                quickAddCents: const [1000, 2000, 5000, 10000], // +10, +20, +50, +100
                onChanged: (money) {
                  setState(() {
                    _cents = money.cents;
                  });
                },
              ),
              if (_selectedProjectId != null || _foreignCurrencyTag != null) ...[
                const SizedBox(height: 6),
                Row(
                  children: [
                    if (_foreignCurrencyTag != null)
                      Chip(
                        avatar: const Icon(Icons.currency_exchange_rounded, size: 14),
                        label: Text(_foreignCurrencyTag!, style: const TextStyle(fontSize: 11)),
                        onDeleted: () {
                          setState(() {
                            _foreignCurrencyTag = null;
                          });
                        },
                      )
                    else
                      TextButton.icon(
                        onPressed: _showCurrencyConverterDialog,
                        icon: const Icon(Icons.currency_exchange_rounded, size: 16),
                        label: const Text('Converter Moeda Estrangeira (USD, EUR...)', style: TextStyle(fontSize: 12)),
                        style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),

              // Input de Nome / Descrição
              TextField(
                controller: _titleController,
                decoration: InputDecoration(
                  labelText: 'O que foi pago?',
                  hintText: 'Ex: Supermercado, Aluguel, Luz, Netflix',
                  prefixIcon: const Icon(Icons.receipt_long_outlined),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 12),

              // Código do boleto: guardado para copiar na hora de pagar
              if (codeFits) ...[
              TextField(
                key: const Key('expense_barcode'),
                controller: _barcodeController,
                keyboardType: TextInputType.number,
                onChanged: _onBarcodeChanged,
                decoration: InputDecoration(
                  labelText: 'Código do boleto (opcional)',
                  hintText: 'Cole a linha digitável',
                  prefixIcon: const Icon(Icons.qr_code_2_rounded),
                  helperText: _barcodeError == null ? _barcodeInfo : null,
                  errorText: _barcodeError,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              ],
              const SizedBox(height: 20),

              // Data e Situação da Despesa (Retroativa, Atual ou Em Atraso) para compras avulsas
              if (!_isRecurring) ...[
                _buildDateAndStatusCard(theme),
                const SizedBox(height: 20),
              ],

              // Seção de Recorrência (Assinaturas / Contas Fixas / Variáveis)
              Material(
                color: _isRecurring
                    ? AppColors.primary.withValues(alpha: 0.06)
                    : theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _isRecurring
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : theme.dividerColor,
                    width: _isRecurring ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(
                        Icons.repeat_rounded,
                        color: _isRecurring ? AppColors.primary : Colors.grey,
                      ),
                      title: const Text(
                        'Repetir todo mês (Recorrente)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text(
                        _isRecurring
                            ? (_isVariable
                                ? 'Conta de consumo (Luz, Água, Gás)'
                                : 'Assinatura fixa (Netflix, Internet, Aluguel)')
                            : 'Ative para contas fixas ou assinaturas mensais',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isRecurring,
                      onChanged: (val) {
                        setState(() {
                          _isRecurring = val;
                          if (_isRecurring) {
                            _expenseStatus = ExpenseStatus.pending;
                          }
                        });
                      },
                    ),
                    if (_isRecurring) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Tipo de Recorrência: Fixa vs Variável
                            const Text(
                              'Tipo de Conta',
                              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: ChoiceChip(
                                    avatar: const Icon(Icons.lock_clock_rounded, size: 16),
                                    label: const Center(child: Text('Valor Fixo')),
                                    selected: !_isVariable,
                                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                    onSelected: (selected) {
                                      if (selected) setState(() => _isVariable = false);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: ChoiceChip(
                                    avatar: const Icon(Icons.trending_up_rounded, size: 16),
                                    label: const Center(child: Text('Valor Variável')),
                                    selected: _isVariable,
                                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                                    onSelected: (selected) {
                                      if (selected) setState(() => _isVariable = true);
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),

                            // Dia do Vencimento
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'Dia do Vencimento',
                                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: DropdownButton<int>(
                                    value: _dueDay,
                                    underline: const SizedBox(),
                                    isDense: true,
                                    items: List.generate(31, (i) => i + 1).map((day) {
                                      return DropdownMenuItem<int>(
                                        value: day,
                                        child: Text('Todo dia $day',
                                            style: const TextStyle(fontWeight: FontWeight.bold)),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) setState(() => _dueDay = val);
                                    },
                                  ),
                                ),
                              ],
                            ),
                              const SizedBox(height: 14),

                              // Situação no Ciclo Atual
                              const Text(
                                'Situação no Ciclo Atual',
                                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: ChoiceChip(
                                      avatar: const Icon(Icons.check_circle_outline, size: 16),
                                      label: const Center(child: Text('Já Paga')),
                                      selected: _expenseStatus == ExpenseStatus.paid,
                                      selectedColor: AppColors.creditGreen.withValues(alpha: 0.15),
                                      onSelected: (selected) {
                                        if (selected) setState(() => _expenseStatus = ExpenseStatus.paid);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: ChoiceChip(
                                      avatar: const Icon(Icons.schedule_rounded, size: 16),
                                      label: const Center(child: Text('A Vencer')),
                                      selected: _expenseStatus == ExpenseStatus.pending,
                                      selectedColor: AppColors.folegoWarning.withValues(alpha: 0.2),
                                      onSelected: (selected) {
                                        if (selected) setState(() => _expenseStatus = ExpenseStatus.pending);
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                ),
              ),
              const SizedBox(height: 20),

              // Seção de Segmentação / Boleto Composto
              Material(
                color: _isItemized
                    ? AppColors.primary.withValues(alpha: 0.04)
                    : theme.cardColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: _isItemized
                        ? AppColors.primary.withValues(alpha: 0.4)
                        : theme.dividerColor,
                    width: _isItemized ? 1.5 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    SwitchListTile(
                      secondary: Icon(
                        Icons.account_tree_outlined,
                        color: _isItemized ? AppColors.primary : Colors.grey,
                      ),
                      title: const Text(
                        'Desmembrar Sub-itens (Boleto Composto)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      subtitle: Text(
                        _isItemized
                            ? 'Segmentado em água, condomínio, gás, obras...'
                            : 'Ative para discriminar condomínio com água, gás, obras ou donos diferentes',
                        style: const TextStyle(fontSize: 12),
                      ),
                      value: _isItemized,
                      onChanged: (val) {
                        setState(() {
                          _isItemized = val;
                          // Valor fixo não combina com sub-itens: volta à divisão da casa
                          if (_isItemized && _selectedSplitType == SplitType.fixed) {
                            _selectedSplitType = SplitType.percentage;
                          }
                          if (_isItemized && _draftItems.isEmpty) {
                            _applyCondoPreset(state);
                          }
                        });
                      },
                    ),
                    if (_isItemized) ...[
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildItemizedBalanceBanner(theme),
                            const SizedBox(height: 14),
                            ..._draftItems.asMap().entries.map((entry) {
                              final index = entry.key;
                              final item = entry.value;
                              return _buildDraftItemCard(theme, state, index, item);
                            }),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: OutlinedButton.icon(
                                    style: OutlinedButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    icon: const Icon(Icons.add_rounded, size: 18),
                                    label: const Text('Adicionar Sub-item'),
                                    onPressed: () {
                                      setState(() {
                                        final sum = _draftItems.fold<int>(0, (acc, i) => acc + i.cents);
                                        final remaining = _cents > sum ? _cents - sum : 0;
                                        _draftItems.add(_DraftExpenseItem(
                                          title: '',
                                          cents: remaining,
                                          categoryId: _selectedCategoryId,
                                        ));
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  onPressed: () {
                                    setState(() {
                                      _applyCondoPreset(state);
                                    });
                                  },
                                  child: const Text('Preset Condomínio'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Seletor de Categoria
              Text('Categoria', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              if (state.categories.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: Colors.amber, size: 20),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Nenhuma categoria encontrada. Uma categoria geral será atribuída.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: state.categories.map((cat) {
                    final isSelected = cat.id == _selectedCategoryId;
                    return ChoiceChip(
                      label: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(cat.name),
                          if (cat.hasOwner) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.person_rounded, size: 14),
                          ],
                        ],
                      ),
                      selected: isSelected,
                      selectedColor: AppColors.primary.withValues(alpha: 0.15),
                      onSelected: (selected) {
                        if (selected) {
                          setState(() {
                            _selectedCategoryId = cat.id;
                          });
                        }
                      },
                    );
                  }).toList(),
                ),
              if (selectedCategory.hasOwner) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: AppColors.accent, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Categoria com Responsável: Alocado 100% para o dono da categoria.',
                          style: theme.textTheme.bodySmall?.copyWith(color: AppColors.accent),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 20),

              // Quem Pagou (e, ao lado, como dividir a despesa nova da casa)
              Row(
                children: [
                  Expanded(child: Text('Quem Pagou / É Responsável?', style: theme.textTheme.titleSmall)),
                  if (_splitChoiceApplies(state)) _buildSplitMenu(theme, state),
                ],
              ),
              const SizedBox(height: 8),
              if (state.members.isEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.person_outline_rounded, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Registrando como: ${sl<AuthRepository>().currentUser?.fullName ?? "Você"}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )
              else if (selectedProjForPayer != null &&
                  selectedProjForPayer.participants.any((p) => p.isExternal))
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ...state.members.map((m) {
                      final isSelected = m.id == _selectedPaidByMemberId;
                      return ChoiceChip(
                        label: Text(m.name),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedPaidByMemberId = m.id);
                        },
                      );
                    }),
                    ...selectedProjForPayer.participants.where((p) => p.isExternal).map((g) {
                      final isSelected = g.id == _selectedPaidByMemberId;
                      return ChoiceChip(
                        avatar: const Icon(Icons.person_pin_rounded, size: 16),
                        label: Text('${g.displayName} (convidado)'),
                        selected: isSelected,
                        onSelected: (selected) {
                          if (selected) setState(() => _selectedPaidByMemberId = g.id);
                        },
                      );
                    }),
                  ],
                )
              else
                Row(
                  children: state.members.map((m) {
                    final isSelected = m.id == _selectedPaidByMemberId;
                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            backgroundColor: isSelected ? AppColors.primary.withValues(alpha: 0.12) : null,
                            side: BorderSide(
                              color: isSelected ? AppColors.primary : theme.dividerColor,
                              width: isSelected ? 2 : 1,
                            ),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () {
                            setState(() {
                              _selectedPaidByMemberId = m.id;
                            });
                          },
                          child: Text(
                            m.name,
                            style: TextStyle(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              color: isSelected ? AppColors.primary : null,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              if (_splitChoiceApplies(state) && _selectedSplitType != SplitType.percentage)
                _buildSplitDetails(theme, state),

              if (_availableProjects.isNotEmpty || _selectedProjectId != null) ...[
                const SizedBox(height: 20),
                // Vincular a Projeto / Viagem (Opcional)
                Text('Vincular a Projeto / Viagem (Opcional)', style: theme.textTheme.titleSmall),
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  key: const Key('add_expense_project_dropdown'),
                  initialValue: _selectedProjectId,
                  isExpanded: true,
                  decoration: InputDecoration(
                    hintText: 'Nenhum projeto (Gasto Geral da Casa)',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    prefixIcon: const Icon(Icons.flight_takeoff_rounded),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Nenhum projeto (Gasto Geral da Casa)', overflow: TextOverflow.ellipsis),
                    ),
                    if (_selectedProjectId != null && !_availableProjects.any((p) => p.id == _selectedProjectId))
                      DropdownMenuItem<String?>(
                        value: _selectedProjectId,
                        child: Text('Projeto Selecionado ($_selectedProjectId)', overflow: TextOverflow.ellipsis),
                      ),
                    ..._availableProjects.map((p) {
                      final tag = p.type == ProjectType.trip ? '🏖️ (Viagem)' : '🛠️ (Projeto)';
                      return DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text('${p.title} $tag', overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (val) {
                    setState(() {
                      _selectedProjectId = val;
                      final proj = _availableProjects.where((p) => p.id == val).firstOrNull;
                      final isGuest = proj?.participants.any((p) => p.isExternal && p.id == _selectedPaidByMemberId) ?? false;
                      final isMember = state.members.any((m) => m.id == _selectedPaidByMemberId);
                      if (!isMember && !isGuest) {
                        _selectedPaidByMemberId = state.members.firstOrNull?.id;
                      }
                    });
                  },
                ),
              ],
              const SizedBox(height: 20),

              // Forma de Pagamento
              Text('Forma de Pagamento', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final currentPm = state.paymentMethods
                      .where((p) => p.id == _selectedPaymentMethodId)
                      .firstOrNull;
                  final isHouse = currentPm == null
                      ? (_selectedPaymentMethodId == 'pm_caixa')
                      : (currentPm.ownerMemberId == null || currentPm.id == 'pm_caixa');

                  return DropdownButtonFormField<String>(
                    initialValue: _selectedPaymentMethodId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      prefixIcon: const Icon(Icons.credit_card_rounded),
                      helperText: isHouse
                          ? 'Meio da Casa: despesa conjunta (sem reembolso pessoal)'
                          : null,
                    ),
                    hint: const Text('Selecione uma forma de pagamento'),
                    items: state.paymentMethods.isNotEmpty
                        ? state.paymentMethods.map((pm) {
                            return DropdownMenuItem(
                              value: pm.id,
                              child: Text(pm.name),
                            );
                          }).toList()
                        : const [
                            DropdownMenuItem(
                              value: 'pm_pix',
                              child: Text('Pix / Transferência (Padrão)'),
                            ),
                          ],
                    onChanged: (val) {
                      setState(() {
                        _selectedPaymentMethodId = val;
                        final pm = state.paymentMethods.where((p) => p.id == val).firstOrNull;
                        if (pm?.ownerMemberId != null) {
                          _selectedPaidByMemberId = pm!.ownerMemberId;
                        }
                      });
                    },
                  );
                },
              ),
              const SizedBox(height: 16),

              // Comprovante ou Cupom Fiscal (Fase 4.1)
              _buildReceiptAttachmentSection(theme),

              const SizedBox(height: 24),

              // Botão de Lançar / Salvar
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                  onPressed: _submit,
                  child: Text(
                    widget.expenseToEdit != null
                        ? 'Salvar Alterações'
                        : (_isRecurring ? 'Salvar Despesa Recorrente' : 'Lançar Gasto da Casa'),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              if (widget.expenseToEdit != null) ...[
                const SizedBox(height: 12),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.debtRed,
                      side: BorderSide(color: AppColors.debtRed.withValues(alpha: 0.5)),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 20),
                    label: const Text(
                      'Excluir Esta Despesa',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _confirmAndDelete,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildItemizedBalanceBanner(ThemeData theme) {
    final itemsSumCents = _draftItems.fold<int>(0, (acc, i) => acc + i.cents);
    final diffCents = _cents - itemsSumCents;

    if (diffCents == 0 && itemsSumCents > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.creditGreen.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.creditGreen.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: AppColors.creditGreen, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Total conferido: ${Money(itemsSumCents).format()} de ${Money(_cents).format()} (100% batendo ✅)',
                style: const TextStyle(
                  color: AppColors.creditGreen,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (diffCents > 0) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.folegoWarning.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.folegoWarning.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline_rounded, color: AppColors.folegoWarning, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Soma: ${Money(itemsSumCents).format()} • Faltam ${Money(diffCents).format()} para fechar os ${Money(_cents).format()}',
                    style: const TextStyle(
                      color: AppColors.folegoWarning,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            if (_draftItems.isNotEmpty) ...[
              const SizedBox(height: 6),
              InkWell(
                onTap: () {
                  setState(() {
                    _draftItems.last.cents += diffCents;
                    _draftItems.last.amountController.setMoney(Money(_draftItems.last.cents));
                  });
                },
                child: Text(
                  '+ Ajustar restante (${Money(diffCents).format()}) no último sub-item',
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    decoration: TextDecoration.underline,
                  ),
                ),
              ),
            ],
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline_rounded, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Soma: ${Money(itemsSumCents).format()} • Ultrapassou em ${Money(-diffCents).format()} o boleto (${Money(_cents).format()})',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDraftItemCard(
    ThemeData theme,
    FinanceState state,
    int index,
    _DraftExpenseItem item,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Sub-item #${index + 1}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                onPressed: () {
                  setState(() {
                    item.dispose();
                    _draftItems.removeAt(index);
                  });
                },
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: item.titleController,
                  decoration: InputDecoration(
                    labelText: 'Nome do sub-item',
                    hintText: 'Ex: Água, Gás, Taxa',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 2,
                child: MoneyTextFormField(
                  controller: item.amountController,
                  labelText: 'Valor',
                  allowEmpty: false,
                  decoration: InputDecoration(
                    labelText: 'Valor',
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onChanged: (money) {
                    setState(() {
                      item.cents = money.cents;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text('Responsável: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
              const SizedBox(width: 6),
              Expanded(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.dividerColor),
                  ),
                  child: DropdownButton<String?>(
                    value: item.responsibleMemberId,
                    isDense: true,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Rateio Geral da Casa', style: TextStyle(fontSize: 12)),
                      ),
                      ...state.members.map((m) {
                        return DropdownMenuItem<String?>(
                          value: m.id,
                          child: Text('100% ${m.name}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        item.responsibleMemberId = val;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDateAndStatusCard(ThemeData theme) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selectedDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final isPast = selectedDay.isBefore(today);
    final isRetroactivePending = isPast && _expenseStatus == ExpenseStatus.pending;
    final daysDiff = today.difference(selectedDay).inDays;

    String dateContextText;
    if (selectedDay == today) {
      dateContextText = 'Hoje';
    } else if (isPast) {
      dateContextText = daysDiff == 1 ? 'Ontem' : 'Há $daysDiff dias';
    } else {
      final futureDays = selectedDay.difference(today).inDays;
      dateContextText = futureDays == 1 ? 'Amanhã' : 'Em $futureDays dias';
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isRetroactivePending
            ? AppColors.debtRed.withValues(alpha: 0.05)
            : theme.cardColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isRetroactivePending
              ? AppColors.debtRed.withValues(alpha: 0.4)
              : theme.dividerColor,
          width: isRetroactivePending ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.calendar_month_rounded,
                    size: 18,
                    color: isRetroactivePending ? AppColors.debtRed : AppColors.primary,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _expenseStatus == ExpenseStatus.pending
                        ? 'Data de Vencimento'
                        : 'Data do Pagamento',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                ],
              ),
              InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) {
                    setState(() => _selectedDate = picked);
                  }
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Text(
                        '${DateFormat('dd/MM/yyyy').format(_selectedDate)} ($dateContextText)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.edit_calendar_rounded, size: 14, color: AppColors.primary),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Situação no Ciclo Atual
          const Text(
            'Situação no Ciclo Atual',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.check_circle_outline, size: 16),
                  label: const Center(child: Text('Já Paga')),
                  selected: _expenseStatus == ExpenseStatus.paid,
                  selectedColor: AppColors.creditGreen.withValues(alpha: 0.15),
                  onSelected: (selected) {
                    if (selected) setState(() => _expenseStatus = ExpenseStatus.paid);
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  avatar: const Icon(Icons.schedule_rounded, size: 16),
                  label: const Center(child: Text('A Vencer')),
                  selected: _expenseStatus == ExpenseStatus.pending,
                  selectedColor: AppColors.folegoWarning.withValues(alpha: 0.2),
                  onSelected: (selected) {
                    if (selected) setState(() => _expenseStatus = ExpenseStatus.pending);
                  },
                ),
              ),
            ],
          ),

          if (isRetroactivePending) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: AppColors.debtRed.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.debtRed.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: AppColors.debtRed),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⚠️ Conta Vencida / Em Atraso (venceu há $daysDiff dias). Ficará como compromisso pendente no Fôlego da casa até ser paga.',
                      style: const TextStyle(
                        color: AppColors.debtRed,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }



  Future<void> _pickReceiptAttachment() async {
    try {
      final file = await sl<ReceiptAttachmentService>().pickReceiptFile();
      if (file != null) {
        setState(() {
          _pendingAttachmentFile = file;
          _clearAttachment = false;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Comprovante "${file.name}" anexado! 📄'),
              backgroundColor: AppColors.creditGreen,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString()),
            backgroundColor: AppColors.debtRed,
          ),
        );
      }
    }
  }

  Widget _buildReceiptAttachmentSection(ThemeData theme) {
    final isPremium = sl<AuthRepository>().isDemoMode ||
        (sl<AccountAccessCubit>().state.access?.isPremium ?? false);
    final hasAttachment = _pendingAttachmentFile != null ||
        (!_clearAttachment && _existingAttachmentPath != null);
    final fileName = _pendingAttachmentFile?.name ?? _existingAttachmentName ?? 'Comprovante';
    final sizeBytes = _pendingAttachmentFile?.sizeBytes ?? _existingAttachmentSizeBytes;
    final sizeText = sizeBytes != null
        ? (sizeBytes < 1024 * 1024
            ? '${(sizeBytes / 1024).toStringAsFixed(1)} KB'
            : '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB')
        : null;

    if (hasAttachment) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.cardColor,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.creditGreen.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () {
                ReceiptViewerModal.show(
                  context,
                  attachmentPath: _existingAttachmentPath,
                  localBytes: _pendingAttachmentFile?.bytes,
                  attachmentName: fileName,
                  attachmentContentType: _pendingAttachmentFile?.contentType ?? _existingAttachmentContentType,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppColors.creditGreen.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.receipt_long_rounded,
                  color: AppColors.creditGreen,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(6),
                onTap: () {
                  ReceiptViewerModal.show(
                    context,
                    attachmentPath: _existingAttachmentPath,
                    localBytes: _pendingAttachmentFile?.bytes,
                    attachmentName: fileName,
                    attachmentContentType: _pendingAttachmentFile?.contentType ?? _existingAttachmentContentType,
                  );
                },
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            fileName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Icon(Icons.visibility_outlined, size: 14, color: AppColors.primary),
                      ],
                    ),
                    Text(
                      sizeText != null ? 'Comprovante anexado • $sizeText' : 'Comprovante anexado (toque para ver)',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.creditGreen,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 18, color: AppColors.primary),
              tooltip: 'Trocar comprovante',
              onPressed: _pickReceiptAttachment,
            ),
            IconButton(
              icon: const Icon(Icons.close_rounded, size: 18, color: Colors.grey),
              tooltip: 'Remover comprovante',
              onPressed: () {
                setState(() {
                  _pendingAttachmentFile = null;
                  _clearAttachment = true;
                });
              },
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.camera_alt_outlined,
              color: AppColors.primary,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Comprovante / Cupom',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    if (!isPremium) ...[
                      const SizedBox(width: 6),
                      const Text(
                        '⭐ Premium',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFB45309),
                        ),
                      ),
                    ],
                  ],
                ),
                Text(
                  isPremium
                      ? 'Anexe a foto da nota ou comprovante de pagamento'
                      : 'Guarda em nuvem durante o ciclo e 30 dias após',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () {
              if (isPremium) {
                _pickReceiptAttachment();
              } else {
                PremiumReceiptInfoSheet.show(context);
              }
            },
            icon: Icon(isPremium ? Icons.upload_file_rounded : Icons.info_outline_rounded, size: 16),
            label: Text(isPremium ? 'Anexar' : 'Saiba mais', style: const TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  void _showCurrencyConverterDialog() {
    String selectedCurrency = 'USD';
    final amountCtrl = TextEditingController();
    final rateCtrl = TextEditingController(text: '5.65');

    showDialog<void>(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          final foreignAmount = double.tryParse(amountCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final rate = double.tryParse(rateCtrl.text.replaceAll(',', '.')) ?? 0.0;
          final totalBrlCents = (foreignAmount * rate * 100).round();
          final totalBrl = Money(totalBrlCents);

          return AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.currency_exchange_rounded, color: AppColors.primary),
                SizedBox(width: 8),
                Text('Converter Moeda', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: selectedCurrency,
                    decoration: const InputDecoration(labelText: 'Moeda Estrangeira', isDense: true),
                    items: const [
                      DropdownMenuItem(value: 'USD', child: Text('USD - Dólar Americano (\$)')),
                      DropdownMenuItem(value: 'EUR', child: Text('EUR - Euro (€)')),
                      DropdownMenuItem(value: 'GBP', child: Text('GBP - Libra Esterlina (£)')),
                      DropdownMenuItem(value: 'ARS', child: Text('ARS - Peso Argentino (\$)')),
                      DropdownMenuItem(value: 'CLP', child: Text('CLP - Peso Chileno (\$)')),
                      DropdownMenuItem(value: 'UYU', child: Text('UYU - Peso Uruguaio (\$)')),
                      DropdownMenuItem(value: 'CAD', child: Text('CAD - Dólar Canadense (\$)')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedCurrency = val);
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor em $selectedCurrency',
                      hintText: 'Ex: 150.00',
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: rateCtrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      labelText: r'Cotação / Taxa de Câmbio (R$)',
                      hintText: 'Ex: 5.65',
                      prefixText: r'R$ ',
                      isDense: true,
                    ),
                    onChanged: (_) => setDialogState(() {}),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Convertido em Reais:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        Text(
                          totalBrl.formatted,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: totalBrlCents <= 0
                    ? null
                    : () {
                        Navigator.pop(dialogCtx);
                        setState(() {
                          _cents = totalBrlCents;
                          _amountFieldVersion++;
                          _foreignCurrencyTag =
                              '[Câmbio: $selectedCurrency ${foreignAmount.toStringAsFixed(2)} @ R\$ ${rate.toStringAsFixed(2)}]';
                        });
                      },
                child: const Text('Aplicar em R\$'),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Data que o formulário mostra ao editar uma despesa. Em compra no cartão o
/// vencimento guardado é o da fatura, então a data editável é a da compra;
/// nos demais casos é o vencimento, quando existe.
@visibleForTesting
DateTime editableDateOfExpense(HouseExpense expense, PaymentMethod? paymentMethod) {
  final isCardPurchase = paymentMethod != null &&
      paymentMethod.type == PaymentMethodType.card &&
      paymentMethod.closingDay != null &&
      paymentMethod.dueDay != null;
  if (isCardPurchase) return expense.date;
  return expense.dueDate ?? expense.date;
}

/// Rateio ao salvar a edição de uma despesa: mantém o que foi gravado no
/// lançamento. Só é refeito pelo padrão atual quando a categoria muda (ela pode
/// ter dono) ou quando a despesa entra ou sai de um projeto.
@visibleForTesting
SplitRule splitRuleForEdit(
  HouseExpense old,
  String newCategoryId,
  SplitRule defaultRule, {
  String? newProjectId,
}) =>
    newCategoryId == old.categoryId && newProjectId == old.projectId
        ? old.splitRule
        : defaultRule;
