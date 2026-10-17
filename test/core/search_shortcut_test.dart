import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/widgets/search_shortcut.dart';

class _SearchPage extends StatefulWidget {
  const _SearchPage({super.key});

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

  testWidgets('Com duas abas vivas, foca a busca da aba visível', (tester) async {
    Widget tab(bool active, Key key) => Offstage(
          offstage: !active,
          child: TickerMode(enabled: active, child: _SearchPage(key: key)),
        );
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SearchShortcut.listener(child: child!),
      home: Stack(children: [tab(true, const Key('visivel')), tab(false, const Key('escondida'))]),
    ));

    expect(SearchShortcut.focusSearch(), isTrue);
    await tester.pump();
    final visible = tester.widget<TextField>(
      find.descendant(of: find.byKey(const Key('visivel')), matching: find.byKey(const Key('busca'))),
    );
    expect(visible.focusNode!.hasFocus, isTrue);
  });

  testWidgets('Sem campo de busca, a tecla não é tratada', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => SearchShortcut.listener(child: child!),
      home: const Scaffold(body: TextField()),
    ));
    expect(SearchShortcut.focusSearch(), isFalse);
  });
}
