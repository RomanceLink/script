import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:scriptapp/src/app.dart';

void main() {
  testWidgets('dashboard renders timeline summary', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ScriptAssistantApp(enablePlatformServices: false),
    );
    await tester.pumpAndSettle();

    expect(find.text('今日箴言'), findsOneWidget);
    expect(find.text('上午刷视频'), findsOneWidget);
    expect(find.text('首页显示 9 项'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });
}
