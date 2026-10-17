import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/finance/presentation/cubit/finance_cubit.dart';
import 'package:omni_lar/main.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<FinanceCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('Rotina da Casa renderiza cards de atalho sem quebra de texto', (tester) async {
    await tester.pumpWidget(const OmniLarApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    // Valida que os atalhos de rotina estão todos presentes
    expect(find.text('Compras'), findsOneWidget);
    expect(find.text('Caixinhas'), findsOneWidget);
    expect(find.text('Metas da casa'), findsOneWidget);
    expect(find.text('Tarefas'), findsWidgets);
    expect(find.text('Viagens'), findsOneWidget);
    expect(find.text('e Projetos'), findsOneWidget);
  });
}
