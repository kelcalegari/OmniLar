import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/di/service_locator.dart';
import 'package:omni_lar/main.dart';

void main() {
  setUpAll(() async {
    await initServiceLocator();
  });

  testWidgets('App renders Home tab smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OmniLarApp());
    // Avança para completar os Futures do Mock DataSource
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pumpAndSettle();

    expect(find.text('Nossa Casa'), findsWidgets);
    expect(find.text('Fôlego do Caixa'), findsOneWidget);
  });
}
