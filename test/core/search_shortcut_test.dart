import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/widgets/search_shortcut.dart';

class _SearchPage extends StatefulWidget {
  const _SearchPage();

  @override
  State<_SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<_SearchPage> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    SearchShortcut.register(_focus);
  }

  @override
  void dispose() {
    SearchShortcut.unregister(_focus);
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Column(children: [
          TextField(focusNode: _focus, key: const Key('busca')),
          const TextField(key: Key('outro')),
        ]),
      );
}

void main() {
  testWidgets('Ctrl + F foca o campo de busca da tela', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SearchShortcut.listener(child: child!),
      home: const _SearchPage(),
    ));
    await tester.tap(find.byKey(const Key('outro')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    final field = tester.widget<TextField>(find.byKey(const Key('busca')));
    expect(field.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Sem campo de busca, a tecla não é tratada', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SearchShortcut.listener(child: child!),
      home: const Scaffold(body: TextField()),
    ));
    expect(SearchShortcut.focusSearch(), isFalse);
  });
}
