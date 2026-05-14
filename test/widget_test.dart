import 'package:flutter_test/flutter_test.dart';
import 'package:vigo/main.dart';

void main() {
  testWidgets('Vi Go app loads', (WidgetTester tester) async {

    await tester.pumpWidget(const ViGoApp());

    expect(find.text('Firebase Connected 🚀'), findsOneWidget);
  });
}