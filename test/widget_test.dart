import 'package:flutter_test/flutter_test.dart';
import 'package:vigo/main.dart'; // Your import is perfectly correct here

void main() {
  testWidgets('ViGo app loads to landing screen', (WidgetTester tester) async {
    
    // 1. FIXED: Capital G in ViGoApp
    await tester.pumpWidget(const ViGoApp());

    // 2. We need to wait a second for the fade-in animation to finish!
    await tester.pumpAndSettle();

    // 3. FIXED: Look for the actual text on your new landing page
    expect(find.text('Campus Transit, Simplified.'), findsOneWidget);
    
  });
}