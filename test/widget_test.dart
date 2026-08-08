import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:session_timer/app.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('SessionTimerApp builds without crashing', (tester) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      const ProviderScope(child: SessionTimerApp()),
    );
    await tester.pump();

    expect(find.text('現在時刻'), findsOneWidget);
    expect(find.text('完了まで'), findsOneWidget);
  });
}
