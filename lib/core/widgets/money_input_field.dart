import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/value_objects/money.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';

/// Campo de entrada de valor monetário contínuo no estilo ATM/Fintech (Nubank/Revolut).
/// O usuário digita apenas dígitos e o valor se preenche naturalmente em centavos
/// da direita para a esquerda:
/// 1 -> R$ 0,01
/// 10 -> R$ 0,10
/// 100 -> R$ 1,00
/// 1000 -> R$ 10,00
class MoneyInputField extends StatefulWidget {
  final Money initialValue;
  final ValueChanged<Money> onChanged;
  final String label;
  final bool autoFocus;
  final bool showKeypad;
  final Color? primaryColor;
  final List<int>? quickAddCents; // Ex: [1000, 5000, 10000] para +R$10, +R$50, +R$100

  const MoneyInputField({
    super.key,
    this.initialValue = const Money.zero(),
    required this.onChanged,
    this.label = 'Valor',
    this.autoFocus = false,
    this.showKeypad = true,
    this.primaryColor,
    this.quickAddCents,
  });

  @override
  State<MoneyInputField> createState() => _MoneyInputFieldState();
}

class _MoneyInputFieldState extends State<MoneyInputField> {
  late int _cents;

  @override
  void initState() {
    super.initState();
    _cents = widget.initialValue.cents;
  }

  void _onDigit(int digit) {
    if (_cents >= 100000000) return; // Limite de 1 milhão de reais
    setState(() {
      _cents = (_cents * 10) + digit;
    });
    AppHaptics.selection();
    widget.onChanged(Money(_cents));
  }

  void _onBackspace() {
    setState(() {
      _cents = _cents ~/ 10;
    });
    AppHaptics.light();
    widget.onChanged(Money(_cents));
  }

  void _onClear() {
    setState(() {
      _cents = 0;
    });
    AppHaptics.light();
    widget.onChanged(const Money.zero());
  }

  void _addQuick(int addCents) {
    setState(() {
      _cents += addCents;
    });
    AppHaptics.light();
    widget.onChanged(Money(_cents));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final money = Money(_cents);
    final formatted = money.format();
    final accentColor = widget.primaryColor ?? theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Column(
            children: [
              Text(
                widget.label,
                style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              GestureDetector(
                onLongPress: _onClear,
                child: Text(
                  formatted,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.bold,
                    letterSpacing: -0.5,
                    color: _cents > 0 ? accentColor : theme.textTheme.bodySmall?.color,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (widget.quickAddCents != null && widget.quickAddCents!.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            children: widget.quickAddCents!.map((add) {
              return ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text('+ ${Money(add).format()}'),
                onPressed: () => _addQuick(add),
              );
            }).toList(),
          ),
        ],
        if (widget.showKeypad) ...[
          const SizedBox(height: 20),
          _buildNumericKeypad(theme),
        ],
      ],
    );
  }

  Widget _buildNumericKeypad(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.brightness == Brightness.dark
            ? AppColors.cardDark.withValues(alpha: 0.5)
            : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.5)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Row(
            children: [
              _keyButton('1', () => _onDigit(1)),
              _keyButton('2', () => _onDigit(2)),
              _keyButton('3', () => _onDigit(3)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _keyButton('4', () => _onDigit(4)),
              _keyButton('5', () => _onDigit(5)),
              _keyButton('6', () => _onDigit(6)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _keyButton('7', () => _onDigit(7)),
              _keyButton('8', () => _onDigit(8)),
              _keyButton('9', () => _onDigit(9)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _keyButton('C', _onClear, isAction: true),
              _keyButton('0', () => _onDigit(0)),
              _iconKeyButton(Icons.backspace_outlined, _onBackspace),
            ],
          ),
        ],
      ),
    );
  }

  Widget _keyButton(String label, VoidCallback onTap, {bool isAction = false}) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: isAction ? 16 : 22,
                  fontWeight: isAction ? FontWeight.bold : FontWeight.w600,
                  color: isAction ? AppColors.debtRed : null,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconKeyButton(IconData icon, VoidCallback onTap) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              height: 48,
              alignment: Alignment.center,
              child: Icon(icon, size: 22),
            ),
          ),
        ),
      ),
    );
  }
}
