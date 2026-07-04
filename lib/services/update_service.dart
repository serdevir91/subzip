import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:new_version_plus/new_version_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class AppUpdateStatus {
  final bool canUpdate;
  final String localVersion;
  final String storeVersion;
  final String? appStoreLink;
  final bool storeVersionAvailable;

  const AppUpdateStatus({
    required this.canUpdate,
    required this.localVersion,
    required this.storeVersion,
    this.appStoreLink,
    this.storeVersionAvailable = true,
  });
}

class UpdateService {
  static const String androidPackageId = 'www.subzip.app';
  static const String androidPlayStoreCountry = 'TR';
  static const String androidPlayStoreLink =
      'https://play.google.com/store/apps/details?id=$androidPackageId';

  Future<AppUpdateStatus?> checkForUpdate() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return null;
    }

    try {
      final updater = NewVersionPlus(
        androidId: androidPackageId,
        androidPlayStoreCountry: androidPlayStoreCountry,
      );
      final status = await updater.getVersionStatus();
      if (status == null) return _localOnlyStatus();

      return AppUpdateStatus(
        canUpdate: status.canUpdate,
        localVersion: status.localVersion,
        storeVersion: status.storeVersion,
        appStoreLink: status.appStoreLink,
      );
    } catch (e) {
      debugPrint('Update version lookup failed: $e');
      return _localOnlyStatus();
    }
  }

  Future<bool> openUpdatePage(AppUpdateStatus status) async {
    final candidates = <Uri>[
      if (Platform.isAndroid)
        Uri.parse('market://details?id=$androidPackageId'),
      if (status.appStoreLink != null && status.appStoreLink!.trim().isNotEmpty)
        Uri.parse(status.appStoreLink!),
      if (Platform.isAndroid) Uri.parse(androidPlayStoreLink),
    ];

    for (final uri in candidates) {
      try {
        if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          return true;
        }
      } catch (e) {
        debugPrint('Update link failed for $uri: $e');
      }
    }
    return false;
  }

  Future<AppUpdateStatus> _localOnlyStatus() async {
    final info = await PackageInfo.fromPlatform();
    return AppUpdateStatus(
      canUpdate: false,
      localVersion: info.version,
      storeVersion: 'Unknown',
      appStoreLink: Platform.isAndroid ? androidPlayStoreLink : null,
      storeVersionAvailable: false,
    );
  }
}
