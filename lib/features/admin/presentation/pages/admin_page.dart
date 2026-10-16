import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/save_feedback.dart';
import '../../domain/entities/account_access.dart';
import '../../domain/entities/admin_models.dart';
import '../cubit/admin_cubit.dart';

String _day(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year}';
}

String _dayTime(DateTime? d) {
  if (d == null) return '—';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${_day(d)} ${two(d.hour)}:${two(d.minute)}';
}

Color _statusColor(AccountStatus s) => switch (s) {
      AccountStatus.active => AppColors.creditGreen,
      AccountStatus.pending => Colors.orange,
      AccountStatus.rejected || AccountStatus.suspended => AppColors.debtRed,
    };

/// Painel administrativo do Omni Lar (fase A do plano_painel_admin.md). Só
/// aparece para quem administra o app; o banco confere de novo cada função.
class AdminPage extends StatelessWidget {
  /// Aba inicial: visao, contas, aprovacoes, configuracoes ou historico.
  final String? initialTab;

  const AdminPage({super.key, this.initialTab});

  static const tabs = ['visao', 'contas', 'aprovacoes', 'configuracoes', 'historico'];

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AdminCubit>()..load(),
      child: _AdminView(initialIndex: tabs.indexOf(initialTab ?? '').clamp(0, tabs.length - 1)),
    );
  }
}

class _AdminView extends StatelessWidget {
  final int initialIndex;

  const _AdminView({required this.initialIndex});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AdminCubit, AdminState>(
      listenWhen: (prev, curr) => curr.errorMessage != null && curr.errorMessage != prev.errorMessage,
      listener: (context, state) {
        if (state.status == AdminLoadStatus.failure) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(backgroundColor: AppColors.debtRed, content: Text(state.errorMessage!)),
        );
      },
      builder: (context, state) {
        return DefaultTabController(
          length: AdminPage.tabs.length,
          initialIndex: initialIndex,
          child: Scaffold(
            appBar: AppBar(
              title: const Text('Administração do Omni Lar', style: TextStyle(fontWeight: FontWeight.bold)),
              actions: [
                IconButton(
                  tooltip: 'Atualizar',
                  onPressed: () => context.read<AdminCubit>().load(),
                  icon: const Icon(Icons.refresh_rounded),
                ),
              ],
              bottom: TabBar(
                isScrollable: true,
                tabs: [
                  const Tab(text: 'Visão geral'),
                  const Tab(text: 'Contas'),
                  Tab(text: state.pending.isEmpty ? 'Aprovações' : 'Aprovações (${state.pending.length})'),
                  const Tab(text: 'Configurações'),
                  const Tab(text: 'Histórico'),
                ],
              ),
            ),
            body: switch (state.status) {
              AdminLoadStatus.initial || AdminLoadStatus.loading when state.overview == null =>
                const Center(child: CircularProgressIndicator()),
              AdminLoadStatus.failure when state.overview == null => _ErrorView(message: state.errorMessage),
              _ => TabBarView(
                  children: [
                    _OverviewTab(state: state),
                    _AccountsTab(state: state),
                    _ApprovalsTab(state: state),
                    _SettingsTab(settings: state.settings ?? const AdminSettings()),
                    _AuditTab(entries: state.audit),
                  ],
                ),
            },
          ),
        );
      },
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String? message;

  const _ErrorView({this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded, size: 40, color: Colors.grey),
            const SizedBox(height: 12),
            Text(message ?? 'Não foi possível abrir o painel.', textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => context.read<AdminCubit>().load(),
              child: const Text('Tentar de novo'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- Visão geral
class _OverviewTab extends StatelessWidget {
  final AdminState state;

  const _OverviewTab({required this.state});

  @override
  Widget build(BuildContext context) {
    final o = state.overview;
    if (o == null) return const SizedBox.shrink();
    Widget tile(String label, String value, IconData icon, {Color? color, VoidCallback? onTap}) => SizedBox(
          width: 220,
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(icon, color: color ?? AppColors.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                          Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (o.count(AccountStatus.pending) > 0)
          Card(
            color: Colors.orange.withValues(alpha: 0.12),
            elevation: 0,
            child: ListTile(
              leading: const Icon(Icons.hourglass_top_rounded, color: Colors.orange),
              title: Text('${o.count(AccountStatus.pending)} conta(s) esperando aprovação'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => DefaultTabController.of(context).animateTo(2),
            ),
          ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            tile('Contas', '${o.accountsTotal}', Icons.people_alt_rounded),
            for (final s in AccountStatus.values)
              tile(s.label, '${o.count(s)}', Icons.circle, color: _statusColor(s)),
            tile('Contas novas em 7 dias', '${o.accountsNew7d}', Icons.person_add_alt_1_rounded),
            tile('Casas', '${o.housesTotal}', Icons.home_rounded),
            tile('Casas ativas em 30 dias', '${o.housesActive30d}', Icons.home_work_rounded),
            tile('Leituras de IA hoje', '${o.aiReadsToday}', Icons.auto_awesome_rounded),
            tile('Leituras de IA no mês', '${o.aiReadsMonth}', Icons.auto_awesome_motion_rounded),
            tile('Administradores', '${o.admins}', Icons.admin_panel_settings_rounded),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'O painel mostra só dados das contas e números de uso, nunca valores ou lançamentos das casas.',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}

// --------------------------------------------------------------------- Contas
class _AccountsTab extends StatefulWidget {
  final AdminState state;

  const _AccountsTab({required this.state});

  @override
  State<_AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<_AccountsTab> {
  late final _searchController = TextEditingController(text: widget.state.search);

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<AdminCubit>();
    final state = widget.state;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            controller: _searchController,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Buscar por nome ou e-mail',
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onSubmitted: (v) => cubit.filterAccounts(search: v),
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: ChoiceChip(
                  label: const Text('Todas'),
                  selected: state.statusFilter == null,
                  onSelected: (_) => cubit.filterAccounts(clearStatus: true),
                ),
              ),
              for (final s in AccountStatus.values)
                Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: ChoiceChip(
                    label: Text(s.label),
                    selected: state.statusFilter == s,
                    onSelected: (_) => cubit.filterAccounts(status: s),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: state.accounts.isEmpty
              ? const Center(child: Text('Nenhuma conta encontrada.', style: TextStyle(color: Colors.grey)))
              : ListView.separated(
                  itemCount: state.accounts.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _AccountTile(account: state.accounts[i]),
                ),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final AccountStatus status;

  const _StatusChip(this.status);

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(8)),
      child: Text(status.label, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }
}

class _AccountTile extends StatelessWidget {
  final AdminAccount account;
  final Widget? leading;

  const _AccountTile({required this.account, this.leading});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: leading ??
          CircleAvatar(
            child: Text(account.fullName.isEmpty ? '?' : account.fullName.characters.first.toUpperCase()),
          ),
      title: Row(
        children: [
          Flexible(child: Text(account.fullName, overflow: TextOverflow.ellipsis)),
          if (account.isAdmin) ...[
            const SizedBox(width: 6),
            const Icon(Icons.admin_panel_settings_rounded, size: 16, color: AppColors.primary),
          ],
        ],
      ),
      subtitle: Text(
        '${account.email}\nCriada em ${_day(account.createdAt)} · último acesso ${_day(account.lastSignInAt)} · '
        '${account.houses} casa(s)',
        style: const TextStyle(fontSize: 12),
      ),
      isThreeLine: true,
      trailing: _StatusChip(account.status),
      onTap: () => showAccountDetail(context, account.userId),
    );
  }
}

/// Pede o motivo de recusa ou suspensão. Devolve nulo se cancelado.
Future<String?> _askReason(BuildContext context, String title) {
  final controller = TextEditingController();
  String? error;
  return showDialog<String>(
    context: context,
    builder: (dialogCtx) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            labelText: 'Motivo (a pessoa vê este texto)',
            errorText: error,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancelar')),
          FilledButton(
            onPressed: () {
              final reason = controller.text.trim();
              if (reason.isEmpty) {
                setDialogState(() => error = 'Informe o motivo');
                return;
              }
              Navigator.pop(dialogCtx, reason);
            },
            child: const Text('Confirmar'),
          ),
        ],
      ),
    ),
  );
}

/// Muda o status com a confirmação e o motivo certos e mostra o resultado.
Future<void> _changeStatus(BuildContext context, List<AdminAccount> accounts, AccountStatus to) async {
  final cubit = context.read<AdminCubit>();
  final messenger = ScaffoldMessenger.of(context);
  String? reason;
  if (to == AccountStatus.rejected || to == AccountStatus.suspended) {
    reason = await _askReason(
      context,
      to == AccountStatus.rejected
          ? (accounts.length == 1 ? 'Recusar ${accounts.first.fullName}' : 'Recusar ${accounts.length} contas')
          : 'Suspender ${accounts.first.fullName}',
    );
    if (reason == null) return;
  }
  final changed = await cubit.setStatus([for (final a in accounts) a.userId], to, reason: reason);
  final verb = switch (to) {
    AccountStatus.active => accounts.any((a) => a.status == AccountStatus.pending) ? 'aprovada(s)' : 'reativada(s)',
    AccountStatus.rejected => 'recusada(s)',
    AccountStatus.suspended => 'suspensa(s)',
    AccountStatus.pending => '',
  };
  showSaveFeedback(
    messenger,
    ok: changed != null,
    success: '$changed conta(s) $verb.',
    failure: cubit.state.errorMessage,
  );
}

/// Detalhe da conta com as ações do painel.
Future<void> showAccountDetail(BuildContext context, String userId) async {
  final cubit = context.read<AdminCubit>();
  final detail = await cubit.accountDetail(userId);
  if (detail == null || !context.mounted) return;
  final a = detail.account;

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) => BlocProvider.value(
      value: cubit,
      child: Builder(
        // As ações usam o contexto da página: o do diálogo some ao fechar
        builder: (_) {
          Future<void> act(Future<void> Function() action) async {
            Navigator.pop(dialogCtx);
            await action();
          }

          return AlertDialog(
            title: Row(
              children: [
                Expanded(child: Text(a.fullName)),
                _StatusChip(a.status),
              ],
            ),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(a.email),
                    if (detail.phone != null && detail.phone!.isNotEmpty) Text(detail.phone!),
                    const SizedBox(height: 8),
                    Text('Criada em ${_dayTime(a.createdAt)}', style: const TextStyle(fontSize: 12)),
                    Text('Último acesso: ${_dayTime(a.lastSignInAt)}', style: const TextStyle(fontSize: 12)),
                    if (a.approvedAt != null)
                      Text(
                        'Liberada em ${_dayTime(a.approvedAt)}'
                        '${detail.approvedByName == null ? '' : ' por ${detail.approvedByName}'}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    if (a.statusReason != null && a.statusReason!.isNotEmpty)
                      Text('Motivo: ${a.statusReason}', style: const TextStyle(fontSize: 12)),
                    if (a.isAdmin)
                      const Padding(
                        padding: EdgeInsets.only(top: 4),
                        child: Text(
                          'Administra o app',
                          style: TextStyle(fontSize: 12, color: AppColors.primary, fontWeight: FontWeight.w600),
                        ),
                      ),
                    const Divider(height: 24),
                    const Text('Casas', style: TextStyle(fontWeight: FontWeight.bold)),
                    if (detail.houses.isEmpty)
                      const Text('Nenhuma casa.', style: TextStyle(fontSize: 12, color: Colors.grey))
                    else
                      for (final h in detail.houses)
                        Text('${h.name} · ${h.roleLabel} desde ${_day(h.joinedAt)}', style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 12),
                    Text(
                      'Leituras de IA: ${detail.aiReadsToday} hoje, ${detail.aiReadsMonth} no mês',
                      style: const TextStyle(fontSize: 13),
                    ),
                    if (detail.history.isNotEmpty) ...[
                      const Divider(height: 24),
                      const Text('Histórico', style: TextStyle(fontWeight: FontWeight.bold)),
                      for (final h in detail.history)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '${_dayTime(h.createdAt)} · ${h.description}'
                            '${h.actorName == null ? '' : ' · por ${h.actorName}'}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
            actionsOverflowButtonSpacing: 6,
            actions: [
              if (a.status == AccountStatus.pending) ...[
                OutlinedButton(
                  onPressed: () => act(() => _changeStatus(context, [a], AccountStatus.rejected)),
                  child: const Text('Recusar'),
                ),
                FilledButton(
                  onPressed: () => act(() => _changeStatus(context, [a], AccountStatus.active)),
                  child: const Text('Aprovar'),
                ),
              ],
              if (a.status == AccountStatus.active)
                OutlinedButton(
                  onPressed: () => act(() => _changeStatus(context, [a], AccountStatus.suspended)),
                  style: OutlinedButton.styleFrom(foregroundColor: AppColors.debtRed),
                  child: const Text('Suspender'),
                ),
              if (a.status == AccountStatus.rejected || a.status == AccountStatus.suspended)
                FilledButton(
                  onPressed: () => act(() => _changeStatus(context, [a], AccountStatus.active)),
                  child: const Text('Reativar'),
                ),
              if (a.status == AccountStatus.active)
                TextButton(
                  onPressed: () => act(() async {
                    final messenger = ScaffoldMessenger.of(context);
                    final ok = await cubit.setPlatformAdmin(a.userId, !a.isAdmin);
                    showSaveFeedback(
                      messenger,
                      ok: ok,
                      success: a.isAdmin
                          ? '${a.fullName} deixou de administrar o app.'
                          : '${a.fullName} agora administra o app.',
                      failure: cubit.state.errorMessage,
                    );
                  }),
                  child: Text(a.isAdmin ? 'Tirar administração' : 'Tornar administrador'),
                ),
              TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Fechar')),
            ],
          );
        },
      ),
    ),
  );
}

// ----------------------------------------------------------------- Aprovações
class _ApprovalsTab extends StatefulWidget {
  final AdminState state;

  const _ApprovalsTab({required this.state});

  @override
  State<_ApprovalsTab> createState() => _ApprovalsTabState();
}

class _ApprovalsTabState extends State<_ApprovalsTab> {
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final pending = widget.state.pending;
    _selected.removeWhere((id) => !pending.any((a) => a.userId == id));
    if (pending.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nenhuma conta esperando aprovação.', style: TextStyle(color: Colors.grey)),
        ),
      );
    }
    final chosen = pending.where((a) => _selected.contains(a.userId)).toList();
    final target = chosen.isEmpty ? pending : chosen;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(chosen.isEmpty ? '${pending.length} esperando' : '${chosen.length} selecionada(s)'),
              FilledButton.icon(
                onPressed: () => _changeStatus(context, target, AccountStatus.active),
                icon: const Icon(Icons.check_rounded, size: 18),
                label: Text(chosen.isEmpty ? 'Aprovar todas' : 'Aprovar selecionadas'),
              ),
              OutlinedButton.icon(
                onPressed: () => _changeStatus(context, target, AccountStatus.rejected),
                icon: const Icon(Icons.close_rounded, size: 18),
                label: Text(chosen.isEmpty ? 'Recusar todas' : 'Recusar selecionadas'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: pending.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final a = pending[i];
              return _AccountTile(
                account: a,
                leading: Checkbox(
                  value: _selected.contains(a.userId),
                  onChanged: (v) => setState(() {
                    if (v == true) {
                      _selected.add(a.userId);
                    } else {
                      _selected.remove(a.userId);
                    }
                  }),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- Configurações
class _SettingsTab extends StatefulWidget {
  final AdminSettings settings;

  const _SettingsTab({required this.settings});

  @override
  State<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends State<_SettingsTab> {
  late bool _requireApproval = widget.settings.requireApproval;
  late bool _autoApproveInvited = widget.settings.autoApproveInvited;
  late final _domains = TextEditingController(text: widget.settings.autoApproveDomains.join(', '));
  late final _emails = TextEditingController(text: widget.settings.autoApproveEmails.join(', '));
  bool _saving = false;

  @override
  void dispose() {
    _domains.dispose();
    _emails.dispose();
    super.dispose();
  }

  static List<String> _split(String text) =>
      [for (final part in text.split(RegExp(r'[,;\s]+'))) if (part.trim().isNotEmpty) part.trim()];

  Future<void> _save() async {
    final cubit = context.read<AdminCubit>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final ok = await cubit.updateSettings(widget.settings.copyWith(
      requireApproval: _requireApproval,
      autoApproveInvited: _autoApproveInvited,
      autoApproveDomains: _split(_domains.text),
      autoApproveEmails: _split(_emails.text),
    ));
    if (!mounted) return;
    setState(() => _saving = false);
    showSaveFeedback(messenger, ok: ok, success: 'Configurações salvas.', failure: cubit.state.errorMessage);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.settings;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SwitchListTile(
          value: _requireApproval,
          onChanged: (v) => setState(() => _requireApproval = v),
          title: const Text('Conta nova espera aprovação'),
          subtitle: const Text(
            'Desligado, toda conta nova já nasce liberada. Mudar vale para as contas novas; '
            'as que já esperam continuam esperando.',
          ),
        ),
        SwitchListTile(
          value: _autoApproveInvited,
          onChanged: (v) => setState(() => _autoApproveInvited = v),
          title: const Text('Convite de uma casa aprova a conta'),
          subtitle: const Text('Quem entra com um código de convite válido é liberado na hora.'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _domains,
          decoration: InputDecoration(
            labelText: 'Domínios aprovados direto',
            hintText: 'Ex.: minhaempresa.com.br',
            helperText: 'Separados por vírgula. E-mails desses domínios nascem liberados.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _emails,
          minLines: 1,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'E-mails aprovados direto',
            hintText: 'Ex.: mae@gmail.com, irmao@gmail.com',
            helperText: 'Separados por vírgula.',
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Salvar configurações'),
          ),
        ),
        if (s.updatedAt != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Última mudança em ${_dayTime(s.updatedAt)}${s.updatedByName == null ? '' : ' por ${s.updatedByName}'}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ Histórico
class _AuditTab extends StatelessWidget {
  final List<AdminAuditEntry> entries;

  const _AuditTab({required this.entries});

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(child: Text('Nenhuma ação registrada ainda.', style: TextStyle(color: Colors.grey)));
    }
    return ListView.separated(
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) {
        final e = entries[i];
        return ListTile(
          dense: true,
          title: Text(e.targetName == null ? e.description : '${e.targetName}: ${e.description}'),
          subtitle: Text('${_dayTime(e.createdAt)}${e.actorName == null ? '' : ' · por ${e.actorName}'}'),
          onTap: e.targetUserId == null ? null : () => showAccountDetail(context, e.targetUserId!),
        );
      },
    );
  }
}
