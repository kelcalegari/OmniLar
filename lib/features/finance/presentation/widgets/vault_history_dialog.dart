import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../../core/di/service_locator.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/privacy_toggle.dart';
import '../../domain/entities/house_member.dart';
import '../../domain/entities/savings_vault.dart';
import '../../domain/repositories/finance_repository.dart';
import '../cubit/finance_cubit.dart';
import '../cubit/finance_state.dart';

/// Extrato da caixinha: quem guardou, resgatou ou transferiu, quanto, quando e
/// por quê. Relê sozinho quando o saldo da caixinha muda (inclusive por outro
/// aparelho), carrega os mais antigos sob demanda e filtra por tipo e morador.
class VaultHistoryDialog extends StatefulWidget {
  final SavingsVault vault;
  final List<HouseMember> members;
  final List<SavingsVault> vaults;
  final int pageSize;

  const VaultHistoryDialog({
    super.key,
    required this.vault,
    required this.members,
    required this.vaults,
    this.pageSize = 30,
  });

  static Future<void> show(
    BuildContext context, {
    required SavingsVault vault,
    required List<HouseMember> members,
    required List<SavingsVault> vaults,
  }) {
    final cubit = context.read<FinanceCubit>();
    return showDialog<void>(
      context: context,
      builder: (_) => BlocProvider.value(
        value: cubit,
        child: VaultHistoryDialog(vault: vault, members: members, vaults: vaults),
      ),
    );
  }

  @override
  State<VaultHistoryDialog> createState() => _VaultHistoryDialogState();
}

class _VaultHistoryDialogState extends State<VaultHistoryDialog> {
  final _items = <SavingsTransaction>[];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  bool _failed = false;
  VaultHistoryFilter _filter = VaultHistoryFilter.all;
  String? _memberId;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final page = await sl<FinanceRepository>().getVaultTransactions(widget.vault.id, limit: widget.pageSize);
      if (!mounted) return;
      setState(() {
        _items
          ..clear()
          ..addAll(page);
        _hasMore = page.length == widget.pageSize;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _failed = true;
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _items.isEmpty) return;
    setState(() => _loadingMore = true);
    try {
      final page = await sl<FinanceRepository>().getVaultTransactions(
        widget.vault.id,
        limit: widget.pageSize,
        before: _items.last.date,
      );
      if (!mounted) return;
      setState(() {
        _items.addAll(page);
        _hasMore = page.length == widget.pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingMore = false);
    }
  }

  String _memberName(String id) {
    for (final m in widget.members) {
      if (m.id == id) return m.name.split(' ').first;
    }
    return 'Morador';
  }

  String _vaultName(String? id) {
    for (final v in widget.vaults) {
      if (v.id == id) return v.name;
    }
    return 'outra caixinha';
  }

  String _label(SavingsTransaction t) {
    if (t.isTransfer) {
      return t.isDeposit
          ? 'Transferido de ${_vaultName(t.counterpartVaultId)}'
          : 'Transferido para ${_vaultName(t.counterpartVaultId)}';
    }
    if (t.takenFromCycle) return 'Veio do Caixa do ciclo';
    if (t.returnedToCycle) return 'Devolvido ao ciclo';
    return t.isDeposit ? 'Entrada' : 'Saída';
  }

  String _formatDate(DateTime d) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final visible = _items
        .where((t) => _filter.matches(t) && (_memberId == null || t.memberId == _memberId))
        .toList();

    return BlocListener<FinanceCubit, FinanceState>(
      // Saldo desta caixinha mudou (aqui ou em outro aparelho): relê o extrato
      listenWhen: (prev, curr) {
        Object? balanceOf(FinanceState s) =>
            s.savingsVaults.where((v) => v.id == widget.vault.id).firstOrNull?.currentBalance;
        return balanceOf(prev) != balanceOf(curr);
      },
      listener: (_, _) => _reload(),
      child: AlertDialog(
        title: Text('Histórico: ${widget.vault.name}'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final f in VaultHistoryFilter.values)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(f.label, style: const TextStyle(fontSize: 12)),
                          selected: _filter == f,
                          onSelected: (_) => setState(() => _filter = f),
                        ),
                      ),
                  ],
                ),
              ),
              if (widget.members.length > 1) ...[
                const SizedBox(height: 8),
                DropdownButtonFormField<String?>(
                  initialValue: _memberId,
                  isDense: true,
                  decoration: InputDecoration(
                    labelText: 'Morador',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('Todos')),
                    for (final m in widget.members)
                      DropdownMenuItem<String?>(value: m.id, child: Text(m.name)),
                  ],
                  onChanged: (v) => setState(() => _memberId = v),
                ),
              ],
              const SizedBox(height: 12),
              Flexible(child: _buildList(visible)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<SavingsTransaction> visible) {
    if (_loading && _items.isEmpty) {
      return const SizedBox(height: 80, child: Center(child: CircularProgressIndicator()));
    }
    if (_failed) {
      return const Text('Não foi possível carregar o histórico desta caixinha.');
    }
    if (_items.isEmpty) {
      return const Text('Nenhuma entrada ou saída registrada nesta caixinha.');
    }

    return ListView(
      shrinkWrap: true,
      children: [
        if (visible.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Nenhum lançamento com este filtro entre os carregados.',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        for (var i = 0; i < visible.length; i++) ...[
          if (i > 0) const Divider(height: 12),
          _buildRow(visible[i]),
        ],
        if (_hasMore)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Center(
              child: _loadingMore
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : TextButton.icon(
                      onPressed: _loadMore,
                      icon: const Icon(Icons.expand_more_rounded, size: 18),
                      label: const Text('Carregar mais'),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _buildRow(SavingsTransaction t) {
    final color = t.isDeposit ? AppColors.creditGreen : AppColors.debtRed;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          t.isTransfer
              ? Icons.swap_horiz_rounded
              : t.isDeposit
                  ? Icons.south_west_rounded
                  : Icons.north_east_rounded,
          size: 18,
          color: color,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_label(t)} • ${_memberName(t.memberId)}',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
              if (t.description.isNotEmpty) Text(t.description, style: const TextStyle(fontSize: 12)),
              Text(_formatDate(t.date), style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        PrivacySensitiveText(
          '${t.isDeposit ? '+' : '-'}${t.amount.format()}',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: color),
        ),
      ],
    );
  }
}
