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

    expect(find.text('上午刷视频'), findsOneWidget);
    expect(find.textContaining('总共 9 项，完成 0 项'), findsOneWidget);
    expect(find.byIcon(Icons.settings), findsOneWidget);
  });

  testWidgets('settings can save a template without lifecycle crash', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      const ScriptAssistantApp(enablePlatformServices: false),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    await tester.tap(find.text('模板库'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('save_template_group_button')).hitTestable(),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('template_name_field')), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('template_name_field')),
      '测试模板',
    );
    await tester.tap(find.byKey(const ValueKey('template_name_submit_button')));
    await tester.pumpAndSettle();

    expect(find.text('测试模板'), findsOneWidget);
  });
}
