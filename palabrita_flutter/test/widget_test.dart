import 'package:flutter_test/flutter_test.dart';
import 'package:palabrita_flutter/main.dart';

void main() {
  testWidgets('Palabrita Benchmark Dashboard UI smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const PalabritaBenchmarkApp());

    // Verify key UI elements render
    expect(find.text('Palabrita AI Benchmark'), findsOneWidget);
    expect(find.text('Test Environment'), findsOneWidget);
    expect(find.text('Benchmark Settings'), findsOneWidget);
    expect(find.text('Start Full Benchmark (30 Prompts)'), findsOneWidget);
    expect(find.text('Clean Success'), findsOneWidget);
    expect(find.text('F1 (Format Violation)'), findsOneWidget);
    expect(find.text('Live Execution Feed'), findsOneWidget);
  });
}
