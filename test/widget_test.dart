import 'package:flutter_test/flutter_test.dart';

import 'package:disaster_mesh/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const DisasterMeshApp());
    expect(find.byType(DisasterMeshApp), findsOneWidget);
  });
}
