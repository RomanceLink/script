import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scriptapp/src/app.dart';

void main() {
  testWidgets('dashboard renders timeline summary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ScriptAssistantApp(enablePlatformServices: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('半自动任务精灵'), findsOneWidget);
    expect(find.text('上午刷视频'), findsOneWidget);
    expect(find.text('打开抖音极速版'), findsOneWidget);
    expect(find.text('重置今日'), findsOneWidget);
  });
}
