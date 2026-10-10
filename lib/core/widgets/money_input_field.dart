import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/value_objects/money.dart';
import '../theme/app_colors.dart';
import '../utils/app_haptics.dart';

/// Formatter para entrada monetária contínua no estilo ATM/Fintech (Nubank/Revolut).
/// O usuário digita apenas dígitos e o valor é deslocado da direita para a esquerda:
/// 1 -> R$ 0,01
/// 11 -> R$ 0,11
/// 110 -> R$ 1,10
/// 1100 -> R$ 11,00
///
/// Trata digitação tecla a tecla, colagem de valores, backspace e
/// garante que cliques acidentais no meio do texto não quebrem o buffer de centavos.
class MoneyInputFormatter extends TextInputFormatter {
  final int maxCents;

  const MoneyInputFormatter({this.maxCents = 100000000});

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // 1. Campo limpo
    if (newValue.text.isEmpty) {
      final formatted = const Money.zero().format();
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    // 2. Se o texto não mudou, apenas assegura cursor no fim
    if (oldValue.text == newValue.text) {
      return newValue.copyWith(
        selection: TextSelection.collapsed(offset: newValue.text.length),
      );
    }

    // 3. Se for entrada direta / colagem sem a máscara (ex: '1250' ou teste com enterText)
    final hasMaskPrefix = newValue.text.contains('R\$');
    if (!hasMaskPrefix) {
      final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
      var newCents = int.tryParse(digits) ?? 0;
      if (newCents > maxCents) newCents = maxCents;
      final formatted = Money(newCents).format();
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    // 4. Usuário apagou caractere(s) com Backspace mantendo a máscara
    if (newValue.text.length < oldValue.text.length) {
      final oldDigits = oldValue.text.replaceAll(RegExp(r'[^0-9]'), '');
      final oldCents = int.tryParse(oldDigits) ?? 0;
      final newCents = oldCents ~/ 10;
      final formatted = Money(newCents).format();
      return TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    }

    // 5. Usuário inseriu dígitos sobre a máscara
    final oldDigits = oldValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    final newDigits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    int finalCents;
    if (newDigits.length > oldDigits.length) {
      final oldCents = int.tryParse(oldDigits) ?? 0;
      final addedCount = newDigits.length - oldDigits.length;

      if (addedCount > 2) {
        // Colagem de valor formatado extenso (ex: "R$ 1.250,00")
        finalCents = int.tryParse(newDigits) ?? 0;
      } else {
        // Digitação tecla a tecla (mesmo se o cursor estivesse em posição arbitrária)
        final insertedStr = _extractInsertedText(oldValue.text, newValue.text);
        final insertedDigits = insertedStr.replaceAll(RegExp(r'[^0-9]'), '');
        var cents = oldCents;
        for (int i = 0; i < insertedDigits.length; i++) {
          final digit = int.tryParse(insertedDigits[i]);
          if (digit != null) {
            if (cents * 10 + digit <= maxCents) {
              cents = (cents * 10) + digit;
            }
          }
        }
        finalCents = cents;
      }
    } else {
      finalCents = int.tryParse(newDigits) ?? 0;
    }

    if (finalCents > maxCents) {
      finalCents = maxCents;
    }

    final formatted = Money(finalCents).format();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  static String _extractInsertedText(String oldText, String newText) {
    int start = 0;
    while (start < oldText.length && start < newText.length && oldText[start] == newText[start]) {
      start++;
    }
    int endOld = oldText.length - 1;
    int endNew = newText.length - 1;
    while (endOld >= start && endNew >= start && oldText[endOld] == newText[endNew]) {
      endOld--;
      endNew--;
    }
    if (start <= endNew + 1) {
      return newText.substring(start, endNew + 1);
    }
    return '';
  }
}

/// Controller especializado que força a seleção/cursor sempre para o final do texto
class _MoneyTextEditingController extends TextEditingController {
  _MoneyTextEditingController({super.text});

  @override
  set value(TextEditingValue newValue) {
    super.value = newValue.copyWith(
      selection: TextSelection.collapsed(offset: newValue.text.length),
    );
  }
}

/// Campo de entrada de valor monetário contínuo no estilo ATM/Fintech (Nubank/Revolut).
/// O usuário digita apenas dígitos pelo teclado nativo (do celular ou físico no PC)
/// e o valor se preenche naturalmente em centavos da direita para a esquerda:
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
  final List<int>? quickAddCents; // Ex: [1000, 2000, 5000, 10000] para +R$10, +R$20, +R$50, +R$100

  const MoneyInputField({
    super.key,
    this.initialValue = const Money.zero(),
    required this.onChanged,
    this.label = 'Valor',
    this.autoFocus = false,
    this.showKeypad = false, // Desativado por padrão: utiliza o teclado nativo do dispositivo
    this.primaryColor,
    this.quickAddCents,
  });

  @override
  State<MoneyInputField> createState() => _MoneyInputFieldState();
}

class _MoneyInputFieldState extends State<MoneyInputField> {
  late int _cents;
  late TextEditingController _controller;
  late FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _cents = widget.initialValue.cents;
    _controller = _MoneyTextEditingController();
    _focusNode = FocusNode();
    _syncController();

    _focusNode.addListener(() {
      if (_focusNode.hasFocus) {
        _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
      }
    });
  }

  @override
  void didUpdateWidget(covariant MoneyInputField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialValue.cents != widget.initialValue.cents &&
        widget.initialValue.cents != _cents) {
      _cents = widget.initialValue.cents;
      _syncController();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _syncController() {
    final formatted = Money(_cents).format();
    _controller.value = TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  void _onInputChanged(String text) {
    final digits = text.replaceAll(RegExp(r'[^0-9]'), '');
    final newCents = int.tryParse(digits) ?? 0;
    if (newCents > 100000000) return; // Limite de R$ 1 milhão

    if (_cents != newCents) {
      setState(() {
        _cents = newCents;
      });
      AppHaptics.selection();
      widget.onChanged(Money(_cents));
    }
  }

  void _onDigit(int digit) {
    if (_cents >= 100000000) return;
    setState(() {
      _cents = (_cents * 10) + digit;
      _syncController();
    });
    AppHaptics.selection();
    widget.onChanged(Money(_cents));
  }

  void _onBackspace() {
    setState(() {
      _cents = _cents ~/ 10;
      _syncController();
    });
    AppHaptics.light();
    widget.onChanged(Money(_cents));
  }

  void _onClear() {
    setState(() {
      _cents = 0;
      _syncController();
    });
    AppHaptics.light();
    widget.onChanged(const Money.zero());
  }

  void _addQuick(int addCents) {
    if (_cents + addCents > 100000000) return;
    setState(() {
      _cents += addCents;
      _syncController();
    });
    AppHaptics.light();
    widget.onChanged(Money(_cents));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
              const SizedBox(height: 4),

              // Campo de entrada nativo centralizado e estilizado
              IntrinsicWidth(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Flexible(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        autofocus: widget.autoFocus,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          MoneyInputFormatter(),
                        ],
                        textAlign: TextAlign.center,
                        textInputAction: TextInputAction.next,
                        enableInteractiveSelection: false,
                        onTap: () {
                          _controller.selection = TextSelection.collapsed(offset: _controller.text.length);
                        },
                        style: TextStyle(
                          fontSize: 38,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                          color: _cents > 0 ? accentColor : theme.textTheme.bodySmall?.color,
                        ),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          isDense: true,
                        ),
                        onChanged: _onInputChanged,
                      ),
                    ),
                    if (_cents > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: IconButton(
                          icon: const Icon(Icons.backspace_outlined, size: 20),
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Apagar dígito',
                          onPressed: _onBackspace,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // Atalhos rápidos de valores (+R$10, +R$20, +R$50, +R$100)
        if (widget.quickAddCents != null && widget.quickAddCents!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 6,
            children: widget.quickAddCents!.map((add) {
              return ActionChip(
                visualDensity: VisualDensity.compact,
                label: Text('+ ${Money(add).format()}'),
                onPressed: () => _addQuick(add),
              );
            }).toList(),
          ),
        ],

        // Teclado virtual sob demanda (apenas se explicitamente habilitado)
        if (widget.showKeypad) ...[
          const SizedBox(height: 16),
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
