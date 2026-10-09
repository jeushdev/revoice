import 'package:flutter_test/flutter_test.dart';
import 'package:revise/main.dart';

void main() {
  testWidgets('home renders consent notice and demo toggle', (tester) async {
    await tester.pumpWidget(const ReviseApp());
    expect(find.text('Start session'), findsOneWidget);
    expect(find.text('Demo / Sample data'), findsOneWidget);
    expect(
      find.textContaining('Processing stays on this phone'),
      findsOneWidget,
    );
  });
}
