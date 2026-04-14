import 'dart:io';

import 'package:android_intent_plus/android_intent.dart';

class DouyinLauncher {
  Future<void> openDouyin() async {
    if (!Platform.isAndroid) {
      return;
    }
    const intent = AndroidIntent(
      action: 'action_main',
      package: 'com.ss.android.ugc.aweme',
      category: 'android.intent.category.LAUNCHER',
    );
    await intent.launch();
  }
}
