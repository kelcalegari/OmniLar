import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/features/notifications/data/datasources/mock_notifications_datasource.dart';
import 'package:omni_lar/features/notifications/domain/entities/app_notification.dart';
import 'package:omni_lar/features/notifications/domain/entities/notification_preferences.dart';
import 'package:omni_lar/features/notifications/presentation/widgets/notification_preferences_block.dart';

/// Fonte que recusa gravar.
class _FailingSource extends MockNotificationsDataSource {
  @override
  Future<void> saveGroupPreference(NotificationCategory group, GroupPreference preference) async =>
      throw Exception('sem rede');
}

Future<void> _pump(WidgetTester tester, MockNotificationsDataSource source) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: NotificationPreferencesBlock(dataSource: source))),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('Desligar o sino de um grupo grava a preferência', (tester) async {
    final source = MockNotificationsDataSource();
    await _pump(tester, source);

    expect(find.text('Despesas e contas'), findsOneWidget);
    // Primeiro interruptor da primeira linha: sino de "Despesas e contas"
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    final saved = await source.getPreferences();
    expect(saved.of(NotificationCategory.despesas).inApp, isFalse);
    expect(saved.of(NotificationCategory.despesas).push, isTrue);
  });

  testWidgets('Horário silencioso liga com 22:00 às 07:00 e o resumo semanal vem ligado', (tester) async {
    final source = MockNotificationsDataSource();
    await _pump(tester, source);

    expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Resumo semanal')).value, isTrue);
    await tester.tap(find.widgetWithText(SwitchListTile, 'Horário silencioso'));
    await tester.pumpAndSettle();

    final saved = await source.getPreferences();
    expect(saved.quietStart, (hour: 22, minute: 0));
    expect(saved.quietEnd, (hour: 7, minute: 0));
    expect(find.text('Das 22:00'), findsOneWidget);
  });

  testWidgets('Falha ao gravar volta o interruptor e avisa', (tester) async {
    await _pump(tester, _FailingSource());

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(find.byType(Switch).first).value, isTrue);
    expect(find.text('Não foi possível salvar. Tente de novo.'), findsOneWidget);
  });
}
