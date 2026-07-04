import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AgeSignalsStatus {
  final int? userStatus;
  final String? userStatusName;
  final int? ageLower;
  final int? ageUpper;
  final int? mostRecentApprovalEpochMs;
  final String? installId;
  final int checkedAtEpochMs;

  const AgeSignalsStatus({
    required this.userStatus,
    required this.userStatusName,
    required this.ageLower,
    required this.ageUpper,
    required this.mostRecentApprovalEpochMs,
    required this.installId,
    required this.checkedAtEpochMs,
  });

  bool get isAccessDenied => userStatus == 3;

  Map<String, dynamic> toJson() => {
    'userStatus': userStatus,
    'userStatusName': userStatusName,
    'ageLower': ageLower,
    'ageUpper': ageUpper,
    'mostRecentApprovalEpochMs': mostRecentApprovalEpochMs,
    'installId': installId,
    'checkedAtEpochMs': checkedAtEpochMs,
  };

  factory AgeSignalsStatus.fromMap(Map<dynamic, dynamic> map) {
    return AgeSignalsStatus(
      userStatus: map['userStatus'] as int?,
      userStatusName: map['userStatusName'] as String?,
      ageLower: map['ageLower'] as int?,
      ageUpper: map['ageUpper'] as int?,
      mostRecentApprovalEpochMs: map['mostRecentApprovalEpochMs'] as int?,
      installId: map['installId'] as String?,
      checkedAtEpochMs:
          map['checkedAtEpochMs'] as int? ??
          DateTime.now().millisecondsSinceEpoch,
    );
  }
}

class AgeSignalsService {
  static const MethodChannel _channel = MethodChannel('app.subzip/age_signals');
  static const String _keyLatestAgeSignals = 'latest_age_signals';
  static const String _keyLatestAgeSignalsError = 'latest_age_signals_error';

  Future<AgeSignalsStatus?> checkAndCacheAgeSignals() async {
    if (!Platform.isAndroid) {
      return null;
    }

    try {
      final result = await _channel.invokeMapMethod<String, dynamic>(
        'checkAgeSignals',
      );
      if (result == null) {
        return null;
      }

      final status = AgeSignalsStatus.fromMap(result);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyLatestAgeSignals, jsonEncode(status.toJson()));
      await prefs.remove(_keyLatestAgeSignalsError);
      return status;
    } on PlatformException catch (e) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _keyLatestAgeSignalsError,
        jsonEncode({
          'code': e.code,
          'message': e.message,
          'details': e.details,
          'checkedAtEpochMs': DateTime.now().millisecondsSinceEpoch,
        }),
      );
      debugPrint('Play Age Signals error: ${e.code} ${e.message}');
      return null;
    }
  }
}
