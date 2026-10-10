import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/widgets/omni_logo.dart';

void main() {
  group('OmniLogo Widget Tests', () {
    testWidgets('Renderiza OmniLogo horizontal com tema claro e escuro', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                OmniLogo.horizontal(isDark: false),
                OmniLogo.horizontal(isDark: true),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(OmniLogo), findsNWidgets(2));
      expect(find.byType(Image), findsNWidgets(2));
    });

    testWidgets('Renderiza OmniLogo ícone e vertical', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                OmniLogo.icon(isDark: false),
                OmniLogo.icon(isDark: true),
                OmniLogo.vertical(),
              ],
            ),
          ),
        ),
      );

      expect(find.byType(OmniLogo), findsNWidgets(3));
      expect(find.byType(Image), findsNWidgets(3));
    });
  });
}
