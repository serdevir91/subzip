import 'dart:io';

import 'package:in_app_review/in_app_review.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_service.dart';

class ReviewService {
  Future<bool> requestInAppReview() async {
    final review = InAppReview.instance;
    final isAvailable = await review.isAvailable();
    if (!isAvailable) {
      return false;
    }
    await review.requestReview();
    return true;
  }

  Future<bool> openStoreReviewPage() async {
    if (!Platform.isAndroid) {
      return false;
    }

    final candidates = <Uri>[
      Uri.parse('market://details?id=${UpdateService.androidPackageId}'),
      Uri.parse(UpdateService.androidPlayStoreLink),
    ];

    for (final uri in candidates) {
      if (await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        return true;
      }
    }
    return false;
  }
}
