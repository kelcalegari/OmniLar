import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/features/projects/presentation/cubit/projects_cubit.dart';
import 'package:omni_lar/features/projects/presentation/cubit/projects_state.dart';
import 'package:omni_lar/features/projects/presentation/pages/projects_hub_page.dart';

void main() {
  setUpAll(() async {
    if (!sl.isRegistered<ProjectsCubit>()) {
      await initServiceLocator();
    }
  });

  testWidgets('participantes do projeto: o total precisa fechar 100% para salvar', (tester) async {
    tester.view.physicalSize = const Size(900, 2000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final cubit = sl<ProjectsCubit>();
    await tester.pumpWidget(BlocProvider.value(
      value: cubit,
      child: const MaterialApp(home: ProjectsHubPage()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    final project = (cubit.state as ProjectsLoaded).projects.first;
    await tester.tap(find.text(project.title).first);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    final open = find.textContaining('Participantes (');
    await tester.ensureVisible(open);
    await tester.tap(open);
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
    await tester.pumpAndSettle();

    expect(find.text('Participantes de ${project.title}'), findsOneWidget);
    FilledButton save() => tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Salvar'));
    expect(find.text('Total: 100%'), findsOneWidget);
    expect(save().onPressed, isNotNull);

    // Tirar 1% de alguém deixa o total errado e trava o salvar
    await tester.tap(find.byTooltip('Diminuir').first);
    await tester.pumpAndSettle();
    expect(find.text('Total: 99% (precisa somar 100%)'), findsOneWidget);
    expect(save().onPressed, isNull);

    await tester.tap(find.text('Dividir igualmente'));
    await tester.pumpAndSettle();
    expect(find.text('Total: 100%'), findsOneWidget);

    // Convidado de fora entra na divisão igual
    await tester.enterText(find.widgetWithText(TextField, 'Convidado de fora da casa'), 'Bia');
    await tester.tap(find.text('Adicionar'));
    await tester.pumpAndSettle();
    expect(find.text('Bia (convidado)'), findsOneWidget);
    expect(find.text('Total: 100%'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.text('Participantes de ${project.title}'), findsNothing);
  });
}
