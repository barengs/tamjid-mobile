import 'package:flutter_test/flutter_test.dart';
import 'package:komprasi_tamjid/main.dart';

void main() {
  testWidgets('KomprasiTamjidApp smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const KomprasiTamjidApp());
  });
}
