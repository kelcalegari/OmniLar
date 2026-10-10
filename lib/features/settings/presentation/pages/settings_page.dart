import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/payment_method.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _showMembersModal(BuildContext context, String houseName, String houseId) {
    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                Text(
                  'Membros de $houseName',
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Todos os participantes dividem o Caixa e a rotina da casa.',
                  style: TextStyle(color: Colors.grey, fontSize: 13),
                ),
                const SizedBox(height: 20),

                // Cartão do Código de Convite
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppColors.primary.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 24),
                      ),
                      const SizedBox(width: 14),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Código de Convite:',
                              style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              'LAR123',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy_rounded, color: AppColors.primary),
                        tooltip: 'Copiar Código',
                        onPressed: () {
                          Clipboard.setData(const ClipboardData(text: 'LAR123'));
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Código LAR123 copiado para a área de transferência!')),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),

                const Text(
                  'Membros Ativos (2):',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 10),

                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primary,
                    child: Text('C', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: const Text('Carlos Eduardo', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('carlos@omnilar.com • 50% de rateio'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Proprietário', style: TextStyle(color: AppColors.primary, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.accent,
                    child: Text('M', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: const Text('Marina Silva', style: TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: const Text('marina@omnilar.com • 50% de rateio'),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text('Admin', style: TextStyle(color: AppColors.accent, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      );
    }

  void _showAssistantPreferencesModal(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Icon(Icons.auto_awesome_rounded, color: Colors.purple, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'Assistente & Privacidade',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              const Text(
                'Controle a inteligência artificial da casa e a proteção dos seus dados.',
                style: TextStyle(color: Colors.grey, fontSize: 13),
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Assistente Ativo', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Permite consultas e propostas por linguagem natural'),
                value: true,
                onChanged: (val) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Preferência de assistente atualizada.')),
                  );
                },
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Resumos e Alertas Proativos', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: const Text('Receber alertas de fôlego do ciclo e tarefas atrasadas'),
                value: true,
                onChanged: (val) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Alertas proativos atualizados.')),
                  );
                },
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('Horário Silencioso', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text('22:00 às 08:00 (Nenhum aviso emitido)'),
                trailing: Icon(Icons.bedtime_outlined, color: Colors.purple),
              ),
              const Divider(),
              Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.shield_outlined, color: AppColors.primary, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Privacidade LGPD: seus dados bancários, CPF e números de cartão são mascarados no dispositivo antes de qualquer processamento.',
                        style: TextStyle(fontSize: 12, color: AppColors.primary),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _showCategoriesModal(BuildContext context) {
    final financeCubit = context.read<FinanceCubit>();

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          final categories = financeCubit.state.categories;
          final members = financeCubit.state.members;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.category_outlined, color: AppColors.primary, size: 24),
                          SizedBox(width: 8),
                          Text(
                            'Categorias da Casa',
                            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                        tooltip: 'Nova Categoria',
                        onPressed: () {
                          _showAddCategoryDialog(context, financeCubit, members);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Categorias com dono direcionam 100% da responsabilidade para o membro escolhido.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: categories.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final cat = categories[index];
                        final owner = members.where((m) => m.id == cat.ownerMemberId).firstOrNull;

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                            child: const Icon(Icons.label_outline_rounded, size: 18, color: AppColors.primary),
                          ),
                          title: Text(cat.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            owner != null ? 'Responsável: 100% ${owner.name}' : 'Divisão padrão da casa',
                            style: TextStyle(
                              fontSize: 12,
                              color: owner != null ? AppColors.accent : Colors.grey,
                              fontWeight: owner != null ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                          trailing: owner != null
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.accent.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    owner.name,
                                    style: const TextStyle(color: AppColors.accent, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      _showAddCategoryDialog(context, financeCubit, members);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Cadastrar Nova Categoria'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddCategoryDialog(BuildContext context, FinanceCubit financeCubit, List<dynamic> members) {
    final nameController = TextEditingController();
    String? selectedOwnerId;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Nova Categoria de Gastos', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: nameController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: 'Nome da Categoria',
                    hintText: 'Ex: Farmácia, Academia, Pet Shop',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Dono Responsável (Opcional):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  value: selectedOwnerId,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Compartilhado (Divisão da Casa)'),
                    ),
                    ...members.map((m) => DropdownMenuItem<String?>(
                          value: m.id as String,
                          child: Text('100% ${m.name}'),
                        )),
                  ],
                  onChanged: (val) {
                    setDialogState(() {
                      selectedOwnerId = val;
                    });
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  final newCat = ExpenseCategory(
                    id: 'cat_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    icon: 'category',
                    colorHex: '#0F766E',
                    ownerMemberId: selectedOwnerId,
                  );

                  financeCubit.addCategory(newCat);
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Categoria "$name" cadastrada com sucesso! 🎉')),
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showSplitModelsModal(BuildContext context) {
    final financeCubit = context.read<FinanceCubit>();
    final members = financeCubit.state.members;

    double carlosPercent = members.isNotEmpty ? members[0].defaultSplitPercent : 50.0;
    double marinaPercent = members.length > 1 ? members[1].defaultSplitPercent : (100.0 - carlosPercent);
    String selectedModel = 'percentage'; // 'percentage', 'equal', 'category'

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                      Icon(Icons.tune_rounded, color: AppColors.accent, size: 24),
                      SizedBox(width: 8),
                      Text(
                        'Modelos de Rateio',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Defina como as despesas gerais da casa serão divididas entre os membros.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),

                  // Opções de Modelo
                  RadioListTile<String>(
                    title: const Text('Porcentagem Personalizada', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: Text('${carlosPercent.round()}% Carlos / ${marinaPercent.round()}% Marina'),
                    value: 'percentage',
                    groupValue: selectedModel,
                    onChanged: (val) => setModalState(() => selectedModel = val!),
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (selectedModel == 'percentage') ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text('Carlos: ${carlosPercent.round()}%', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              Text('Marina: ${marinaPercent.round()}%', style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                            ],
                          ),
                          Slider(
                            value: carlosPercent,
                            min: 10,
                            max: 90,
                            divisions: 16,
                            activeColor: AppColors.primary,
                            inactiveColor: AppColors.accent.withValues(alpha: 0.3),
                            onChanged: (val) {
                              setModalState(() {
                                carlosPercent = val;
                                marinaPercent = 100 - val;
                              });
                            },
                          ),
                          Wrap(
                            alignment: WrapAlignment.center,
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ActionChip(
                                label: const Text('50% / 50%'),
                                onPressed: () {
                                  setModalState(() {
                                    carlosPercent = 50.0;
                                    marinaPercent = 50.0;
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('60% / 40%'),
                                onPressed: () {
                                  setModalState(() {
                                    carlosPercent = 60.0;
                                    marinaPercent = 40.0;
                                  });
                                },
                              ),
                              ActionChip(
                                label: const Text('70% / 30%'),
                                onPressed: () {
                                  setModalState(() {
                                    carlosPercent = 70.0;
                                    marinaPercent = 30.0;
                                  });
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],

                  const Divider(),
                  RadioListTile<String>(
                    title: const Text('Por Categoria de Gasto', style: TextStyle(fontWeight: FontWeight.w600)),
                    subtitle: const Text('Despesas com dono (ex: Carro) vão 100% para ele; o resto divide igualmente.'),
                    value: 'category',
                    groupValue: selectedModel,
                    onChanged: (val) => setModalState(() => selectedModel = val!),
                    contentPadding: EdgeInsets.zero,
                  ),

                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            selectedModel == 'percentage'
                                ? 'Rateio atualizado: ${carlosPercent.round()}% Carlos e ${marinaPercent.round()}% Marina.'
                                : 'Rateio atualizado para: Por Categoria de Gasto.',
                          ),
                        ),
                      );
                    },
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Salvar Modelo de Rateio'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showPaymentMethodsModal(BuildContext context) {
    final financeCubit = context.read<FinanceCubit>();

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          final methods = financeCubit.state.paymentMethods;
          final members = financeCubit.state.members;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
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
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Expanded(
                        child: Row(
                          children: [
                            Icon(Icons.credit_card_rounded, color: Colors.orange, size: 24),
                            SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                'Formas de Pagamento',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline_rounded, color: AppColors.primary),
                        tooltip: 'Adicionar Cartão/Método',
                        onPressed: () {
                          _showAddPaymentMethodDialog(context, financeCubit, members);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Cadastre cartões de crédito e vales da casa para vincular faturas e vencimentos.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 16),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 360),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: methods.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final pm = methods[index];
                        final owner = members.where((m) => m.id == pm.ownerMemberId).firstOrNull;

                        IconData iconData;
                        Color iconColor;
                        if (pm.isCreditCard) {
                          iconData = Icons.credit_card_rounded;
                          iconColor = Colors.orange;
                        } else if (pm.isBenefit) {
                          iconData = Icons.restaurant_rounded;
                          iconColor = Colors.green;
                        } else {
                          iconData = Icons.account_balance_wallet_rounded;
                          iconColor = AppColors.primary;
                        }

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: iconColor.withValues(alpha: 0.15),
                            child: Icon(iconData, size: 18, color: iconColor),
                          ),
                          title: Text(pm.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(
                            pm.closingDay != null && pm.dueDay != null
                                ? 'Fecha dia ${pm.closingDay} • Vence dia ${pm.dueDay}'
                                : 'Conta / Débito imediato',
                            style: const TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                          trailing: owner != null
                              ? Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    owner.name,
                                    style: const TextStyle(color: AppColors.primary, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                )
                              : Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Text(
                                    'Casa',
                                    style: TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      _showAddPaymentMethodDialog(context, financeCubit, members);
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Cadastrar Cartão ou VR'),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _showAddPaymentMethodDialog(BuildContext context, FinanceCubit financeCubit, List<dynamic> members) {
    final nameController = TextEditingController();
    PaymentMethodType selectedType = PaymentMethodType.card;
    String? selectedOwnerId;
    int closingDay = 25;
    int dueDay = 5;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Nova Forma de Pagamento', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: InputDecoration(
                      labelText: 'Nome do Cartão ou Carteira',
                      hintText: 'Ex: Nubank Carlos, VR Alelo, Inter Marina',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text('Tipo:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<PaymentMethodType>(
                    value: selectedType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: const [
                      DropdownMenuItem(value: PaymentMethodType.card, child: Text('Cartão de Crédito')),
                      DropdownMenuItem(value: PaymentMethodType.vr, child: Text('Vale Refeição (VR)')),
                      DropdownMenuItem(value: PaymentMethodType.va, child: Text('Vale Alimentação (VA)')),
                      DropdownMenuItem(value: PaymentMethodType.pix, child: Text('Pix / Débito em Conta')),
                      DropdownMenuItem(value: PaymentMethodType.cash, child: Text('Dinheiro em Espécie')),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text('Titular do Cartão:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    value: selectedOwnerId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Compartilhado (Caixa da Casa)'),
                      ),
                      ...members.map((m) => DropdownMenuItem<String?>(
                            value: m.id as String,
                            child: Text(m.name as String),
                          )),
                    ],
                    onChanged: (val) => setDialogState(() => selectedOwnerId = val),
                  ),
                  if (selectedType == PaymentMethodType.card) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Fechamento:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                value: closingDay,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('Dia $d'))).toList(),
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => closingDay = val);
                                },
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Vencimento:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey)),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                value: dueDay,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                ),
                                items: List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('Dia $d'))).toList(),
                                onChanged: (val) {
                                  if (val != null) setDialogState(() => dueDay = val);
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final name = nameController.text.trim();
                  if (name.isEmpty) return;

                  final newPm = PaymentMethod(
                    id: 'pm_${DateTime.now().millisecondsSinceEpoch}',
                    name: name,
                    type: selectedType,
                    ownerMemberId: selectedOwnerId,
                    closingDay: selectedType == PaymentMethodType.card ? closingDay : null,
                    dueDay: selectedType == PaymentMethodType.card ? dueDay : null,
                  );

                  financeCubit.addPaymentMethod(newPm);
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Forma de pagamento "$name" cadastrada com sucesso! 🎉')),
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showCycleDayDialog(BuildContext context, int currentDay) {
    int selectedDay = currentDay;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Dia de Início do Ciclo', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'O ciclo financeiro da casa agrupa todas as faturas e despesas de um período para calcular o acerto mensal.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Todo dia $selectedDay',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.primary),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  value: selectedDay,
                  decoration: InputDecoration(
                    labelText: 'Selecione o Dia',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  items: List.generate(31, (i) => i + 1).map((d) => DropdownMenuItem(value: d, child: Text('Dia $d de cada mês'))).toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedDay = val);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Período do ciclo: dia $selectedDay ao dia ${selectedDay == 1 ? 31 : selectedDay - 1} do mês seguinte.',
                  style: const TextStyle(fontSize: 12, color: Colors.teal, fontWeight: FontWeight.w500),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogCtx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.pop(dialogCtx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Ciclo financeiro atualizado para o dia $selectedDay! 📅')),
                  );
                },
                style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _confirmSignOut(BuildContext context) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Sair do Omni Lar?'),
        content: const Text('Você precisará entrar com seu e-mail e senha novamente para acessar os dados da casa.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogCtx);
              context.read<AuthCubit>().signOut();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.debtRed,
              foregroundColor: Colors.white,
            ),
            child: const Text('Sair da Conta'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ajustes da Casa', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: BlocBuilder<AuthCubit, AuthState>(
        builder: (context, authState) {
          final user = authState.user;
          final house = authState.house;

          final userName = user?.fullName ?? 'Usuário';
          final userEmail = user?.email ?? 'sem e-mail';
          final houseName = house?.name ?? 'Minha Casa';
          final cycleDay = house?.cycleStartDay ?? 5;

          return SingleChildScrollView(
            child: ResponsiveContainer(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Card do Perfil e Casa Ativa
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.cardColor,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 26,
                        backgroundColor: AppColors.primary,
                        child: Text(
                          userName.isNotEmpty ? userName[0].toUpperCase() : 'U',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              userName,
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Text(
                              userEmail,
                              style: const TextStyle(fontSize: 13, color: Colors.grey),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                const Icon(Icons.home_outlined, size: 14, color: AppColors.primary),
                                const SizedBox(width: 4),
                                Text(
                                  '$houseName (Ciclo dia $cycleDay)',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: AppColors.primary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),

              ListTile(
                leading: const Icon(Icons.people_outline_rounded, color: AppColors.primary),
                title: const Text('Membros da Casa e Convites'),
                subtitle: const Text('Carlos, Marina • Código LAR123'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showMembersModal(context, houseName, house?.id ?? ''),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.category_outlined, color: AppColors.primary),
                title: const Text('Categorias de Gastos'),
                subtitle: const Text('Supermercado, Aluguel, Carro e donos'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showCategoriesModal(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.tune_rounded, color: AppColors.accent),
                title: const Text('Modelos de Rateio'),
                subtitle: const Text('Porcentagem (50/50), fixo ou categoria'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showSplitModelsModal(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.credit_card_rounded, color: Colors.orange),
                title: const Text('Cartões e Formas de Pagamento'),
                subtitle: const Text('Nubank Carlos, Inter Marina, VR Alelo'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showPaymentMethodsModal(context),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.calendar_today_outlined, color: Colors.teal),
                title: const Text('Ciclo Financeiro'),
                subtitle: Text('Dia $cycleDay ao dia ${cycleDay == 1 ? 31 : cycleDay - 1}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showCycleDayDialog(context, cycleDay),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.auto_awesome_rounded, color: Colors.purple),
                title: const Text('Assistente IA'),
                subtitle: const Text('Preferências e consentimento LGPD'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => _showAssistantPreferencesModal(context),
              ),
              const Divider(),
              const SizedBox(height: 16),

              // Botão Sair da Conta
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: OutlinedButton.icon(
                  onPressed: () => _confirmSignOut(context),
                  icon: const Icon(Icons.logout_rounded, color: AppColors.debtRed),
                  label: const Text(
                    'Sair da Conta',
                    style: TextStyle(color: AppColors.debtRed, fontWeight: FontWeight.bold),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    side: BorderSide(color: AppColors.debtRed.withValues(alpha: 0.4)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      );
    },
  ),
);
  }
}

