import 'package:fap_attendance/ui/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppColors palette', () {
    test('exposes distinct brand and semantic colors', () {
      expect(AppColors.orange, isNot(equals(AppColors.orangeDark)));
      expect(AppColors.orangeSoft, isNot(equals(AppColors.orange)));
      expect(AppColors.cream, isNot(equals(AppColors.canvas)));
      expect(AppColors.creamLight, isNot(equals(AppColors.ink)));
      expect(AppColors.success, isNot(equals(AppColors.danger)));
      expect(AppColors.info, isNot(equals(AppColors.infoSoft)));
      expect(AppColors.panel.a, 1.0);
    });

    test('maintains readable contrast between ink and light surfaces', () {
      final inkLuminance = AppColors.ink.computeLuminance();
      final canvasLuminance = AppColors.canvas.computeLuminance();
      final panelLuminance = AppColors.panel.computeLuminance();
      final creamLuminance = AppColors.cream.computeLuminance();

      expect(canvasLuminance - inkLuminance, greaterThan(0.5));
      expect(panelLuminance - inkLuminance, greaterThan(0.5));
      expect(creamLuminance - inkLuminance, greaterThan(0.4));
    });

    test('primary orange and dark orange have clear tonal separation', () {
      expect(
        AppColors.orange.computeLuminance(),
        greaterThan(AppColors.orangeDark.computeLuminance()),
      );
      expect(
        AppColors.orangeSoft.computeLuminance(),
        greaterThan(AppColors.orange.computeLuminance()),
      );
      expect(
        AppColors.infoSoft.computeLuminance(),
        greaterThan(AppColors.info.computeLuminance()),
      );
    });
  });

  group('buildAppTheme', () {
    test('configures Material 3 light theme with brand color scheme', () {
      final theme = buildAppTheme();

      expect(theme.useMaterial3, isTrue);
      expect(theme.brightness, Brightness.light);
      expect(theme.colorScheme.brightness, Brightness.light);
      expect(theme.colorScheme.primary, AppColors.orange);
      expect(theme.colorScheme.surface, Colors.white);
      expect(theme.scaffoldBackgroundColor, AppColors.canvas);
    });

    test('configures card, appBar, divider, and input decoration themes', () {
      final theme = buildAppTheme();

      expect(theme.appBarTheme.backgroundColor, Colors.white);
      expect(theme.appBarTheme.elevation, 0);
      expect(theme.cardTheme.color, Colors.white);
      expect(theme.cardTheme.elevation, 0);
      expect(theme.dividerTheme.color, AppColors.border);
      expect(theme.inputDecorationTheme.filled, isTrue);
      expect(theme.inputDecorationTheme.border, isA<OutlineInputBorder>());
    });

    testWidgets('renders styled Material widgets cleanly without exceptions', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            appBar: AppBar(title: const Text('FAP Theme Preview')),
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Card content'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const TextField(
                    decoration: InputDecoration(labelText: 'Course Code'),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      FilledButton(
                        onPressed: () {},
                        child: const Text('Primary Action'),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton(
                        onPressed: () {},
                        child: const Text('Secondary Action'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Wrap(
                    spacing: 8,
                    children: [
                      Chip(label: Text('Slot 1')),
                      Chip(label: Text('SE1801')),
                    ],
                  ),
                  const Divider(),
                ],
              ),
            ),
          ),
        ),
      );

      expect(find.text('FAP Theme Preview'), findsOneWidget);
      expect(find.text('Card content'), findsOneWidget);
      expect(find.text('Course Code'), findsOneWidget);
      expect(find.text('Primary Action'), findsOneWidget);
      expect(find.text('Secondary Action'), findsOneWidget);
      expect(find.text('Slot 1'), findsOneWidget);
      expect(find.text('SE1801'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
