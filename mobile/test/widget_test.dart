import 'package:flutter_test/flutter_test.dart';
import 'package:teqlif/main.dart';

void main() {
  testWidgets('Splash screen shows teqlif', (WidgetTester tester) async {
    await tester.pumpWidget(const TeqlifApp());
    expect(find.text('teqlif'), findsWidgets);
  });
}
