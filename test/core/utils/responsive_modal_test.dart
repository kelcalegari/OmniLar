import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omni_lar/core/utils/responsive.dart';

void main() {
  group('showAdaptiveModal Layout & Responsiveness', () {
    testWidgets('Desktop: Renders without infinite size when child has SingleChildScrollView and Material/InkWell', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('Modal Title'),
                          Row(
                            children: [
                              Expanded(
                                child: Material(
                                  color: Colors.blue.withValues(alpha: 0.1),
                                  child: InkWell(
                                    onTap: () {},
                                    child: const Text('Action Button'),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Modal'));
      await tester.pumpAndSettle();

      // Expect dialog to be open without layout exception
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Modal Title'), findsOneWidget);
      expect(find.text('Action Button'), findsOneWidget);
    });

    testWidgets('Desktop: Renders without layout exception when child is a Scaffold with ListView', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 540,
                    child: Scaffold(
                      appBar: AppBar(title: const Text('Scaffold In Modal')),
                      body: ListView(
                        children: const [
                          Text('Item 1'),
                          Text('Item 2'),
                        ],
                      ),
                    ),
                  );
                },
                child: const Text('Open Scaffold Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Scaffold Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Scaffold In Modal'), findsOneWidget);
      expect(find.text('Item 1'), findsOneWidget);
    });

    testWidgets('Desktop: Renders without layout exception when child has Column with Expanded', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAdaptiveModal(
                    context: context,
                    maxWidth: 600,
                    child: Column(
                      children: [
                        const Text('Header'),
                        Expanded(
                          child: ListView(
                            children: const [Text('Message 1'), Text('Message 2')],
                          ),
                        ),
                        const Text('Footer'),
                      ],
                    ),
                  );
                },
                child: const Text('Open Expanded Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Expanded Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.text('Header'), findsOneWidget);
      expect(find.text('Message 1'), findsOneWidget);
      expect(find.text('Footer'), findsOneWidget);
    });

    testWidgets('Mobile: Renders as ModalBottomSheet on screens < 768px', (tester) async {
      tester.view.physicalSize = const Size(400, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showAdaptiveModal(
                    context: context,
                    child: const Text('Mobile Content'),
                  );
                },
                child: const Text('Open Mobile Modal'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Mobile Modal'));
      await tester.pumpAndSettle();

      expect(find.byType(ModalBottomSheetRoute), findsNothing); // route is internal, but BottomSheet exists
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('Mobile Content'), findsOneWidget);
    });
  });
}
