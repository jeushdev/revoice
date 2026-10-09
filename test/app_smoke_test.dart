import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:revise/app/app_state.dart';
import 'package:revise/main.dart';

void main() {
  testWidgets('tabs: Record, Library and Settings render', (tester) async {
    await tester.pumpWidget(ReviseApp(app: AppState()));
    expect(find.text('Welcome'), findsOneWidget);
    expect(find.text('Start session'), findsOneWidget);
    expect(find.text('Place it between speakers'), findsOneWidget);

    await tester.tap(find.text('Library'));
    await tester.pump();
    expect(find.text('No sessions yet'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pump();
    expect(find.text('Sample data'), findsWidgets);
    expect(find.text('Thanks for coming in.'), findsOneWidget);
    expect(
      find.text('Everything runs on this phone. Nothing is uploaded.'),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
