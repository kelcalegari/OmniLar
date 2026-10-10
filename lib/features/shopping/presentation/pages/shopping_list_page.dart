import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../domain/entities/shopping_item.dart';
import '../../domain/entities/shopping_list.dart';
import '../cubit/shopping_cubit.dart';
import '../cubit/shopping_state.dart';

class ShoppingListPage extends StatefulWidget {
  const ShoppingListPage({super.key});

  @override
  State<ShoppingListPage> createState() => _ShoppingListPageState();
}

class _ShoppingListPageState extends State<ShoppingListPage> {
  final _addController = TextEditingController();
  bool _isPersonalNewItem = false;

  @override
  void dispose() {
    _addController.dispose();
    super.dispose();
  }

  void _onAddItem() {
    final text = _addController.text.trim();
    if (text.isEmpty) return;

    context.read<ShoppingCubit>().addItem(
          name: text,
          isPersonal: _isPersonalNewItem,
          assignedMemberId: _isPersonalNewItem ? 'member_marina' : null,
        );

    _addController.clear();
    setState(() {
      _isPersonalNewItem = false;
    });
  }

  void _showFinishTripSheet(BuildContext context, ShoppingState state) {
    final financeState = context.read<FinanceCubit>().state;
    final paymentMethods = financeState.paymentMethods;
    final members = financeState.members;

    final personalItems = state.items.where((i) => i.isBought && i.isPersonal).toList();
    final hasPersonal = personalItems.isNotEmpty;

    final amountController = TextEditingController();
    final personalAmountController = TextEditingController();
    String? selectedPmId = paymentMethods.isNotEmpty ? paymentMethods.first.id : null;
    String selectedPayerId = 'member_carlos';
    String selectedDebtorId = 'member_marina';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Row(
                    children: [
                      Icon(Icons.shopping_bag_outlined, color: AppColors.primary),
                      SizedBox(width: 8),
                      Text(
                        'Finalizar Compra da Casa',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Lança o gasto no Caixa da Casa e gera empréstimo P2P para itens pessoais.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),

                  // Valor Total
                  TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: 'Valor Total da Compra (Nota Fiscal)',
                      prefixText: 'R\$ ',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Forma de Pagamento
                  DropdownButtonFormField<String>(
                    value: selectedPmId,
                    decoration: InputDecoration(
                      labelText: 'Forma de Pagamento',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: paymentMethods.map((pm) {
                      return DropdownMenuItem(
                        value: pm.id,
                        child: Text(pm.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setSheetState(() => selectedPmId = val);
                    },
                  ),
                  const SizedBox(height: 12),

                  // Quem Pagou
                  DropdownButtonFormField<String>(
                    value: selectedPayerId,
                    decoration: InputDecoration(
                      labelText: 'Quem Pagou no Caixa',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    items: members.map((m) {
                      return DropdownMenuItem(
                        value: m.id,
                        child: Text(m.name),
                      );
                    }).toList(),
                    onChanged: (val) {
                      if (val != null) setSheetState(() => selectedPayerId = val);
                    },
                  ),

                  // Se houver itens pessoais comprados
                  if (hasPersonal) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.accent.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppColors.accent.withValues(alpha: 0.3)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.person_pin_circle_outlined, size: 16, color: AppColors.accent),
                              const SizedBox(width: 6),
                              Text(
                                '${personalItems.length} item pessoal no carrinho (${personalItems.map((i) => i.name).join(", ")})',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: AppColors.accent),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: personalAmountController,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            decoration: InputDecoration(
                              labelText: 'Subtotal dos Itens Pessoais',
                              prefixText: 'R\$ ',
                              isDense: true,
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        final total = Money.parse(amountController.text);
                        if (total.isZero) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Informe o valor total da compra')),
                          );
                          return;
                        }

                        Money? personalMoney;
                        if (personalAmountController.text.isNotEmpty) {
                          personalMoney = Money.parse(personalAmountController.text);
                        }

                        Navigator.pop(sheetCtx);

                        context.read<ShoppingCubit>().completeTrip(
                              totalAmount: total,
                              paymentMethodId: selectedPmId ?? 'pm_caixa',
                              paidByMemberId: selectedPayerId,
                              personalItemsAmount: personalMoney,
                              personalDebtorMemberId: selectedDebtorId,
                            );

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            backgroundColor: AppColors.creditGreen,
                            content: Text(
                              'Compra de ${total.formatted} registrada! Gasto lançado no Caixa da Casa. 🛒🎉',
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.check_circle_outline_rounded),
                      label: const Text('Confirmar e Lançar Gasto', style: TextStyle(fontWeight: FontWeight.bold)),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: 'Voltar ao painel',
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        title: const Text('Lista de Compras', style: TextStyle(fontWeight: FontWeight.bold)),
        actions: [
          BlocBuilder<ShoppingCubit, ShoppingState>(
            builder: (context, state) {
              return TextButton.icon(
                onPressed: () => context.read<ShoppingCubit>().toggleShoppingMode(),
                icon: Icon(
                  state.isShoppingMode ? Icons.shopping_basket : Icons.shopping_basket_outlined,
                  size: 18,
                  color: state.isShoppingMode ? AppColors.accent : null,
                ),
                label: Text(
                  state.isShoppingMode ? 'Sair Modo Mercado' : 'Modo Mercado',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: state.isShoppingMode ? AppColors.accent : null,
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: BlocBuilder<ShoppingCubit, ShoppingState>(
        builder: (context, state) {
          if (state.status == ShoppingCubitStatus.loading && state.items.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          final pendingItems = state.items.where((i) => !i.isBought).toList();
          final boughtItems = state.items.where((i) => i.isBought).toList();

          return Column(
            children: [
              // Barra de Seleção de Lista & Progresso
              _buildListsHeader(context, state),

              // Lista de Itens
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    if (pendingItems.isEmpty && boughtItems.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 60),
                        child: Center(
                          child: Column(
                            children: [
                              Icon(Icons.shopping_cart_outlined, size: 60, color: Colors.grey),
                              SizedBox(height: 16),
                              Text('Nenhum item na lista. Adicione abaixo!'),
                            ],
                          ),
                        ),
                      ),

                    // Pendentes
                    if (pendingItems.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                          'A COMPRAR',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1),
                        ),
                      ),
                      ...pendingItems.map((item) => _buildItemTile(context, item, state.isShoppingMode)),
                    ],

                    // Comprados
                    if (boughtItems.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'NO CARRINHO (${boughtItems.length})',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.creditGreen, letterSpacing: 1),
                          ),
                          if (boughtItems.isNotEmpty)
                            TextButton(
                              onPressed: () => _showFinishTripSheet(context, state),
                              child: const Text('Finalizar Compra ❯', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                            ),
                        ],
                      ),
                      ...boughtItems.map((item) => _buildItemTile(context, item, state.isShoppingMode)),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
              ),

              // Barra de Adição Rápida de Item no Rodapé
              _buildAddBar(context),
            ],
          );
        },
      ),
    );
  }

  Widget _buildListsHeader(BuildContext context, ShoppingState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(bottom: BorderSide(color: Colors.grey.withValues(alpha: 0.15))),
      ),
      child: Column(
        children: [
          Row(
            children: state.lists.map((list) {
              final isSelected = state.selectedList?.id == list.id;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(list.name),
                  onSelected: (_) => context.read<ShoppingCubit>().selectList(list),
                  selectedColor: AppColors.primary.withValues(alpha: 0.15),
                  checkmarkColor: AppColors.primary,
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    backgroundColor: Colors.grey.withValues(alpha: 0.2),
                    color: AppColors.primary,
                    minHeight: 6,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                '${state.boughtCount} de ${state.items.length}',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemTile(BuildContext context, ShoppingItem item, bool isShoppingMode) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: item.isBought
              ? AppColors.creditGreen.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: isShoppingMode ? 16 : 12, vertical: isShoppingMode ? 6 : 0),
        leading: IconButton(
          icon: Icon(
            item.isBought ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: item.isBought ? AppColors.creditGreen : Colors.grey,
            size: isShoppingMode ? 28 : 22,
          ),
          onPressed: () => context.read<ShoppingCubit>().toggleItemBought(item.id),
        ),
        title: Text(
          item.name,
          style: TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: isShoppingMode ? 16 : 14,
            decoration: item.isBought ? TextDecoration.lineThrough : null,
            color: item.isBought ? Colors.grey : null,
          ),
        ),
        subtitle: Row(
          children: [
            Text(
              '${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} ${item.unit}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            if (item.isPersonal) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Text('Pessoal', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: AppColors.accent)),
              ),
            ],
          ],
        ),
        trailing: !isShoppingMode
            ? IconButton(
                icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.grey),
                onPressed: () => context.read<ShoppingCubit>().deleteItem(item.id),
              )
            : null,
      ),
    );
  }

  Widget _buildAddBar(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border(top: BorderSide(color: Colors.grey.withValues(alpha: 0.2))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            // Checkbox de Item Pessoal
            IconButton(
              icon: Icon(
                _isPersonalNewItem ? Icons.person_rounded : Icons.person_outline_rounded,
                color: _isPersonalNewItem ? AppColors.accent : Colors.grey,
              ),
              tooltip: _isPersonalNewItem ? 'Item Pessoal (gera P2P)' : 'Marcar como Pessoal',
              onPressed: () {
                setState(() {
                  _isPersonalNewItem = !_isPersonalNewItem;
                });
              },
            ),
            Expanded(
              child: TextField(
                controller: _addController,
                decoration: InputDecoration(
                  hintText: _isPersonalNewItem ? 'Adicionar item pessoal...' : 'Adicionar item à lista...',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.3)),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onSubmitted: (_) => _onAddItem(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              icon: const Icon(Icons.add_rounded),
              onPressed: _onAddItem,
              style: IconButton.styleFrom(backgroundColor: AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
