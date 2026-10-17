import 'package:flutter/material.dart';

import '../../../../core/di/service_locator.dart';
import '../../data/datasources/notifications_datasource.dart';
import '../../domain/entities/app_notification.dart';
import '../../domain/entities/notification_preferences.dart';

/// Preferências de notificação nos Ajustes: cada grupo no sino e no celular,
/// horário silencioso, esconder valores e resumo semanal. Cada mudança é
/// gravada na hora; se a gravação falha, a tela volta ao que era.
class NotificationPreferencesBlock extends StatefulWidget {
  /// Permite trocar a fonte nos testes.
  final NotificationsDataSource? dataSource;

  const NotificationPreferencesBlock({super.key, this.dataSource});

  @override
  State<NotificationPreferencesBlock> createState() => _NotificationPreferencesBlockState();
}

class _NotificationPreferencesBlockState extends State<NotificationPreferencesBlock> {
  late final NotificationsDataSource _source = widget.dataSource ?? sl<NotificationsDataSource>();
  NotificationPreferences? _preferences;
  String? _loadError;

  static const _defaultQuietStart = (hour: 22, minute: 0);
  static const _defaultQuietEnd = (hour: 7, minute: 0);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final preferences = await _source.getPreferences();
      if (mounted) setState(() => _preferences = preferences);
    } catch (_) {
      if (mounted) setState(() => _loadError = 'Não foi possível carregar as preferências.');
    }
  }

  Future<void> _save(NotificationPreferences updated, Future<void> Function() write) async {
    final previous = _preferences;
    setState(() => _preferences = updated);
    try {
      await write();
    } catch (_) {
      if (!mounted) return;
      setState(() => _preferences = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível salvar. Tente de novo.')),
      );
    }
  }

  void _setGroup(NotificationCategory group, GroupPreference preference) {
    final updated = _preferences!.withGroup(group, preference);
    _save(updated, () => _source.saveGroupPreference(group, preference));
  }

  void _setSettings(NotificationPreferences updated) {
    _save(updated, () => _source.saveSettings(updated));
  }

  String _formatTime(({int hour, int minute}) time) =>
      '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

  Future<void> _pickQuietTime({required bool start}) async {
    final preferences = _preferences!;
    final current = (start ? preferences.quietStart : preferences.quietEnd) ??
        (start ? _defaultQuietStart : _defaultQuietEnd);
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
      helpText: start ? 'Silêncio a partir de' : 'Silêncio até',
    );
    if (picked == null || !mounted) return;
    final time = (hour: picked.hour, minute: picked.minute);
    _setSettings(start
        ? preferences.withSettings(quietStart: time, quietEnd: preferences.quietEnd ?? _defaultQuietEnd)
        : preferences.withSettings(quietStart: preferences.quietStart ?? _defaultQuietStart, quietEnd: time));
  }

  @override
  Widget build(BuildContext context) {
    final preferences = _preferences;
    if (preferences == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: _loadError == null
            ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            : Row(
                children: [
                  Expanded(child: Text(_loadError!, style: const TextStyle(color: Colors.grey))),
                  TextButton(onPressed: _load, child: const Text('Tentar de novo')),
                ],
              ),
      );
    }

    final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.grey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              const Expanded(child: Text('Avisos por grupo', style: TextStyle(fontWeight: FontWeight.w600))),
              SizedBox(width: 64, child: Text('Sino', textAlign: TextAlign.center, style: labelStyle)),
              SizedBox(width: 64, child: Text('Celular', textAlign: TextAlign.center, style: labelStyle)),
            ],
          ),
        ),
        for (final group in NotificationPreferences.groups)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Expanded(child: Text(NotificationPreferences.labelOf(group))),
                SizedBox(
                  width: 64,
                  child: Switch(
                    value: preferences.of(group).inApp,
                    onChanged: (value) => _setGroup(group, preferences.of(group).copyWith(inApp: value)),
                  ),
                ),
                SizedBox(
                  width: 64,
                  child: Switch(
                    value: preferences.of(group).push,
                    onChanged: (value) => _setGroup(group, preferences.of(group).copyWith(push: value)),
                  ),
                ),
              ],
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Text(
            'Avisos essenciais (contas vencendo, fechamento, empréstimos e convites) continuam chegando no sino mesmo com o grupo desligado.',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
        const Divider(height: 1),
        SwitchListTile(
          title: const Text('Horário silencioso'),
          subtitle: Text(
            preferences.hasQuietHours
                ? 'Das ${_formatTime(preferences.quietStart!)} às ${_formatTime(preferences.quietEnd!)} os avisos aparecem só no sino e chegam ao celular quando o silêncio acaba.'
                : 'Os avisos chegam no celular a qualquer hora.',
          ),
          value: preferences.hasQuietHours,
          onChanged: (on) => _setSettings(on
              ? preferences.withSettings(quietStart: _defaultQuietStart, quietEnd: _defaultQuietEnd)
              : preferences.withSettings(clearQuietHours: true)),
        ),
        if (preferences.hasQuietHours)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.bedtime_outlined, size: 18),
                  label: Text('Das ${_formatTime(preferences.quietStart!)}'),
                  onPressed: () => _pickQuietTime(start: true),
                ),
                OutlinedButton.icon(
                  icon: const Icon(Icons.wb_sunny_outlined, size: 18),
                  label: Text('Às ${_formatTime(preferences.quietEnd!)}'),
                  onPressed: () => _pickQuietTime(start: false),
                ),
              ],
            ),
          ),
        SwitchListTile(
          title: const Text('Esconder valores no celular'),
          subtitle: const Text('O aviso no celular não mostra quantias; o sino mostra tudo.'),
          value: preferences.hideAmounts,
          onChanged: (on) => _setSettings(preferences.withSettings(hideAmounts: on)),
        ),
        SwitchListTile(
          title: const Text('Resumo semanal'),
          subtitle: const Text('Domingo às 18h: gastos da semana, contas da próxima e o Fôlego.'),
          value: preferences.weeklySummary,
          onChanged: (on) => _setSettings(preferences.withSettings(weeklySummary: on)),
        ),
      ],
    );
  }
}
