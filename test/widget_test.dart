// This is a basic Flutter widget test.

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_payment_system/main.dart';

void main() {
  testWidgets('App initializes with login screen', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const QRPaymentApp());

    // Verify the app loads and shows the login screen.
    expect(find.text('Login'), findsWidgets);
  });
}
