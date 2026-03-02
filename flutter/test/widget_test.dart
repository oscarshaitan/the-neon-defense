import 'package:flutter_test/flutter_test.dart';
import 'package:neon_defense/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const NeonDefenseApp());
    expect(find.byType(NeonDefenseApp), findsOneWidget);
  });
}
