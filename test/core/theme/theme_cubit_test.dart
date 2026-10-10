import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:omni_lar/core/theme/theme_cubit.dart';
import 'package:omni_lar/core/widgets/theme_toggle_button.dart';

void main() {
  group('ThemeCubit Unit Tests', () {
    test('Valor inicial do ThemeCubit padrão é ThemeMode.system', () {
      final cubit = ThemeCubit();
      expect(cubit.state, equals(ThemeMode.system));
    });

    test('Permite definir ThemeMode explicitamente', () {
      final cubit = ThemeCubit();
      cubit.setThemeMode(ThemeMode.dark);
      expect(cubit.state, equals(ThemeMode.dark));

      cubit.setThemeMode(ThemeMode.light);
      expect(cubit.state, equals(ThemeMode.light));

      cubit.setThemeMode(ThemeMode.system);
      expect(cubit.state, equals(ThemeMode.system));
    });
  });

  group('ThemeToggleButton Widget Tests', () {
    testWidgets('Alterna de tema ao clicar no ThemeToggleButton', (tester) async {
      final cubit = ThemeCubit(ThemeMode.light);

      await tester.pumpWidget(
        BlocProvider<ThemeCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              appBar: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: AppBar(
                  actions: const [
                    ThemeToggleButton(),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ThemeToggleButton), findsOneWidget);

      // Clica para alternar
      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(cubit.state, equals(ThemeMode.dark));

      // Clica novamente para voltar a claro
      await tester.tap(find.byType(ThemeToggleButton));
      await tester.pumpAndSettle();

      expect(cubit.state, equals(ThemeMode.light));
    });

    testWidgets('Abre modal de seleção de tema via showThemeSelectionDialog', (tester) async {
      final cubit = ThemeCubit(ThemeMode.system);

      await tester.pumpWidget(
        BlocProvider<ThemeCubit>.value(
          value: cubit,
          child: MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  return ElevatedButton(
                    onPressed: () => showThemeSelectionDialog(context),
                    child: const Text('Abrir Tema'),
                  );
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Abrir Tema'));
      await tester.pumpAndSettle();

      expect(find.text('Aparência & Tema'), findsOneWidget);
      expect(find.text('Modo Claro'), findsOneWidget);
      expect(find.text('Modo Escuro'), findsOneWidget);
      expect(find.text('Padrão do Sistema'), findsOneWidget);

      // Clica em Modo Escuro
      await tester.tap(find.text('Modo Escuro'));
      await tester.pumpAndSettle();

      expect(cubit.state, equals(ThemeMode.dark));
    });
  });
}
