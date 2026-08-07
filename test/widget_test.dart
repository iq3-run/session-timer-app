import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/app.dart';

void main() {
  testWidgets('SessionTimerApp builds without crashing', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: SessionTimerApp()),
    );

    expect(find.text('SESSION TIMER'), findsOneWidget);
  });
}
