import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/utils/responsive.dart';
import '../../../../core/widgets/responsive_container.dart';
import '../../../auth/domain/repositories/auth_repository.dart';
import '../../../auth/domain/entities/user_profile.dart';
import '../../../auth/domain/entities/house.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../../auth/presentation/cubit/auth_state.dart';
import '../../../finance/presentation/cubit/finance_cubit.dart';
import '../../../finance/domain/entities/category.dart';
import '../../../finance/domain/entities/payment_method.dart';
import '../../../finance/presentation/cubit/finance_state.dart';
import '../../../finance/presentation/pages/add_expense_page.dart';
import '../../../finance/presentation/widgets/audit_log_sheet.dart';
import '../../../reconciliation/presentation/widgets/split_invoice_modal.dart';
import '../../../../core/domain/value_objects/money.dart';
import '../../../../core/widgets/recurrence_scope_dialog.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../../core/widgets/theme_toggle_button.dart';
import '../widgets/ai_key_config_sheet.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  void _showEditProfileModal(BuildContext context, UserProfile? user) {
    if (user == null) return;
    final nameController = TextEditingController(text: user.fullName);
    final emailController = TextEditingController(text: user.email);
    final pixKeyController = TextEditingController(text: user.pixKey ?? '');
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
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
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.manage_accounts_rounded,
                              color: AppColors.primary,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Editar Perfil da Conta',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Atualize seu nome de exibição, e-mail de acesso e Chave Pix para transferências e Super Pix.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: nameController,
                        decoration: InputDecoration(
                          labelText: 'Nome Completo',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe seu nome completo';
                          }
                          if (value.trim().length < 2) {
                            return 'O nome deve ter pelo menos 2 caracteres';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: 'E-mail da Conta',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Informe seu e-mail';
                          }
                          final emailRegex = RegExp(
                            r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$',
                          );
                          if (!emailRegex.hasMatch(value.trim())) {
                            return 'Informe um e-mail válido';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: pixKeyController,
                        decoration: InputDecoration(
                          labelText: 'Chave Pix (para receber acertos e Super Pix)',
                          hintText: 'Ex: CPF, e-mail, celular ou chave aleatória',
                          prefixIcon: const Icon(
                            Icons.pix_rounded,
                            color: AppColors.creditGreen,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.info_outline_rounded,
                              color: Colors.amber,
                              size: 20,
                            ),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Ao alterar seu e-mail, pode ser necessário confirmar o novo endereço através de um link enviado para a sua caixa postal.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.brown,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving
                                  ? null
                                  : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      if (!formKey.currentState!.validate())
                                        return;
                                      setModalState(() => isSaving = true);

                                      final newName = nameController.text
                                          .trim();
                                      final newEmail = emailController.text
                                          .trim();
                                      final newPixKey = pixKeyController.text
                                          .trim();
                                      final emailChanged =
                                          newEmail.toLowerCase() !=
                                          user.email.toLowerCase();
                                      final messenger = ScaffoldMessenger.of(
                                        context,
                                      );
                                      final navigator = Navigator.of(context);

                                      try {
                                        await context
                                            .read<AuthCubit>()
                                            .updateProfile(
                                              fullName: newName,
                                              email: newEmail,
                                              pixKey: newPixKey,
                                            );
                                        navigator.pop();
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              emailChanged
                                                  ? 'Perfil atualizado! Verifique a confirmação em $newEmail caso necessário.'
                                                  : 'Perfil atualizado com sucesso! ✨',
                                            ),
                                            backgroundColor: AppColors.primary,
                                          ),
                                        );
                                      } catch (e) {
                                        setModalState(() => isSaving = false);
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              'Erro ao atualizar: ${e.toString().replaceAll("AuthFailure:", "").trim()}',
                                            ),
                                            backgroundColor: AppColors.debtRed,
                                          ),
                                        );
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                padding: const EdgeInsets.symmetric(
                                  vertical: 14,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text(
                                      'Salvar',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _showMembersModal(
    BuildContext context,
    String houseName,
    String houseId,
  ) {
    final authRepo = sl<AuthRepository>();
    final isDemo = authRepo.isDemoMode;

    Future<Map<String, dynamic>> loadData() async {
      if (isDemo || houseId.isEmpty) {
        return {
          'code': 'LAR123',
          'members': [
            {
              'name': 'Carlos Eduardo',
              'email': 'carlos@omnilar.com',
              'pixKey': 'carlos@omnilar.com',
              'role': 'Proprietário',
              'initial': 'C',
              'color': AppColors.primary,
            },
            {
              'name': 'Marina Silva',
              'email': 'marina@omnilar.com',
              'pixKey': 'marina@omnilar.com',
              'role': 'Admin',
              'initial': 'M',
              'color': AppColors.accent,
            },
          ],
        };
      }
      try {
        // Só admins geram convite; os demais continuam vendo a lista de moradores.
        var code = '---';
        try {
          code = await authRepo.createHouseInvite(houseId);
        } catch (_) {}
        final membersInfo = await authRepo.getHouseMembers(houseId);
        final list = membersInfo.map((m) {
          final name = m.profile?.fullName ?? 'Membro';
          final email = m.profile?.email ?? '';
          final pixKey = m.profile?.pixKey;
          final initial = name.isNotEmpty ? name[0].toUpperCase() : 'M';
          final role = m.role == 'owner'
              ? 'Proprietário'
              : (m.role == 'admin' ? 'Admin' : 'Membro');
          return {
            'name': name,
            'email': email,
            'pixKey': pixKey,
            'role': role,
            'initial': initial,
            'color': m.role == 'owner' ? AppColors.primary : AppColors.accent,
          };
        }).toList();

        if (list.isEmpty && authRepo.currentUser != null) {
          final u = authRepo.currentUser!;
          list.add({
            'name': u.fullName,
            'email': u.email,
            'pixKey': u.pixKey,
            'role': 'Proprietário',
            'initial': u.fullName.isNotEmpty
                ? u.fullName[0].toUpperCase()
                : 'U',
            'color': AppColors.primary,
          });
        }
        return {'code': code, 'members': list};
      } catch (_) {
        final u = authRepo.currentUser;
        return {
          'code': '---',
          'members': [
            if (u != null)
              {
                'name': u.fullName,
                'email': u.email,
                'role': 'Proprietário',
                'initial': u.fullName.isNotEmpty
                    ? u.fullName[0].toUpperCase()
                    : 'U',
                'color': AppColors.primary,
              },
          ],
        };
      }
    }

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: FutureBuilder<Map<String, dynamic>>(
            future: loadData(),
            builder: (context, snapshot) {
              final data = snapshot.data;
              final code =
                  data?['code'] as String? ??
                  (isDemo ? 'LAR123' : 'Carregando...');
              final members = (data?['members'] as List<dynamic>?) ?? [];

              return SingleChildScrollView(
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
                    Text(
                      'Membros de $houseName',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
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
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.vpn_key_rounded,
                              color: Colors.white,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Código de Convite:',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                Text(
                                  code,
                                  style: const TextStyle(
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
                            icon: const Icon(
                              Icons.copy_rounded,
                              color: AppColors.primary,
                            ),
                            tooltip: 'Copiar Código',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: code));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'Código $code copiado para a área de transferência!',
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      'Membros Ativos (${members.length}):',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),

                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(16),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else
                      ...members.map((m) {
                        final mName = m['name'] as String;
                        final mEmail = m['email'] as String;
                        final mPixKey = m['pixKey'] as String?;
                        final mRole = m['role'] as String;
                        final mInitial = m['initial'] as String;
                        final mColor = m['color'] as Color;

                        return Column(
                          children: [
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              leading: CircleAvatar(
                                backgroundColor: mColor,
                                child: Text(
                                  mInitial,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                mName,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (mEmail.isNotEmpty) Text(mEmail),
                                  if (mPixKey != null && mPixKey.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 2),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.pix_rounded,
                                            size: 12,
                                            color: AppColors.creditGreen,
                                          ),
                                          const SizedBox(width: 4),
                                          Flexible(
                                            child: Text(
                                              'Pix: $mPixKey',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: AppColors.creditGreen,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                ],
                              ),
                              trailing: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: mColor.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  mRole,
                                  style: TextStyle(
                                    color: mColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                            const Divider(),
                          ],
                        );
                      }),
                    const SizedBox(height: 16),
                  ],
                ),
              );
            },
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
          child: SingleChildScrollView(
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
                    Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.purple,
                      size: 24,
                    ),
                    SizedBox(width: 8),
                    Text(
                      'Assistente & Privacidade',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
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
                  title: const Text(
                    'Assistente Ativo',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Permite consultas e propostas por linguagem natural',
                  ),
                  value: true,
                  onChanged: (val) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Preferência de assistente atualizada.'),
                      ),
                    );
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Resumos e Alertas Proativos',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Receber alertas de fôlego do ciclo e tarefas atrasadas',
                  ),
                  value: true,
                  onChanged: (val) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Alertas proativos atualizados.'),
                      ),
                    );
                  },
                ),
                const Divider(),
                const ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    'Horário Silencioso',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text('22:00 às 08:00 (Nenhum aviso emitido)'),
                  trailing: Icon(Icons.bedtime_outlined, color: Colors.purple),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.vpn_key_rounded, color: Colors.purple),
                  title: const Text(
                    'Chave de IA & Modelo (BYOK)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: const Text(
                    'Cadastre sua chave gratuita do Google AI Studio ou use a padrão',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () {
                    Navigator.pop(context);
                    AiKeyConfigSheet.show(context);
                  },
                ),
                const Divider(),
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Privacidade LGPD: seus dados bancários, CPF e números de cartão são mascarados no dispositivo antes de qualquer processamento.',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                          ),
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
              child: SingleChildScrollView(
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
                            Icon(
                              Icons.category_outlined,
                              color: AppColors.primary,
                              size: 24,
                            ),
                            SizedBox(width: 8),
                            Text(
                              'Categorias da Casa',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            color: AppColors.primary,
                          ),
                          tooltip: 'Nova Categoria',
                          onPressed: () {
                            _showAddCategoryDialog(
                              context,
                              financeCubit,
                              members,
                            );
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
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: categories.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final cat = categories[index];
                          final owner = members
                              .where((m) => m.id == cat.ownerMemberId)
                              .firstOrNull;

                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              radius: 18,
                              backgroundColor: AppColors.primary.withValues(
                                alpha: 0.15,
                              ),
                              child: const Icon(
                                Icons.label_outline_rounded,
                                size: 18,
                                color: AppColors.primary,
                              ),
                            ),
                            title: Text(
                              cat.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(
                              owner != null
                                  ? 'Responsável: 100% ${owner.name}'
                                  : 'Divisão padrão da casa',
                              style: TextStyle(
                                fontSize: 12,
                                color: owner != null
                                    ? AppColors.accent
                                    : Colors.grey,
                                fontWeight: owner != null
                                    ? FontWeight.w600
                                    : FontWeight.normal,
                              ),
                            ),
                            trailing: owner != null
                                ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppColors.accent.withValues(
                                        alpha: 0.1,
                                      ),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      owner.name,
                                      style: const TextStyle(
                                        color: AppColors.accent,
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
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
            ),
          );
        },
      ),
    );
  }

  void _showAddCategoryDialog(
    BuildContext context,
    FinanceCubit financeCubit,
    List<dynamic> members,
  ) {
    final nameController = TextEditingController();
    String? selectedOwnerId;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text(
              'Nova Categoria de Gastos',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
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
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Dono Responsável (Opcional):',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(height: 6),
                DropdownButtonFormField<String?>(
                  initialValue: selectedOwnerId,
                  decoration: InputDecoration(
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Compartilhado (Divisão da Casa)'),
                    ),
                    ...members.map(
                      (m) => DropdownMenuItem<String?>(
                        value: m.id as String,
                        child: Text('100% ${m.name}'),
                      ),
                    ),
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
                    SnackBar(
                      content: Text(
                        'Categoria "$name" cadastrada com sucesso! 🎉',
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
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
    final authRepo = sl<AuthRepository>();
    final isDemo = authRepo.isDemoMode;
    final currentUser = authRepo.currentUser;

    final name1 = isDemo
        ? 'Carlos'
        : (members.isNotEmpty
              ? members[0].name.split(' ').first
              : (currentUser?.fullName.isNotEmpty == true
                    ? currentUser!.fullName.split(' ').first
                    : 'Você'));
    final name2 = isDemo
        ? 'Marina'
        : (members.length > 1
              ? members[1].name.split(' ').first
              : 'Parceiro(a)');

    // Determina o modelo ativo baseado nos dados dos membros
    final hasFixedActive = members.any((m) => (m.defaultFixedAmountCents ?? 0) > 0);
    String selectedModel = hasFixedActive ? 'fixed' : 'percentage';

    double percent1 = members.isNotEmpty
        ? members[0].defaultSplitPercent
        : 50.0;
    double percent2 = members.length > 1
        ? members[1].defaultSplitPercent
        : (100.0 - percent1);

    // Aportes fixos por membro (ex: Balde Comum)
    final fixedAmountsByMember = <String, int>{};
    for (int i = 0; i < members.length; i++) {
      final m = members[i];
      if ((m.defaultFixedAmountCents ?? 0) > 0) {
        fixedAmountsByMember[m.id] = m.defaultFixedAmountCents!;
      } else if (i == 0) {
        fixedAmountsByMember[m.id] = 70000; // R$ 700,00 padrão
      } else if (i == 1) {
        fixedAmountsByMember[m.id] = 130000; // R$ 1.300,00 padrão
      } else {
        fixedAmountsByMember[m.id] = 100000;
      }
    }
    String deficitPolicy = 'proportional'; // 'proportional' ou 'equal'

    showAdaptiveModal(
      context: context,
      maxWidth: 500,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
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
                        Icon(
                          Icons.tune_rounded,
                          color: AppColors.accent,
                          size: 24,
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Modelos de Rateio',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Defina como as despesas gerais da casa serão divididas entre os membros.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // 1. Porcentagem Personalizada
                    RadioListTile<String>(
                      title: const Text(
                        'Porcentagem Personalizada',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${percent1.round()}% $name1 / ${percent2.round()}% $name2',
                      ),
                      value: 'percentage',
                      groupValue: selectedModel,
                      onChanged: (val) =>
                          setModalState(() => selectedModel = val!),
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
                                Text(
                                  '$name1: ${percent1.round()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                                Text(
                                  '$name2: ${percent2.round()}%',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                  ),
                                ),
                              ],
                            ),
                            Slider(
                              value: percent1,
                              min: 10,
                              max: 90,
                              divisions: 16,
                              activeColor: AppColors.primary,
                              inactiveColor: AppColors.accent.withValues(
                                alpha: 0.3,
                              ),
                              onChanged: (val) {
                                setModalState(() {
                                  percent1 = val;
                                  percent2 = 100 - val;
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
                                      percent1 = 50.0;
                                      percent2 = 50.0;
                                    });
                                  },
                                ),
                                ActionChip(
                                  label: const Text('60% / 40%'),
                                  onPressed: () {
                                    setModalState(() {
                                      percent1 = 60.0;
                                      percent2 = 40.0;
                                    });
                                  },
                                ),
                                ActionChip(
                                  label: const Text('70% / 30%'),
                                  onPressed: () {
                                    setModalState(() {
                                      percent1 = 70.0;
                                      percent2 = 30.0;
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

                    // 2. Aportes Fixos (Balde Comum / Orçamento Base)
                    RadioListTile<String>(
                      title: const Text(
                        'Aportes Fixos (Balde Comum)',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Cada membro aporta um valor fixo estipulado. Sobras vão pro cofre e déficit é coberto pela reserva ou rateado.',
                      ),
                      value: 'fixed',
                      groupValue: selectedModel,
                      onChanged: (val) =>
                          setModalState(() => selectedModel = val!),
                      contentPadding: EdgeInsets.zero,
                    ),
                    if (selectedModel == 'fixed') ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            ...members.map((m) {
                              final currentCents =
                                  fixedAmountsByMember[m.id] ?? 100000;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).cardColor,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.grey.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.spaceBetween,
                                      children: [
                                        Expanded(
                                          child: Text(
                                            'Aporte de ${m.name}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        InkWell(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                          onTap: () {
                                            final controller =
                                                TextEditingController(
                                                  text: (currentCents / 100)
                                                      .toStringAsFixed(0),
                                                );
                                            showDialog(
                                              context: context,
                                              builder: (dialogCtx) => AlertDialog(
                                                title: Text(
                                                  'Aporte de ${m.name}',
                                                ),
                                                content: TextField(
                                                  controller: controller,
                                                  keyboardType:
                                                      TextInputType.number,
                                                  autofocus: true,
                                                  decoration:
                                                      const InputDecoration(
                                                        prefixText: 'R\$ ',
                                                        labelText:
                                                            'Valor mensal',
                                                        border:
                                                            OutlineInputBorder(),
                                                      ),
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          dialogCtx,
                                                        ),
                                                    child: const Text(
                                                      'Cancelar',
                                                    ),
                                                  ),
                                                  FilledButton(
                                                    onPressed: () {
                                                      final val =
                                                          double.tryParse(
                                                            controller.text
                                                                .replaceAll(
                                                                  ',',
                                                                  '.',
                                                                ),
                                                          );
                                                      if (val != null &&
                                                          val > 0) {
                                                        setModalState(() {
                                                          fixedAmountsByMember[m
                                                              .id] = (val * 100)
                                                              .round();
                                                        });
                                                      }
                                                      Navigator.pop(dialogCtx);
                                                    },
                                                    child: const Text(
                                                      'Confirmar',
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 10,
                                              vertical: 5,
                                            ),
                                            decoration: BoxDecoration(
                                              color: AppColors.primary
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  Money(currentCents).format(),
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    color: AppColors.primary,
                                                    fontSize: 14,
                                                  ),
                                                ),
                                                const SizedBox(width: 4),
                                                const Icon(
                                                  Icons.edit_outlined,
                                                  size: 14,
                                                  color: AppColors.primary,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    SingleChildScrollView(
                                      scrollDirection: Axis.horizontal,
                                      child: Row(
                                        children:
                                            [
                                              50000,
                                              70000,
                                              100000,
                                              130000,
                                              150000,
                                              200000,
                                            ].map((cents) {
                                              final isSelected =
                                                  currentCents == cents;
                                              return Padding(
                                                padding: const EdgeInsets.only(
                                                  right: 6,
                                                ),
                                                child: ChoiceChip(
                                                  visualDensity:
                                                      VisualDensity.compact,
                                                  label: Text(
                                                    Money(cents).format(),
                                                    style: const TextStyle(
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                  selected: isSelected,
                                                  selectedColor: AppColors
                                                      .primary
                                                      .withValues(alpha: 0.2),
                                                  onSelected: (sel) {
                                                    if (sel) {
                                                      setModalState(() {
                                                        fixedAmountsByMember[m
                                                                .id] =
                                                            cents;
                                                      });
                                                    }
                                                  },
                                                ),
                                              );
                                            }).toList(),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }),
                            Builder(
                              builder: (ctx) {
                                final totalBalde = fixedAmountsByMember.values
                                    .fold<int>(0, (a, b) => a + b);
                                final proportions = members
                                    .map((m) {
                                      final val =
                                          fixedAmountsByMember[m.id] ?? 0;
                                      final pct = totalBalde > 0
                                          ? (val / totalBalde * 100).round()
                                          : 0;
                                      return '${m.name} ($pct%)';
                                    })
                                    .join(' • ');

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.primary.withValues(
                                      alpha: 0.08,
                                    ),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: AppColors.primary.withValues(
                                        alpha: 0.25,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          const Expanded(
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Icon(
                                                  Icons
                                                      .account_balance_wallet_outlined,
                                                  color: AppColors.primary,
                                                  size: 18,
                                                ),
                                                SizedBox(width: 8),
                                                Flexible(
                                                  child: Text(
                                                    'Balde Mensal Previsto:',
                                                    style: TextStyle(
                                                      fontSize: 13,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                    ),
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            Money(totalBalde).format(),
                                            style: const TextStyle(
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold,
                                              color: AppColors.primary,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (proportions.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Text(
                                          'Proporção calculada: $proportions',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.grey.shade600,
                                          ),
                                        ),
                                      ],
                                      const Divider(height: 16),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.savings_outlined,
                                            color: Colors.green,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Sobra do ciclo: Se os gastos forem menores que o balde, a sobra fica no Cofre da Casa como reserva.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          const Icon(
                                            Icons.shield_outlined,
                                            color: Colors.orange,
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              'Se faltar (Déficit): A Casa consome primeiro a reserva do cofre. Se o cofre não cobrir, haverá rateio do excedente.',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: Colors.grey.shade800,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      const Text(
                                        'Divisão do excedente (se o cofre não cobrir):',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ChoiceChip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: const Text(
                                                'Proporcional',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              selected:
                                                  deficitPolicy ==
                                                  'proportional',
                                              selectedColor: AppColors.primary
                                                  .withValues(alpha: 0.2),
                                              onSelected: (sel) {
                                                if (sel)
                                                  setModalState(
                                                    () => deficitPolicy =
                                                        'proportional',
                                                  );
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ChoiceChip(
                                              visualDensity:
                                                  VisualDensity.compact,
                                              label: const Text(
                                                '50% / 50%',
                                                style: TextStyle(fontSize: 11),
                                              ),
                                              selected:
                                                  deficitPolicy == 'equal',
                                              selectedColor: AppColors.primary
                                                  .withValues(alpha: 0.2),
                                              onSelected: (sel) {
                                                if (sel)
                                                  setModalState(
                                                    () =>
                                                        deficitPolicy = 'equal',
                                                  );
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],

                    const Divider(),

                    // 3. Por Categoria com Dono
                    RadioListTile<String>(
                      title: const Text(
                        'Por Categoria de Gasto',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: const Text(
                        'Despesas com dono (ex: Carro) vão 100% para ele; o resto divide igualmente.',
                      ),
                      value: 'category',
                      groupValue: selectedModel,
                      onChanged: (val) =>
                          setModalState(() => selectedModel = val!),
                      contentPadding: EdgeInsets.zero,
                    ),

                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () {
                        Navigator.pop(context);

                        // Monta os percentuais e quantias nominais para persistência
                        final percentages = <String, double>{};
                        final fixedAmounts = <String, int>{};

                        if (selectedModel == 'percentage') {
                          if (members.isNotEmpty) percentages[members[0].id] = percent1;
                          if (members.length > 1) percentages[members[1].id] = percent2;
                          // Reseta valores fixos quando estiver no modelo percentual
                          for (final m in members) {
                            fixedAmounts[m.id] = 0;
                          }
                        } else if (selectedModel == 'fixed') {
                          final totalBalde = fixedAmountsByMember.values.fold<int>(0, (a, b) => a + b);
                          for (final m in members) {
                            final val = fixedAmountsByMember[m.id] ?? 0;
                            fixedAmounts[m.id] = val;
                            percentages[m.id] = totalBalde > 0 ? (val / totalBalde * 100) : (100.0 / members.length);
                          }
                        } else {
                          // Modelo por categoria de gasto: mantém 50/50 como base geral
                          final equalShare = members.isNotEmpty ? (100.0 / members.length) : 50.0;
                          for (final m in members) {
                            percentages[m.id] = equalShare;
                            fixedAmounts[m.id] = 0;
                          }
                        }

                        // Persiste no Cubit / Banco / Mock
                        financeCubit.updateHouseSplitModel(
                          splitModel: selectedModel,
                          percentages: percentages,
                          fixedAmountsCents: fixedAmounts,
                        );

                        String feedback;
                        if (selectedModel == 'percentage') {
                          feedback =
                              'Rateio atualizado: ${percent1.round()}% $name1 e ${percent2.round()}% $name2.';
                        } else if (selectedModel == 'fixed') {
                          final totalBalde = fixedAmountsByMember.values
                              .fold<int>(0, (a, b) => a + b);
                          final parts = members
                              .map((m) {
                                final val = fixedAmountsByMember[m.id] ?? 0;
                                return '${m.name}: ${Money(val).format()}';
                              })
                              .join(' + ');
                          feedback =
                              'Rateio atualizado: Balde de ${Money(totalBalde).format()} ($parts). Sobras para o cofre da casa.';
                        } else {
                          feedback =
                              'Rateio atualizado para: Por Categoria de Gasto.';
                        }

                        ScaffoldMessenger.of(
                          context,
                        ).showSnackBar(SnackBar(content: Text(feedback)));
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
      child: BlocBuilder<FinanceCubit, FinanceState>(
        builder: (context, financeState) {
          final methods = financeState.paymentMethods;
          final members = financeState.members;

          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
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
                              Icon(
                                Icons.credit_card_rounded,
                                color: Colors.orange,
                                size: 24,
                              ),
                              SizedBox(width: 8),
                              Flexible(
                                child: Text(
                                  'Formas de Pagamento',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(
                            Icons.add_circle_outline_rounded,
                            color: AppColors.primary,
                          ),
                          tooltip: 'Adicionar Cartão/Método',
                          onPressed: () {
                            _showAddPaymentMethodDialog(
                              context,
                              financeCubit,
                              members,
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Cadastre cartões de crédito e vales da casa para vincular faturas e vencimentos. Toque em uma forma para editar.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),
                    if (methods.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(
                          child: Text(
                            'Nenhuma forma de pagamento cadastrada.',
                            style: TextStyle(color: Colors.grey),
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 280),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: methods.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, index) {
                            final pm = methods[index];
                            final owner = members
                                .where((m) => m.id == pm.ownerMemberId)
                                .firstOrNull;

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
                                backgroundColor: iconColor.withValues(
                                  alpha: 0.15,
                                ),
                                child: Icon(iconData, size: 18, color: iconColor),
                              ),
                              title: Text(
                                pm.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                pm.closingDay != null && pm.dueDay != null
                                    ? 'Fecha dia ${pm.closingDay} • Vence dia ${pm.dueDay}'
                                    : 'Conta / Débito imediato',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey,
                                ),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (owner != null)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.primary.withValues(
                                          alpha: 0.1,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        owner.name,
                                        style: const TextStyle(
                                          color: AppColors.primary,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: const Text(
                                        'Casa',
                                        style: TextStyle(
                                          color: Colors.grey,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  PopupMenuButton<String>(
                                    icon: const Icon(
                                      Icons.more_vert,
                                      size: 20,
                                      color: Colors.grey,
                                    ),
                                    tooltip: 'Opções',
                                    onSelected: (action) {
                                      if (action == 'edit') {
                                        _showPaymentMethodFormDialog(
                                          context: context,
                                          financeCubit: financeCubit,
                                          members: members,
                                          existingPm: pm,
                                        );
                                      } else if (action == 'delete') {
                                        _confirmDeletePaymentMethod(
                                          context,
                                          financeCubit,
                                          pm,
                                          methods.length,
                                        );
                                      }
                                    },
                                    itemBuilder: (context) => [
                                      const PopupMenuItem(
                                        value: 'edit',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.edit_outlined,
                                              size: 18,
                                              color: AppColors.primary,
                                            ),
                                            SizedBox(width: 8),
                                            Text('Editar'),
                                          ],
                                        ),
                                      ),
                                      const PopupMenuItem(
                                        value: 'delete',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.delete_outline_rounded,
                                              size: 18,
                                              color: AppColors.debtRed,
                                            ),
                                            SizedBox(width: 8),
                                            Text(
                                              'Excluir',
                                              style: TextStyle(
                                                color: AppColors.debtRed,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                              onTap: () {
                                _showPaymentMethodFormDialog(
                                  context: context,
                                  financeCubit: financeCubit,
                                  members: members,
                                  existingPm: pm,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () {
                        _showAddPaymentMethodDialog(
                          context,
                          financeCubit,
                          members,
                        );
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
            ),
          );
        },
      ),
    );
  }

  void _confirmDeletePaymentMethod(
    BuildContext context,
    FinanceCubit financeCubit,
    PaymentMethod pm,
    int totalMethods,
  ) {
    if (totalMethods <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Não é possível excluir a única forma de pagamento da casa. Cadastre outra antes de excluir esta.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text(
          'Excluir Forma de Pagamento',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        content: Text(
          'Deseja realmente excluir "${pm.name}"?\n\n'
          'As despesas já registradas permanecerão vinculadas, mas esta forma não aparecerá mais para novos lançamentos.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.debtRed,
            ),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              await financeCubit.deletePaymentMethod(pm.id);
              if (context.mounted) {
                if (financeCubit.state.status == FinanceStatus.failure) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        financeCubit.state.errorMessage ??
                            'Não foi possível excluir a forma de pagamento.',
                      ),
                      backgroundColor: Colors.red.shade700,
                    ),
                  );
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Forma de pagamento "${pm.name}" removida com sucesso.',
                      ),
                    ),
                  );
                }
              }
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
  }

  void _showAddPaymentMethodDialog(
    BuildContext context,
    FinanceCubit financeCubit,
    List<dynamic> members,
  ) {
    _showPaymentMethodFormDialog(
      context: context,
      financeCubit: financeCubit,
      members: members,
    );
  }

  void _showPaymentMethodFormDialog({
    required BuildContext context,
    required FinanceCubit financeCubit,
    required List<dynamic> members,
    PaymentMethod? existingPm,
  }) {
    final nameController = TextEditingController(text: existingPm?.name ?? '');
    PaymentMethodType selectedType = existingPm?.type ?? PaymentMethodType.card;
    String? selectedOwnerId = existingPm?.ownerMemberId;
    int closingDay = existingPm?.closingDay ?? 25;
    int dueDay = existingPm?.dueDay ?? 5;
    final isEditing = existingPm != null;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text(
              isEditing ? 'Editar Forma de Pagamento' : 'Nova Forma de Pagamento',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: !isEditing,
                    decoration: InputDecoration(
                      labelText: 'Nome do Cartão ou Carteira',
                      hintText: sl<AuthRepository>().isDemoMode
                          ? 'Ex: Nubank Carlos, VR Alelo, Inter Marina'
                          : 'Ex: Nubank, Cartão Inter, VR Alelo',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Tipo:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<PaymentMethodType>(
                    initialValue: selectedType,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: PaymentMethodType.card,
                        child: Text('Cartão de Crédito'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.vr,
                        child: Text('Vale Refeição (VR)'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.va,
                        child: Text('Vale Alimentação (VA)'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.pix,
                        child: Text('Pix / Débito em Conta'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.account,
                        child: Text('Conta Corrente / Caixa da Casa'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.cash,
                        child: Text('Dinheiro em Espécie'),
                      ),
                      DropdownMenuItem(
                        value: PaymentMethodType.other,
                        child: Text('Outro'),
                      ),
                    ],
                    onChanged: (val) {
                      if (val != null) setDialogState(() => selectedType = val);
                    },
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Titular do Cartão:',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String?>(
                    initialValue: selectedOwnerId,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('Compartilhado (Caixa da Casa)'),
                      ),
                      ...members.map(
                        (m) => DropdownMenuItem<String?>(
                          value: m.id as String,
                          child: Text(m.name as String),
                        ),
                      ),
                    ],
                    onChanged: (val) =>
                        setDialogState(() => selectedOwnerId = val),
                  ),
                  if (selectedType == PaymentMethodType.card) ...[
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Fechamento:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                initialValue: closingDay,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: List.generate(31, (i) => i + 1)
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text('Dia $d'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null)
                                    setDialogState(() => closingDay = val);
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
                              const Text(
                                'Vencimento:',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey,
                                ),
                              ),
                              const SizedBox(height: 6),
                              DropdownButtonFormField<int>(
                                initialValue: dueDay,
                                decoration: InputDecoration(
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                ),
                                items: List.generate(31, (i) => i + 1)
                                    .map(
                                      (d) => DropdownMenuItem(
                                        value: d,
                                        child: Text('Dia $d'),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (val) {
                                  if (val != null)
                                    setDialogState(() => dueDay = val);
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

                  if (isEditing) {
                    final updatedPm = existingPm.copyWith(
                      name: name,
                      type: selectedType,
                      ownerMemberId: selectedOwnerId,
                      clearOwner: selectedOwnerId == null,
                      closingDay: selectedType == PaymentMethodType.card
                          ? closingDay
                          : null,
                      clearClosingDay: selectedType != PaymentMethodType.card,
                      dueDay: selectedType == PaymentMethodType.card
                          ? dueDay
                          : null,
                      clearDueDay: selectedType != PaymentMethodType.card,
                    );

                    financeCubit.updatePaymentMethod(updatedPm);
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Forma de pagamento "$name" atualizada com sucesso! ✨',
                        ),
                      ),
                    );
                  } else {
                    final newPm = PaymentMethod(
                      id: 'pm_${DateTime.now().millisecondsSinceEpoch}',
                      name: name,
                      type: selectedType,
                      ownerMemberId: selectedOwnerId,
                      closingDay: selectedType == PaymentMethodType.card
                          ? closingDay
                          : null,
                      dueDay: selectedType == PaymentMethodType.card
                          ? dueDay
                          : null,
                    );

                    financeCubit.addPaymentMethod(newPm);
                    Navigator.pop(dialogCtx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'Forma de pagamento "$name" cadastrada com sucesso! 🎉',
                        ),
                      ),
                    );
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: Text(isEditing ? 'Salvar Alterações' : 'Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showRecurringExpensesModal(BuildContext context) {
    showAdaptiveModal(
      context: context,
      maxWidth: 540,
      child: SafeArea(
        child: BlocBuilder<FinanceCubit, FinanceState>(
          builder: (context, financeState) {
            final recurring = financeState.expenses
                .where((e) => e.isRecurring)
                .toList();
            final totalCents = recurring.fold(
              0,
              (sum, e) => sum + e.amount.cents,
            );

            return Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
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
                          child: Text(
                            'Assinaturas & Contas Fixas',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const Text(
                      'Compromissos mensais provisionados automaticamente no Fôlego da Casa.',
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                    const SizedBox(height: 16),

                    // Card de Resumo do Custo Mensal
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: AppColors.primary.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Comprometimento Mensal',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.grey,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Total Provisionado',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            Money(totalCents).format(),
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Lista de Despesas Recorrentes
                    if (recurring.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'Nenhuma despesa recorrente cadastrada ainda.',
                          ),
                        ),
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: ListView.separated(
                          shrinkWrap: true,
                          itemCount: recurring.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final item = recurring[index];
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(context).cardColor,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.grey.withValues(alpha: 0.15),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.isVariable
                                        ? Icons.trending_up_rounded
                                        : Icons.lock_clock_rounded,
                                    color: AppColors.primary,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          item.title,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                        Text(
                                          '${item.isVariable ? "Consumo Variável" : "Assinatura Fixa"} • Vence dia ${item.dueDay ?? item.dueDate?.day ?? "—"}',
                                          style: const TextStyle(
                                            color: Colors.grey,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        item.amount.format(),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      InkWell(
                                        onTap: () async {
                                          final scope =
                                              await showRecurrenceScopeDialog(
                                                context: context,
                                                itemTitle: item.title,
                                                isDelete: true,
                                                isExpense: true,
                                              );
                                          if (scope != null) {
                                            if (!context.mounted) return;
                                            await context
                                                .read<FinanceCubit>()
                                                .deleteExpense(
                                                  item.id,
                                                  scope: scope,
                                                );
                                            if (context.mounted) {
                                              ScaffoldMessenger.of(
                                                context,
                                              ).showSnackBar(
                                                SnackBar(
                                                  content: Text(
                                                    'Assinatura "${item.title}" atualizada.',
                                                  ),
                                                ),
                                              );
                                            }
                                          }
                                        },
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(
                                            vertical: 2,
                                            horizontal: 4,
                                          ),
                                          child: Text(
                                            'Excluir',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: AppColors.debtRed,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),

                    const SizedBox(height: 20),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text(
                        'Cadastrar Nova Recorrente',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        showAdaptiveModal(
                          context: context,
                          maxWidth: 540,
                          child: const AddExpensePage(isRecurringDefault: true),
                        );
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        ),
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
            title: const Text(
              'Dia de Início do Ciclo',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
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
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Text(
                      'Todo dia $selectedDay',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<int>(
                  initialValue: selectedDay,
                  decoration: InputDecoration(
                    labelText: 'Selecione o Dia',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  items: List.generate(31, (i) => i + 1)
                      .map(
                        (d) => DropdownMenuItem(
                          value: d,
                          child: Text('Dia $d de cada mês'),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    if (val != null) setDialogState(() => selectedDay = val);
                  },
                ),
                const SizedBox(height: 12),
                Text(
                  'Período do ciclo: dia $selectedDay ao dia ${selectedDay == 1 ? 31 : selectedDay - 1} do mês seguinte.',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.teal,
                    fontWeight: FontWeight.w500,
                  ),
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
                    SnackBar(
                      content: Text(
                        'Ciclo financeiro atualizado para o dia $selectedDay! 📅',
                      ),
                    ),
                  );
                },
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                ),
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showHousePixKeyModal(BuildContext context, House? house) {
    if (house == null) return;
    final pixKeyController = TextEditingController(text: house.pixKey ?? '');
    final holderNameController = TextEditingController(text: house.pixKeyHolderName ?? '');
    final bankController = TextEditingController(text: house.pixKeyBank ?? '');
    String selectedType = house.pixKeyType ?? 'email';
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    showAdaptiveModal(
      context: context,
      maxWidth: 520,
      child: StatefulBuilder(
        builder: (context, setModalState) {
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Form(
                key: formKey,
                child: SingleChildScrollView(
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
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.teal.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(
                              Icons.pix_rounded,
                              color: Colors.teal,
                              size: 24,
                            ),
                          ),
                          const SizedBox(width: 12),
                          const Expanded(
                            child: Text(
                              'Chave Pix da Casa',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Cadastre a Chave Pix da conta conjunta ou do responsável financeiro da residência. Ela será usada automaticamente em Aportes e liquidações do Super Pix.',
                        style: TextStyle(color: Colors.grey, fontSize: 13),
                      ),
                      const SizedBox(height: 20),
                      DropdownButtonFormField<String>(
                        value: selectedType,
                        decoration: InputDecoration(
                          labelText: 'Tipo de Chave Pix',
                          prefixIcon: const Icon(Icons.category_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cpf', child: Text('CPF')),
                          DropdownMenuItem(value: 'cnpj', child: Text('CNPJ')),
                          DropdownMenuItem(value: 'email', child: Text('E-mail')),
                          DropdownMenuItem(value: 'phone', child: Text('Telefone / Celular')),
                          DropdownMenuItem(value: 'random', child: Text('Chave Aleatória (EVP)')),
                          DropdownMenuItem(value: 'other', child: Text('Outro')),
                        ],
                        onChanged: (val) {
                          if (val != null) {
                            setModalState(() => selectedType = val);
                          }
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: pixKeyController,
                        decoration: InputDecoration(
                          labelText: 'Chave Pix da Residência',
                          hintText: 'Ex: financeiro.casa@gmail.com',
                          prefixIcon: const Icon(Icons.vpn_key_outlined, color: Colors.teal),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: holderNameController,
                        decoration: InputDecoration(
                          labelText: 'Nome do Titular / Favorecido',
                          hintText: 'Ex: Caixa Nossa Casa ou Nome do Gestor',
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: bankController,
                        decoration: InputDecoration(
                          labelText: 'Banco / Instituição (opcional)',
                          hintText: 'Ex: Nubank, Inter, Banco do Brasil',
                          prefixIcon: const Icon(Icons.account_balance_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: isSaving ? null : () => Navigator.pop(context),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: const Text('Cancelar'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: isSaving
                                  ? null
                                  : () async {
                                      setModalState(() => isSaving = true);
                                      final newPixKey = pixKeyController.text.trim();
                                      final newHolderName = holderNameController.text.trim();
                                      final newBank = bankController.text.trim();
                                      final messenger = ScaffoldMessenger.of(context);
                                      final navigator = Navigator.of(context);

                                      try {
                                        await context.read<AuthCubit>().updateHouse(
                                          houseId: house.id,
                                          pixKey: newPixKey,
                                          pixKeyType: selectedType,
                                          pixKeyHolderName: newHolderName,
                                          pixKeyBank: newBank,
                                        );
                                        navigator.pop();
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            backgroundColor: AppColors.creditGreen,
                                            content: Text('Chave Pix da Casa salva com sucesso! 🏠✨'),
                                          ),
                                        );
                                      } catch (err) {
                                        setModalState(() => isSaving = false);
                                        messenger.showSnackBar(
                                          SnackBar(
                                            backgroundColor: AppColors.debtRed,
                                            content: Text('Erro ao salvar Chave Pix da Casa: $err'),
                                          ),
                                        );
                                      }
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.teal,
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              child: isSaving
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Salvar'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
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
        content: const Text(
          'Você precisará entrar com seu e-mail e senha novamente para acessar os dados da casa.',
        ),
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
        title: const Text(
          'Ajustes da Casa',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: const [ThemeToggleButton()],
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
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => _showEditProfileModal(context, user),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.cardColor,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: Colors.grey.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              CircleAvatar(
                                radius: 26,
                                backgroundColor: AppColors.primary,
                                child: Text(
                                  userName.isNotEmpty
                                      ? userName[0].toUpperCase()
                                      : 'U',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 20,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      userName,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    Text(
                                      userEmail,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        color: Colors.grey,
                                      ),
                                    ),
                                    if (user?.pixKey != null &&
                                        user!.pixKey!.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          const Icon(
                                            Icons.pix_rounded,
                                            size: 13,
                                            color: AppColors.creditGreen,
                                          ),
                                          const SizedBox(width: 4),
                                          Expanded(
                                            child: Text(
                                              'Pix: ${user.pixKey}',
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.creditGreen,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.home_outlined,
                                          size: 14,
                                          color: AppColors.primary,
                                        ),
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
                              IconButton(
                                icon: const Icon(
                                  Icons.edit_outlined,
                                  color: AppColors.primary,
                                ),
                                tooltip: 'Editar Perfil',
                                onPressed: () =>
                                    _showEditProfileModal(context, user),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),

                  ListTile(
                    leading: const Icon(
                      Icons.person_outline_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text('Meu Perfil da Conta'),
                    subtitle: Text(
                      user?.pixKey != null && user!.pixKey!.isNotEmpty
                          ? 'Nome, e-mail e Chave Pix (${user.pixKey})'
                          : 'Alterar nome, e-mail e cadastrar Chave Pix',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showEditProfileModal(context, user),
                  ),
                  const Divider(),

                  ListTile(
                    leading: const Icon(
                      Icons.people_outline_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text('Membros da Casa e Convites'),
                    subtitle: Text(
                      sl<AuthRepository>().isDemoMode
                          ? 'Carlos, Marina • Código LAR123'
                          : '$userName • Gerenciar membros e convites',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () =>
                        _showMembersModal(context, houseName, house?.id ?? ''),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.category_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text('Categorias de Gastos'),
                    subtitle: const Text(
                      'Supermercado, Aluguel, Carro e donos',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showCategoriesModal(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.tune_rounded,
                      color: AppColors.accent,
                    ),
                    title: const Text('Modelos de Rateio'),
                    subtitle: const Text(
                      'Porcentagem (50/50), balde de aportes fixos ou categoria',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showSplitModelsModal(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.credit_card_rounded,
                      color: Colors.orange,
                    ),
                    title: const Text('Cartões e Formas de Pagamento'),
                    subtitle: Text(
                      sl<AuthRepository>().isDemoMode
                          ? 'Nubank Carlos, Inter Marina, VR Alelo'
                          : 'Cadastre cartões e formas de pagamento da casa',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showPaymentMethodsModal(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.call_split_rounded,
                      color: AppColors.accent,
                    ),
                    title: const Text('Rachar Fatura & Extratos (RN09)'),
                    subtitle: const Text(
                      'Conciliação de cartão misto entre Casa, Pessoal e P2P',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => SplitInvoiceModal.show(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.repeat_rounded,
                      color: Colors.indigoAccent,
                    ),
                    title: const Text('Assinaturas & Contas Fixas'),
                    subtitle: const Text(
                      'Aluguel, Luz, Internet, Netflix e consumo',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showRecurringExpensesModal(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.calendar_today_outlined,
                      color: Colors.teal,
                    ),
                    title: const Text('Ciclo Financeiro'),
                    subtitle: Text(
                      'Dia $cycleDay ao dia ${cycleDay == 1 ? 31 : cycleDay - 1}',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showCycleDayDialog(context, cycleDay),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.pix_rounded,
                      color: AppColors.creditGreen,
                    ),
                    title: const Text('Chave Pix da Casa'),
                    subtitle: Text(
                      house?.pixKey != null && house!.pixKey!.isNotEmpty
                          ? '${house.pixKey} • ${house.pixKeyHolderName ?? "Caixa da Casa"}'
                          : 'Configure a chave oficial do Caixa da Casa',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showHousePixKeyModal(context, house),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.purple,
                    ),
                    title: const Text('Assistente IA'),
                    subtitle: const Text('Chave Gemini (BYOK), preferências e privacidade'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _showAssistantPreferencesModal(context),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(
                      Icons.history_edu_rounded,
                      color: AppColors.primary,
                    ),
                    title: const Text('Auditoria e Histórico da Casa'),
                    subtitle: const Text('Rastreabilidade de criações, edições e exclusões'),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => showAuditLogSheet(context: context, title: 'Auditoria da Casa'),
                  ),
                  Builder(
                    builder: (context) {
                      ThemeMode mode = ThemeMode.system;
                      try {
                        mode = context.watch<ThemeCubit>().state;
                      } catch (_) {}
                      return ListTile(
                        leading: const Icon(
                          Icons.palette_outlined,
                          color: Colors.blueAccent,
                        ),
                        title: const Text('Aparência & Tema'),
                        subtitle: Text(_getThemeModeLabel(mode)),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => showThemeSelectionDialog(context),
                      );
                    },
                  ),
                  const Divider(),
                  const SizedBox(height: 16),

                  // Botão Sair da Conta
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: OutlinedButton.icon(
                      onPressed: () => _confirmSignOut(context),
                      icon: const Icon(
                        Icons.logout_rounded,
                        color: AppColors.debtRed,
                      ),
                      label: const Text(
                        'Sair da Conta',
                        style: TextStyle(
                          color: AppColors.debtRed,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        side: BorderSide(
                          color: AppColors.debtRed.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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

  String _getThemeModeLabel(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Modo Claro';
      case ThemeMode.dark:
        return 'Modo Escuro';
      case ThemeMode.system:
        return 'Padrão do Sistema';
    }
  }
}
