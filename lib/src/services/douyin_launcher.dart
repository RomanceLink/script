import 'dart:io';

import 'package:device_apps/device_apps.dart';

class LaunchableApp {
  const LaunchableApp({required this.packageName, required this.appName});

  final String packageName;
  final String appName;
}

class DouyinLauncher {
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
    );

    final mapped =
        apps
            .map(
              (app) => LaunchableApp(
                packageName: app.packageName,
                appName: app.appName,
              ),
            )
            .toList()
          ..sort((a, b) => a.appName.compareTo(b.appName));

    return mapped;
  }
}
