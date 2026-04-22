import 'dart:io';
import 'dart:typed_data';

import 'package:device_apps/device_apps.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LaunchableApp {
  const LaunchableApp({
    required this.packageName,
    required this.appName,
    this.icon,
  });

  final String packageName;
  final String appName;
  final Uint8List? icon;
}

class DouyinLauncher {
  static const _recentAppsKey = 'recent_launchable_apps_v1';

  Future<bool> openPackage(String packageName) async {
    if (!Platform.isAndroid) {
      return false;
    }
    return DeviceApps.openApp(packageName);
  }

  Future<List<LaunchableApp>> listLaunchableApps() async {
    if (!Platform.isAndroid) {
      return const [];
    }

    final apps = await DeviceApps.getInstalledApplications(
      includeSystemApps: false,
      onlyAppsWithLaunchIntent: true,
      includeAppIcons: true,
    );

    final mapped =
        apps
            .map(
              (app) => LaunchableApp(
                packageName: app.packageName,
                appName: app.appName,
                icon: app is ApplicationWithIcon ? app.icon : null,
              ),
            )
            .toList()
          ..sort((a, b) => a.appName.compareTo(b.appName));

    return mapped;
  }

  Future<void> markAppAsRecent(String packageName) async {
    final value = packageName.trim();
    if (value.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    final current = prefs.getStringList(_recentAppsKey) ?? const [];
    final next = <String>[value];
    for (final item in current) {
      if (item != value && item.trim().isNotEmpty) {
        next.add(item);
      }
      if (next.length >= 8) break;
    }
    await prefs.setStringList(_recentAppsKey, next);
  }

  Future<List<String>> loadRecentAppPackages() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    return (prefs.getStringList(_recentAppsKey) ?? const [])
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }
}
